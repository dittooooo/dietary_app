# 優先清理：安全、會話與敏感資料紀錄

本文件只記錄本次重新掃描 `frontend/lib` 後，尚未被既有模組文件完整涵蓋的高影響項目。重點是帳號憑證、個人健康資料、語音內容與飲食紀錄是否被保存或寫入除錯輸出。

行號以 2026-09-04 本次掃描的原始碼為準；實作前若前面已有修改，需重新確認行號與呼叫流程。

## 待作清單

| 狀態 | 待作項目 | 優先度 | 實作難易度 |
| :--- | :--- | :--- | :--- |
| [ ] | 停止保存完整密碼，移除本地密碼靜默登入 | 優先度最高 | 難易度中 |
| [ ] | 移除問卷 payload 與 API response 的完整 log | 優先度最高 | 難易度簡單 |
| [ ] | 移除飲食日誌的完整紀錄與逐筆欄位 log | 優先度最高 | 難易度簡單 |
| [ ] | 移除首頁語音、帳號識別與飲食清單 log | 優先度最高 | 難易度簡單 |
| [ ] | 將啟動流程的全量偏好設定清除改為明確 session 清除 | 優先度中 | 難易度簡單 |

## 優先度與難易度

- **優先度最高**：可能造成帳號憑證、個人資料或健康資料暴露，或可能造成使用者本地資料被非預期清除。
- **優先度中**：高影響的會話流程或資料保存行為，但需要先確認產品策略。
- **難易度簡單**：單點刪除、遮罩或改成只記錄狀態。
- **難易度中**：需要同時調整登入、刷新或啟動流程，並做回歸測試。

## 1. 登入頁保存完整密碼，ApiClient 以本地密碼靜默登入

### 涉及檔案與行號

- `views/auth/login_page.dart:62-65`
- `core/api_client.dart:250-278`

### 精簡原始程式碼

```dart
// login_page.dart
await prefs.setString('user_email', userEmail);
await prefs.setString('user_password', _passwordController.text);
```

```dart
// api_client.dart
final email = prefs.getString('user_email');
final password = prefs.getString('user_password');
...
body: jsonEncode({'email': email, 'password': password});
```

### 原因

App 將使用者輸入的完整密碼放入 `SharedPreferences`，之後在 Refresh Token 失敗時重新送到登入 API。這不是單純的快取：裝置備份、除錯檔、Root／越獄環境或其他本地資料暴露時，都可能讓密碼跟著外洩；而且登入失效時的行為也從「使用 Refresh Token」擴大成「自動重送完整密碼」。

### 判定

- **優先度：優先度最高**
- **難易度：難易度中**

### 目前證據

目前程式碼明確存在 `user_password` 的寫入與讀取，且 `api_client.dart` 的靜默登入分支會將它組進 POST body。這是原始碼可直接重現的風險，不是根據舊分析推測。

### 驗證方式

1. 新登入後檢查本地偏好設定不再新增完整密碼。
2. 讓 Access Token 過期，確認只使用 Refresh Token；Refresh Token 失效時應回到正常重新登入流程。
3. 確認登出、登入失效、切換帳號後，不會殘留上一個帳號的密碼。
4. 確認 API 失敗時不會因自動登入反覆重試造成登入迴圈。

### 完成條件

- 登入頁不再保存完整密碼。
- ApiClient 不再讀取或送出 `user_password`。
- 舊版本已保存的 `user_password` 在升級或登出時被安全移除。
- Refresh Token 成功、失效、網路錯誤與切換帳號情境都有明確測試結果。

## 2. 問卷提交把健康資料與 API 回應寫入除錯輸出

### 涉及檔案與行號

- `views/auth/initial_info_page.dart:325-352`

### 精簡原始程式碼

```dart
final Map<String, dynamic> onboardingData = {
  'birthDate': _birthDateString,
  'age': _calculatedAge,
  'height': double.tryParse(_height) ?? 170.0,
  'weight': double.tryParse(_weight) ?? 60.0,
  'healthConditions': ProfileValueMapper.healthConditionsToApi(_diseases),
};

debugPrint('提交資料至後端: $onboardingData');
...
debugPrint('API 回應內容: $result');
```

### 原因

問卷資料包含出生日期、年齡、身高、體重、健康狀況與飲食目標。把整個 payload 與 response map 寫入 log，會讓健康與個人資料出現在開發工具、裝置 log 或錯誤收集流程中。即使目前只在開發階段使用，也容易因忘記移除而進入正式版本。

### 判定

- **優先度：優先度最高**
- **難易度：難易度簡單**

### 目前證據

目前有一行直接插值整個 `onboardingData`，另有一行直接輸出整個解析後的 API response；兩者都不是欄位遮罩後的狀態紀錄。

### 驗證方式

1. 送出問卷後，檢查 debug console、Android logcat 與正式模式 log，不出現身高、體重、健康狀況、出生日期或完整 response。
2. 保留必要時的狀態碼與成功／失敗結果，但不輸出 payload 和 response body。
3. 確認問卷送出成功、失敗提示與重試行為不受影響。

### 完成條件

- 移除完整 payload 與 response 的除錯輸出。
- 若確實需要診斷，只記錄不含個資的狀態碼、錯誤類型或 request id。
- 程式碼搜尋不再找到對 `onboardingData` 或 `result` 的整體 log。

## 3. 飲食日誌把完整飲食紀錄寫入除錯輸出

### 涉及檔案與行號

- `views/records/diary_page.dart:174-190`

### 精簡原始程式碼

```dart
final records = await DietService().getMyDietRecords();
debugPrint("DEBUG: Fetched ${records.length} records: $records");
for (var r in records) {
  debugPrint(
    "DEBUG: record id=${r['id']}, dishName=${r['dishName']}, "
    "mealDate=${r['mealDate']}, createdAt=${r['createdAt']} ...",
  );
}
```

### 原因

飲食紀錄可能包含餐點名稱、日期、照片路徑、營養數值與使用者生活習慣。這裡不是只記錄筆數，而是把整包紀錄與餐點欄位逐筆輸出。這和 `ApiClient` 已停止輸出 response body 的改善不同：頁面層仍然可能洩漏資料。

### 判定

- **優先度：優先度最高**
- **難易度：難易度簡單**

### 目前證據

`getMyDietRecords()` 的回傳值被直接插入字串，且迴圈逐筆列出 `dishName`、日期與時間欄位。

### 驗證方式

1. 載入有多筆飲食紀錄的帳號，確認 log 不出現餐點名稱、日期、營養內容或整包 JSON。
2. 確認圖片預載入、日期篩選、編輯與刪除功能維持正常。
3. 失敗時只保留不含紀錄內容的錯誤類型或狀態。

### 完成條件

- 移除完整 records 與逐筆欄位的 log。
- 若需要診斷，只記錄筆數、成功／失敗與非敏感錯誤類型。
- 全專案搜尋後，不再有以 log 輸出日誌完整資料的程式碼。

## 4. 首頁把語音內容、帳號識別與飲食摘要寫入除錯輸出

### 涉及檔案與行號

- `views/home/home_view.dart:208`
- `views/home/home_view.dart:773`

### 精簡原始程式碼

```dart
debugPrint(
  '🗣️ [SpeechToText Result] 收到文字: "${result.recognizedWords}" ...',
);
```

```dart
debugPrint(
  '準備跳出昨日飲食總結彈窗！ User: $userKey, Dishes: $yesterdayDishes',
);
```

### 原因

語音辨識結果可能包含使用者直接說出的個人內容；`userKey` 是帳號識別資訊，`yesterdayDishes` 則是飲食明細。這些內容不應因為 UI 流程除錯而進入 log。一般的「初始化成功」或「狀態碼」紀錄不屬於本項目。

### 判定

- **優先度：優先度最高**
- **難易度：難易度簡單**

### 目前證據

目前原始碼直接插值 `recognizedWords`、`userKey` 與 `yesterdayDishes`，並非只輸出固定訊息。

### 驗證方式

1. 使用語音輸入與有昨日飲食紀錄的帳號測試，確認 log 不出現語音文字、帳號識別值或餐點清單。
2. 確認語音轉文字、飲食總結彈窗與聊天流程仍正常。

### 完成條件

- 敏感欄位不再被插入 debug log。
- 必要診斷只記錄固定事件名稱、筆數或狀態，不記錄原文與清單內容。

## 5. 啟動時以 `prefs.clear()` 清除全部本地偏好設定

### 涉及檔案與行號

- `main.dart:39-44`

### 精簡原始程式碼

```dart
if (result['success'] != true) {
  await prefs.clear();
  initialScreen = const LoginPage(initialMessage: '登入憑證已失效，請重新登入');
}
```

### 原因

登入憑證失效時，目前會清除整個 `SharedPreferences`，不只清除 session。這可能一併刪除使用者尚未同步的本地 UI 狀態、對話快取、設定或其他未來新增的偏好。登入失效處理應明確清除帳號憑證與帳號快取，避免把不相關資料當成 session 一起刪除。

### 判定

- **優先度：優先度中**
- **難易度：難易度簡單**

### 目前證據

`AuthService` 已有集中清除 session 的方法；啟動流程卻另外使用無條件的 `prefs.clear()`。這是兩套清除契約並存的證據。

### 驗證方式

1. 建立失效 token 情境，確認只清除 token、帳號與帳號專屬快取。
2. 確認與登入無關的偏好設定仍保留。
3. 確認下一次登入不會讀到上一個帳號的頭像、暱稱或對話內容。

### 完成條件

- 啟動流程使用明確的 session 清除契約，不再無條件清空所有偏好設定。
- 失效 token、登出、切換帳號三種情境的保留／清除項目有測試記錄。

## 本文件不列入的項目

一般 `print`、無效 import、格式、deprecated API，以及不含個資的固定錯誤訊息不列為本文件的主要急件；先處理上述可直接暴露資料或影響 session 的項目。
