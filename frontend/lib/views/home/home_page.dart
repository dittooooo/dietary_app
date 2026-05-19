import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/profile_page.dart';
import '../records/dietary_record_page.dart';
import 'home_view.dart';
import '../../color/app_colors.dart';
import '../../services/auth_service.dart';

class HomePage extends StatefulWidget {
  final int initialIndex;
  final bool showChat;
  const HomePage({super.key, this.initialIndex = 0, this.showChat = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex;
  late List<Widget> _pages;
  bool _isAdmin = false;
  bool _isRoleChecked = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pages = [];
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    // 1. 先嘗試從本地快取讀取，立即改變 UI
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    if (cachedRole == 'ROLE_ADMIN') {
      _applyAdminConfig();
    } else {
      if (mounted) {
        setState(() {
          _isAdmin = false;
          _pages = [
            HomeView(initialOpenChat: widget.showChat),
            const DietaryRecordPage(),
            const ProfilePage(),
          ];
          _isRoleChecked = true;
        });
      }
    }

    // 2. 向後端確認最新狀態，確保資料同步
    final result = await AuthService().getUserProfile();
    if (mounted && result['success'] == true) {
      final data = result['data'];
      final String? role = data?['user']?['role'] ?? data?['role'];
      if (role == 'ROLE_ADMIN') {
        if (cachedRole != 'ROLE_ADMIN') {
          await prefs.setString('user_role', 'ROLE_ADMIN');
          _applyAdminConfig();
        }
      } else {
        if (cachedRole == 'ROLE_ADMIN') {
          await prefs.remove('user_role');
          setState(() {
            _isAdmin = false;
            _selectedIndex = 0;
            _pages = [
              HomeView(initialOpenChat: widget.showChat),
              const DietaryRecordPage(),
              const ProfilePage(),
            ];
            _isRoleChecked = true;
          });
        }
      }
    }
  }

  void _applyAdminConfig() {
    setState(() {
      _isAdmin = true;
      _selectedIndex = 0; // 管理員只有一頁，索引強制為 0
      _pages = [
        const ProfilePage(returnIndex: 0),
      ];
      _isRoleChecked = true;
    });
  }

  void _onItemTapped(int index) {
    if (_isAdmin) return; // 管理員無法切換分頁
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRoleChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: _isAdmin
          ? Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.5), width: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 3.9,
                    offset: const Offset(0, -1.17),
                  ),
                ],
              ),
              child: const SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_circle, color: AppColors.primary),
                      SizedBox(height: 4),
                      Text(
                        '個人首頁',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 3.9,
                    offset: const Offset(0, -1.17),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.textPrimary.withOpacity(0.4),
                backgroundColor: AppColors.background,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: '首頁',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.edit_note),
                    label: '飲食紀錄',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_circle),
                    label: '個人首頁',
                  ),
                ],
              ),
            ),
    );
  }
}


