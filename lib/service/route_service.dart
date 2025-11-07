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

  /// 計算加權成本
  double get weightedCost {
    final baseCost = travelTime ?? length;
    return baseCost * securityCostFactor;
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
    final est = diag / 200; // 對角的1/200作為搜索半徑
    return est.clamp(500, 5000);
  }

  /// 取得上次匹配的最近節點（起/終點）
  (LatLng?, LatLng?) get lastNearestNodes => (_lastNearestStart, _lastNearestEnd);

  /// 使用 Dijkstra 算法規劃最短路徑（考慮安全權重）
  RouteResult? planRoute(LatLng start, LatLng end) {
    if (_graph == null) {
      return null;
    }

    final radius = _configuredSearchRadiusMeters ?? _adaptiveSearchRadiusMeters();
    final startNodeId = _graph!.findNearestNode(start, maxDistanceMeters: radius);
    final endNodeId = _graph!.findNearestNode(end, maxDistanceMeters: radius);

    if (startNodeId == null || endNodeId == null) {
      return null;
    }

    // 保存 debug 最近節點座標
    _lastNearestStart = _graph!.nodes[startNodeId]?.latLng;
    _lastNearestEnd = _graph!.nodes[endNodeId]?.latLng;

    // Dijkstra 算法
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final unvisited = <String>{};
    final visited = <String>{};

    // 初始化
    for (final nodeId in _graph!.nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
      unvisited.add(nodeId);
    }
    distances[startNodeId] = 0.0;

    // 主循環
    while (unvisited.isNotEmpty) {
      // 找到未訪問節點中距離最小的
      String? currentNodeId;
      double minDistance = double.infinity;
      for (final nodeId in unvisited) {
        if (distances[nodeId]! < minDistance) {
          minDistance = distances[nodeId]!;
          currentNodeId = nodeId;
        }
      }

      if (currentNodeId == null || minDistance == double.infinity) {
        break; // 無法到達終點
      }

      if (currentNodeId == endNodeId) {
        break; // 已到達終點
      }

      unvisited.remove(currentNodeId);
      visited.add(currentNodeId);

      // 更新鄰接節點的距離
      final neighbors = _graph!.getNeighbors(currentNodeId);
      for (final edge in neighbors) {
        if (visited.contains(edge.toNodeId)) {
          continue;
        }

        final alt = distances[currentNodeId]! + edge.weightedCost;
        if (alt < distances[edge.toNodeId]!) {
          distances[edge.toNodeId] = alt;
          previous[edge.toNodeId] = currentNodeId;
        }
      }
    }

    // 重建路徑
    if (distances[endNodeId] == double.infinity) {
      return null; // 無法找到路徑
    }

    final pathNodeIds = <String>[];
    String? current = endNodeId;
    while (current != null) {
      pathNodeIds.insert(0, current);
      current = previous[current];
    }

    // 轉換為座標點列表
    final path = pathNodeIds
        .map((id) => _graph!.nodes[id]!.latLng)
        .toList();

    // 計算統計資訊
    double totalCost = 0.0;
    double totalDistance = 0.0;
    int safeSegments = 0;
    int totalSegments = 0;

    for (int i = 0; i < pathNodeIds.length - 1; i++) {
      final fromId = pathNodeIds[i];
      final toId = pathNodeIds[i + 1];
      final neighbors = _graph!.getNeighbors(fromId);
      final edge = neighbors.firstWhere(
        (e) => e.toNodeId == toId,
        orElse: () => neighbors.first,
      );

      totalCost += edge.weightedCost;
      totalDistance += edge.length;
      totalSegments++;
      if (edge.securityCostFactor < 1.0) {
        safeSegments++;
      }
    }

    return RouteResult(
      path: path,
      totalCost: totalCost,
      totalDistance: totalDistance,
      safeSegments: safeSegments,
      totalSegments: totalSegments,
    );
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

