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
  /// 當權重高時，需要確保最大化安全路段數量，而不只是最小化加權成本
  double cost(double safetyPreference) {
    final baseCost = travelTime ?? length;
    final clampedPreference = safetyPreference.clamp(0.0, 1.0);
    final clampedSecurity = securityCostFactor.clamp(0.1, 1.0);
    
    // 當 preference = 0 時，完全不考慮安全權重（factor = 1.0）
    if (clampedPreference <= 0.0) {
      return baseCost;
    }
    
    // 當 preference = 1.0（最高安全）時，使用特殊處理：
    // 為了確保最安全路徑真正最大化安全路段數量，我們需要：
    // 1. 對不安全路段（securityCostFactor = 1.0）增加懲罰
    // 2. 對安全路段（securityCostFactor < 1.0）減少成本
    if (clampedPreference >= 0.95) {
      // 最高安全模式：大幅懲罰不安全路段，鼓勵選擇安全路段
      if (clampedSecurity >= 1.0) {
        // 不安全路段：增加大量成本（懲罰係數）
        return baseCost * 5.0; // 大幅增加不安全路段的成本
      } else {
        // 安全路段：減少成本（獎勵係數）
        // 安全係數越低（越安全），成本越低
        return baseCost * clampedSecurity * 0.8; // 安全路段成本降低
      }
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

  /// 找到在起點和終點直線連線上最近的節點
  /// 這可以避免從起點出發時繞大圈的問題
  /// 算法：選擇讓"起點->節點->終點"路徑長度最接近直線距離的節點
  String? findNearestNodeOnLine(
    LatLng start,
    LatLng end,
    double searchRadiusMeters,
  ) {
    if (nodes.isEmpty) return null;

    final distance = Distance();
    String? bestNodeId;
    double bestScore = double.infinity;

    // 計算起點到終點的直線距離
    final directDistance = distance.as(LengthUnit.Meter, start, end);
    
    // 如果起點和終點太接近，直接返回最近的節點
    if (directDistance < 10.0) {
      return findNearestNode(start, maxDistanceMeters: searchRadiusMeters);
    }

    // 在起點附近搜索節點
    for (final node in nodes.values) {
      final nodePoint = node.latLng;
      
      // 計算節點到起點的距離
      final distToStart = distance.as(
        LengthUnit.Meter,
        start,
        nodePoint,
      );

      // 只考慮在搜索半徑內的節點
      if (distToStart > searchRadiusMeters) continue;

      // 計算節點到終點的距離
      final distToEnd = distance.as(
        LengthUnit.Meter,
        nodePoint,
        end,
      );

      // 計算通過該節點的總路徑長度
      final pathViaNode = distToStart + distToEnd;
      
      // 計算路徑偏差（理想情況下應該接近 directDistance）
      final deviation = pathViaNode - directDistance;
      
      // 限制偏差：如果節點讓路徑變長太多（超過直線距離的50%），不考慮
      // 這可以過濾掉明顯繞遠的節點
      if (deviation > directDistance * 0.5) continue;
      
      // 進一步限制：節點應該在起點附近（不超過搜索半徑的80%）
      // 這確保我們選擇的節點確實靠近起點，不會選擇太遠的節點
      if (distToStart > searchRadiusMeters * 0.8) continue;

      // 評分系統：
      // 1. 優先選擇靠近起點的節點（避免繞遠路）
      // 2. 優先選擇路徑偏差小的節點（在直線方向上）
      // 權重：到起點距離（60%）+ 路徑偏差（40%）
      // 使用加權平均，讓兩個因素都重要
      final normalizedDistToStart = distToStart / searchRadiusMeters; // 歸一化到 0-1
      final normalizedDeviation = deviation / directDistance; // 歸一化偏差
      final score = normalizedDistToStart * 0.6 + normalizedDeviation * 0.4;

      if (score < bestScore) {
        bestScore = score;
        bestNodeId = node.id;
      }
    }

    // 如果沒找到合適的節點，回退到找最近的節點
    final result = bestNodeId ?? findNearestNode(start, maxDistanceMeters: searchRadiusMeters);
    
    if (result != null && bestNodeId != null) {
      final selectedNode = nodes[result]!;
      final distToStart = distance.as(LengthUnit.Meter, start, selectedNode.latLng);
      final distToEnd = distance.as(LengthUnit.Meter, selectedNode.latLng, end);
      final totalDistance = distance.as(LengthUnit.Meter, start, end);
      final pathViaNode = distToStart + distToEnd;
      final deviation = pathViaNode - totalDistance;
      // ignore: avoid_print
      print('[RouteGraph] 選擇直線路徑上的起點節點: ${result}');
      // ignore: avoid_print
      print('  到起點距離: ${distToStart.toStringAsFixed(1)}m, 路徑偏差: ${deviation.toStringAsFixed(1)}m');
    } else if (result != null) {
      // ignore: avoid_print
      print('[RouteGraph] 回退到最近節點作為起點: ${result}');
    }
    
    return result;
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

  /// 使用 Dijkstra 算法在本地圖形上規劃路徑
  /// 權重計算已整合在 edge.cost() 中，會根據 safetyPreference 調整
  Future<RouteResult?> planRouteWithGraph(
    LatLng start,
    LatLng end, {
    double safetyPreference = 0.0,
  }) async {
    if (_graph == null) {
      // ignore: avoid_print
      print('[RouteService] Graph not loaded, cannot plan route with graph');
      return null;
    }

    // 找到起點和終點的最近節點
    final searchRadius = _configuredSearchRadiusMeters ?? _adaptiveSearchRadiusMeters();
    
    // 優化起點選擇：找到在起點和終點直線連線上的最近節點
    // 這可以避免從起點出發時繞大圈的問題
    final startNodeId = _graph!.findNearestNodeOnLine(
      start,
      end,
      searchRadius,
    );
    
    // 終點使用傳統的最近節點查找
    final endNodeId = _graph!.findNearestNode(end, maxDistanceMeters: searchRadius);

    if (startNodeId == null || endNodeId == null) {
      // ignore: avoid_print
      print('[RouteService] Cannot find nearest nodes: start=${startNodeId != null}, end=${endNodeId != null}');
      return null;
    }

    if (startNodeId == endNodeId) {
      // 起點和終點在同一節點
      final node = _graph!.nodes[startNodeId]!;
      return RouteResult(
        path: [node.latLng],
        totalCost: 0.0,
        totalDistance: 0.0,
        safeSegments: 0,
        totalSegments: 0,
      );
    }

    // 記錄匹配的節點位置（用於除錯）
    _lastNearestStart = _graph!.nodes[startNodeId]!.latLng;
    _lastNearestEnd = _graph!.nodes[endNodeId]!.latLng;

    // Dijkstra 算法
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final visited = <String>{};
    final unvisitedDistances = <String, double>{}; // 未訪問節點的距離映射

    // 初始化
    for (final nodeId in _graph!.nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
      unvisitedDistances[nodeId] = double.infinity;
    }
    distances[startNodeId] = 0.0;
    unvisitedDistances[startNodeId] = 0.0;

    // 主要算法循環
    while (unvisitedDistances.isNotEmpty) {
      // 找到未訪問節點中距離最小的
      String? currentNodeId;
      double minDistance = double.infinity;
      for (final entry in unvisitedDistances.entries) {
        if (entry.value < minDistance) {
          minDistance = entry.value;
          currentNodeId = entry.key;
        }
      }

      if (currentNodeId == null || minDistance == double.infinity) break;
      unvisitedDistances.remove(currentNodeId);
      visited.add(currentNodeId);

      // 如果到達終點，提前退出
      if (currentNodeId == endNodeId) {
        break;
      }

      // 更新鄰居節點的距離
      final neighbors = _graph!.getNeighbors(currentNodeId);
      for (final edge in neighbors) {
        if (visited.contains(edge.toNodeId)) continue;

        final edgeCost = edge.cost(safetyPreference);
        final alt = distances[currentNodeId]! + edgeCost;

        if (alt < distances[edge.toNodeId]!) {
          distances[edge.toNodeId] = alt;
          previous[edge.toNodeId] = currentNodeId;
          unvisitedDistances[edge.toNodeId] = alt;
        }
      }
    }

    // 重建路徑
    if (distances[endNodeId] == double.infinity) {
      // ignore: avoid_print
      print('[RouteService] No path found from $startNodeId to $endNodeId');
      return null;
    }

    // 從終點回溯到起點
    final pathNodeIds = <String>[];
    String? currentNodeId = endNodeId;
    while (currentNodeId != null) {
      pathNodeIds.insert(0, currentNodeId);
      currentNodeId = previous[currentNodeId];
    }

    // 轉換為 LatLng 路徑
    final path = pathNodeIds.map((nodeId) => _graph!.nodes[nodeId]!.latLng).toList();

    // 計算路徑統計
    int safeSegments = 0;
    int totalSegments = 0;
    double totalDistance = 0.0;
    double totalCost = 0.0;
    final distance = const Distance();

    for (int i = 0; i < pathNodeIds.length - 1; i++) {
      final fromNodeId = pathNodeIds[i];
      final toNodeId = pathNodeIds[i + 1];
      
      // 找到對應的邊
      final neighbors = _graph!.getNeighbors(fromNodeId);
      RouteEdge? edge;
      for (final e in neighbors) {
        if (e.toNodeId == toNodeId) {
          edge = e;
          break;
        }
      }

      if (edge != null) {
        totalSegments++;
        if (edge.securityCostFactor < 1.0) {
          safeSegments++;
        }
        totalDistance += edge.length;
        totalCost += edge.cost(safetyPreference);
      } else {
        // 如果找不到邊，使用節點間距離
        final fromNode = _graph!.nodes[fromNodeId]!;
        final toNode = _graph!.nodes[toNodeId]!;
        final segmentLength = distance.as(
          LengthUnit.Meter,
          fromNode.latLng,
          toNode.latLng,
        );
        totalDistance += segmentLength;
        totalSegments++;
      }
    }

    // 計算安全路段百分比
    final safetyPercentage = totalSegments > 0 
        ? (safeSegments / totalSegments * 100) 
        : 0.0;
    
    // ignore: avoid_print
    print('[RouteService] Graph route planned:');
    // ignore: avoid_print
    print('  Distance: ${totalDistance.toStringAsFixed(1)}m');
    // ignore: avoid_print
    print('  Cost: ${totalCost.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('  Safe segments: $safeSegments/$totalSegments (${safetyPercentage.toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('  Safety preference: $safetyPreference');
    
    // 當安全偏好很高時，驗證安全路段百分比是否合理
    if (safetyPreference >= 0.9 && safetyPercentage < 50.0) {
      // ignore: avoid_print
      print('  ⚠️ 警告：高安全偏好但安全路段百分比較低，可能存在路網數據問題');
    }

    return RouteResult(
      path: path,
      totalCost: totalCost,
      totalDistance: totalDistance,
      safeSegments: safeSegments,
      totalSegments: totalSegments,
    );
  }

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

  /// 規劃路徑（優先使用本地圖形，否則回退到 OSRM API）
  /// 當有圖形數據時，使用 Dijkstra 算法根據安全權重進行路徑規劃
  /// 當沒有圖形數據時，使用 OSRM API 獲取候選路徑並評估監視器權重
  Future<RouteResult?> planRoute(
    LatLng start,
    LatLng end, {
    double safetyPreference = 1.0,
  }) async {
    // 如果有圖形數據，使用本地路徑規劃（權重在規劃時就考慮）
    if (_graph != null) {
      // ignore: avoid_print
      print('[RouteService] Using local graph with Dijkstra algorithm, safety preference: $safetyPreference');
      final result = await planRouteWithGraph(start, end, safetyPreference: safetyPreference);
      if (result != null) {
        return result;
      }
      // 如果本地規劃失敗，回退到 OSRM
      // ignore: avoid_print
      print('[RouteService] Local graph planning failed, falling back to OSRM API');
    }
    
    // 沒有圖形數據或本地規劃失敗時，使用 OSRM API
    // ignore: avoid_print
    print('[RouteService] Using OSRM API with safety preference: $safetyPreference');
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

