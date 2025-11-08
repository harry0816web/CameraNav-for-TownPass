import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

class GeoLocatorService extends GetxService {
  Future<GeoLocatorService> init() async {
    return this;
  }

  Future<Position> position() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('未開啟定位服務');
    }

    // Test if location services are enabled.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('使用者未允許定位權限');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error('使用者未允許定位權限（永久），無法取得定位資訊');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    // 使用較高的精度設定以獲得更好的定位準確性
    // 強制使用GPS定位，避免使用網絡定位（可能不準確）
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
      forceAndroidLocationManager: false, // 使用新的Fused Location Provider
    );
  }

  /// 檢查位置是否在台灣範圍內
  /// 台灣大致範圍：緯度 21.9-25.3, 經度 119.3-122.0
  static bool isLocationInTaiwan(double latitude, double longitude) {
    const double taiwanMinLat = 21.9;
    const double taiwanMaxLat = 25.3;
    const double taiwanMinLng = 119.3;
    const double taiwanMaxLng = 122.0;
    
    return latitude >= taiwanMinLat && 
           latitude <= taiwanMaxLat && 
           longitude >= taiwanMinLng && 
           longitude <= taiwanMaxLng;
  }
}
