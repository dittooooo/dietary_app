//負責所有網路請求的共通邏輯
import 'dart:convert'; // 匯入 dart:convert 套件或模組
import 'package:flutter/material.dart'; // 匯入 material.dart 以便使用 Dialog/Snackbar
import 'package:http/http.dart' as http; // 匯入 http.dart 套件或模組
import '../config/api_config.dart'; // 匯入 api_config.dart 套件或模組
import '../views/auth/login_page.dart'; // 匯入登入頁面以便權限降級/未授權跳轉

class ApiClient { // 定義 ApiClient 類別，封裝相關功能或資料
  // 全域 NavigatorKey 用於無 Context 導航與攔截處理
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 統一處理 POST 請求
  Future<http.Response> post(String path, Map<String, dynamic> body, {Map<String, String>? headers}) async { // 發送 HTTP POST 請求方法，封裝相關 API 呼叫
    final url = Uri.parse('${ApiConfig.baseUrl}$path'); // 宣告類別屬性或方法內部的區域變數
    
    print('🚀 發送 POST 請求至: $url'); // 執行相對應的程式邏輯運算或欄位宣告設定
    print('📦 請求內容: $body'); // 執行相對應的程式邏輯運算或欄位宣告設定

    try { // 執行相對應的程式邏輯運算或欄位宣告設定
      final response = await http.post( // 宣告類別屬性或方法內部的區域變數
        url, // 執行相對應的程式邏輯運算或欄位宣告設定
        headers: { // 執行相對應的程式邏輯運算或欄位宣告設定
          'Content-Type': 'application/json', // 執行相對應的程式邏輯運算或欄位宣告設定
          ...?headers, // 執行相對應的程式邏輯運算或欄位宣告設定
        }, // 程式碼區塊或結構結束
        body: jsonEncode(body), // 將 Map 結構資料編碼序列化為 JSON 字串形式
      ); // 程式碼區塊或結構結束
      _checkResponse(response);
      return response; // 回傳方法執行結果或計算完成的數據
    } catch (e) { // 執行相對應的程式邏輯運算或欄位宣告設定
      print('❌ POST 網路連線異常: $e'); // 執行相對應的程式邏輯運算或欄位宣告設定
      rethrow; // 執行相對應的程式邏輯運算或欄位宣告設定
    } // 程式碼區塊或結構結束
  } // 程式碼區塊或結構結束

  // 統一處理 GET 請求
  Future<http.Response> get(String path, {Map<String, String>? headers}) async { // 發送 HTTP GET 請求方法，封裝相關 API 呼叫
    final url = Uri.parse('${ApiConfig.baseUrl}$path'); // 宣告類別屬性或方法內部的區域變數
    print('🚀 GET 請求至: $url'); // 執行相對應的程式邏輯運算或欄位宣告設定

    try { // 執行相對應的程式邏輯運算或欄位宣告設定
      final response = await http.get( // 宣告類別屬性或方法內部的區域變數
        url, // 執行相對應的程式邏輯運算或欄位宣告設定
        headers: { // 執行相對應的程式邏輯運算或欄位宣告設定
          'Content-Type': 'application/json', // 執行相對應的程式邏輯運算或欄位宣告設定
          ...?headers, // 執行相對應的程式邏輯運算或欄位宣告設定
        }, // 程式碼區塊或結構結束
      ); // 程式碼區塊或結構結束
      _checkResponse(response);
      return response; // 回傳方法執行結果或計算完成的數據
    } catch (e) { // 執行相對應的程式邏輯運算或欄位宣告設定
      print('❌ GET 網路連線異常: $e'); // 執行相對應的程式邏輯運算或欄位宣告設定
      rethrow; // 執行相對應的程式邏輯運算或欄位宣告設定
    } // 程式碼區塊或結構結束
  } // 程式碼區塊或結構結束

  // 統一處理 PUT 請求
  Future<http.Response> put(String path, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    print('🚀 PUT 請求至: $url');
    print('📦 請求內容: $body');

    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
        body: jsonEncode(body),
      );
      _checkResponse(response);
      return response;
    } catch (e) {
      print('❌ PUT 網路連線異常: $e');
      rethrow;
    }
  }

  // 統一處理 Multipart/Form-data 檔案上傳請求
  Future<http.Response> multipart(String path, List<int> fileBytes, String filename, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    print('🚀 發送 Multipart 請求至: $url');

    try {
      final request = http.MultipartRequest('POST', url);
      if (headers != null) {
        request.headers.addAll(headers);
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _checkResponse(response);
      return response;
    } catch (e) {
      print('❌ Multipart 網路連線異常: $e');
      rethrow;
    }
  }

  // 統一處理 DELETE 請求
  Future<http.Response> delete(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    print('🚀 DELETE 請求至: $url');

    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
      );
      _checkResponse(response);
      return response;
    } catch (e) {
      print('❌ DELETE 網路連線異常: $e');
      rethrow;
    }
  }

  // 私有工具：檢查 API 回傳狀態，處理 403 權限降級或未授權攔截
  void _checkResponse(http.Response response) {
    if (response.statusCode == 403 || response.statusCode == 401) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // 延遲執行，避免與當前 Build 衝突
        Future.delayed(Duration.zero, () {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('存取權限受限'),
              content: Text(response.statusCode == 403 
                  ? '您目前的使用者角色沒有權限存取此管理頁面。系統將為您進行導向降級。' 
                  : '您的登入憑證已過期，請重新登入。'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // 強制重導向至登入頁面
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                      (route) => false,
                    );
                  },
                  child: const Text('確定'),
                ),
              ],
            ),
          );
        });
      }
    }
  }
} // 程式碼區塊或結構結束
