# 前端對接 Companion Agent 修改規劃說明書 (connect_frontend_to_companion.md)

> 本文件是 Companion Agent 的對接規格與實作備忘錄，不是服務程式碼；已由 `services/` 移至 `lib/文件/` 保存。內容中的行號、原始碼片段與批次狀態屬於歷史規劃，重新開發前必須以目前原始碼和後端契約重新驗證。

本文件依據專案外部的 `companion/doc/frontendConnectcompanion.md` 與 `connect.md` 規格撰寫；這兩份來源目前不在本 checkout，使用前需重新取得並驗證。**本文件僅作為改碼依據說明檔案，未經確認不會更動任何程式碼**。
以下詳細列出連線至 Companion Agent (Port 3000) 預計修改的 **4 個檔案**、**修改行號範圍**、**原程式碼與預計更動程式碼**，以及 **`meal_record` 飲食草稿彈窗 (Dialog) 互動與持久化儲存流程**。

## 文件待作清單

| 狀態 | 待作項目 | 優先度 | 實作難易度 |
| :--- | :--- | :--- | :--- |
| [ ] | 重新取得並確認外部 Companion 規格文件 | 優先度中 | 難易度簡單 |
| [ ] | 以目前 API 與 Dart 程式重新核對本文行號及程式碼片段 | 優先度中 | 難易度中 |
| [ ] | 確認 Companion 對話、飲食草稿與主後端寫入流程的資料契約 | 優先度中 | 難易度中 |

本文件是歷史對接說明，不是目前已核准的改碼清單；在上述確認完成前，不應直接依本文修改程式。

---

## 📁 修改檔案 1: `frontend/lib/config/api_config.dart`

* **檔案路徑**：[api_config.dart](../config/api_config.dart)
* **修改目的**：新增 Companion Agent 後端服務 (Port 3000) 的動態 Base URL 取得邏輯（相容 Web、Android 模擬器與桌面版）。

### 📍 修改位置與逐行程式碼對照：

**在第 31 行 `serverBaseUrl` 結束後、第 32 行 `}` 之前新增以下 Getter**：

```dart
  /// 陪伴精靈 Companion Agent 的 Base URL (Port 3000)
  static String get companionBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    } else {
      return 'http://localhost:3000';
    }
  }
```

---

## 📁 修改檔案 2: `frontend/lib/core/api_client.dart`

* **檔案路徑**：[api_client.dart](../core/api_client.dart)
* **修改目的**：
  1. 允許 `_resolveUrl` 接收完整 `http://` / `https://` 開頭的 URL，以便發送請求至 Port 3000。
  2. 調整 `_checkResponse`，當 Companion API (Port 3000 或 `/companion/`) 回傳 401/403 時不觸發全域強迫登出彈窗，改由業務層自行處理。

### 📍 修改位置 1: `_resolveUrl` 方法 (原第 15~21 行)

**原程式碼 (第 15~21 行)**：
```dart
15:   Uri _resolveUrl(String path) {
16:     final normalizedPath = path.startsWith('/') ? path : '/$path';
17:     final base = normalizedPath.startsWith('/dietary-agent/')
18:         ? ApiConfig.serverBaseUrl
19:         : ApiConfig.baseUrl;
20:     return Uri.parse('$base$normalizedPath');
21:   }
```

**預計替換程式碼**：
```dart
  Uri _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = normalizedPath.startsWith('/dietary-agent/')
        ? ApiConfig.serverBaseUrl
        : ApiConfig.baseUrl;
    return Uri.parse('$base$normalizedPath');
  }
```

---

### 📍 修改位置 2: `_checkResponse` 方法 (原第 255~264 行)

> 💡 **觀念解析：什麼是「全域登入過期彈窗」？為何需要避開？**
> 1. **全域彈窗機制**：`ApiClient` 原有的 `_checkResponse` 針對所有 API 請求，只要收到 `401 Unauthorized` (登入過期) 或 `403 Forbidden` (權限不足)，預設會透過全域 `navigatorKey` 在螢幕最上層彈出強迫登出的 `AlertDialog`，點擊「確定」後會清空登入 Session 並強制踢回登入頁 (`LoginPage`)。
> 2. **陪伴精靈獨立性**：Companion Agent (Port 3000) 為獨立執行的 AI 服務。若 Companion 服務連線失敗、伺服器未啟動或回應 401/403，我們希望僅在聊天視窗中顯示提示（如：「精靈暫時無法回應」），不應直接清除主後端 (Port 8080) 的使用者登入 Session，更不應將使用者強制踢回登入畫面。
> 3. **處置方式**：因此在此處過濾，若請求來自 Port 3000 或包含 `/companion/` 路徑，直接 `return` 繞過全域登出彈窗，交由前端對話 View 業務層自行處理錯誤提示。

**原程式碼 (第 255~264 行)**：
```dart
255:   void _checkResponse(http.Response response) {
256:     if (response.statusCode == 401 || response.statusCode == 403) {
257:       final context = navigatorKey.currentContext;
258:       if (context == null) {
259:         return;
260:       }
261: 
262:       final requestUrl = response.request?.url.path ?? '';
263:       final isLogin = requestUrl.contains('/login');
```

**預計替換程式碼**：
```dart
  void _checkResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      final requestUrlStr = response.request?.url.toString() ?? '';
      // 若為陪伴精靈端點 (Port 3000 或 /companion/)，不跳出全域登入過期彈窗
      if (requestUrlStr.contains(':3000') || requestUrlStr.contains('/companion/')) {
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) {
        return;
      }

      final requestUrl = response.request?.url.path ?? '';
      final isLogin = requestUrl.contains('/login');
```

---

## 📁 修改檔案 3: `frontend/lib/services/diet_service.dart`

* **檔案路徑**：[diet_service.dart](../services/diet_service.dart)
* **修改目的**：
  1. 匯入 `api_config.dart`。
  2. 新增與 MAF Workflow (`POST /maf/ask`) 發送對話的 service 方法 `sendCompanionUserPrompt`。

### 📍 修改位置 1: 檔案頂點 import 區塊 (第 1~6 行)

**原程式碼 (第 5~6 行)**：
```dart
5: import '../core/api_client.dart';
6: import '../utils/profile_value_mapper.dart';
```

**預計替換程式碼**：
```dart
import '../config/api_config.dart';
import '../core/api_client.dart';
import '../utils/profile_value_mapper.dart';
```

---

### 📍 修改位置 2: 新增 `sendCompanionUserPrompt` 方法 (置於 `DietService` 類別內)

**預計新增程式碼**：
```dart
  /// 發送使用者訊息至 MAF Workflow (Port 3001 /maf/ask)
  Future<Map<String, dynamic>> sendCompanionUserPrompt(String userPrompt) async {
    final normalizedPrompt = userPrompt.trim();
    if (normalizedPrompt.isEmpty) {
      return {'success': false, 'message': 'User prompt cannot be empty.'};
    }

    final token = await _token();
    try {
      final response = await _client.post(
        '${ApiConfig.companionBaseUrl}/maf/ask',
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
          'intent_category': data['intent_category'] ?? 'general',
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

### 📍 修改位置 3: 重構 `createDietRecord` 參數為 3 大核心必填欄位 (`dishName`, `mealType`, `amount`)

* **修改目的**：
  明確定義新增飲食紀錄的核心 3 大必填欄位：
  1. **`dishName`** (`required String dishName`)：餐點名稱（如：`蛋餅`）
  2. **`mealType`** (`required String mealType`)：餐期（如：`早餐`）
  3. **`amount`** (`required String amount`)：數量/份量（將原本可選的 `portions` 改名為必填的 `amount`，如：`2 個`）
  4. 將 `description` 調整為可選欄位（預設 `String description = ''`）。

**原程式碼 (第 120~127 行)**：
```dart
120:   Future<Map<String, dynamic>> createDietRecord({
121:     required String dishName,
122:     required String mealType,
123:     required String description,
124:     String portions = '',
125:     String nutrition = '',
126:     DateTime? mealDate,
127:   }) async {
```

**預計替換程式碼**：
```dart
  /// 新增飲食紀錄 (3大核心必填欄位: dishName, mealType, amount)
  Future<Map<String, dynamic>> createDietRecord({
    required String dishName,
    required String mealType,
    required String amount,
    String description = '',
    String nutrition = '',
    DateTime? mealDate,
  }) async {
    final token = await _token();
    if (token == null) {
      return {'success': false, 'message': 'Please sign in again.'};
    }

    final parsedNutrition = _parseNutrition(nutrition);

    String apiMealType = _mealTypeForApi(mealType);
    String apiDescription = description;
    if (mealType == '其他' || mealType.trim().toUpperCase() == 'OTHER') {
      apiMealType = 'DINNER';
      apiDescription = '[MealType:OTHER]$description';
    }

    try {
      final response = await _client.post(
        '/diet-records',
        {
          'dishName': dishName,
          'mealType': apiMealType,
          'description': apiDescription,
          'portions': amount,
          'nutrition': nutrition,
          'calories': parsedNutrition['calories'],
          'protein': parsedNutrition['protein'],
          'fat': parsedNutrition['fat'],
          'carbohydrates': parsedNutrition['carbohydrates'],
          if (mealDate != null) 'date': _formatDate(mealDate),
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      // 💡 _decodeObject: 安全地將 HTTP 回傳的 JSON 字串解析為 Map 字典 (具防錯保護，避免非標準 JSON 導致 App 閃退)
      final data = _decodeObject(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final recordData = data['data'] ?? data;
        if (recordData is Map) {
          final desc = (recordData['description'] ?? '').toString();
          if (desc.startsWith('[MealType:OTHER]')) {
            final newRecord = Map<String, dynamic>.from(recordData);
            newRecord['mealType'] = 'OTHER';
            newRecord['description'] = desc.replaceFirst(
              '[MealType:OTHER]',
              '',
            );
            return {'success': true, 'data': newRecord};
          }
        }
        return {'success': true, 'data': recordData};
      }

      return {
        'success': false,
        'message': _errorMessage(
          'Create diet record',
          response.statusCode,
          response.body,
        ),
      };
    } catch (e) {
      return {'success': false, 'message': 'Create diet record failed: $e'};
    }
  }
```

* **關聯調用處隨之調整**：
  1. **`home_view.dart`** (草稿彈窗)：將 `portions: '$qty $unit'.trim()` 替換為 `amount: '$qty $unit'.trim()`，且可省略 `description` 或視需要傳入。
  2. **`manual_record_page.dart`** (第 190 行)：將傳參 `portions: ...` 替換為 `amount: ...`。

---

## 📁 修改檔案 4: `frontend/lib/views/home/home_view.dart`

* **檔案路徑**：[home_view.dart](../views/home/home_view.dart)
* **修改目的**：
  1. 將首頁對話面板的訊息傳送邏輯（`_handleMessage`），切換為呼叫 `DietService().sendCompanionUserPrompt(text)`，並將回傳的 `companion_reply` 渲染至精靈對話氣泡中。
  2. 新增 `intent_category == "meal_record"` 判斷，若包含草稿陣列則自動呼叫 `_showMealRecordDraftDialog()` 跳出飲食草稿確認卡片彈窗。

### 📍 修改位置 1: `_handleMessage` 方法中的 API 呼叫區塊 (原第 584~638 行)

**原程式碼 (第 584~638 行)**：
```dart
584:       DietService().askWeeklyAnalysis(text).then((res) {
585:         _showDogResponseThenIdle();
586:         setState(() {
587:           if (_messages.isNotEmpty && _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...') {
588:             _messages.removeLast();
589:           }
590:           
591:           if (res['success'] == true) {
592:             final payload = res['data'] ?? {};
593:             String answer = '';
594:             if (payload['answer'] != null) {
595:               answer = payload['answer'].toString();
596:             } else if (payload['message'] != null) {
597:               answer = payload['message'].toString();
598:             } else if (payload['partner_response'] != null) {
599:               final pr = payload['partner_response'];
600:               if (pr is Map && pr['answer'] != null) {
601:                 answer = pr['answer'].toString();
602:               } else if (pr is Map && pr['message'] != null) {
603:                 answer = pr['message'].toString();
604:               } else if (pr is Map && pr['response'] != null) {
605:                 answer = pr['response'].toString();
606:               } else {
607:                 answer = pr.toString();
608:               }
609:             } else {
610:               answer = '分析成功，但未取得回覆內容。';
611:             }
612: 
613:             _messages.add({
614:               'isElf': true,
615:               'text': answer,
616:             });
617:           } else {
618:             _messages.add({
619:               'isElf': true,
620:               'text': '飲食分析服務暫時無法使用，請稍後再試。',
621:             });
622:           }
623:         });
624:         _scrollToBottom(); // 新增：智能評估分析完成後滑到底部
625:       }).catchError((e) {
626:         _showDogResponseThenIdle();
627:         setState(() {
628:           if (_messages.isNotEmpty && _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...') {
629:             _messages.removeLast();
630:           }
631:           _messages.add({
632:             'isElf': true,
633:             'text': '飲食分析服務發生異常，請稍後再試。',
634:           });
635:         });
636:         _scrollToBottom(); // 新增：發生異常後滑到底部
637:       });
```

**預計替換程式碼**：
```dart
      DietService().sendCompanionUserPrompt(text).then((res) {
        _showDogResponseThenIdle();
        setState(() {
          if (_messages.isNotEmpty &&
              (_messages.last['text'] == '正在思考中...' ||
               _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
            _messages.removeLast();
          }

          final reply = res['companion_reply'] ??
              (res['data'] is Map ? res['data']['companion_reply'] : null);

          if (res['success'] == true && reply != null && reply.toString().isNotEmpty) {
            _messages.add({
              'isElf': true,
              'text': reply.toString(),
            });

            // 判斷意圖若為 meal_record 且含草稿，自動觸發飲食紀錄確認彈窗
            final intent = res['intent_category'] ?? '';
            final mealRecords = res['meal_records'] as List<dynamic>? ?? [];
            if (intent == 'meal_record' && mealRecords.isNotEmpty) {
              _showMealRecordDraftDialog(context, mealRecords);
            }
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
          if (_messages.isNotEmpty &&
              (_messages.last['text'] == '正在思考中...' ||
               _messages.last['text'] == '正在為您載入個人與週飲食紀錄，進行智能評估中...')) {
            _messages.removeLast();
          }
          _messages.add({
            'isElf': true,
            'text': '連線發生錯誤: $e',
          });
        });
        _scrollToBottom();
      });
```

---

## 🔔 累積擴充: UI 與彈窗互動層 — `meal_record` 意圖之前端可編輯草稿視窗 (Editable Draft Dialog) 完整設計

依據最新需求，當 Companion Agent 回傳 `intent_category == "meal_record"` 時，跳出的草稿確認視窗將由「唯讀預覽模式」提升為**「可編輯草稿模式 (Editable Draft Mode)」**。使用者可即時修正在彈窗上顯示有誤的欄位，最終以使用者修正後的數據寫入資料庫。

---

### 1. 欄位編輯實作方式說明 (Field Editing Specifications)

| 欄位 | 預設來源 | UI 編輯元件實作方式 | 資料同步機制 |
| :--- | :--- | :--- | :--- |
| **餐期 (Meal Period)** | Companion 解析 (如 `早餐`) | **下拉選單 (`DropdownButtonFormField<String>`)**<br>選項包含：`早餐`、`午餐`、`晚餐`、`其他`。 | 選擇新選單項目時，更新本地狀態中該餐期的 `meal_period` 數值。 |
| **餐點名稱 (Dish Name)** | Companion 解析 (如 `蛋餅`) | **可編輯單行輸入框 (`TextFormField`)**<br>以 `initialValue` 帶入初始名稱。 | 當 `onChanged` 觸發時，即時更新本地狀態中的 `item['name']`。 |
| **數量 (Quantity)** | Companion 解析 (如 `2`) | **`[-]` 與 `[+]` 計數按鈕組 (`IconButton Counter`)**<br>中間顯示數字，按 `-` 遞減（最小為 1），按 `+` 遞增。 | 按按鈕時更新本地狀態中的 `item['quantity']` 並調用 `setDialogState()`。 |
| **單位 (Unit)** | Companion 解析 (如 `個`) | **純文字展示 (`Text`)**<br>暫維持唯讀狀態（如需求所述）。 | 直接顯示原始單位字串。 |

---

### 2. 本地可變狀態維護與儲存流程 (State Management)

1. **狀態深拷貝 (Deep Copy)**：
   在 `_showMealRecordDraftDialog` 建立時，先將傳入的唯讀 `mealRecords` 深拷貝為一份可變動的本地 List：
   ```dart
   final List<Map<String, dynamic>> editableRecords = mealRecords.map((rec) {
     final items = (rec['meal_items'] as List<dynamic>? ?? []).map((item) {
       return {
         'name': item['name']?.toString() ?? '',
         'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
         'unit': item['unit']?.toString() ?? '',
       };
     }).toList();
     return {
       'meal_period': rec['meal_period']?.toString() ?? '早餐',
       'meal_items': items,
     };
   }).toList();
   ```

2. **持久化寫入 (Save to DB)**：
   點擊【確認儲存】時，遍歷這份**經使用者修改後的 `editableRecords`**，讀取最新修正之餐期、餐點名稱與數量，呼叫 `DietService().createDietRecord(...)` 寫入主後端資料庫。

---

### 2. 在 `_HomeViewState` 內預計新增之 `_showMealRecordDraftDialog` 方法程式碼

此可編輯版彈窗方法將替換原本 [home_view.dart](../views/home/home_view.dart) 的唯讀版本：

```dart
  /// 彈出「飲食紀錄草稿」可編輯確認視窗，允許使用者自行修正餐期、餐點名稱與數量
  void _showMealRecordDraftDialog(BuildContext context, List<dynamic> mealRecords) {
    // 1. 深拷貝為本地可變狀態，確保使用者修改不影響全域原數據
    final List<Map<String, dynamic>> editableRecords = mealRecords.map((rec) {
      final items = (rec['meal_items'] as List<dynamic>? ?? []).map((item) {
        return {
          'name': item['name']?.toString() ?? '',
          'quantity': int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
          'unit': item['unit']?.toString() ?? '',
        };
      }).toList();
      return {
        'meal_period': rec['meal_period']?.toString() ?? '早餐',
        'meal_items': items,
      };
    }).toList();

    const List<String> mealPeriodOptions = ['早餐', '午餐', '晚餐', '其他'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: AppColors.background,
              title: Row(
                children: const [
                  Icon(Icons.edit_note, color: AppColors.primary, size: 28),
                  SizedBox(width: 8),
                  Text(
                    '核對與修改飲食紀錄草稿',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '陪伴精靈已為您整理出以下飲食草稿啦~\n請確認紀錄是否正確\n修正完畢後，請按下確認儲存',
                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    ...editableRecords.asMap().entries.map((recEntry) {
                      final recIndex = recEntry.key;
                      final record = recEntry.value;
                      final currentPeriod = record['meal_period'].toString();
                      final items = record['meal_items'] as List<Map<String, dynamic>>;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. 可編輯餐期：下拉選單 (Dropdown)
                            Row(
                              children: [
                                const Text(
                                  '餐期：',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: mealPeriodOptions.contains(currentPeriod)
                                            ? currentPeriod
                                            : '早餐',
                                        isExpanded: true,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                        onChanged: isSaving
                                            ? null
                                            : (newPeriod) {
                                                if (newPeriod != null) {
                                                  setDialogState(() {
                                                    editableRecords[recIndex]['meal_period'] = newPeriod;
                                                  });
                                                }
                                              },
                                        items: mealPeriodOptions.map((period) {
                                          return DropdownMenuItem<String>(
                                            value: period,
                                            child: Text(period),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),

                            // 2. 餐點品項列表 (可編輯名稱與數量)
                            ...items.asMap().entries.map((itemEntry) {
                              final itemIndex = itemEntry.key;
                              final item = itemEntry.value;
                              final currentQty = item['quantity'] as int;
                              final unitStr = item['unit'].toString();

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    // (A) 餐點名稱可編輯輸入框
                                    Expanded(
                                      flex: 5,
                                      child: TextFormField(
                                        initialValue: item['name'].toString(),
                                        enabled: !isSaving,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          hintText: '餐點名稱',
                                        ),
                                        onChanged: (val) {
                                          editableRecords[recIndex]['meal_items'][itemIndex]['name'] = val;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // (B) 數量可加減計數按鈕 [-] 1 [+]
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: (isSaving || currentQty <= 1)
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    editableRecords[recIndex]['meal_items'][itemIndex]['quantity'] = currentQty - 1;
                                                  });
                                                },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: (currentQty <= 1 || isSaving)
                                                  ? Colors.grey.shade300
                                                  : AppColors.primary.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.remove, size: 16, color: AppColors.primary),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            '$currentQty',
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: isSaving
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    editableRecords[recIndex]['meal_items'][itemIndex]['quantity'] = currentQty + 1;
                                                  });
                                                },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: isSaving ? Colors.grey.shade300 : AppColors.primary.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.add, size: 16, color: AppColors.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),

                                    // (C) 單位展示（唯讀）
                                    Text(
                                      unitStr,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            // 核心儲存邏輯：讀取使用者修正後的最新 editableRecords
                            for (var record in editableRecords) {
                              final mealPeriod = record['meal_period']?.toString() ?? '早餐';
                              final items = record['meal_items'] as List<Map<String, dynamic>>;
                              for (var item in items) {
                                final name = item['name']?.toString().trim() ?? '';
                                final qty = item['quantity']?.toString() ?? '1';
                                final unit = item['unit']?.toString() ?? '';
                                if (name.isNotEmpty) {
                                  // =========================================================================
                                  // 【將飲食紀錄傳到後端資料庫的核心 API 呼叫】
                                  // 呼叫 DietService().createDietRecord(...) 發送 POST /api/
                                  // 將使用者最終確認修正後的餐點名稱 (dishName)、餐期 (mealType)、
                                  // 數量份量 (portions) 與紀錄時間 (mealDate) 持久化存入資料庫中。
                                  // =========================================================================
                                  await DietService().createDietRecord(
                                    dishName: name,
                                    mealType: mealPeriod,
                                    amount: '$qty $unit'.trim(),
                                    description: '陪伴精靈解析並經使用者核對修正',
                                    mealDate: DateTime.now(),
                                  );
                                }
                              }
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🎉 飲食紀錄已成功儲存！'),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            debugPrint('儲存飲食草稿失敗: $e');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('確認儲存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
```

---

## 🚀 階段性實作批次規劃總覽 (Batch Implementation Roadmap)

- **✅ 批次一 (已完成實作)**：基礎 API 連線與 Service 方法建置
  - **[api_config.dart](../config/api_config.dart)**：新增 `companionBaseUrl` 靜態 Getter。
  - **[api_client.dart](../core/api_client.dart)**：支援完整 URL 解析，並過濾對話端點全域登出彈窗。
  - **[diet_service.dart](../services/diet_service.dart)**：新增 `sendCompanionUserPrompt` 對接 `/maf/ask`。

- **✅ 批次二 (已完成實作)**：基礎 UI 與彈窗互動層對接
  - **[home_view.dart](../views/home/home_view.dart)**：`_handleMessage` 訊息發送、氣泡渲染與 `_showMealRecordDraftDialog` 基礎彈窗流程。

- **✅ 批次三 (待確認後執行)**：處理「可編輯草稿模式 (Editable Draft Mode)」
  - **目標檔案**：[home_view.dart](../views/home/home_view.dart)
  - **細節說明**：
    1. 將 `_showMealRecordDraftDialog` 升級為動態可編輯草稿彈窗。
    2. 加入親切語氣提示文字：`'陪伴精靈已為您整理出以下飲食草稿啦~\n請確認紀錄是否正確\n修正完畢後，請按下確認儲存'`。
    3. **餐期**：改為下拉選單 (`DropdownButtonHideUnderline` + `DropdownButton<String>`)，支援早餐/午餐/晚餐/其他。
    4. **餐點名稱**：改為單行輸入框 (`TextFormField`)，允許使用者輸入修正。
    5. **數量**：改為 `[-]`/`[+]` 動態計數按鈕組（最低限制為 1）。
    6. **單位**：保持純文字唯讀顯示。
    7. **本地狀態同步**：建立 `editableRecords` 深拷貝本地狀態，使用者修正時即時覆蓋狀態，按下「確認儲存」時讀取最新修正數據寫入 DB。

- **✅ 批次四 (已完成實作)**：處理 `DietService` 後續 `createDietRecord` 重構與呼叫端調整
  - **目標檔案 1**：[diet_service.dart](../services/diet_service.dart)
    - 將 `createDietRecord` 參數重新定義為三大核心必填欄位：`dishName` (必填), `mealType` (必填), `amount` (必填)，並將 `description` 設為選填（預設 `''`）。
  - **目標檔案 2**：[home_view.dart](../views/home/home_view.dart)
    - 更新 `_showMealRecordDraftDialog` 中的 API 呼叫，將引數 `portions:` 改為 `amount: '$qty $unit'.trim()`。
  - **目標檔案 3**：[manual_record_page.dart](../views/records/manual_record_page.dart)
    - 更新第 190 行手動記錄頁面中的 `createDietRecord` 引數，將 `portions:` 改為 `amount:`。

---

## 🔗 延伸檔案與補充說明 (Extended File References & Explanation)

### 1. 為何是 `DietService().createDietRecord(...)`？
在 Flutter 前端專案中，所有的飲食紀錄資料庫操作（包含新增、查詢、修改、刪除紀錄）都被統一封裝在 [diet_service.dart](../services/diet_service.dart) 的 `DietService` 類別中。
當使用者在草稿彈窗點擊「確認儲存」時，前端直接調用 `DietService().createDietRecord(...)` 即可將使用者核對修正後的草稿資料傳送給主後端寫入資料庫。
---
### 2. 真的有 `POST /api/diet-records` 這個 Endpoint 嗎？在哪些檔案可以看到？
**是的，`POST /api/diet-records` 是前端與 Spring Boot 主後端 (Port 8080) 之間正式定義並使用的持久化寫入 API 端點。**
您可以在以下檔案中看到完整的定義與拼裝邏輯：
1. **[diet_service.dart](../services/diet_service.dart)（第 119~188 行）**
   - 在 `createDietRecord` 方法中，呼叫 `_client.post('/diet-records', ...)` 發送新增飲食紀錄的請求。
2. **[api_config.dart](../config/api_config.dart)（第 14、20、23 行）**
   - 定義主後端 (Port 8080) 的 API Base URL 為 `'http://localhost:8080/api'`。
3. **[api_client.dart](../core/api_client.dart)（第 15~21 行）**
   - `_resolveUrl('/diet-records')` 會自動將 `ApiConfig.baseUrl` (`http://localhost:8080/api`) 與 `/diet-records` 組合，拼出完整的 Endpoint URL：**`http://localhost:8080/api/diet-records`**。
4. **`connect.md`（專案外部規格檔，原第 68、222、235、271 行；需重新取得）**
   - 專案對接規格清單中，詳細記載了 Companion Agent 解析出草稿後，前端最終透過呼叫 `DietService.createDietRecord()` 將資料傳入 `POST /api/diet-records` 並持久化至 PostgreSQL 資料庫。
