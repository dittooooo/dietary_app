# 優先清理：搜尋與資料 API 連線契約

本文件記錄本次掃描發現、且尚未在既有模組文件中完整說明的搜尋與資料服務問題。重點不是現在拆檔，而是先讓連線入口、逾時、錯誤格式與 token 來源有一致契約。

行號以 2026-09-04 本次掃描的原始碼為準；實作前需重新確認行號。

## 待作清單

| 狀態 | 待作項目 | 優先度 | 實作難易度 |
| :--- | :--- | :--- | :--- |
| [ ] | 為餐點搜尋補上 timeout、錯誤分類與授權契約 | 優先度中 | 難易度中 |
| [ ] | 對齊 Body Status 的 token 來源與 response 解析契約 | 優先度中 | 難易度中 |

## 優先度與難易度

- **優先度最高**：可能造成主要功能無限等待、資料錯誤或跨帳號資料風險。
- **優先度中**：高影響連線契約或重複處理，容易在後端格式或登入流程變更時出錯。
- **難易度簡單**：單一服務增加逾時、錯誤分類或改用共用常數。
- **難易度中**：需要同步服務、呼叫頁面與測試資料契約。
- **難易度困難**：跨多個 API 邊界或需重新設計整體資料層；本文件目前沒有要求立刻拆檔。

## 1. 餐點搜尋直接使用裸 `http.get`，沒有逾時與統一錯誤契約

### 涉及檔案與行號

- `services/dish_search_service.dart:72-99`
- `views/records/manual_record_page.dart:512`（目前建立並使用服務）

### 精簡原始程式碼

```dart
class DishSearchService {
  Future<List<DishSearchResult>> search(String query) async {
    final baseUri = Uri.parse(
      '${ApiConfig.nutritionistBaseUrl}/nutritionist-agent/dishes/search',
    );
    final uri = baseUri.replace(
      queryParameters: {'q': trimmedQuery, 'limit': '20'},
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Food search service is unavailable');
    }
    final decoded = jsonDecode(response.body);
    ...
  }
}
```

### 原因

搜尋功能直接繞過共用 `ApiClient`，因此沒有共用的逾時、錯誤處理、請求記錄與 session 契約。當營養服務未啟動、網路中斷或後端沒有回應時，`await http.get` 可能長時間卡住；非 200 response 與 JSON 格式錯誤也都只轉成一般 `Exception`，呼叫頁面難以判斷是逾時、服務不可用還是資料格式變更。

目前不能直接假設營養搜尋一定要帶使用者 token，因為它可能是公開的營養資料服務；是否加上授權 header 應先和後端契約確認。

### 判定

- **優先度：優先度中**
- **難易度：難易度中**

### 目前證據

`dish_search_service.dart` 直接 import `package:http/http.dart as http` 並呼叫 `http.get`，沒有 `.timeout(...)`；`manual_record_page.dart` 確實建立這個服務，表示不是孤立程式碼。

### 驗證方式

1. 讓營養服務關閉或模擬網路中斷，確認畫面在明確時間內結束 loading 並顯示可理解的提示。
2. 測試成功、非 200、逾時、非 JSON 與空結果五種回應。
3. 確認搜尋結果仍能填入手動紀錄，且不會因重複輸入產生過多並行請求。
4. 與後端確認此 endpoint 是否需要 token，再決定是否沿用 `ApiClient` 的授權處理。

### 完成條件

- 搜尋請求有明確 timeout 與可辨識的錯誤類型。
- 呼叫頁面在成功、失敗、逾時時都能結束 loading 狀態。
- endpoint、授權需求與 response schema 有文件或測試固定下來。
- 若改用共用 client，確認不會誤觸發主後端的全域登入失效流程。

## 2. Body Status service 自己讀 token 並重複解析 response

### 涉及檔案與行號

- `services/body_status_api_service.dart:13-63`
- `views/home/home_view.dart:46`
- `views/auth/success_transition_page.dart:35`

### 精簡原始程式碼

```dart
final token = await _token();
...
headers: {'Authorization': 'Bearer $token'},
...
Future<String?> _token() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('jwt_token');
}
```

```dart
Map<String, dynamic> _decodeMap(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : decoded;
  }
  throw BodyStatusApiException('API 回傳格式不正確');
}
```

### 原因

目前 `BodyStatusApiService` 另外讀取固定字串 `'jwt_token'`，再自行組 Authorization header；同一服務也自行決定 response 是否取 `data` 外層。這與 `ApiClient`、`AuthService.accessTokenKey` 及其他 service 的處理邊界重複。未來若 token key、token type 或後端 response 包裝格式調整，體態同步可能單獨失效，而且錯誤會分散在頁面流程中。

這不是目前要求立即拆檔的項目；先對齊共用 token 常數與 response contract 即可。

### 判定

- **優先度：優先度中**
- **難易度：難易度中**

### 目前證據

此 service 被首頁與登入成功過渡頁使用，並且同時包含 token 取得、header 組裝、HTTP 呼叫、JSON 解包與 domain model 建立。它不是未使用的服務，但有明確的連線契約重複。

### 驗證方式

1. 確認正常登入、token 過期、token 缺失與 401 response 的行為。
2. 確認首頁同步與成功頁每日結算都能解析目前 API 的 wrapped 與 unwrapped response。
3. 確認 token key 只由共用常數提供，切換帳號後不會沿用舊 token。
4. 確認錯誤訊息仍能讓首頁與成功頁進入正確的失敗狀態。

### 完成條件

- Body Status 使用共用的 access-token 契約，不再散落固定 key 字串。
- response 外層格式與 `BodyStatusModel`、`SettlementResponse` 的對應方式有單元或整合測試。
- 首頁與成功過渡頁的同步、結算、401 與網路錯誤流程均驗證完成。

## 與既有文件的邊界

- `core/api_client.dart` 的 HTTP／refresh／全域登入失效耦合，已記錄在 [優先清理_services_core_config.md](優先清理_services_core_config.md)；本文件只補充其中「完整密碼靜默登入」的資料安全風險。
- `services/diet_service.dart` 的飲食 API、response normalization 與 Companion 責任集中，已記錄在 [優先清理_services_core_config.md](優先清理_services_core_config.md)；本文件不重複要求拆檔。
- `views/records/manual_record_page.dart` 的大檔案與資料模型責任，已記錄在 [優先清理_records.md](優先清理_records.md)；本文件只記錄它確實使用餐點搜尋服務的證據。
