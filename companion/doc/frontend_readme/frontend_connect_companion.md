# 前端與陪伴精靈 API 對接規格說明書 (frontendConnectcompanion.md)

本文件專為前端開發人員編寫，詳細說明前端（Flutter / Web / App）如何與 **Companion Agent（陪伴精靈後端服務）** 進行 API 對接、發送使用者訊息、解析回傳資料以及各端口（Endpoints）的配置規範。

---

## 📍 一、 服務端口與位址配置 (Port & Server Configuration)

| 項目 | 預設定值 | 說明 |
| :--- | :--- | :--- |
| **預設 Port** | `3000` | 可透過環境變數 `COMPANION_API_PORT` 修改 |
| **Base URL** | `http://<COMPANION_HOST>:3000` | 本地測試通常為 `http://localhost:3000` |
| **對話主要端點** | `/companion/ask` | 處理使用者對話、意圖分析與對話生成的主端點 (POST) |
| **健康檢查端點** | `/health` | 用於測試伺服器是否正常運作 (GET) |

---

## 📩 二、 前端如何發送訊息？ (Request Specifications)

前端需向 `/companion/ask` 發送 **HTTP POST** 請求。

### 1. HTTP 請求標頭 (Headers)
```http
Content-Type: application/json
Authorization: Bearer <JWT_TOKEN>
```
* **`Content-Type`**: 必須為 `application/json`。
* **`Authorization`**: *(可選但建議)* 若使用者已登入，請帶上 Bearer Token，後端將自動轉發以取得個人資料或飲食紀錄。

### 2. Request Body (JSON 格式)
```json
{
  "user_prompt": "我今天早餐吃了兩個蛋餅和一杯無糖豆漿，這樣熱量會太高嗎？"
}
```

| 欄位名稱 | 型別 | 必填 | 說明 |
| :--- | :--- | :--- | :--- |
| `user_prompt` | `String` | **是** | 使用者在前端聊天視窗輸入的原始文字內容（不可為空字串）。 |

---

## 📤 三、 後端回傳哪些資料？ (Response Specifications)

後端經過意圖分析與對話重組後，會回傳極簡化的 **HTTP status 200** JSON 資料（包含 5 個前端 UI 繪製、意圖分類與狀態感知關鍵欄位）。
在 **Companion Agent (v6)** 版本中，飲食草稿採用高效能一維陣列 **`meal_items`**（包含 `meal_period` 欄位），以確保 LLM 解析與輸出穩定度。

### 1. 回傳資料範例 (Success 200 OK)

#### 範例 A：飲食紀錄意圖 (`intent_category == "meal_record"`)
```json
{
  "success": true,
  "companion_reply": "幫你整理好早餐的「2個蛋餅與1杯無糖豆漿」草稿囉！蛋餅提供了優質碳水與蛋白質，無糖豆漿更是極佳的植物蛋白來源。整體熱量適中，是相當均衡的早餐選擇喔！✨",
  "intent_category": "meal_record",
  "meal_items": [
    {
      "name": "蛋餅",
      "quantity": 2,
      "unit": "個",
      "meal_period": "早餐"
    },
    {
      "name": "無糖豆漿",
      "quantity": 1,
      "unit": "杯",
      "meal_period": "早餐"
    }
  ],
  "dietary_agent_error": null
}
```

#### 範例 B：飲食諮詢成功 (`intent_category == "dish_advice"`)
```json
{
  "success": true,
  "companion_reply": "大麥克套餐的熱量大約落在 800~1000 大卡之間，若想控制熱量，建議將飲料替換為無糖綠茶或黑咖啡喔！",
  "intent_category": "dish_advice",
  "meal_items": [],
  "dietary_agent_error": null
}
```

#### 範例 C：飲食諮詢降級處理 (Dietary Agent 連線失敗)
```json
{
  "success": true,
  "companion_reply": "我知道你想了解這道餐點，但我目前暫時連不上專業營養數據庫，稍後再試試看喔！",
  "intent_category": "dish_advice",
  "meal_items": [],
  "dietary_agent_error": "Dietary Agent API connection refused (503)"
}
```

---

## 🧩 四、 前端核心 5 大欄位與資料轉化處理指南 (Frontend Handling Guide)

| 欄位名稱 | 型別 | 預設/正常值 | 說明與前端 UI 處理建議 |
| :--- | :--- | :--- | :--- |
| **`success`** | `Boolean` | `true` | 代表 Companion Agent 後端處理成功與否。 |
| **`companion_reply`** | `String` | 對話文字 | **【聊天氣泡內容】** 精靈經過溫馨重組後的對話，**直接顯示於聊天氣泡中**。 |
| **`intent_category`** | `String` | `"general"` 等 | **【UI 邏輯切換】** 意圖分類：`meal_record` (紀錄飲食), `dish_advice` (諮詢建議), `general` (閒聊)。 |
| **`meal_items`** | `Array` | `[]` | **【後端一維草稿數據】** Companion Agent 回傳的一維飲食項目陣列 `[{ name, quantity, unit, meal_period }]`。僅當 `intent_category == "meal_record"` 時會有內容。 |
| **`dietary_agent_error`** | `String?` | `null` | **【微服務降級標記】** 若 Dietary Agent 正常則為 `null`；若 Dietary Agent 異常掛掉則傳回錯誤訊息，前端可據此顯示提示或進行紀錄。 |

### 💡 飲食紀錄草稿 (meal_items -> meal_records) 前端處理流程：
1. Companion Agent 後端傳回一維陣列 `meal_items`（含 `meal_period`）。
2. 前端 `DietService` 在接收到 Response 後，自動將 `meal_items` 按 `meal_period` 進行 `Group By` 轉化，組裝出 2D 巢狀陣列 `meal_records`（`[{ meal_period, meal_items: [...] }]`）。
3. 當 `intent_category == "meal_record"` 且轉化後的 `meal_records` 不為空時：
4. 前端 `home_view.dart` 自動彈出「草稿預覽卡片」對話視窗 (`_showMealRecordDraftDialog`)，按餐期（早餐/午餐/晚餐/其他）展示卡片與項目。
5. 使用者確認無誤點擊「確認儲存」後，由前端發送儲存請求至後端持久化 API：`POST /dietary-record/save`。

---

## ⚠️ 五、 異常與錯誤狀態碼處理 (Error Handling)

當 HTTP 狀態碼非 200 時，後端會回傳統一格式的錯誤物件：

### 1. `400 Bad Request` (請求格式錯誤)
* **原因**：未傳入 `user_prompt` 或 `user_prompt` 為空字串。
```json
{
  "success": false,
  "error_code": "BAD_REQUEST",
  "error_message": "The 'user_prompt' field is required and must be a non-empty string."
}
```

### 2. `502 Bad Gateway` (上游服務異常)
* **原因**：OpenAI API 通訊失敗。
```json
{
  "success": false,
  "error_code": "OPENAI_SERVICE_ERROR",
  "error_message": "Failed to communicate with OpenAI API. Please try again later."
}
```

### 3. `500 Internal Server Error` (伺服器內部錯誤)
```json
{
  "success": false,
  "error_code": "INTERNAL_SERVER_ERROR",
  "error_message": "An unexpected error occurred on the server."
}
```

---

## 💻 六、 前端發送與接收範例程式碼 (Flutter / Dart)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> sendUserPromptToCompanion(String userPrompt, String? authToken) async {
  final url = Uri.parse('http://localhost:3000/companion/ask');
  
  final headers = {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  final body = jsonEncode({
    'user_prompt': userPrompt,
  });

  try {
    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      bool success = data['success'] ?? false;
      String replyText = data['companion_reply'] ?? '';
      String intent = data['intent_category'] ?? 'general';
      List<dynamic> rawMealItems = data['meal_items'] ?? [];
      String? dietaryAgentError = data['dietary_agent_error'];

      if (success) {
        // 1. 顯示精靈對話文字於聊天氣泡
        print('精靈回覆: $replyText');

        // 2. 若 Dietary Agent 有連線錯誤，可記錄或微幅提示
        if (dietaryAgentError != null) {
          print('警告：飲食助理降級運行 ($dietaryAgentError)');
        }

        // 3. 按 meal_period 進行 Group By 轉化成 UI 彈窗相容之 meal_records 結構
        if (intent == 'meal_record' && rawMealItems.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> groupedMap = {};
          for (var item in rawMealItems) {
            if (item is Map) {
              final period = item['meal_period']?.toString().trim() ?? '其他';
              if (!groupedMap.containsKey(period)) {
                groupedMap[period] = [];
              }
              groupedMap[period]!.add({
                'name': item['name']?.toString() ?? '',
                'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
                'unit': item['unit']?.toString() ?? '',
              });
            }
          }

          final List<Map<String, dynamic>> mealRecords = groupedMap.entries.map((entry) {
            return {
              'meal_period': entry.key,
              'meal_items': entry.value,
            };
          }).toList();

          // TODO: 觸發前端彈出飲食草稿確認卡片 UI (_showMealRecordDraftDialog)
        }
      }
    } else {
      final errorData = jsonDecode(response.body);
      print('請求失敗 [${response.statusCode}]: ${errorData['error_message']}');
    }
  } catch (e) {
    print('網路請求異常: $e');
  }
}
```

---

## 🛠️ 七、 前端連線實際修改檔完整說明 (Frontend Modifications Log)

為實現 Flutter 前端與陪伴精靈 (Port 3000, `http://localhost:3000/companion/ask`) 的連線與 UI 渲染對接，**前端共針對以下 4 個檔案進行了更動**：

---

### 1. `lib/config/api_config.dart` (環境配置檔)
**修改目的**：新增 Companion Agent (Port 3000) 的 Base URL 動態配置。

**修改內容**：
在 `ApiConfig` 類別中新增 `companionBaseUrl` 靜態 Getter：

```dart
class ApiConfig {
  // 原有之主後端 API (Port 8080) 配置...
  static String get baseUrl { ... }

  /// 陪伴精靈 Companion Agent 的 Base URL (Port 3000)
  static String get companionBaseUrl {
    if (kIsWeb) {
      // 網頁瀏覽器 (Chrome / Edge)
      return 'http://localhost:3000';
    } else if (Platform.isAndroid) {
      // Android 模擬器 (使用 10.0.2.2 存取宿主電腦 localhost)
      return 'http://10.0.2.2:3000';
    } else {
      // 其他平台 (Windows 桌面版、iOS 模擬器)
      return 'http://localhost:3000';
    }
  }
}
```

---

### 2. `lib/core/api_client.dart` (網路請求封裝層)
**修改目的**：
1. 允許 `ApiClient` 傳入完整的 HTTP/HTTPS 網址，而不強制加上 `ApiConfig.baseUrl` (Port 8080) 前綴。
2. 避免當 Companion API 回傳 401/403 時誤觸發主後端的全域「登入過期/權限不足」彈跳視窗。

**修改內容**：
1. **跨網址相容**（`post`, `get`, `put`, `multipart`, `delete` 方法）：
   ```dart
   // 將原有的 Uri.parse('${ApiConfig.baseUrl}$path') 改為支援傳入完整網址：
   final url = path.startsWith('http') ? Uri.parse(path) : Uri.parse('${ApiConfig.baseUrl}$path');
   ```

2. **避開全域 401/403 攔截彈窗**（`_checkResponse` 方法）：
   ```dart
   void _checkResponse(http.Response response) {
     if (response.statusCode == 403 || response.statusCode == 401) {
       final requestUrl = response.request?.url.toString() ?? '';
       // 如果是陪伴精靈端點 (Port 3000 或 /companion/)，不跳出全域登入失敗彈窗，交由業務層處理
       if (requestUrl.contains(':3000') || requestUrl.contains('/companion/')) {
         return;
       }
       
       // 原有之 401/403 彈跳視窗邏輯...
     }
   }
   ```

---

### 3. `lib/services/diet_service.dart` (業務邏輯服務層)
**修改目的**：
1. 新增與 Companion Agent 後端 Port 3000 發送對話的端點方法。
2. 接收 Companion Agent (v6) 回傳之 `meal_items` 一維陣列，並按 `meal_period` 自動進行 `Group By` 轉化，組裝為前端 UI 彈窗相容之 `meal_records` 兩層巢狀陣列。

**修改內容**：
在 `sendCompanionUserPrompt` 方法中進行一維陣列解析與資料型態轉化：

```dart
Future<Map<String, dynamic>> sendCompanionUserPrompt(String userPrompt) async {
  final normalizedPrompt = userPrompt.trim();
  if (normalizedPrompt.isEmpty) {
    return {'success': false, 'message': 'User prompt cannot be empty.'};
  }

  final token = await _token();
  try {
    final response = await _client.post(
      '${ApiConfig.companionBaseUrl}/companion/ask',
      {'user_prompt': normalizedPrompt},
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> rawMealItems = data['meal_items'] ?? [];

      // 1. 將 Companion 一維平坦陣列 (1D) 按餐期 (meal_period) 自動進行 Group By 轉換
      final Map<String, List<Map<String, dynamic>>> groupedMap = {};
      for (var item in rawMealItems) {
        if (item is Map) {
          final period = item['meal_period']?.toString().trim() ?? '其他';
          if (!groupedMap.containsKey(period)) {
            groupedMap[period] = [];
          }
          groupedMap[period]!.add({
            'name': item['name']?.toString() ?? '',
            'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
            'unit': item['unit']?.toString() ?? '',
          });
        }
      }

      // 2. 組裝成前端 UI 彈窗現行相容的 meal_records 兩層巢狀陣列
      final List<Map<String, dynamic>> mealRecords = groupedMap.entries.map((entry) {
        return {
          'meal_period': entry.key,
          'meal_items': entry.value,
        };
      }).toList();

      return {
        'success': data['success'] ?? true,
        'companion_reply': data['companion_reply'] ?? '',
        'intent_category': data['intent_category'] ?? 'general_chat',
        'meal_items': rawMealItems,        // 保留原汁原味的一維陣列
        'meal_records': mealRecords,      // 前端 UI 現行彈窗立即可用之分組陣列
        'dietary_agent_error': data['dietary_agent_error'],
        'data': data,
      };
    }

    return {
      'success': false,
      'message': _errorMessage('Send companion prompt', response.statusCode, response.body),
    };
  } catch (e) {
    return {'success': false, 'message': 'Send companion prompt failed: $e'};
  }
}
```

---

### 4. `lib/views/home/home_view.dart` (首頁對話 UI 畫面)
**修改目的**：將首頁對話輸入框點擊傳送後的處理邏輯，由舊有的單純週分析切換為呼叫 `DietService().sendCompanionUserPrompt(text)`，並即時渲染精靈回覆與自動觸發飲食草稿彈窗。

**修改內容**：
在對話傳送處更新連線與 UI 狀態處理邏輯：

```dart
// 新增載入中狀態文字
_messages.add({
  'isElf': true,
  'text': '正在思考中...',
});
_scrollToBottom();

// 呼叫陪伴精靈 API
DietService().sendCompanionUserPrompt(text).then((res) {
  _showDogResponseThenIdle();
  setState(() {
    // 移除「正在思考中...」預載提示
    if (_messages.isNotEmpty && (_messages.last['text'] == '正在思考中...' || _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
      _messages.removeLast();
    }
    
    // 1. 提取陪伴精靈回應文字 companion_reply 並渲染至聊天氣泡
    final reply = res['companion_reply'] ?? (res['data'] is Map ? res['data']['companion_reply'] : null);
    if (res['success'] == true && reply != null && reply.toString().isNotEmpty) {
      _messages.add({
        'isElf': true,
        'text': reply.toString(),
      });
    } else {
      _messages.add({
        'isElf': true,
        'text': res['message'] ?? '讀取精靈回覆失敗，請稍後再試。',
      });
    }
  });

  // 2. 判斷意圖若為 meal_record 且含草稿，自動觸發飲食紀錄確認彈窗
  final intent = res['intent_category'] ?? '';
  final mealRecords = res['meal_records'] as List<dynamic>? ?? [];

  if (intent == 'meal_record' && mealRecords.isNotEmpty) {
    _showMealRecordDraftDialog(context, mealRecords, userPrompt: text);
  }

  _scrollToBottom();
}).catchError((e) {
  _showDogResponseThenIdle();
  setState(() {
    if (_messages.isNotEmpty && (_messages.last['text'] == '正在思考中...' || _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
      _messages.removeLast();
    }
    _messages.add({'isElf': true, 'text': '連線發生錯誤: $e'});
  });
  _scrollToBottom();
});
```

---
*文件更新時間：2026-08-23 17:53 (已同步對照 frontend_adjust.md 更新 Companion Agent (v6) 一維陣列 meal_items 結構與 DietService 轉化 meal_records 相容邏輯)*
