# 前端與陪伴精靈 API 對接規格說明書 (fromendConnectcompanion.md)

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

後端經過意圖分析與對話重組後，會回傳極簡化的 **HTTP status 200** JSON 資料（僅保留 5 個前端 UI 繪製與狀態感知關鍵欄位，已剔除所有後端內部偵錯欄位）。

### 1. 回傳資料範例 (Success 200 OK)

#### 範例 A：飲食紀錄意圖 (`intent_category == "meal_record"`)
```json
{
  "success": true,
  "companion_reply": "幫你整理好早餐的「2個蛋餅與1杯無糖豆漿」草稿囉！蛋餅提供了優質碳水與蛋白質，無糖豆漿更是極佳的植物蛋白來源。整體熱量適中，是相當均衡的早餐選擇喔！✨",
  "intent_category": "meal_record",
  "meal_records": [
    {
      "meal_period": "早餐",
      "meal_items": [
        { "name": "蛋餅", "quantity": 2, "unit": "個" },
        { "name": "無糖豆漿", "quantity": 1, "unit": "杯" }
      ]
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
  "meal_records": [],
  "dietary_agent_error": null
}
```

#### 範例 C：飲食諮詢降級處理 (Dietary Agent 連線失敗)
```json
{
  "success": true,
  "companion_reply": "我知道你想了解這道餐點，但我目前暫時連不上專業營養數據庫，稍後再試試看喔！",
  "intent_category": "dish_advice",
  "meal_records": [],
  "dietary_agent_error": "Dietary Agent API connection refused (503)"
}
```

---

## 🧩 四、 前端核心 5 大欄位處理指南 (Frontend Handling Guide)

| 欄位名稱 | 型別 | 預設/正常值 | 說明與前端 UI 處理建議 |
| :--- | :--- | :--- | :--- |
| **`success`** | `Boolean` | `true` | 代表 Companion Agent 後端處理成功與否。 |
| **`companion_reply`** | `String` | 對話文字 | **【聊天氣泡內容】** 精靈經過溫馨重組後的對話，**直接顯示於聊天氣泡中**。 |
| **`intent_category`** | `String` | `"general"` 等 | **【UI 邏輯切換】** 意圖分類：`meal_record` (紀錄飲食), `dish_advice` (諮詢建議), `general` (閒聊)。 |
| **`meal_records`** | `Array` | `[]` | **【草稿卡片數據】** 飲食紀錄草稿陣列。僅當 `intent_category == "meal_record"` 時會有內容。 |
| **`dietary_agent_error`** | `String?` | `null` | **【微服務降級標記】** 若 Dietary Agent 正常則為 `null`；若 Dietary Agent 異常掛掉則傳回錯誤訊息，前端可據此顯示提示或進行紀錄。 |

### 飲食紀錄草稿卡片 (Draft Card) 的前端處理流程：
1. 當 `intent_category == "meal_record"` 且 `meal_records` 不為空時：
2. 前端畫出「草稿預覽卡片」（一餐期一張卡片），顯示餐期（早餐/午餐/晚餐/其他）、餐點名稱、數量與單位。
3. 使用者確認無誤點擊「確認儲存」後，由前端直接發送儲存請求至後端持久化 API：`POST /dietary-record/save`。

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
      List<dynamic> mealRecords = data['meal_records'] ?? [];
      String? dietaryAgentError = data['dietary_agent_error'];

      if (success) {
        // 1. 顯示精靈對話文字於聊天氣泡
        print('精靈回覆: $replyText');

        // 2. 若 Dietary Agent 有連線錯誤，可記錄或微幅提示
        if (dietaryAgentError != null) {
          print('警告：飲食助理降級運行 ($dietaryAgentError)');
        }

        // 3. 若為飲食紀錄意圖且包含草稿，彈出確認卡片 UI
        if (intent == 'meal_record' && mealRecords.isNotEmpty) {
          // TODO: 觸發前端彈出飲食草稿確認卡片 (Draft Card)
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
**修改目的**：新增與 Companion Agent 後端 Port 3000 發送對話的端點方法。

**修改內容**：
1. 匯入 `api_config.dart`：
   ```dart
   import '../config/api_config.dart';
   ```
2. 在 `sendCompanionUserPrompt` 方法中將對話 API 連線位址切換為 Port 3000：
   ```dart
   Future<Map<String, dynamic>> sendCompanionUserPrompt(String userPrompt) async {
     final normalizedPrompt = userPrompt.trim();
     if (normalizedPrompt.isEmpty) {
       return {'success': false, 'message': 'User prompt cannot be empty.'};
     }

     final token = await _token();
     try {
       // 使用 ApiConfig.companionBaseUrl 組裝 Port 3000 的完整 URL
       final response = await _client.post(
         '${ApiConfig.companionBaseUrl}/companion/ask',
         {'user_prompt': normalizedPrompt},
         headers: {
           if (token != null) 'Authorization': 'Bearer $token',
         },
       );

       if (response.statusCode == 200) {
         final data = jsonDecode(response.body);
         return {
           'success': data['success'] ?? true,
           'companion_reply': data['companion_reply'] ?? '',
           'intent_category': data['intent_category'] ?? 'general_chat',
           'meal_records': data['meal_records'] ?? [],
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
**修改目的**：將首頁對話輸入框點擊傳送後的處理邏輯，由舊有的單純週分析切換為呼叫 `DietService().sendCompanionUserPrompt(text)`，並即時渲染精靈回覆。

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
    
    // 提取陪伴精靈回應文字 companion_reply 並渲染至聊天氣泡
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
*文件更新時間：2026-08-10 (已同步更新前端全套 4 大修改檔案紀錄與精簡版 API 頂層 Response 解析邏輯)*


