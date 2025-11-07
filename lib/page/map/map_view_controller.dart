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
      if (cameraDisplayMode.value == CameraDisplayMode.route) {
        cameraDisplayMode.value = CameraDisplayMode.all;
      }
      _refreshCameraDisplayItems();
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

    if (cameraDisplayMode.value == CameraDisplayMode.route && routeCameraLocations.isEmpty) {
      cameraDisplayMode.value = CameraDisplayMode.all;
    }
    _refreshCameraDisplayItems();
  }

  void _refreshCameraDisplayItems() {
    final allSource = visibleCameraLocations;
    if (allSource.isEmpty) {
      cameraDisplayItems.clear();
      return;
    }
    LatLngBounds? bounds;
    try {
      bounds = mapController.camera.visibleBounds;
    } catch (_) {
      bounds = null;
    }
    final filtered = bounds == null
        ? List<CameraLocation>.from(allSource)
        : allSource
            .where((camera) => bounds!.contains(camera.position))
            .toList(growable: false);

    final source = filtered.isEmpty ? allSource : filtered;

    final clusters = _clusterCameraLocations(source, mapZoom.value);
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
      final result = _routeService.planRoute(
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
      final result = _routeService.planRoute(
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
      currentPosition.value = LatLng(position.latitude, position.longitude);
      mapCenter.value = currentPosition.value!;
      locationError.value = null; // 清除錯誤訊息
    } catch (error) {
      // 如果無法取得位置，保持預設的台北市位置
      final errorMessage = error.toString();
      print('無法取得當前位置: $errorMessage');
      
      // 設置友好的錯誤訊息
      if (errorMessage.contains('未開啟定位服務')) {
        locationError.value = '定位服務未開啟\n請在模擬器中設置模擬位置：\nFeatures > Location > Custom Location';
      } else if (errorMessage.contains('未允許定位權限')) {
        locationError.value = '定位權限未允許\n請在設置中允許定位權限';
      } else {
        locationError.value = '無法取得位置：$errorMessage\n\n模擬器用戶：請設置模擬位置\nFeatures > Location > Custom Location';
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
          initialAddressTextController.clear();
          isSearchingAddress.value = false;
          return;
        }
      }

      // 使用 OpenStreetMap Nominatim API 進行地址解析
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1&addressdetails=1';
      
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
            initialAddressTextController.clear();
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
          addressTextController.clear();
          isSearchingAddress.value = false;
          return;
        }
      }

      // 使用 OpenStreetMap Nominatim API 進行地址解析
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1&addressdetails=1';
      
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
            addressTextController.clear();
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

  // 規劃路徑（從初始位置到回家位置）
  Future<void> planRouteFromInitialToHome() async {
    if (initialPosition.value == null) {
      routeError.value = '請先設定初始位置';
      return;
    }
    if (homePosition.value == null) {
      routeError.value = '請先設定回家位置';
      return;
    }
    await _executeRoutePlanning(
      initialPosition.value!,
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

