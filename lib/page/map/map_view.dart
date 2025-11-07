import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/page/map/map_view_controller.dart';
import 'package:town_pass/service/route_service.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

class MapView extends GetView<MapViewController> {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.white,
      appBar: TPAppBar(
        title: '回家ㄉ路',
        actions: [
          Obx(
            () => controller.settingMode.value.isNotEmpty
                ? TextButton(
                    onPressed: () => controller.cancelSettingMode(),
                    child: const TPText(
                      '取消',
                      style: TPTextStyles.bodySemiBold,
                      color: TPColors.primary500,
                    ),
                  )
                : const SizedBox(width: 56),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 地圖
          Obx(
            () => FlutterMap(
              options: MapOptions(
                initialCenter: controller.mapCenter.value,
                initialZoom: 15.0,
                minZoom: 10.0,
                maxZoom: 18.0,
                onTap: (tapPosition, point) => controller.onMapTap(point),
              ),
              children: [
                // OSM 圖磚層
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.townpass.app',
                  maxZoom: 19,
                ),
                // 路徑線條層
                Obx(
                  () => controller.routeResult.value != null
                      ? PolylineLayer<LatLng>(
                          polylines: [
                            Polyline<LatLng>(
                              points: controller.routeResult.value!.path,
                              strokeWidth: 5.0,
                              color: TPColors.primary500,
                            ),
                          ],
                        )
                      : const PolylineLayer<LatLng>(polylines: []),
                ),
                // 標記層
                MarkerLayer(
                  markers: [
                    // 當前位置標記
                    if (controller.currentPosition.value != null)
                      Marker(
                        point: controller.currentPosition.value!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: TPColors.primary500,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: TPColors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    // 初始位置標記
                    if (controller.initialPosition.value != null)
                      Marker(
                        point: controller.initialPosition.value!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: TPColors.secondary500,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.place,
                            color: TPColors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    // 回家位置標記
                    if (controller.homePosition.value != null)
                      Marker(
                        point: controller.homePosition.value!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: TPColors.red500,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.home,
                            color: TPColors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    // Debug: 匹配到的最近節點
                    if (controller.debugShowNearestNodes.value)
                      ...controller.debugNearestNodes
                          .map(
                            (p) => Marker(
                              point: p,
                              width: 16,
                              height: 16,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: TPColors.orange500.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  ],
                ),
              ],
            ),
          ),
          // 設定模式提示
          Obx(
            () => controller.settingMode.value.isNotEmpty
                ? Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: TPColors.primary500,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TPText(
                        '請點擊地圖設定回家位置',
                        style: TPTextStyles.bodySemiBold,
                        color: TPColors.white,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 控制按鈕
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 重新定位按鈕
                Obx(
                  () => FloatingActionButton.extended(
                    onPressed: controller.isLoadingLocation.value
                        ? null
                        : () => controller.refreshCurrentLocation(),
                    backgroundColor: TPColors.primary500,
                    icon: controller.isLoadingLocation.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(TPColors.white),
                            ),
                          )
                        : const Icon(Icons.my_location, color: TPColors.white),
                    label: const TPText(
                      '定位我的位置',
                      style: TPTextStyles.bodySemiBold,
                      color: TPColors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 回家位置輸入框
              _HomeAddressInputField(controller: controller),
                const SizedBox(height: 12),
              // 初始位置輸入框
              _InitialAddressInputField(controller: controller),
              const SizedBox(height: 12),
                // 或點擊地圖設定回家位置
                Obx(
                  () => _SettingButton(
                    icon: Icons.map,
                    label: controller.settingMode.value == 'home'
                        ? '點擊地圖設定'
                        : '點擊地圖設定回家位置',
                    onTap: () => controller.startSettingHomePosition(),
                    color: TPColors.red500,
                  ),
                ),
                const SizedBox(height: 12),
              // 或點擊地圖設定初始位置
              Obx(
                () => _SettingButton(
                  icon: Icons.edit_location_alt,
                  label: controller.settingMode.value == 'initial'
                      ? '點擊地圖設定'
                      : '點擊地圖設定初始位置',
                        onTap: () => controller.startSettingInitialPosition(),
                        color: TPColors.secondary500,
                ),
              ),
              const SizedBox(height: 12),
                // 導航按鈕組
                Obx(
                  () => Row(
                    children: [
                    // Debug 切換
                    IconButton(
                      onPressed: () => controller.debugShowNearestNodes.value = !controller.debugShowNearestNodes.value,
                      icon: Icon(
                        controller.debugShowNearestNodes.value ? Icons.visibility : Icons.visibility_off,
                        color: controller.debugShowNearestNodes.value ? TPColors.orange500 : TPColors.grayscale600,
                      ),
                      tooltip: '顯示/隱藏匹配節點',
                    ),
                      Expanded(
                        child: _NavigationButton(
                          icon: Icons.navigation,
                          label: controller.isPlanningRoute.value
                              ? '規劃中...'
                              : '開始導航',
                          onTap: controller.isPlanningRoute.value
                              ? null
                              : () => controller.planRouteToHome(),
                          isLoading: controller.isPlanningRoute.value,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NavigationButton(
                        icon: Icons.directions,
                        label: controller.isPlanningRoute.value
                            ? '規劃中...'
                            : '從初始位置導航',
                        onTap: controller.isPlanningRoute.value
                            ? null
                            : (controller.initialPosition.value != null && controller.homePosition.value != null)
                                ? () => controller.planRouteFromInitialToHome()
                                : null,
                        isLoading: controller.isPlanningRoute.value,
                      ),
                    ),
                      if (controller.routeResult.value != null) ...[
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () => controller.clearRoute(),
                          icon: const Icon(Icons.clear, color: TPColors.grayscale600),
                          tooltip: '清除路徑',
                        ),
                      ],
                    ],
                  ),
                ),
                // 路徑統計資訊
                Obx(
                  () => controller.routeResult.value != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _RouteStatsCard(
                            result: controller.routeResult.value!,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // 定位錯誤訊息
                Obx(
                  () => controller.locationError.value != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TPColors.orange500,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_off,
                                      color: TPColors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TPText(
                                        controller.locationError.value!,
                                        style: TPTextStyles.bodyRegular,
                                        color: TPColors.white,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => controller.locationError.value = null,
                                      icon: const Icon(
                                        Icons.close,
                                        color: TPColors.white,
                                        size: 20,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // 路徑規劃錯誤訊息
                Obx(
                  () => controller.routeError.value != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TPColors.red500,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: TPColors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TPText(
                                    controller.routeError.value!,
                                    style: TPTextStyles.bodyRegular,
                                    color: TPColors.white,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => controller.routeError.value = null,
                                  icon: const Icon(
                                    Icons.close,
                                    color: TPColors.white,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAddressInputField extends StatelessWidget {
  const _HomeAddressInputField({required this.controller});

  final MapViewController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TPColors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Obx(
        () => TextField(
          controller: controller.addressTextController,
          enabled: !controller.isSearchingAddress.value,
          decoration: InputDecoration(
            hintText: '輸入地址或座標（例如：台北市信義區或 25.0330,121.5654）',
            hintStyle: TPTextStyles.bodyRegular.copyWith(
              color: TPColors.grayscale400,
            ),
            prefixIcon: controller.isSearchingAddress.value
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(TPColors.primary500),
                      ),
                    ),
                  )
                : const Icon(Icons.search, color: TPColors.grayscale600),
            suffixIcon: controller.homePosition.value != null
                ? IconButton(
                    icon: const Icon(Icons.clear, color: TPColors.grayscale600),
                    onPressed: () {
                      controller.clearHomePosition();
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: TPColors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TPTextStyles.bodyRegular.copyWith(
            color: TPColors.grayscale800,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              controller.setHomePositionFromAddress(value.trim());
            }
          },
        ),
      ),
    );
  }
}

class _InitialAddressInputField extends StatelessWidget {
  const _InitialAddressInputField({required this.controller});

  final MapViewController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TPColors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Obx(
        () => TextField(
          controller: controller.initialAddressTextController,
          enabled: !controller.isSearchingAddress.value,
          decoration: InputDecoration(
            hintText: '輸入初始位置地址或座標（例如：25.0330,121.5654）',
            hintStyle: TPTextStyles.bodyRegular.copyWith(
              color: TPColors.grayscale400,
            ),
            prefixIcon: controller.isSearchingAddress.value
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(TPColors.secondary500),
                      ),
                    ),
                  )
                : const Icon(Icons.search, color: TPColors.grayscale600),
            suffixIcon: controller.initialPosition.value != null
                ? IconButton(
                    icon: const Icon(Icons.clear, color: TPColors.grayscale600),
                    onPressed: () => controller.clearInitialPosition(),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: TPColors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TPTextStyles.bodyRegular.copyWith(
            color: TPColors.grayscale800,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              controller.setInitialPositionFromAddress(value.trim());
            }
          },
        ),
      ),
    );
  }
}

class _SettingButton extends StatelessWidget {
  const _SettingButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: TPColors.white, size: 20),
            const SizedBox(width: 8),
            TPText(
              label,
              style: TPTextStyles.bodySemiBold,
              color: TPColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isLoading,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: onTap != null ? TPColors.primary500 : TPColors.grayscale400,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(TPColors.white),
                ),
              )
            else
              Icon(icon, color: TPColors.white, size: 20),
            const SizedBox(width: 8),
            TPText(
              label,
              style: TPTextStyles.bodySemiBold,
              color: TPColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStatsCard extends StatelessWidget {
  const _RouteStatsCard({required this.result});

  final RouteResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TPColors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TPText(
            '路徑資訊',
            style: TPTextStyles.bodySemiBold,
            color: TPColors.grayscale800,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: '總距離',
                  value: '${(result.totalDistance / 1000).toStringAsFixed(1)} 公里',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: '安全路段',
                  value: '${result.safetyPercentage.toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TPText(
          label,
          style: TPTextStyles.caption,
          color: TPColors.grayscale600,
        ),
        const SizedBox(height: 4),
        TPText(
          value,
          style: TPTextStyles.bodySemiBold,
          color: TPColors.grayscale800,
        ),
      ],
    );
  }
}

