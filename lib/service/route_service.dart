import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

/// 路網節點
class RouteNode {
  final String id;
  final double latitude;
  final double longitude;

  RouteNode({
    required this.id,
    required this.latitude,
    required this.longitude,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

/// 路網邊緣（道路段）
class RouteEdge {
  final String fromNodeId;
  final String toNodeId;
  final double length; // 路段長度（公尺）
  final double? travelTime; // 旅行時間（秒）
  final double securityCostFactor; // 安全成本因子 (0.1-1.0)
  final int coveredByCameras; // 覆蓋該路段的監視器數量

  RouteEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.length,
    this.travelTime,
    required this.securityCostFactor,
    required this.coveredByCameras,
  });

  /// 依據安全偏好計算加權成本
  /// 在權重偏低時使用極端非線性函數，最低時完全不考慮監視器權重
  double cost(double safetyPreference) {
    final baseCost = travelTime ?? length;
    final clampedPreference = safetyPreference.clamp(0.0, 1.0);
    final clampedSecurity = securityCostFactor.clamp(0.1, 1.0);
    
    // 當 preference = 0 時，完全不考慮安全權重（factor = 1.0）
    if (clampedPreference <= 0.0) {
      return baseCost;
    }
    
    // 在權重偏低時使用極端非線性函數（4次方），讓低權重時幾乎不考慮安全
    // 當 preference = 0.1 時，factor ≈ 0.9999（幾乎不考慮安全）
    // 當 preference = 0.3 時，factor ≈ 0.9919（幾乎不考慮安全）
    // 當 preference >= 0.5 時，使用較溫和的非線性（平方）
    double effectivePreference;
    if (clampedPreference < 0.5) {
      // 低權重時使用4次方，極端偏向距離
      effectivePreference = clampedPreference * clampedPreference * clampedPreference * clampedPreference;
    } else {
      // 高權重時使用平方，正常考慮安全
      effectivePreference = clampedPreference * clampedPreference;
    }
    
    final combinedFactor = (1 - effectivePreference) + effectivePreference * clampedSecurity;
    return baseCost * combinedFactor;
  }
}

/// 路網圖形
class RouteGraph {
  final Map<String, RouteNode> nodes;
  final Map<String, List<RouteEdge>> edges; // fromNodeId -> List<RouteEdge>

  RouteGraph({
    required this.nodes,
    required this.edges,
  });

  /// 獲取節點的所有鄰接邊緣
  List<RouteEdge> getNeighbors(String nodeId) {
    return edges[nodeId] ?? [];
  }

  /// 找到距離指定座標最近的節點
  String? findNearestNode(LatLng point, {double maxDistanceMeters = 1000}) {
    String? nearestId;
    double minDistance = double.infinity;
    final distance = Distance();

    for (final node in nodes.values) {
      final dist = distance.as(
        LengthUnit.Meter,
        point,
        node.latLng,
      );
      if (dist < minDistance && dist <= maxDistanceMeters) {
        minDistance = dist;
        nearestId = node.id;
      }
    }

    return nearestId;
  }

  /// 計算圖形邊界 [minLat, maxLat, minLng, maxLng]
  (double, double, double, double) bounds() {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final n in nodes.values) {
      if (n.latitude < minLat) minLat = n.latitude;
      if (n.latitude > maxLat) maxLat = n.latitude;
      if (n.longitude < minLng) minLng = n.longitude;
      if (n.longitude > maxLng) maxLng = n.longitude;
    }
    return (minLat, maxLat, minLng, maxLng);
  }
}

/// 路徑規劃結果
class RouteResult {
  final List<LatLng> path; // 路徑座標點列表
  final double totalCost; // 總成本
  final double totalDistance; // 總距離（公尺）
  final int safeSegments; // 安全路段數量
  final int totalSegments; // 總路段數量
  final double safetyPercentage; // 安全路段百分比

  RouteResult({
    required this.path,
    required this.totalCost,
    required this.totalDistance,
    required this.safeSegments,
    required this.totalSegments,
  }) : safetyPercentage = totalSegments > 0
            ? (safeSegments / totalSegments * 100)
            : 0.0;
}

/// 路徑規劃服務
class RouteService extends GetxService {
  RouteGraph? _graph;
  final RxBool isLoading = false.obs;
  double? _configuredSearchRadiusMeters;

  // Debug: 上次匹配到的最近節點
  LatLng? _lastNearestStart;
  LatLng? _lastNearestEnd;

  /// 初始化服務
  Future<RouteService> init() async {
    return this;
  }

  /// 載入路網圖形（從 JSON 或 GraphML 轉換後的數據）
  Future<void> loadGraph(Map<String, dynamic> graphData) async {
    isLoading.value = true;
    try {
      final nodesMap = <String, RouteNode>{};
      final edgesMap = <String, List<RouteEdge>>{};

      // 解析節點
      final nodesData = graphData['nodes'] as List<dynamic>;
      for (final nodeData in nodesData) {
        final node = RouteNode(
          id: nodeData['id'] as String,
          latitude: (nodeData['latitude'] as num).toDouble(),
          longitude: (nodeData['longitude'] as num).toDouble(),
        );
        nodesMap[node.id] = node;
      }

      // 解析邊緣
      final edgesData = graphData['edges'] as List<dynamic>;
      for (final edgeData in edgesData) {
        final edge = RouteEdge(
          fromNodeId: edgeData['from'] as String,
          toNodeId: edgeData['to'] as String,
          length: (edgeData['length'] as num).toDouble(),
          travelTime: edgeData['travel_time'] != null
              ? (edgeData['travel_time'] as num).toDouble()
              : null,
          securityCostFactor: (edgeData['security_cost_factor'] as num)
              .toDouble(),
          coveredByCameras: (edgeData['covered_by_cameras'] as num).toInt(),
        );

        edgesMap.putIfAbsent(edge.fromNodeId, () => []).add(edge);
      }

      _graph = RouteGraph(nodes: nodesMap, edges: edgesMap);

      // 載入完成後列印統計與邊界
      final nodeCount = nodesMap.length;
      final edgeCount = edgesMap.values.fold<int>(0, (p, e) => p + e.length);
      final (minLat, maxLat, minLng, maxLng) = _graph!.bounds();
      // ignore: avoid_print
      print('[RouteService] Graph loaded: nodes=$nodeCount edges=$edgeCount');
      // ignore: avoid_print
      print('[RouteService] Bounds: lat[$minLat, $maxLat], lng[$minLng, $maxLng]');
    } finally {
      isLoading.value = false;
    }
  }

  /// 設定最近節點搜尋半徑（公尺）。若不設定則使用自適應。
  void setSearchRadiusMeters(double? radius) {
    _configuredSearchRadiusMeters = radius;
  }

  /// 依據圖形密度自適應的搜尋半徑
  double _adaptiveSearchRadiusMeters() {
    if (_graph == null || _graph!.nodes.isEmpty) return 2000;
    final (minLat, maxLat, minLng, maxLng) = _graph!.bounds();
    final d = const Distance();
    final diag = d.as(
      LengthUnit.Meter,
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
    // 基於對角線長度粗略估算：城市級圖形給出較大半徑；加上下限/上限
    // 增加搜尋半徑以提高節點匹配準確性
    final est = diag / 150; // 對角的1/150作為搜索半徑（從1/200增加）
    return est.clamp(1000, 10000); // 提高下限和上限
  }

  /// 取得上次匹配的最近節點（起/終點）
  (LatLng?, LatLng?) get lastNearestNodes => (_lastNearestStart, _lastNearestEnd);

  /// 評估路徑的監視器覆蓋情況
  /// 返回 (安全路段數, 總路段數, 加權成本)
  (int, int, double) _evaluatePathSafety(
    List<LatLng> path,
    double safetyPreference,
  ) {
    if (_graph == null || path.length < 2) {
      return (0, 0, 0.0);
    }

    int safeSegments = 0;
    int totalSegments = 0;
    double totalWeightedCost = 0.0;
    final distance = const Distance();

    for (int i = 0; i < path.length - 1; i++) {
      final segmentStart = path[i];
      final segmentEnd = path[i + 1];
      final segmentLength = distance.as(
        LengthUnit.Meter,
        segmentStart,
        segmentEnd,
      );

      // 找到路段中點附近的路網邊緣
      final midPoint = LatLng(
        (segmentStart.latitude + segmentEnd.latitude) / 2,
        (segmentStart.longitude + segmentEnd.longitude) / 2,
      );

      // 搜尋附近的路網節點
      final radius = 50.0; // 50 公尺搜尋半徑
      final nearestNodeId = _graph!.findNearestNode(midPoint, maxDistanceMeters: radius);

      if (nearestNodeId != null) {
        // 找到該節點的鄰接邊緣，選擇最接近路段的邊緣
        final neighbors = _graph!.getNeighbors(nearestNodeId);
        RouteEdge? bestEdge;
        double minDistance = double.infinity;

        for (final edge in neighbors) {
          final toNode = _graph!.nodes[edge.toNodeId];
          if (toNode != null) {
            final edgeMidPoint = LatLng(
              (midPoint.latitude + toNode.latitude) / 2,
              (midPoint.longitude + toNode.longitude) / 2,
            );
            final dist = distance.as(LengthUnit.Meter, midPoint, edgeMidPoint);
            if (dist < minDistance) {
              minDistance = dist;
              bestEdge = edge;
            }
          }
        }

        if (bestEdge != null) {
          totalSegments++;
          if (bestEdge.securityCostFactor < 1.0) {
            safeSegments++;
          }
          // 計算加權成本
          final baseCost = bestEdge.travelTime ?? segmentLength;
          final clampedPreference = safetyPreference.clamp(0.0, 1.0);
          final clampedSecurity = bestEdge.securityCostFactor.clamp(0.1, 1.0);
          
          double effectivePreference;
          if (clampedPreference < 0.5) {
            effectivePreference = clampedPreference *
                clampedPreference *
                clampedPreference *
                clampedPreference;
          } else {
            effectivePreference = clampedPreference * clampedPreference;
          }
          
          final combinedFactor = (1 - effectivePreference) + effectivePreference * clampedSecurity;
          totalWeightedCost += baseCost * combinedFactor;
        } else {
          // 如果找不到匹配的邊緣，使用原始距離
          totalSegments++;
          totalWeightedCost += segmentLength;
        }
      } else {
        // 如果找不到附近節點，使用原始距離
        totalSegments++;
        totalWeightedCost += segmentLength;
      }
    }

    return (safeSegments, totalSegments, totalWeightedCost);
  }

  /// 使用 OSRM API 規劃路徑（支援監視器權重評估）
  Future<RouteResult?> planRouteWithOSRM(
    LatLng start,
    LatLng end, {
    double safetyPreference = 0.0,
  }) async {
    try {
      // 使用 OSRM 的公開 API（免費，但有限制）
      // 格式：{lon1},{lat1};{lon2},{lat2}
      // 總是獲取多條候選路徑以評估監視器覆蓋（即使權重為 0，也獲取多條路徑以選擇最短的）
      final alternatives = 3; // 獲取最多 3 條候選路徑
      final url = 'http://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&alternatives=$alternatives';
      
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.add('User-Agent', 'TownPass/1.0');
        final response = await request.close();

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final Map<String, dynamic> data = jsonDecode(responseBody);

          if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
            final routes = (data['routes'] as List<dynamic>).cast<Map<String, dynamic>>();
            
            // 評估所有候選路徑並選擇最佳
            // 如果有路網數據，評估監視器覆蓋；否則選擇最短距離
            RouteResult? bestResult;
            double bestScore = double.infinity;

            for (final route in routes) {
              final geometry = route['geometry'] as Map<String, dynamic>;
              final coordinates = geometry['coordinates'] as List<dynamic>;
              
              // 轉換 GeoJSON 座標格式 [lon, lat] 為 LatLng
              final path = coordinates
                  .map((coord) {
                    final coordList = coord as List<dynamic>;
                    return LatLng(
                      coordList[1] as double, // lat
                      coordList[0] as double, // lon
                    );
                  })
        .toList();

              final distance = (route['distance'] as num).toDouble();
              final duration = (route['duration'] as num).toDouble();

    int safeSegments = 0;
    int totalSegments = 0;
              double score;

              // 如果有路網數據，評估監視器覆蓋
              if (_graph != null) {
                final (safe, total, weightedCost) =
                    _evaluatePathSafety(path, safetyPreference);
                safeSegments = safe;
                totalSegments = total;
                // 當權重為 0 時，使用距離作為分數；否則使用加權成本
                score = safetyPreference <= 0.0 ? distance : weightedCost;
              } else {
                // 沒有路網數據時，使用距離作為分數
                totalSegments = (distance / 50).ceil().clamp(1, 1000);
                score = distance;
              }

              // ignore: avoid_print
              print('[RouteService] OSRM route candidate:');
              // ignore: avoid_print
              print('  Distance: ${distance.toStringAsFixed(1)}m');
              // ignore: avoid_print
              print('  Duration: ${duration.toStringAsFixed(1)}s');
              if (_graph != null && totalSegments > 0) {
                // ignore: avoid_print
                print('  Safe segments: $safeSegments/$totalSegments');
              }
              // ignore: avoid_print
              print('  Score: ${score.toStringAsFixed(2)}');

              if (score < bestScore) {
                bestScore = score;
                bestResult = RouteResult(
                  path: path,
                  totalCost: _graph != null && safetyPreference > 0.0
                      ? score
                      : duration,
                  totalDistance: distance,
                  safeSegments: safeSegments,
                  totalSegments: totalSegments > 0
                      ? totalSegments
                      : (distance / 50).ceil().clamp(1, 1000),
                );
              }
            }

            if (bestResult != null) {
              // ignore: avoid_print
              print('[RouteService] Selected best OSRM route with score: ${bestScore.toStringAsFixed(2)}');
              return bestResult;
            }

            // 如果沒有找到最佳路徑（不應該發生），返回 null
            // ignore: avoid_print
            print('[RouteService] Failed to select best route from candidates');
            return null;
          } else {
            // ignore: avoid_print
            print('[RouteService] OSRM returned no route: ${data['code']}');
            return null;
          }
        } else {
          // ignore: avoid_print
          print('[RouteService] OSRM API error: ${response.statusCode}');
          return null;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RouteService] OSRM API exception: $e');
      return null;
    }
  }

  /// 使用 OSRM API 規劃路徑並評估監視器權重
  /// 所有權重值都使用 OSRM API 作為基礎，確保路徑正確
  Future<RouteResult?> planRoute(
    LatLng start,
    LatLng end, {
    double safetyPreference = 1.0,
  }) async {
    // 所有權重值都使用 OSRM API 作為基礎，確保路徑正確
    // 然後根據監視器權重評估並選擇最佳路徑
    // ignore: avoid_print
    print('[RouteService] Using OSRM API with safety preference: $safetyPreference');
    // 設置最近節點為實際起點和終點（OSRM 不需要匹配節點）
    _lastNearestStart = start;
    _lastNearestEnd = end;
    return await planRouteWithOSRM(start, end, safetyPreference: safetyPreference);
  }

  /// 檢查圖形是否已載入
  bool get isGraphLoaded => _graph != null;

  /// 取得統計與邊界資訊（提供除錯）
  ({int nodeCount, int edgeCount, double minLat, double maxLat, double minLng, double maxLng})? get graphStats {
    if (_graph == null) return null;
    final nodeCount = _graph!.nodes.length;
    final edgeCount = _graph!.edges.values.fold<int>(0, (p, e) => p + e.length);
    final (minLat, maxLat, minLng, maxLng) = _graph!.bounds();
    return (nodeCount: nodeCount, edgeCount: edgeCount, minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }
}

