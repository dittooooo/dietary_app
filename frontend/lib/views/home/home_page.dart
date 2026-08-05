import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import '../records/dietary_record_page.dart'; // 匯入 dietary_record_page.dart 元件庫或套件
import 'home_view.dart'; // 匯入 home_view.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件

class HomePage extends StatefulWidget { // 定義 HomePage 類別，繼承自 StatefulWidget
  final int initialIndex; // 宣告類別成員或方法內部的區域變數
  final bool showChat; // 宣告類別成員或方法內部的區域變數
  const HomePage({super.key, this.initialIndex = 0, this.showChat = false}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<HomePage> createState() => _HomePageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _HomePageState extends State<HomePage> { // 定義 _HomePageState 類別，繼承自 State
  late int _selectedIndex; // 宣告類別成員或方法內部的區域變數
  late List<Widget> _pages; // 宣告類別成員或方法內部的區域變數
  bool _isAdmin = false; // 宣告類別成員或方法內部的區域變數
  bool _isRoleChecked = false; // 宣告類別成員或方法內部的區域變數

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _selectedIndex = widget.initialIndex; // 執行相對應的邏輯計算或設定屬性參數
    _pages = []; // 執行相對應的邏輯計算或設定屬性參數
    _checkAdminRole(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Future<void> _checkAdminRole() async { // 定義非同步方法（Future），執行耗時操作
    // 1. 先嘗試從本地快取讀取，立即改變 UI
    final prefs = await SharedPreferences.getInstance(); // 宣告類別成員或方法內部的區域變數
    final cachedRole = prefs.getString('user_role'); // 宣告類別成員或方法內部的區域變數
    if (cachedRole == 'ROLE_ADMIN') { // 執行相對應的邏輯計算或設定屬性參數
      _applyAdminConfig(); // 執行相對應的邏輯計算或設定屬性參數
    } else { // 程式碼區塊或元件結構結束
      if (mounted) { // 執行相對應的邏輯計算或設定屬性參數
        setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
          _isAdmin = false; // 執行相對應的邏輯計算或設定屬性參數
          _pages = [ // 執行相對應的邏輯計算或設定屬性參數
            HomeView(initialOpenChat: widget.showChat), // 執行相對應的邏輯計算或設定屬性參數
            const DietaryRecordPage(), // 建立編譯期常數，優化 Flutter 渲染效能
            const ProfilePage(), // 建立編譯期常數，優化 Flutter 渲染效能
          ]; // 程式碼區塊或元件結構結束
          _isRoleChecked = true; // 執行相對應的邏輯計算或設定屬性參數
        }); // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束

    // 2. 向後端確認最新狀態，確保資料同步
    final result = await AuthService().getUserProfile(); // 宣告類別成員或方法內部的區域變數
    if (mounted && result['success'] == true) { // 執行相對應的邏輯計算或設定屬性參數
      final data = result['data']; // 宣告類別成員或方法內部的區域變數
      final String? role = data?['user']?['role'] ?? data?['role']; // 宣告類別成員或方法內部的區域變數
      if (role == 'ROLE_ADMIN') { // 執行相對應的邏輯計算或設定屬性參數
        if (cachedRole != 'ROLE_ADMIN') { // 執行相對應的邏輯計算或設定屬性參數
          await prefs.setString('user_role', 'ROLE_ADMIN'); // 執行相對應的邏輯計算或設定屬性參數
          _applyAdminConfig(); // 執行相對應的邏輯計算或設定屬性參數
        } // 程式碼區塊或元件結構結束
      } else { // 程式碼區塊或元件結構結束
        if (cachedRole == 'ROLE_ADMIN') { // 執行相對應的邏輯計算或設定屬性參數
          await prefs.remove('user_role'); // 執行相對應的邏輯計算或設定屬性參數
          setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
            _isAdmin = false; // 執行相對應的邏輯計算或設定屬性參數
            _selectedIndex = 0; // 執行相對應的邏輯計算或設定屬性參數
            _pages = [ // 執行相對應的邏輯計算或設定屬性參數
              HomeView(initialOpenChat: widget.showChat), // 執行相對應的邏輯計算或設定屬性參數
              const DietaryRecordPage(), // 建立編譯期常數，優化 Flutter 渲染效能
              const ProfilePage(), // 建立編譯期常數，優化 Flutter 渲染效能
            ]; // 程式碼區塊或元件結構結束
            _isRoleChecked = true; // 執行相對應的邏輯計算或設定屬性參數
          }); // 程式碼區塊或元件結構結束
        } // 程式碼區塊或元件結構結束
      } // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _applyAdminConfig() { // 執行相對應的邏輯計算或設定屬性參數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _isAdmin = true; // 執行相對應的邏輯計算或設定屬性參數
      _selectedIndex = 0; // 管理員只有一頁，索引強制為 0
      _pages = [ // 執行相對應的邏輯計算或設定屬性參數
        const ProfilePage(returnIndex: 0), // 建立編譯期常數，優化 Flutter 渲染效能
      ]; // 程式碼區塊或元件結構結束
      _isRoleChecked = true; // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _onItemTapped(int index) { // 執行相對應的邏輯計算或設定屬性參數
    if (_isAdmin) return; // 管理員無法切換分頁
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _selectedIndex = index; // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    if (!_isRoleChecked) { // 執行相對應的邏輯計算或設定屬性參數
      return const Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        body: Center( // 設定頁面的主要內容區域（body）
          child: CircularProgressIndicator(color: AppColors.primary), // 設定顏色數值（Color）
        ), // 執行相對應的邏輯計算或設定屬性參數
      ); // 程式碼區塊或元件結構結束
    } // 程式碼區塊或元件結構結束
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      body: IndexedStack( // 設定頁面的主要內容區域（body）
        index: _selectedIndex, // 執行相對應的邏輯計算或設定屬性參數
        children: _pages, // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      bottomNavigationBar: _isAdmin // 執行相對應的邏輯計算或設定屬性參數
          ? Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              height: 90, // 執行相對應的邏輯計算或設定屬性參數
              decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                color: AppColors.background, // 設定顏色數值（Color）
                border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.5)), // 設定顏色數值（Color）
                boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                  BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                    color: Colors.black.withOpacity(0.15), // 設定顏色數值（Color）
                    blurRadius: 3.9, // 執行相對應的邏輯計算或設定屬性參數
                    offset: const Offset(0, -1.17), // 建立編譯期常數，優化 Flutter 渲染效能
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              child: const SafeArea( // 建立編譯期常數，優化 Flutter 渲染效能
                child: Center( // 建立置中對齊元件（Center），將子元件居中顯示
                  child: Column( // 建立垂直排列元件（Column），縱向排列多個子元件
                    mainAxisAlignment: MainAxisAlignment.center, // 執行相對應的邏輯計算或設定屬性參數
                    children: [ // 執行相對應的邏輯計算或設定屬性參數
                      Icon(Icons.account_circle, color: AppColors.primary), // 設定顏色數值（Color）
                      SizedBox(height: 4), // 建立固定尺寸的空白區塊或限制寬高的容器（SizedBox）
                      Text( // 建立文字顯示元件（Text）
                        '個人首頁', // 執行相對應的邏輯計算或設定屬性參數
                        style: TextStyle( // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                          color: AppColors.primary, // 設定顏色數值（Color）
                          fontWeight: FontWeight.bold, // 執行相對應的邏輯計算或設定屬性參數
                          fontSize: 12, // 執行相對應的邏輯計算或設定屬性參數
                        ), // 執行相對應的邏輯計算或設定屬性參數
                      ), // 執行相對應的邏輯計算或設定屬性參數
                    ], // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ), // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ) // 執行相對應的邏輯計算或設定屬性參數
          : Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
              decoration: BoxDecoration( // 建立盒子裝飾元件（BoxDecoration），用來設定圓角、背景色、陰影等樣式
                boxShadow: [ // 執行相對應的邏輯計算或設定屬性參數
                  BoxShadow( // 設定容器的陰影效果，包括顏色、模糊半徑與偏移量
                    color: Colors.black.withOpacity(0.15), // 設定顏色數值（Color）
                    blurRadius: 3.9, // 執行相對應的邏輯計算或設定屬性參數
                    offset: const Offset(0, -1.17), // 建立編譯期常數，優化 Flutter 渲染效能
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
              child: BottomNavigationBar( // 執行相對應的邏輯計算或設定屬性參數
                currentIndex: _selectedIndex, // 執行相對應的邏輯計算或設定屬性參數
                onTap: _onItemTapped, // 執行相對應的邏輯計算或設定屬性參數
                selectedItemColor: AppColors.primary, // 設定顏色數值（Color）
                unselectedItemColor: AppColors.textPrimary.withOpacity(0.4), // 設定顏色數值（Color）
                backgroundColor: AppColors.background, // 設定顏色數值（Color）
                type: BottomNavigationBarType.fixed, // 執行相對應的邏輯計算或設定屬性參數
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                unselectedLabelStyle: const TextStyle(fontSize: 12), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                items: const [ // 建立編譯期常數，優化 Flutter 渲染效能
                  BottomNavigationBarItem( // 執行相對應的邏輯計算或設定屬性參數
                    icon: Icon(Icons.home), // 顯示預設的圖示元件（Icon）
                    label: '首頁', // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  BottomNavigationBarItem( // 執行相對應的邏輯計算或設定屬性參數
                    icon: Icon(Icons.edit_note), // 顯示預設的圖示元件（Icon）
                    label: '飲食紀錄', // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                  BottomNavigationBarItem( // 執行相對應的邏輯計算或設定屬性參數
                    icon: Icon(Icons.account_circle), // 顯示預設的圖示元件（Icon）
                    label: '個人首頁', // 執行相對應的邏輯計算或設定屬性參數
                  ), // 執行相對應的邏輯計算或設定屬性參數
                ], // 執行相對應的邏輯計算或設定屬性參數
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束
} // 程式碼區塊或元件結構結束


