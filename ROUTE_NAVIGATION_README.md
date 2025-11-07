# 安全路徑導航功能使用指南

## 📋 概述

本功能實現了基於監視器覆蓋的安全路徑導航，能夠引導使用者從當前位置或初始位置導航到回家位置，並優先選擇有監視器覆蓋的安全路段。

## 🔧 設置步驟

### 1. 準備路網數據

首先，你需要使用 Python 腳本生成帶有安全權重的路網數據：

```bash
# 1. 執行 create_camera_map.py 生成 GraphML 文件
python create_camera_map.py

# 2. 將 GraphML 轉換為 JSON 格式（供 Flutter 使用）
python export_graph_to_json.py
```

這會生成 `taipei_with_security.json` 文件。

### 2. 將 JSON 文件添加到 Flutter 項目

將生成的 JSON 文件複製到 `assets/mock_data/` 目錄：

```bash
cp taipei_with_security.json assets/mock_data/
```

### 3. 更新 pubspec.yaml

確保 `pubspec.yaml` 中的 assets 配置包含該文件：

```yaml
flutter:
  assets:
    - assets/mock_data/
    - assets/image/
    - assets/svg/
```

### 4. 運行應用

```bash
flutter pub get
flutter run
```

## 🎯 功能說明

### 主要功能

1. **位置設定**
   - 設定初始位置（起點）
   - 設定回家位置（終點）
   - 自動獲取當前 GPS 位置

2. **路徑規劃**
   - 點擊「開始導航」按鈕
   - 系統會使用 Dijkstra 算法計算最短路徑
   - 優先選擇有監視器覆蓋的安全路段（安全成本因子較低）

3. **路徑顯示**
   - 在地圖上以藍色線條顯示規劃的路徑
   - 顯示路徑統計資訊（總距離、安全路段百分比）

### 安全權重說明

路徑規劃使用以下安全等級：

- **極高安全** (security_cost_factor = 0.1): 監視器正前方，FOV 範圍內
- **次級安全** (security_cost_factor = 0.3): 監視器側前方，90度範圍內
- **中等安全** (security_cost_factor = 0.7): 監視器後方，90-180度範圍
- **不安全** (security_cost_factor = 1.0): 未覆蓋路段

算法會優先選擇安全成本因子較低的路段，從而引導使用者走更安全的路徑。

## 📁 文件結構

```
lib/
├── service/
│   └── route_service.dart          # 路徑規劃服務（Dijkstra 算法）
├── page/
│   └── map/
│       ├── map_view.dart            # 地圖視圖
│       └── map_view_controller.dart # 地圖控制器
└── util/
    └── graphml_converter.dart       # GraphML 轉換工具

export_graph_to_json.py              # Python 轉換腳本
```

## 🔍 技術細節

### 路徑規劃算法

使用 **Dijkstra 最短路徑算法**，權重計算公式：

```
weighted_cost = base_cost × security_cost_factor
```

其中：
- `base_cost` = `travel_time`（優先）或 `length`（備用）
- `security_cost_factor` ∈ {0.1, 0.3, 0.7, 1.0}

### 數據格式

JSON 文件格式：

```json
{
  "nodes": [
    {
      "id": "node_id",
      "latitude": 25.0330,
      "longitude": 121.5654
    }
  ],
  "edges": [
    {
      "from": "node_id_1",
      "to": "node_id_2",
      "length": 100.5,
      "travel_time": 12.3,
      "security_cost_factor": 0.1,
      "covered_by_cameras": 2
    }
  ]
}
```

## ⚠️ 注意事項

1. **路網數據大小**：大型路網（>10萬邊緣）的 JSON 文件可能很大，建議：
   - 使用區域性路網（例如只包含特定區域）
   - 考慮使用後端 API 提供路徑規劃服務

2. **性能優化**：
   - 路徑規劃在後台線程執行，不會阻塞 UI
   - 對於大型路網，可以考慮使用 A* 算法替代 Dijkstra

3. **數據更新**：
   - 當監視器數據更新時，需要重新生成路網數據
   - 建議定期更新路網數據以反映最新的監視器配置

## 🐛 故障排除

### 問題：無法載入路網數據

**解決方案**：
- 確認 JSON 文件在 `assets/mock_data/` 目錄下
- 確認 `pubspec.yaml` 中已配置 assets
- 執行 `flutter pub get` 重新載入資源

### 問題：無法找到路徑

**解決方案**：
- 確認起終點位置在路網範圍內
- 檢查路網數據是否完整
- 確認起終點距離路網節點不超過 1000 公尺

### 問題：路徑規劃速度慢

**解決方案**：
- 考慮使用區域性子圖（只載入相關區域的路網）
- 優化路網數據結構
- 考慮使用後端 API 進行路徑規劃

## 📝 未來改進

1. **實時導航**：添加轉彎提示和語音導航
2. **多路徑選項**：提供多條路徑供使用者選擇
3. **路徑優化**：支持平衡距離和安全的參數調整
4. **離線地圖**：支持離線路徑規劃
5. **路徑分享**：支持分享路徑給他人

## 📞 支援

如有問題或建議，請聯繫開發團隊。

