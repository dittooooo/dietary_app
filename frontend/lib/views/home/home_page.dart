import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'package:shared_preferences/shared_preferences.dart'; // 匯入 shared_preferences.dart 元件庫或套件
import '../auth/edit_profile_page.dart'; // 匯入 edit_profile_page.dart 元件庫或套件
import '../auth/profile_page.dart'; // 匯入 profile_page.dart 元件庫或套件
import '../records/dietary_record_page.dart'; // 匯入 dietary_record_page.dart 元件庫或套件
import '../records/report_page.dart';
import 'home_view.dart'; // 匯入 home_view.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/auth_service.dart'; // 匯入 auth_service.dart 元件庫或套件

class HomePage extends StatefulWidget { // 定義 HomePage 類別，繼承自 StatefulWidget
  final int initialIndex; // 宣告類別成員或方法內部的區域變數
  final bool showChat; // 宣告類別成員或方法內部的區域變數
  final DateTime? initialReportDate;
  const HomePage({
    super.key,
    this.initialIndex = 0,
    this.showChat = false,
    this.initialReportDate,
  }); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<HomePage> createState() => _HomePageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _HomePageState extends State<HomePage> { // 定義 _HomePageState 類別，繼承自 State
  late int _selectedIndex; // 宣告類別成員或方法內部的區域變數
  late List<Widget> _pages; // 宣告類別成員或方法內部的區域變數
  late final ValueNotifier<DateTime> _selectedReportDate;
  bool _isRoleChecked = false;
  bool _hasShownAdminDialog = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _selectedReportDate = ValueNotifier(
      widget.initialReportDate ?? DateTime.now(),
    );
    _pages = [];
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    final cachedEmail = prefs.getString('user_email')?.trim().toLowerCase();

    final bool isCachedAdmin = (cachedRole == 'ROLE_ADMIN' || cachedRole == 'ADMIN') ||
        (cachedEmail == 'admin@gmail.com');

    if (isCachedAdmin) {
      _applyAdminConfig();
    } else {
      _applyUserConfig();
    }

    final result = await AuthService().getUserProfile();
    if (mounted && result['success'] == true) {
      final data = result['data'];
      final String? role = data?['user']?['role'] ?? data?['role'];
      final String? email = (data?['email'] ?? data?['user']?['email'] ?? cachedEmail)?.toString().trim().toLowerCase();
      final bool isBackendAdmin = role == 'ROLE_ADMIN' ||
          role == 'ADMIN' ||
          (email == 'admin@gmail.com');

      if (isBackendAdmin) {
        await prefs.setString('user_role', 'ROLE_ADMIN');
        if (!isCachedAdmin) {
          _applyAdminConfig();
        }
      } else {
        await prefs.setString('user_role', 'ROLE_USER');
        if (isCachedAdmin) {
          _applyUserConfig();
        }
      }
    }
  }

  void _applyUserConfig() {
    if (mounted) {
      setState(() {
        // _isAdmin = false;
        _pages = [
          HomeView(initialOpenChat: widget.showChat),
          DietaryRecordPage(onDateSelected: _updateSelectedReportDate),
          ReportPage(
            selectedDateListenable: _selectedReportDate,
            onDateChanged: _updateSelectedReportDate,
          ),
          const ProfilePage(),
        ];
        _isRoleChecked = true;
      });
    }
  }

  void _applyAdminConfig() {
    if (mounted) {
      setState(() {
        // _isAdmin = true;
        _pages = [
          HomeView(initialOpenChat: widget.showChat),
          DietaryRecordPage(onDateSelected: _updateSelectedReportDate),
          ReportPage(
            selectedDateListenable: _selectedReportDate,
            onDateChanged: _updateSelectedReportDate,
          ),
          const ProfilePage(),
        ];
        _isRoleChecked = true;
      });
      _showAdminMandatoryProfileDialog();
    }
  }

  Future<void> _showAdminMandatoryProfileDialog() async {
    if (_hasShownAdminDialog) return;
    _hasShownAdminDialog = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final profileResult = await AuthService().getUserProfile();
      if (profileResult['success'] != true || profileResult['data'] == null || profileResult['isOffline'] == true) {
        return;
      }

      final profileData = Map<String, dynamic>.from(profileResult['data']);

      final String? email = profileData['email']?.toString().trim().toLowerCase();
      final bool isAlreadyOnboarded = profileData['hasCompletedOnboarding'] == true;
      final hasHeight = profileData['height'] != null && (double.tryParse(profileData['height'].toString()) ?? 0) > 0;
      final hasWeight = profileData['weight'] != null && (double.tryParse(profileData['weight'].toString()) ?? 0) > 0;
      final hasGender = profileData['gender'] != null && profileData['gender'].toString().trim().isNotEmpty;
      
      if (email == 'admin@gmail.com' || isAlreadyOnboarded || (hasHeight && hasWeight && hasGender)) {
        return;
      }

      if (!mounted) return;

      final editKey = GlobalKey<State<EditProfilePage>>();
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        builder: (ctx) => Stack(
          children: [
            GestureDetector(
              onTap: () {
                final state = editKey.currentState;
                if (state != null) {
                  (state as dynamic).triggerValidationError('請輸入完整訊息');
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withOpacity(0.54),
              ),
            ),
            Center(
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(ctx).size.height * 0.85,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: EditProfilePage(
                      key: editKey,
                      initialData: profileData,
                      isMandatoryAdmin: true,
                      onSaveSuccess: () {
                        Navigator.of(ctx, rootNavigator: true).pop(true);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      if (mounted) {
        setState(() {
          _selectedIndex = 0;
        });
      }
    });
  }

  void _onItemTapped(int index) { // 執行相對應的邏輯計算或設定屬性參數
    setState(() { // 更新狀態數據並通知 UI 重新渲染畫面
      _selectedIndex = index; // 執行相對應的邏輯計算或設定屬性參數
    }); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _updateSelectedReportDate(DateTime date) {
    _selectedReportDate.value = DateTime(date.year, date.month, date.day);
  }

  @override
  void dispose() {
    _selectedReportDate.dispose();
    super.dispose();
  }

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
      bottomNavigationBar: Container( // 建立多功能樣式容器（Container），可自訂尺寸、間距與背景樣式
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
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              label: '飲食報告',
            ),
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


