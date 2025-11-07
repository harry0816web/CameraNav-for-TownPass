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
          ClipRect(
            child: Obx(
              () => FlutterMap(
                mapController: controller.mapController,
                options: MapOptions(
                  initialCenter: controller.mapCenter.value,
                  initialZoom: controller.mapZoom.value,
                  minZoom: MapViewController.minMapZoom,
                  maxZoom: MapViewController.maxMapZoom,
                  onMapEvent: controller.onMapEvent,
                  onTap: (tapPosition, point) => controller.onMapTap(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.townpass.app',
                    maxZoom: 19,
                  ),
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
                  Obx(
                    () => MarkerLayer(
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
                        ...controller.cameraDisplayItems
                            .map(
                              (item) => Marker(
                                point: item.position,
                                width: item.isCluster ? 44 : 24,
                                height: item.isCluster ? 44 : 24,
                                child: Tooltip(
                                  message: item.isCluster
                                      ? '附近共有 ${item.cameras.length} 台監視器'
                                      : '${item.single.unit}\n${item.single.address}\n方向: ${item.single.direction}',
                                  child: item.isCluster
                                      ? CustomPaint(
                                          painter: _ClusterMarkerPainter(
                                            backgroundColor: TPColors.primary600.withOpacity(0.92),
                                            borderColor: TPColors.white,
                                            shadowColor: Colors.black38,
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.remove_red_eye,
                                                  size: 16,
                                                  color: TPColors.white,
                                                ),
                                                TPText(
                                                  '${item.cameras.length}',
                                                  style: TPTextStyles.caption,
                                                  color: TPColors.white,
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            color: TPColors.orange500.withOpacity(0.92),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: TPColors.white,
                                              width: 2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black38,
                                                blurRadius: 3,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.remove_red_eye,
                                            size: 16,
                                            color: TPColors.white,
                                          ),
                                        ),
                                ),
                              ),
                            )
                            .toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 120,
                          child: Container(
              width: 44,
              height: 200,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            decoration: BoxDecoration(
                color: TPColors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Obx(
                () => RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: controller.mapZoom.value.clamp(
                      MapViewController.minMapZoom,
                      MapViewController.maxMapZoom,
                    ),
                    min: MapViewController.minMapZoom,
                    max: MapViewController.maxMapZoom,
                    label: controller.mapZoom.value.toStringAsFixed(1),
                    onChanged: controller.onZoomSliderChanged,
                  ),
                ),
              ),
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
            left: 16,
            right: 16,
            bottom: 0,
            child: Obx(
              () => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: controller.controlsExpanded.value
                    ? _ExpandedControls(
                        key: const ValueKey('expandedControls'),
                        controller: controller,
                      )
                    : _CollapsedControls(
                        key: const ValueKey('collapsedControls'),
                        controller: controller,
                      ),
              ),
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

class _ClusterMarkerPainter extends CustomPainter {
  _ClusterMarkerPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.shadowColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 2), radius - 2, shadowPaint);

    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 2, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CollapsedControls extends StatelessWidget {
  const _CollapsedControls({super.key, required this.controller});

  final MapViewController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final bool isLocating = controller.isLoadingLocation.value;
        final bool isPlanning = controller.isPlanningRoute.value;
        final bool canNavigate = controller.initialPosition.value != null &&
            controller.homePosition.value != null;

        return Container(
          padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: TPColors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
              SizedBox(
                width: 120,
                child: _ActionButton(
                  label: isLocating ? '定位中...' : '定位',
                  icon: Icons.my_location,
                  color: TPColors.primary500,
                  onPressed:
                      isLocating ? null : () => controller.refreshCurrentLocation(),
                  isLoading: isLocating,
                  dense: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: isPlanning ? '規劃中...' : '從初始位置導航',
                  icon: Icons.directions,
                  color: TPColors.primary500,
                  onPressed: isPlanning || !canNavigate
                      ? null
                      : () => controller.planRouteFromInitialToHome(),
                  isLoading: isPlanning,
                  dense: true,
                ),
              ),
              if (controller.routeResult.value != null) ...[
                const SizedBox(width: 12),
                _CompactIconButton(
                  icon: Icons.clear,
                  tooltip: '清除路徑',
                  onPressed: controller.clearRoute,
                ),
              ],
              const SizedBox(width: 12),
              _CompactIconButton(
                icon: Icons.expand_less,
                tooltip: '展開控制項',
                onPressed: controller.toggleControlsExpanded,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpandedControls extends StatelessWidget {
  const _ExpandedControls({super.key, required this.controller});

  final MapViewController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final routeResult = controller.routeResult.value;
        final locationError = controller.locationError.value;
        final routeError = controller.routeError.value;
        final bool isLocating = controller.isLoadingLocation.value;
        final bool isPlanning = controller.isPlanningRoute.value;
        final bool canNavigate =
            controller.initialPosition.value != null && controller.homePosition.value != null;

    return Container(
          padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            color: TPColors.white.withOpacity(0.97),
            borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
          ),
        ],
      ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = constraints.maxWidth;
              const double spacing = 12;
              final double halfWidth = maxWidth >= 360
                  ? (maxWidth - spacing) / 2
                  : maxWidth;

              Widget sizedField(Widget child) => SizedBox(
                    width: maxWidth,
                    child: child,
                  );

              Widget half(Widget child) => SizedBox(
                    width: halfWidth,
                    child: child,
                  );

              final widgets = <Widget>[
                Align(
                  alignment: Alignment.topRight,
                  child: _CompactIconButton(
                    icon: Icons.expand_more,
                    tooltip: '收合控制項',
                    onPressed: controller.toggleControlsExpanded,
                  ),
                ),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    sizedField(_HomeAddressInputField(controller: controller)),
                    sizedField(_InitialAddressInputField(controller: controller)),
                    half(
                      _ActionButton(
                        label: '點地圖設回家',
                        icon: Icons.map,
                        color: TPColors.red500,
                        onPressed: () => controller.startSettingHomePosition(),
                      ),
                    ),
                    half(
                      _ActionButton(
                        label: '點地圖設初始',
                        icon: Icons.edit_location_alt,
                        color: TPColors.secondary500,
                        onPressed: () => controller.startSettingInitialPosition(),
                      ),
                    ),
                    half(
                      _ActionButton(
                        label: isLocating ? '定位中...' : '定位我的位置',
                        icon: Icons.my_location,
                        color: TPColors.primary500,
                        onPressed: isLocating
                            ? null
                            : () => controller.refreshCurrentLocation(),
                        isLoading: isLocating,
                      ),
                    ),
                    if (routeResult != null)
                      half(
                        _ActionButton(
                          label: '清除路徑',
                          icon: Icons.clear,
                          color: TPColors.grayscale600,
                          onPressed: controller.clearRoute,
                        ),
                      ),
                    sizedField(
                      _ActionButton(
                        label: isPlanning ? '規劃中...' : '從初始位置導航',
                        icon: Icons.directions,
                        color: TPColors.primary500,
                        onPressed: isPlanning || !canNavigate
                            ? null
                            : () => controller.planRouteFromInitialToHome(),
                        isLoading: isPlanning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _WeightSection(controller: controller),
              ];

              if (routeResult != null) {
                widgets
                  ..add(const SizedBox(height: 12))
                  ..add(_RouteStatsCard(result: routeResult));
              }

              if (locationError != null) {
                widgets
                  ..add(const SizedBox(height: 12))
                  ..add(
                    _InfoBanner(
                      color: TPColors.orange500,
                      icon: Icons.location_off,
                      message: locationError,
                      onClose: () => controller.locationError.value = null,
                    ),
                  );
              }

              if (routeError != null) {
                widgets
                  ..add(const SizedBox(height: 12))
                  ..add(
                    _InfoBanner(
                      color: TPColors.red500,
                      icon: Icons.error_outline,
                      message: routeError,
                      onClose: () => controller.routeError.value = null,
                    ),
                  );
              }

              return Column(
        mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widgets,
              );
            },
          ),
        );
      },
    );
  }
}

class _WeightSection extends StatelessWidget {
  const _WeightSection({required this.controller});

  final MapViewController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const TPText(
                '路徑權重',
            style: TPTextStyles.bodySemiBold,
            color: TPColors.grayscale800,
          ),
              TPText(
                controller.safetyPreferenceLabel,
                style: TPTextStyles.bodyRegular,
                color: TPColors.grayscale600,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 12,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
              showValueIndicator: ShowValueIndicator.always,
            ),
            child: Slider(
              value: controller.safetyPreference.value,
              min: 0,
              max: 1,
              divisions: 10,
              label: controller.safetyPreference.value.toStringAsFixed(2),
              onChanged: controller.onSafetyWeightChanged,
              onChangeEnd: controller.onSafetyWeightChangeEnd,
              activeColor: TPColors.primary500,
              inactiveColor: TPColors.grayscale300,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              TPText(
                '距離優先',
                style: TPTextStyles.caption,
                color: TPColors.grayscale500,
              ),
              TPText(
                '安全優先',
                style: TPTextStyles.caption,
                color: TPColors.grayscale500,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.message,
    this.onClose,
  });

  final Color color;
  final IconData icon;
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: TPColors.white, size: 20),
          const SizedBox(width: 8),
              Expanded(
            child: TPText(
              message,
              style: TPTextStyles.bodyRegular,
              color: TPColors.white,
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: TPColors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.isLoading = false,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final double height = dense ? 44 : 48;
    final ButtonStyle style = ElevatedButton.styleFrom(
      elevation: 0,
      minimumSize: Size(0, height),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 16,
        vertical: dense ? 10 : 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      foregroundColor: TPColors.white,
    ).copyWith(
      backgroundColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.disabled)
            ? color.withOpacity(0.4)
            : color,
      ),
    );

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: style,
      child: isLoading
          ? SizedBox(
              width: dense ? 16 : 18,
              height: dense ? 16 : 18,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(TPColors.white),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
      children: [
                Icon(icon, size: dense ? 18 : 20, color: TPColors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: TPText(
          label,
          style: TPTextStyles.bodySemiBold,
                    color: TPColors.white,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 24,
        icon: Icon(icon, color: TPColors.grayscale600),
      ),
    );
  }
}

