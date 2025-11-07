"""
將 GraphML 格式的路網圖形轉換為 JSON 格式，供 Flutter 應用使用

使用方法：
1. 確保已安裝 networkx 和 osmnx
2. 執行此腳本，將 taipei_with_security.graphml 轉換為 JSON

python export_graph_to_json.py
"""

import json
import os
import osmnx as ox
import networkx as nx


def export_graph_to_json(graph_path, output_path):
    """
    將 GraphML 格式的圖形導出為 JSON 格式
    
    Args:
        graph_path: GraphML 文件路徑
        output_path: 輸出 JSON 文件路徑
    """
    print(f"載入圖形: {graph_path}")
    G = ox.load_graphml(graph_path)
    
    nodes = []
    edges = []
    
    # 導出節點
    print("導出節點...")
    for node_id, data in G.nodes(data=True):
        # OSMnx 圖形中，節點通常有 'y' (緯度) 和 'x' (經度) 屬性
        # 如果沒有，嘗試從 'lat' 和 'lon' 獲取
        lat = data.get('y') or data.get('lat', 0)
        lon = data.get('x') or data.get('lon', 0)
        
        nodes.append({
            'id': str(node_id),
            'latitude': float(lat),
            'longitude': float(lon),
        })
    
    # 導出邊緣
    print("導出邊緣...")
    for u, v, k, data in G.edges(keys=True, data=True):
        edges.append({
            'from': str(u),
            'to': str(v),
            'length': float(data.get('length', 0)),
            'travel_time': float(data['travel_time']) if 'travel_time' in data else None,
            'security_cost_factor': float(data.get('security_cost_factor', 1.0)),
            'covered_by_cameras': int(data.get('covered_by_cameras', 0)),
        })
    
    graph_data = {
        'nodes': nodes,
        'edges': edges,
    }
    
    print(f"寫入 JSON 文件: {output_path}")
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(graph_data, f, ensure_ascii=False, indent=2)
    
    print(f"完成！")
    print(f"  節點數量: {len(nodes)}")
    print(f"  邊緣數量: {len(edges)}")


if __name__ == '__main__':
    # 輸入和輸出文件路徑
    input_graphml = 'taipei_with_security.graphml'
    output_json = 'taipei_with_security.json'
    
    if not os.path.exists(input_graphml):
        print(f"錯誤: 找不到文件 {input_graphml}")
        print("請確保已執行 create_camera_map.py 生成 GraphML 文件")
        exit(1)
    
    export_graph_to_json(input_graphml, output_json)
    print(f"\nJSON 文件已生成: {output_json}")
    print("請將此文件複製到 Flutter 項目的 assets/mock_data/ 目錄下")

