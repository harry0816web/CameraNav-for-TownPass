import 'dart:convert';
import 'package:flutter/services.dart';

/// GraphML 轉換工具
/// 
/// 這個工具用於將 Python 生成的 GraphML 文件轉換為 Flutter 可用的 JSON 格式
/// 
/// 使用方式：
/// 1. 將 Python 生成的 `taipei_with_security.graphml` 放在 `assets/` 目錄下
/// 2. 使用 `convertGraphMLToJson()` 轉換為 JSON
/// 3. 將 JSON 保存到 `assets/` 目錄
/// 
/// 注意：由於 GraphML 解析複雜，建議在 Python 端直接輸出 JSON 格式
/// 可以修改 `create_camera_map.py` 添加 JSON 輸出功能
class GraphMLConverter {
  /// 從 GraphML 文件轉換為 JSON（簡化版，建議在 Python 端直接輸出 JSON）
  static Future<Map<String, dynamic>> convertGraphMLToJson(
    String graphmlPath,
  ) async {
    // 注意：完整的 GraphML 解析需要 XML 解析庫
    // 這裡提供一個簡化的轉換邏輯框架
    // 建議在 Python 端直接輸出 JSON 格式
    
    final graphmlContent = await rootBundle.loadString(graphmlPath);
    
    // TODO: 實現 GraphML XML 解析
    // 由於 GraphML 是 XML 格式，需要解析：
    // - <node> 標籤：提取 id, lat, lon
    // - <edge> 標籤：提取 source, target, 以及屬性（length, travel_time, security_cost_factor, covered_by_cameras）
    
    throw UnimplementedError(
      'GraphML 解析需要 XML 解析庫。建議在 Python 端直接輸出 JSON 格式。',
    );
  }

  /// 從 JSON 文件載入路網數據
  static Future<Map<String, dynamic>> loadGraphFromJson(
    String jsonPath,
  ) async {
    final jsonContent = await rootBundle.loadString(jsonPath);
    return jsonDecode(jsonContent) as Map<String, dynamic>;
  }
}

/// Python 端 JSON 輸出格式範例
/// 
/// 建議在 `create_camera_map.py` 中添加以下函數來輸出 JSON：
/// 
/// ```python
/// import json
/// 
/// def export_graph_to_json(G, output_path):
///     nodes = []
///     edges = []
///     
///     # 導出節點
///     for node_id, data in G.nodes(data=True):
///         nodes.append({
///             'id': str(node_id),
///             'latitude': data.get('y', 0),
///             'longitude': data.get('x', 0),
///         })
///     
///     # 導出邊緣
///     for u, v, k, data in G.edges(keys=True, data=True):
///         edges.append({
///             'from': str(u),
///             'to': str(v),
///             'length': data.get('length', 0),
///             'travel_time': data.get('travel_time'),
///             'security_cost_factor': data.get('security_cost_factor', 1.0),
///             'covered_by_cameras': data.get('covered_by_cameras', 0),
///         })
///     
///     graph_data = {
///         'nodes': nodes,
///         'edges': edges,
///     }
///     
///     with open(output_path, 'w', encoding='utf-8') as f:
///         json.dump(graph_data, f, ensure_ascii=False, indent=2)
/// ```
/// 
/// 然後在 `integrate_fov_with_network` 函數最後調用：
/// ```python
/// export_graph_to_json(G_proj, "taipei_with_security.json")
/// ```

