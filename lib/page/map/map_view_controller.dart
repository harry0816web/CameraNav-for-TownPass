import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/route_service.dart';
import 'package:town_pass/util/graphml_converter.dart';

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

  static const String _keyInitialPosition = 'map_initial_position';
  static const String _keyHomePosition = 'map_home_position';
  
  // 路網數據文件路徑（需要在 assets 中配置）
  static const String _graphDataPath = 'assets/mock_data/taipei_with_security.json';

  @override
  void onInit() {
    super.onInit();
    _loadSavedPositions();
    _getCurrentLocation();
    _loadRouteGraph();
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

    if (!_routeService.isGraphLoaded) {
      routeError.value = '路網數據未載入，無法規劃路徑';
      return;
    }

    isPlanningRoute.value = true;
    routeError.value = null;

    try {
      final result = _routeService.planRoute(
        currentPosition.value!,
        homePosition.value!,
      );

      if (result == null) {
        routeError.value = '無法找到路徑，請確認起終點位置是否在路網範圍內';
      } else {
        routeResult.value = result;
        // 調整地圖視角以顯示完整路徑
        _adjustMapViewToRoute(result.path);
        // 收集 debug 最近節點
        final (s, e) = _routeService.lastNearestNodes;
        debugNearestNodes
          ..clear()
          ..addAll([if (s != null) s, if (e != null) e]);
      }
    } catch (e) {
      routeError.value = '路徑規劃失敗: $e';
    } finally {
      isPlanningRoute.value = false;
    }
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
    if (!_routeService.isGraphLoaded) {
      routeError.value = '路網數據未載入，無法規劃路徑';
      return;
    }

    isPlanningRoute.value = true;
    routeError.value = null;

    try {
      final result = _routeService.planRoute(
        initialPosition.value!,
        homePosition.value!,
      );

      if (result == null) {
        routeError.value = '無法找到路徑，請確認起終點位置是否在路網範圍內';
      } else {
        routeResult.value = result;
        _adjustMapViewToRoute(result.path);
        final (s, e) = _routeService.lastNearestNodes;
        debugNearestNodes
          ..clear()
          ..addAll([if (s != null) s, if (e != null) e]);
      }
    } catch (e) {
      routeError.value = '路徑規劃失敗: $e';
    } finally {
      isPlanningRoute.value = false;
    }
  }


  // 清除路徑
  void clearRoute() {
    routeResult.value = null;
    routeError.value = null;
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
  }
}

