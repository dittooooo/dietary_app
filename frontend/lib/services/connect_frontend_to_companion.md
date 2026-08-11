# 前端對接 Companion Agent 修改規劃說明書 (connect_frontend_to_companion.md)

本文件依據 [frontendConnectcompanion.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/frontendConnectcompanion.md) 與 [connect.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/connect.md) 規格撰寫，**僅作為改碼依據說明檔案，未經確認不會更動任何程式碼**。
以下詳細列出連線至 Companion Agent (Port 3000) 預計修改的 **4 個檔案**、**修改行號範圍**、**原程式碼與預計更動程式碼**，以及 **`meal_record` 飲食草稿彈窗 (Dialog) 互動與持久化儲存流程**。

---

## 📁 修改檔案 1: `frontend/lib/config/api_config.dart`

* **檔案路徑**：[api_config.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/config/api_config.dart)
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

* **檔案路徑**：[api_client.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/core/api_client.dart)
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

* **檔案路徑**：[diet_service.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/services/diet_service.dart)
* **修改目的**：
  1. 匯入 `api_config.dart`。
  2. 新增與 Companion Agent (`POST /companion/ask`) 發送對話的 service 方法 `sendCompanionUserPrompt`。

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
  /// 發送使用者訊息至 Companion Agent (Port 3000 /companion/ask)
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

## 📁 修改檔案 4: `frontend/lib/views/home/home_view.dart`

* **檔案路徑**：[home_view.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/views/home/home_view.dart)
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

## 🔔 累積擴充: UI 與彈窗互動層 — `meal_record` 意圖之前端彈跳視窗 (Dialog) 互動與 confirmation 儲存完整流程

依據 [connect.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/connect.md) 第六點規範，當 Companion Agent 回傳 `intent_category == "meal_record"` 且 `meal_records` 不為空時，前端之完整 UI 互動與持久化流程如下：

### 1. 互動與數據串接流程 (Sequence Flow)

```
[Companion Agent] ──(200 OK: companion_reply + meal_records)──> [home_view.dart]
                                                                        │
 ┌──────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────┐
 │ 1. 氣泡渲染：先將 companion_reply 顯示於聊天氣泡                                                                         │
 │ 2. 彈窗觸發：調用 _showMealRecordDraftDialog(context, mealRecords) 彈出草稿確認視窗                                     │
 └──────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────┘
                                                                        │
                           ┌────────────────────────────────────────────┴────────────────────────────────────────────┐
                           ▼                                                                                         ▼
                 【點擊「取消」按鈕】                                                                       【點擊「確認儲存」按鈕】
                           │                                                                                         │
             關閉彈窗，不進行 DB 寫入                                                               關閉彈窗並發送持久化請求
                                                                                                                     │
                                                                                         遍歷草稿品項，對每一餐點呼叫：
                                                                                         DietService().createDietRecord(...)
                                                                                                                     │
                                                                                                                     ▼
                                                                                         [Spring Boot API] POST /api/diet-records
                                                                                                                     │
                                                                                                                     ▼
                                                                                         跳出 Toast 提示「🎉 飲食紀錄已成功儲存！」
```

---

### 2. 在 `_HomeViewState` 內預計新增之 `_showMealRecordDraftDialog` 方法程式碼

此方法將放置於 [home_view.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/views/home/home_view.dart) 的 `_HomeViewState` 類別內：

```dart
  /// 彈出「飲食紀錄草稿預覽」確認視窗，供使用者核對並確認儲存至 DB
  void _showMealRecordDraftDialog(BuildContext context, List<dynamic> mealRecords) {
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
                  Icon(Icons.restaurant_menu, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    '確認飲食紀錄草稿',
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
                      '陪伴精靈已為您整理出以下飲食草稿，請確認是否儲存至紀錄：',
                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    ...mealRecords.map((record) {
                      final mealPeriod = record['meal_period']?.toString() ?? '早餐';
                      final items = record['meal_items'] as List<dynamic>? ?? [];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '餐期：$mealPeriod',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.secondary,
                              ),
                            ),
                            const Divider(height: 12),
                            ...items.map((item) {
                              final name = item['name']?.toString() ?? '';
                              final qty = item['quantity']?.toString() ?? '1';
                              final unit = item['unit']?.toString() ?? '';
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('• $name', style: const TextStyle(fontSize: 13)),
                                    Text('$qty $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                            for (var record in mealRecords) {
                              final mealPeriod = record['meal_period']?.toString() ?? '早餐';
                              final items = record['meal_items'] as List<dynamic>? ?? [];
                              for (var item in items) {
                                final name = item['name']?.toString() ?? '';
                                final qty = item['quantity']?.toString() ?? '1';
                                final unit = item['unit']?.toString() ?? '';
                                if (name.isNotEmpty) {
                                  await DietService().createDietRecord(
                                    dishName: name,
                                    mealType: mealPeriod,
                                    description: '陪伴精靈自動解析紀錄',
                                    portions: '$qty $unit'.trim(),
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

## 🎯 總結

本說明文件已累積**包含 UI 彈窗互動層 (`meal_record` 飲食草稿卡片與確認儲存)** 的完整設計。
完全**沒有修改任何既有的 Dart 原始程式碼**，請您審閱確認。確認無誤後，即可分兩批次依照本說明書內容逐行實作：
- **批次一**：基礎 API 連線與 Service 方法建置 (`api_config.dart`, `api_client.dart`, `diet_service.dart`)。
- **批次二**：UI 與彈窗互動層對接 (`home_view.dart` 訊息接收與 `_showMealRecordDraftDialog` 彈窗流程)。
