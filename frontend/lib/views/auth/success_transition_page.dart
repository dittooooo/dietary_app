import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'dart:convert'; // 匯入 dart:convert 元件庫或套件
import 'package:http/http.dart' as http; // 匯入 http.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../../config/api_config.dart'; // 匯入 api_config.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../home/home_page.dart'; // 匯入 home_page.dart 元件庫或套件
import 'initial_info_page.dart'; // 匯入 initial_info_page.dart 元件庫或套件

class SuccessTransitionPage extends StatefulWidget { // 定義 SuccessTransitionPage 類別，繼承自 StatefulWidget
  final String title; // 宣告類別成員或方法內部的區域變數
  final bool shouldNavigate; // 宣告類別成員或方法內部的區域變數
  const SuccessTransitionPage({ // 建立編譯期常數，優化 Flutter 渲染效能
    super.key,  // 執行相對應的邏輯計算或設定屬性參數
    this.title = '登入成功！', // 執行相對應的邏輯計算或設定屬性參數
    this.shouldNavigate = true, // 執行相對應的邏輯計算或設定屬性參數
  }); // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  State<SuccessTransitionPage> createState() => _SuccessTransitionPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _SuccessTransitionPageState extends State<SuccessTransitionPage> { // 定義 _SuccessTransitionPageState 類別，繼承自 State
  double _progress = 0.0; // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _animateProgress(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  void _animateProgress() async { // 執行相對應的邏輯計算或設定屬性參數
    // 預先檢查使用者是否已完成 onboarding
    bool alreadyOnboarded = false; // 宣告類別成員或方法內部的區域變數
    try { // 執行相對應的邏輯計算或設定屬性參數
      final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
      final token = prefs.getString('jwt_token'); // 宣告類別成員或方法內部的區域變數
      if (token != null) { // 執行相對應的邏輯計算或設定屬性參數
        final response = await http.get( // 宣告類別成員或方法內部的區域變數
          Uri.parse('${ApiConfig.baseUrl}/user/profile'), // 執行相對應的邏輯計算或設定屬性參數
          headers: {'Authorization': 'Bearer $token'}, // 執行相對應的邏輯計算或設定屬性參數
        ).timeout(const Duration(seconds: 5)); // 建立編譯期常數，優化 Flutter 渲染效能
        
        // 如果能抓到 Profile (200 OK)，代表已經完成過 onboarding 了
        if (response.statusCode == 200) { // 執行相對應的邏輯計算或設定屬性參數
          alreadyOnboarded = true; // 執行相對應的邏輯計算或設定屬性參數
          try { // 執行相對應的邏輯計算或設定屬性參數
            final data = jsonDecode(response.body); // 宣告類別成員或方法內部的區域變數
            final userData = data['data'] ?? data; // 宣告類別成員或方法內部的區域變數
            final String? role = userData['user']?['role'] ?? userData['role']; // 宣告類別成員或方法內部的區域變數
            if (role != null) { // 執行相對應的邏輯計算或設定屬性參數
              await prefs.setString('user_role', role); // 執行相對應的邏輯計算或設定屬性參數
            } // 程式碼區塊或元件結構結束
          } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
            debugPrint('SuccessTransitionPage 解析角色失敗: $e'); // 執行相對應的邏輯計算或設定屬性參數
          } // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } catch (e) { // 執行相對應的邏輯計算或設定屬性參數
      debugPrint('檢查 onboarding 狀態失敗: $e'); // 執行相對應的邏輯計算或設定屬性參數
    } // 程式碼區塊或元件結構結束

    for (int i = 0; i <= 100; i++) { // 執行相對應的邏輯計算或設定屬性參數
      await Future.delayed(const Duration(milliseconds: 15)); // 建立編譯期常數，優化 Flutter 渲染效能
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        setState(() => _progress = i / 100.0); // 更新狀態數據並通知 UI 重新渲染畫面
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    if (mounted && widget.shouldNavigate) { // 執行相對應的邏輯計算或設定屬性參數
      if (alreadyOnboarded) { // 執行相對應的邏輯計算或設定屬性參數
        // 已完成者 -> 直接進首頁
        Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
          context, // 執行相對應的邏輯計算或設定屬性參數
          MaterialPageRoute(builder: (context) => const HomePage()), // 建立編譯期常數，優化 Flutter 渲染效能
        ); // 程式碼區塊或元件結構結束
      } else { // 程式碼區塊或元件結構結束
        // 未完成者 -> 進個資填寫頁面
        Navigator.pushReplacement( // 導航路由跳轉：開啟並推入新頁面
          context, // 執行相對應的邏輯計算或設定屬性參數
          MaterialPageRoute(builder: (context) => const InitialInfoPage()), // 建立編譯期常數，優化 Flutter 渲染效能
        ); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.background, // 設定顏色數值（Color）
      body: Center( // 設定頁面的主要內容區域（body）
        child: Padding( // 建立間距容器（Padding），用於設定內部邊距
          padding: const EdgeInsets.all(40.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
          child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
            mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
            children: [ // 執行相對應的邏輯計算或設定屬性參數
              const Icon(Icons.face, size: 80, color: AppColors.primary),  // 設定顏色數值（Color）
              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              Text( // 建立文字顯示元件（Text）
                widget.title,  // 執行相對應的邏輯計算或設定屬性參數
                style: const TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                  fontSize: 24,  // 執行相對應的邏輯計算或設定屬性參數
                  fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                  color: AppColors.textPrimary // 設定顏色數值（Color）
                ) // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              LinearProgressIndicator( // 執行相對應的邏輯計算或設定屬性參數
                value: _progress, // 執行相對應的邏輯計算或設定屬性參數
                backgroundColor: AppColors.surface, // 設定顏色數值（Color）
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary), // 設定顏色數值（Color）
                minHeight: 10, // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              const SizedBox(height: 40), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              const Icon(Icons.image, size: 100, color: AppColors.secondary),  // 設定顏色數值（Color）
              const SizedBox(height: 20), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
              const Text( // 建立文字顯示元件（Text）
                '希望您能享受 App',  // 執行相對應的邏輯計算或設定屬性參數
                textAlign: TextAlign.center,  // 執行相對應的邏輯計算或設定屬性參數
                style: TextStyle(color: AppColors.textPrimary) // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
              ), // 執行相對應的邏輯計算或設定屬性參數
            ], // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ), // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束
