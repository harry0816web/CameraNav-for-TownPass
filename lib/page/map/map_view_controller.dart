import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/route_service.dart';
import 'package:town_pass/util/graphml_converter.dart';
import 'package:flutter_map/flutter_map.dart';

class CameraLocation {
  CameraLocation({
    required this.id,
    required this.unit,
    required this.address,
    required this.direction,
    required this.position,
  });

  final String id;
  final String unit;
  final String address;
  final String direction;
  final LatLng position;
}

enum CameraDisplayMode { all, route }

class CameraDisplayItem {
  CameraDisplayItem._({
    required this.position,
    required List<CameraLocation> cameras,
  }) : cameras = List.unmodifiable(cameras);

  factory CameraDisplayItem.single(CameraLocation camera) =>
      CameraDisplayItem._(position: camera.position, cameras: [camera]);

  factory CameraDisplayItem.cluster(List<CameraLocation> cameras) {
    final avgLat = cameras.fold<double>(0.0, (sum, c) => sum + c.position.latitude) /
        cameras.length;
    final avgLng = cameras.fold<double>(0.0, (sum, c) => sum + c.position.longitude) /
        cameras.length;
    return CameraDisplayItem._(
      position: LatLng(avgLat, avgLng),
      cameras: cameras,
    );
  }

  final LatLng position;
  final List<CameraLocation> cameras;

  bool get isCluster => cameras.length > 1;
  CameraLocation get single => cameras.first;
}

class MapViewController extends GetxController {
  final GeoLocatorService _geoLocatorService = Get.find<GeoLocatorService>();
  final SharedPreferencesService _sharedPreferencesService = Get.find<SharedPreferencesService>();
  final RouteService _routeService = Get.find<RouteService>();

  // 地圖中心點
  final Rx<LatLng> mapCenter = const LatLng(25.0330, 121.5654).obs; // 台北市預設位置

  // 當前位置
  final Rxn<LatLng> currentPosition = Rxn<LatLng>();

  // 初始位置（可由使用者輸入或點地圖設定）
  final Rxn<LatLng> initialPosition = Rxn<LatLng>();

  // 回家位置
  final Rxn<LatLng> homePosition = Rxn<LatLng>();

  // 是否正在載入位置
  final RxBool isLoadingLocation = false.obs;

  // 是否正在搜索地址
  final RxBool isSearchingAddress = false.obs;

  // 地址輸入控制器（回家位置）
  final TextEditingController addressTextController = TextEditingController();
  // 地址輸入控制器（初始位置）
  final TextEditingController initialAddressTextController = TextEditingController();

  // 設定模式：'home' 或 'initial'
  final RxString settingMode = ''.obs;

  // 路徑規劃結果
  final Rxn<RouteResult> routeResult = Rxn<RouteResult>();

  // 是否正在規劃路徑
  final RxBool isPlanningRoute = false.obs;

  // Debug：顯示匹配到的最近節點
  final RxBool debugShowNearestNodes = false.obs;
  final RxList<LatLng> debugNearestNodes = <LatLng>[].obs;
  // 可調整的最近節點搜尋半徑（公尺），null 代表自適應
  final RxnDouble searchRadiusMeters = RxnDouble();

  // 路徑規劃錯誤訊息
  final RxnString routeError = RxnString();

  // 定位錯誤訊息
  final RxnString locationError = RxnString();

  final RxList<CameraLocation> cameraLocations = <CameraLocation>[].obs;

  final MapController mapController = MapController();
  final RxDouble mapZoom = 15.0.obs;
  static const double minMapZoom = 10.0;
  static const double maxMapZoom = 18.0;

  LatLng? _lastCameraCenter;
  final RxList<CameraLocation> routeCameraLocations = <CameraLocation>[].obs;
  final Rx<CameraDisplayMode> cameraDisplayMode = CameraDisplayMode.all.obs;
  final RxDouble safetyPreference = 0.7.obs;
  final RxList<CameraDisplayItem> cameraDisplayItems = <CameraDisplayItem>[].obs;
  final RxBool controlsExpanded = false.obs;

  static const String _keyInitialPosition = 'map_initial_position';
  static const String _keyHomePosition = 'map_home_position';
  static const String _cameraDataPath = 'assets/mock_data/camera_map_geo_data.csv';
  
  // 路網數據文件路徑（需要在 assets 中配置）
  static const String _graphDataPath = 'assets/mock_data/taipei_with_security.json';
  static const double _cameraRouteThresholdMeters = 40;
  static const double _minClusterCellSizeDegrees = 0.0002;
  static const double _maxClusterCellSizeDegrees = 0.2;

  LatLng? _lastPlannedStart;
  LatLng? _lastPlannedEnd;

  @override
  void onInit() {
    super.onInit();
    _loadSavedPositions();
    _getCurrentLocation();
    _loadRouteGraph();
    _loadCameraLocations();
    // 可選：設定自訂搜尋半徑，預設 null 使用自適應
    _routeService.setSearchRadiusMeters(searchRadiusMeters.value);
  }

  // 載入路網圖形數據
  Future<void> _loadRouteGraph() async {
    try {
      final graphData = await GraphMLConverter.loadGraphFromJson(_graphDataPath);
      await _routeService.loadGraph(graphData);
    } catch (e) {
      print('載入路網數據失敗: $e');
      // 如果路網數據不存在，路徑規劃功能將不可用
    }
  }

  Future<void> _loadCameraLocations() async {
    try {
      final csvContent = await rootBundle.loadString(_cameraDataPath);
      if (csvContent.isEmpty) {
        _refreshCameraDisplayItems();
        return;
      }

      final lines = const LineSplitter().convert(csvContent);
      if (lines.length <= 1) {
        _refreshCameraDisplayItems();
        return;
      }

      final parsed = <CameraLocation>[];

      for (final rawLine in lines.skip(1)) {
        if (rawLine.trim().isEmpty) {
          continue;
        }

        final columns = rawLine.split(',');
        if (columns.length < 7) {
          continue;
        }

        final lon = double.tryParse(columns[5].trim());
        final lat = double.tryParse(columns[6].trim());
        if (lat == null || lon == null) {
          continue;
        }

        parsed.add(
          CameraLocation(
            id: columns[1].trim(),
            unit: columns[2].trim(),
            address: columns[3].trim(),
            direction: columns[4].trim(),
            position: LatLng(lat, lon),
          ),
        );
      }

      cameraLocations.assignAll(parsed);
      _refreshCameraDisplayItems();
    } catch (e) {
      debugPrint('Failed to load camera locations: $e');
    }
  }

  void onMapEvent(MapEvent event) {
    final camera = event.camera;
    final previousCenter = _lastCameraCenter;
    _lastCameraCenter = camera.center;
    mapCenter.value = camera.center;
    final zoomChanged = (mapZoom.value - camera.zoom).abs() > 0.001;
    final centerChanged = previousCenter == null
        ? true
        : const Distance()
                .as(LengthUnit.Meter, previousCenter, camera.center)
                .abs() > 5;

    if (zoomChanged) {
      mapZoom.value = camera.zoom;
    }

    if (zoomChanged || centerChanged) {
      _refreshCameraDisplayItems();
    }
  }

  void onZoomSliderChanged(double zoom) {
    final clamped = zoom.clamp(minMapZoom, maxMapZoom);
    mapZoom.value = clamped;
    final targetCenter = _lastCameraCenter ?? mapCenter.value;
    mapController.move(targetCenter, clamped);
    _refreshCameraDisplayItems();
  }

  List<CameraLocation> get visibleCameraLocations {
    if (cameraDisplayMode.value == CameraDisplayMode.route) {
      return List<CameraLocation>.unmodifiable(routeCameraLocations);
    }
    return List<CameraLocation>.unmodifiable(cameraLocations);
  }

  void toggleCameraDisplayMode() {
    if (cameraDisplayMode.value == CameraDisplayMode.all) {
      if (routeCameraLocations.isNotEmpty) {
        cameraDisplayMode.value = CameraDisplayMode.route;
      }
    } else {
      cameraDisplayMode.value = CameraDisplayMode.all;
    }
    _refreshCameraDisplayItems();
  }

  void toggleControlsExpanded() {
    controlsExpanded.value = !controlsExpanded.value;
  }

  void onSafetyWeightChanged(double value) {
    safetyPreference.value = value.clamp(0.0, 1.0);
  }

  void onSafetyWeightChangeEnd(double value) {
    safetyPreference.value = value.clamp(0.0, 1.0);
    if (_lastPlannedStart != null && _lastPlannedEnd != null) {
      _recalculateRoute();
    }
  }

  String get safetyPreferenceLabel {
    final value = safetyPreference.value;
    if (value <= 0.1) return '最短距離';
    if (value <= 0.35) return '偏距離';
    if (value < 0.65) return '平衡';
    if (value < 0.9) return '偏安全';
    return '最高安全';
  }

  void _updateRouteCameraLocations(List<LatLng> path) {
    routeCameraLocations.clear();
    if (path.length < 2 || cameraLocations.isEmpty) {
      // 如果路徑無效或沒有監視器數據，清空路徑監視器列表
      // 模式切換由調用者（_applyRouteResult）處理
      // ignore: avoid_print
      print('[MapViewController] 路徑無效或沒有監視器數據，清空路徑監視器');
      return;
    }

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final point in path) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    const marginDegrees = 0.01; // 約 1km 的緩衝
    minLat -= marginDegrees;
    maxLat += marginDegrees;
    minLng -= marginDegrees;
    maxLng += marginDegrees;

    final distance = Distance();

    for (final camera in cameraLocations) {
      final pos = camera.position;
      if (pos.latitude < minLat || pos.latitude > maxLat || pos.longitude < minLng || pos.longitude > maxLng) {
        continue;
      }

      double minDistance = double.infinity;
      for (final node in path) {
        final d = distance.as(LengthUnit.Meter, pos, node);
        if (d < minDistance) {
          minDistance = d;
        }
        if (minDistance <= _cameraRouteThresholdMeters) {
          break;
        }
      }

      if (minDistance <= _cameraRouteThresholdMeters) {
        routeCameraLocations.add(camera);
      }
    }

    // 注意：不在這裡自動切換模式，由調用者（_applyRouteResult）決定
    // 如果路徑上沒有監視器，保持當前模式不變
    // ignore: avoid_print
    print('[MapViewController] 路徑上的監視器數量: ${routeCameraLocations.length}');
  }

  /// 計算25vw對應的地理距離（公尺）
  /// 基於當前地圖可見寬度的25%
  double? _calculate25vwRadiusMeters() {
    try {
      final bounds = mapController.camera.visibleBounds;

      // 計算可見區域的寬度（公尺）
      // 使用中心緯度計算東西方向距離
      final centerLat = (bounds.north + bounds.south) / 2;
      
      // 計算東西方向的距離（取左中點到右中點）
      final leftCenter = LatLng(centerLat, bounds.west);
      final rightCenter = LatLng(centerLat, bounds.east);
      final distance = const Distance();
      final viewportWidthMeters = distance.as(
        LengthUnit.Meter,
        leftCenter,
        rightCenter,
      );

      // 25vw = 可見寬度的25%
      final radius25vw = viewportWidthMeters * 0.25;
      return radius25vw;
    } catch (_) {
      return null;
    }
  }

  void _refreshCameraDisplayItems() {
    final allSource = visibleCameraLocations;
    if (allSource.isEmpty) {
      cameraDisplayItems.clear();
      return;
    }

    // 如果是路徑模式，顯示所有路徑上的監視器（不進行25vw過濾）
    if (cameraDisplayMode.value == CameraDisplayMode.route) {
      final clusters = _clusterCameraLocations(allSource, mapZoom.value);
      cameraDisplayItems.assignAll(clusters);
      return;
    }

    // 非路徑模式：根據25vw半徑過濾監視器
    // 計算25vw半徑（公尺）
    final radius25vw = _calculate25vwRadiusMeters();
    
    // 如果無法計算半徑，回退到顯示所有監視器
    if (radius25vw == null) {
      final clusters = _clusterCameraLocations(allSource, mapZoom.value);
      cameraDisplayItems.assignAll(clusters);
      return;
    }

    // 獲取地圖中心點
    final center = mapCenter.value;
    final distance = const Distance();

    // 過濾出在地圖中心25vw半徑圓內的監視器
    final filtered = allSource
        .where((camera) {
          final dist = distance.as(
            LengthUnit.Meter,
            center,
            camera.position,
          );
          return dist <= radius25vw;
        })
        .toList(growable: false);

    final clusters = _clusterCameraLocations(filtered, mapZoom.value);
    cameraDisplayItems.assignAll(clusters);
  }

  List<CameraDisplayItem> _clusterCameraLocations(
    List<CameraLocation> cameras,
    double zoom,
  ) {
    if (cameras.length <= 100) {
      return cameras.map(CameraDisplayItem.single).toList(growable: false);
    }

    double cellSize = _initialCellSizeForZoom(zoom)
        .clamp(_minClusterCellSizeDegrees, _maxClusterCellSizeDegrees);
    List<CameraDisplayItem> clustered = _groupCamerasByCell(cameras, cellSize);

    int iterations = 0;
    while (clustered.length > 100 && iterations < 12) {
      cellSize = (cellSize * 1.6).clamp(_minClusterCellSizeDegrees, _maxClusterCellSizeDegrees);
      clustered = _groupCamerasByCell(cameras, cellSize);
      iterations++;
    }

    if (clustered.length > 100) {
      clustered.sort((a, b) => b.cameras.length.compareTo(a.cameras.length));
      clustered = clustered.take(100).toList(growable: false);
    }

    return clustered;
  }

  List<CameraDisplayItem> _groupCamerasByCell(
    List<CameraLocation> cameras,
    double cellSize,
  ) {
    final buckets = <String, List<CameraLocation>>{};
    final size = cellSize <= 0 ? _minClusterCellSizeDegrees : cellSize;

    for (final camera in cameras) {
      final latIndex = (camera.position.latitude / size).floor();
      final lngIndex = (camera.position.longitude / size).floor();
      final key = '$latIndex:$lngIndex';
      buckets.putIfAbsent(key, () => <CameraLocation>[]).add(camera);
    }

    return buckets.values
        .map((group) => group.length == 1
            ? CameraDisplayItem.single(group.first)
            : CameraDisplayItem.cluster(group))
        .toList(growable: false);
  }

  double _initialCellSizeForZoom(double zoom) {
    final clamped = zoom.clamp(minMapZoom, maxMapZoom);
    final exponent = maxMapZoom - clamped; // 0 at max zoom
    return 0.0004 * math.pow(1.4, exponent);
  }

  Future<void> _recalculateRoute() async {
    if (_lastPlannedStart == null || _lastPlannedEnd == null) {
      return;
    }
    if (!_routeService.isGraphLoaded) {
      return;
    }

    isPlanningRoute.value = true;
    try {
      final result = await _routeService.planRoute(
        _lastPlannedStart!,
        _lastPlannedEnd!,
        safetyPreference: safetyPreference.value,
      );
      _applyRouteResult(
        result,
        notFoundMessage: '無法找到路徑，請確認起終點位置是否在路網範圍內',
      );
    } catch (e) {
      routeError.value = '路徑規劃失敗: $e';
    } finally {
      isPlanningRoute.value = false;
    }
  }

  void _applyRouteResult(
    RouteResult? result, {
    required String notFoundMessage,
  }) {
    if (result == null) {
      routeResult.value = null;
      routeError.value = notFoundMessage;
      routeCameraLocations.clear();
      if (cameraDisplayMode.value == CameraDisplayMode.route) {
        cameraDisplayMode.value = CameraDisplayMode.all;
      }
      _refreshCameraDisplayItems();
      return;
    }

    routeError.value = null;
    routeResult.value = result;
    _adjustMapViewToRoute(result.path);
    final (s, e) = _routeService.lastNearestNodes;
    debugNearestNodes
      ..clear()
      ..addAll([if (s != null) s, if (e != null) e]);
    _updateRouteCameraLocations(result.path);
    
    // 路徑規劃完成後，自動切換到只顯示路徑上的監視器
    if (routeCameraLocations.isNotEmpty) {
      cameraDisplayMode.value = CameraDisplayMode.route;
      // ignore: avoid_print
      print('[MapViewController] 路徑規劃完成，切換到路徑模式，顯示 ${routeCameraLocations.length} 個路徑上的監視器');
    } else {
      // 如果路徑上沒有監視器，保持或切換到全部模式
      if (cameraDisplayMode.value == CameraDisplayMode.route) {
        cameraDisplayMode.value = CameraDisplayMode.all;
        // ignore: avoid_print
        print('[MapViewController] 路徑上沒有監視器，切換到全部模式');
      }
    }
    
    _refreshCameraDisplayItems();
  }

  Future<void> _executeRoutePlanning(
    LatLng start,
    LatLng end, {
    required String notFoundMessage,
  }) async {
    if (!_routeService.isGraphLoaded) {
      routeError.value = '路網數據未載入，無法規劃路徑';
      return;
    }

    isPlanningRoute.value = true;
    routeError.value = null;
    _lastPlannedStart = start;
    _lastPlannedEnd = end;

    try {
      final result = await _routeService.planRoute(
        start,
        end,
        safetyPreference: safetyPreference.value,
      );
      _applyRouteResult(result, notFoundMessage: notFoundMessage);
    } catch (e) {
      routeError.value = '路徑規劃失敗: $e';
    } finally {
      isPlanningRoute.value = false;
    }
  }

  // 載入已儲存的位置
  void _loadSavedPositions() {
    final initialPosJson = _sharedPreferencesService.instance.getString(_keyInitialPosition);
    if (initialPosJson != null) {
      try {
        final data = jsonDecode(initialPosJson) as Map<String, dynamic>;
        initialPosition.value = LatLng(
          data['latitude'] as double,
          data['longitude'] as double,
        );
      } catch (_) {}
    }

    final homePosJson = _sharedPreferencesService.instance.getString(_keyHomePosition);
    if (homePosJson != null) {
      try {
        final data = jsonDecode(homePosJson) as Map<String, dynamic>;
        homePosition.value = LatLng(
          data['latitude'] as double,
          data['longitude'] as double,
        );
      } catch (_) {}
    }
  }

  // 取得當前位置
  Future<void> _getCurrentLocation() async {
    isLoadingLocation.value = true;
    locationError.value = null;
    try {
      final position = await _geoLocatorService.position();
      final location = LatLng(position.latitude, position.longitude);
      
      // 檢查位置是否在台灣範圍內
      final isInTaiwan = GeoLocatorService.isLocationInTaiwan(
        location.latitude,
        location.longitude,
      );
      
      // 檢查精度（accuracy），如果精度太差（>1000米），可能不準確
      final accuracy = position.accuracy;
      final isAccurate = accuracy > 0 && accuracy < 1000;
      
      // 詳細日誌輸出
      // ignore: avoid_print
      print('[MapViewController] 定位結果:');
      // ignore: avoid_print
      print('  位置: lat=${location.latitude}, lng=${location.longitude}');
      // ignore: avoid_print
      print('  精度: ${accuracy.toStringAsFixed(1)} 公尺');
      // ignore: avoid_print
      print('  是否在台灣範圍: $isInTaiwan');
      // ignore: avoid_print
      print('  精度是否可接受: $isAccurate');
      // ignore: avoid_print
      print('  時間戳: ${position.timestamp}');
      
      // 如果位置不在台灣範圍內，可能是模擬器預設位置（如舊金山）
      if (!isInTaiwan) {
        final errorMsg = '定位位置不在台灣範圍內\n'
            '位置: (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})\n'
            '這可能是模擬器的預設位置。\n\n'
            '解決方法：\n'
            '1. iOS模擬器：Features > Location > Custom Location\n'
            '2. Android模擬器：Extended Controls > Location\n'
            '3. 設置為台灣的座標（例如：25.0330, 121.5654）';
        locationError.value = errorMsg;
        // ignore: avoid_print
        print('[MapViewController] 警告：定位位置不在台灣範圍內，可能是模擬器預設位置');
        // 不移動地圖到錯誤位置，保持當前地圖位置
        currentPosition.value = null;
        return;
      }
      
      // 如果精度太差，警告用戶但仍然使用該位置
      if (!isAccurate) {
        // ignore: avoid_print
        print('[MapViewController] 警告：定位精度較差 (${accuracy.toStringAsFixed(1)} 公尺)');
      }
      
      currentPosition.value = location;
      
      // 移動地圖中心到定位座標
      mapCenter.value = location;
      _lastCameraCenter = location;
      
      // 實際移動地圖控制器到定位位置
      // 使用合適的縮放級別（如果當前縮放太小，則設置為較大的縮放級別以便查看周圍）
      final targetZoom = mapZoom.value < 15.0 ? 15.0 : mapZoom.value;
      mapZoom.value = targetZoom;
      mapController.move(location, targetZoom);
      
      // 觸發監視器顯示更新
      _refreshCameraDisplayItems();
      
      locationError.value = null; // 清除錯誤訊息
      
      // ignore: avoid_print
      print('[MapViewController] 定位成功並已移動地圖');
    } catch (error) {
      // 如果無法取得位置，保持預設的台北市位置
      final errorMessage = error.toString();
      // ignore: avoid_print
      print('[MapViewController] 無法取得當前位置: $errorMessage');
      
      // 設置友好的錯誤訊息
      if (errorMessage.contains('未開啟定位服務')) {
        locationError.value = '定位服務未開啟\n\n'
            'iOS模擬器：\n'
            'Features > Location > Custom Location\n'
            '設置為：25.0330, 121.5654\n\n'
            'Android模擬器：\n'
            'Extended Controls > Location\n'
            '設置為：25.0330, 121.5654';
      } else if (errorMessage.contains('未允許定位權限')) {
        locationError.value = '定位權限未允許\n請在設置中允許定位權限';
      } else if (errorMessage.contains('timeout') || errorMessage.contains('time limit')) {
        locationError.value = '定位超時\n請確認定位服務已開啟，或稍後再試';
      } else {
        locationError.value = '無法取得位置：$errorMessage\n\n'
            '模擬器用戶：\n'
            '請設置模擬位置為台灣座標\n'
            '例如：25.0330, 121.5654 (台北)';
      }
    } finally {
      isLoadingLocation.value = false;
    }
  }

  // 重新取得當前位置
  Future<void> refreshCurrentLocation() async {
    await _getCurrentLocation();
  }

  // 在地圖上點擊設定位置
  void onMapTap(LatLng position) {
    if (settingMode.value == 'initial') {
      setInitialPosition(position);
      settingMode.value = '';
    } else if (settingMode.value == 'home') {
      setHomePosition(position);
      settingMode.value = '';
    }
  }

  // 設定初始位置
  void setInitialPosition(LatLng position) {
    initialPosition.value = position;
    _savePosition(_keyInitialPosition, position);
  }

  // 設定回家位置
  void setHomePosition(LatLng position) {
    homePosition.value = position;
    _savePosition(_keyHomePosition, position);
  }

  // 從地址搜索設定初始位置
  Future<void> setInitialPositionFromAddress(String address) async {
    isSearchingAddress.value = true;
    routeError.value = null;

    try {
      // 嘗試解析為座標格式 (緯度,經度)
      if (address.contains(',') && address.split(',').length == 2) {
        final parts = address.split(',');
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          setInitialPosition(LatLng(lat, lng));
          initialAddressTextController.text = address;
          isSearchingAddress.value = false;
          return;
        }
      }

      // 使用 OpenStreetMap Nominatim API 進行地址解析
      // 限制搜尋範圍在台灣（viewbox: 經度,緯度,經度,緯度）
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=5&addressdetails=1&viewbox=119.0,21.0,122.0,26.0&bounded=1&countrycodes=tw';
      
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('User-Agent', 'TownPass/1.0');
        final response = await request.close();

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final List<dynamic> results = jsonDecode(responseBody);
          
          if (results.isNotEmpty) {
            final result = results[0] as Map<String, dynamic>;
            final lat = double.parse(result['lat'] as String);
            final lon = double.parse(result['lon'] as String);
            setInitialPosition(LatLng(lat, lon));
            // 保留搜尋結果的名稱在搜尋框內
            final displayName = result['display_name'] as String? ?? address;
            initialAddressTextController.text = displayName;
          } else {
            routeError.value = '找不到該地址，請確認地址是否正確';
          }
        } else {
          routeError.value = '地址搜索失敗，請稍後再試';
        }
      } finally {
        client.close();
      }
    } catch (e) {
      routeError.value = '地址搜索失敗: $e';
    } finally {
      isSearchingAddress.value = false;
    }
  }

  // 從地址搜索設定回家位置
  Future<void> setHomePositionFromAddress(String address) async {
    isSearchingAddress.value = true;
    routeError.value = null;

    try {
      // 嘗試解析為座標格式 (緯度,經度)
      if (address.contains(',') && address.split(',').length == 2) {
        final parts = address.split(',');
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          setHomePosition(LatLng(lat, lng));
          addressTextController.text = address;
          isSearchingAddress.value = false;
          return;
        }
      }

      // 使用 OpenStreetMap Nominatim API 進行地址解析
      // 限制搜尋範圍在台灣（viewbox: 經度,緯度,經度,緯度）
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=5&addressdetails=1&viewbox=119.0,21.0,122.0,26.0&bounded=1&countrycodes=tw';
      
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('User-Agent', 'TownPass/1.0');
        final response = await request.close();

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final List<dynamic> results = jsonDecode(responseBody);
          
          if (results.isNotEmpty) {
            final result = results[0] as Map<String, dynamic>;
            final lat = double.parse(result['lat'] as String);
            final lon = double.parse(result['lon'] as String);
            setHomePosition(LatLng(lat, lon));
            // 保留搜尋結果的名稱在搜尋框內
            final displayName = result['display_name'] as String? ?? address;
            addressTextController.text = displayName;
          } else {
            routeError.value = '找不到該地址，請確認地址是否正確';
          }
        } else {
          routeError.value = '地址搜索失敗，請稍後再試';
        }
      } finally {
        client.close();
      }
    } catch (e) {
      routeError.value = '地址搜索失敗: $e';
    } finally {
      isSearchingAddress.value = false;
    }
  }

  // 儲存位置到 SharedPreferences
  void _savePosition(String key, LatLng position) {
    final data = {
      'latitude': position.latitude,
      'longitude': position.longitude,
    };
    _sharedPreferencesService.instance.setString(key, jsonEncode(data));
  }

  // 開始設定初始位置（點擊地圖模式）
  void startSettingInitialPosition() {
    settingMode.value = 'initial';
  }

  // 開始設定回家位置（點擊地圖模式）
  void startSettingHomePosition() {
    settingMode.value = 'home';
  }

  // 取消設定模式
  void cancelSettingMode() {
    settingMode.value = '';
  }

  // 清除回家位置
  void clearHomePosition() {
    homePosition.value = null;
    addressTextController.clear();
    _sharedPreferencesService.instance.remove(_keyHomePosition);
  }

  // 清除初始位置
  void clearInitialPosition() {
    initialPosition.value = null;
    initialAddressTextController.clear();
    _sharedPreferencesService.instance.remove(_keyInitialPosition);
  }

  @override
  void onClose() {
    addressTextController.dispose();
    initialAddressTextController.dispose();
    super.onClose();
  }

  // 規劃路徑（從當前位置到回家位置）
  Future<void> planRouteToHome() async {
    // 如果當前位置未取得，先嘗試取得
    if (currentPosition.value == null) {
      await _getCurrentLocation();
    }

    if (currentPosition.value == null) {
      routeError.value = '無法取得當前位置，請確認已開啟定位權限';
      return;
    }

    if (homePosition.value == null) {
      routeError.value = '請先設定回家位置';
      return;
    }

    await _executeRoutePlanning(
      currentPosition.value!,
      homePosition.value!,
      notFoundMessage: '無法找到路徑，請確認起終點位置是否在路網範圍內',
    );
  }

  // 規劃路徑（從定位位置或初始位置到回家位置）
  // 優先使用定位位置，如果沒有定位位置則使用用戶設定的初始位置
  Future<void> planRouteFromInitialToHome() async {
    // 檢查回家位置
    if (homePosition.value == null) {
      routeError.value = '請先設定回家位置';
      return;
    }

    // 優先使用定位位置
    LatLng? startPosition;
    if (currentPosition.value != null) {
      startPosition = currentPosition.value;
      // ignore: avoid_print
      print('[MapViewController] 使用定位位置作為起點: ${startPosition!.latitude}, ${startPosition.longitude}');
    } else if (initialPosition.value != null) {
      startPosition = initialPosition.value;
      // ignore: avoid_print
      print('[MapViewController] 使用初始位置作為起點: ${startPosition!.latitude}, ${startPosition.longitude}');
    } else {
      // 如果都沒有，嘗試獲取定位位置
      // ignore: avoid_print
      print('[MapViewController] 沒有定位位置和初始位置，嘗試獲取定位...');
      await _getCurrentLocation();
      
      if (currentPosition.value != null) {
        startPosition = currentPosition.value;
        // ignore: avoid_print
        print('[MapViewController] 定位成功，使用定位位置作為起點');
      } else if (initialPosition.value != null) {
        startPosition = initialPosition.value;
        // ignore: avoid_print
        print('[MapViewController] 定位失敗，使用初始位置作為起點');
      } else {
        routeError.value = '無法取得定位位置，請先設定初始位置或確認定位權限已開啟';
        return;
      }
    }

    await _executeRoutePlanning(
      startPosition!,
      homePosition.value!,
      notFoundMessage: '無法找到路徑，請確認起終點位置是否在路網範圍內',
    );
  }


  // 清除路徑
  void clearRoute() {
    routeResult.value = null;
    routeError.value = null;
    routeCameraLocations.clear();
    cameraDisplayMode.value = CameraDisplayMode.all;
    _lastPlannedStart = null;
    _lastPlannedEnd = null;
    _refreshCameraDisplayItems();
  }

  // 調整地圖視角以顯示完整路徑
  void _adjustMapViewToRoute(List<LatLng> path) {
    if (path.isEmpty) return;

    // 計算路徑的邊界
    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLng = path.first.longitude;
    double maxLng = path.first.longitude;

    for (final point in path) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // 計算中心點
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    mapCenter.value = LatLng(centerLat, centerLng);
    _lastCameraCenter = mapCenter.value;
    mapController.move(mapCenter.value, mapZoom.value);
  }
}

