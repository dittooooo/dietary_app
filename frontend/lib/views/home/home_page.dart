import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/edit_profile_page.dart';
import '../auth/profile_page.dart';
import '../records/dietary_record_page.dart';
import '../records/report_page.dart';
import 'home_view.dart';
import '../../color/app_colors.dart';
import '../../services/auth_service.dart';

bool shouldShowAdminMandatoryProfileDialog(
  Map<String, dynamic> profileResult,
) {
  if (profileResult['isOffline'] == true) return false;
  if (profileResult['statusCode'] == 404) return true;

  final rawData = profileResult['data'];
  if (profileResult['success'] != true || rawData is! Map) return false;

  final profileData = Map<String, dynamic>.from(rawData);
  final healthConditions = profileData['healthConditions'];
  final hasHealthConditions = healthConditions is Iterable ? healthConditions.isNotEmpty : healthConditions?.toString().trim().isNotEmpty == true;

  return profileData['nickname']?.toString().trim().isNotEmpty != true ||
      profileData['gender']?.toString().trim().isNotEmpty != true ||
      profileData['birthDate']?.toString().trim().isNotEmpty != true ||
      (double.tryParse(profileData['height']?.toString() ?? '') ?? 0) <= 0 ||
      (double.tryParse(profileData['weight']?.toString() ?? '') ?? 0) <= 0 ||
      !hasHealthConditions ||
      profileData['dietGoal']?.toString().trim().isNotEmpty != true;
}

///是否啟用首頁啟動彈窗
bool shouldEnableHomeStartupDialogs(bool isAdmin,Map<String, dynamic> profileResult) {
  return !isAdmin || !shouldShowAdminMandatoryProfileDialog(profileResult);
}

///主框架頁面
class HomePage extends StatefulWidget {
  final int initialIndex;
  final bool showChat;
  final DateTime? initialReportDate;
  const HomePage({
    super.key,
    this.initialIndex = 0,
    this.showChat = false,
    this.initialReportDate,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

///主框架頁面狀態
class _HomePageState extends State<HomePage> {
  late int _selectedIndex;
  late List<Widget> _pages;
  late final ValueNotifier<DateTime> _selectedReportDate;
  late final ValueNotifier<int> _avatarRefreshNotifier;
  bool _isRoleChecked = false;
  bool _hasShownAdminDialog = false;

  ///初始化
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _selectedReportDate = ValueNotifier(widget.initialReportDate ?? DateTime.now(),);
    _avatarRefreshNotifier = ValueNotifier(0);
    _pages = [];
    _checkAdminRole();
  }

  ///管理者權限檢測
  Future<void> _checkAdminRole() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    var isAdmin = cachedRole == 'ROLE_ADMIN';

    final profileResult = await AuthService().getUserProfile();
    if (!mounted) return;

    if (profileResult['success'] == true) {
      final data = profileResult['data'];
      final String? role = data?['user']?['role'] ?? data?['role'];
      if (role != null) {
        final isBackendAdmin = role == 'ROLE_ADMIN';
        if (isBackendAdmin != isAdmin) {
          isAdmin = isBackendAdmin;
        }
        await prefs.setString(
          'user_role',
          isAdmin ? 'ROLE_ADMIN' : 'ROLE_USER',
        );
      }
    }

    ///啟用首頁啟動彈窗
    final enableStartupDialogs = shouldEnableHomeStartupDialogs(isAdmin, profileResult);
    if (isAdmin) {
      _applyAdminConfig(enableStartupDialogs: enableStartupDialogs);
      if (!enableStartupDialogs) { await _showAdminMandatoryProfileDialog(profileResult);}
    } else {
      _applyUserConfig();
    }
  }

  ///套用使用者設定
  void _applyUserConfig() {
    if (mounted) {
      setState(() {
        _pages = [
          HomeView(initialOpenChat: widget.showChat),
          DietaryRecordPage(
            onDateSelected: _updateSelectedReportDate,
            avatarRefreshListenable: _avatarRefreshNotifier,
          ),
          ReportPage(
            selectedDateListenable: _selectedReportDate,
            onDateChanged: _updateSelectedReportDate,
            avatarRefreshListenable: _avatarRefreshNotifier,
          ),
          ProfilePage(onAvatarChanged: _notifyAvatarChanged),
        ];
        _isRoleChecked = true;
      });
    }
  }

  ///套用管理者設定
  void _applyAdminConfig({required bool enableStartupDialogs}) {
    if (mounted) {
      setState(() {
        _pages = [
          HomeView(
            initialOpenChat: widget.showChat,
            enableStartupDialogs: enableStartupDialogs,
          ),
          DietaryRecordPage(
            onDateSelected: _updateSelectedReportDate,
            avatarRefreshListenable: _avatarRefreshNotifier,
          ),
          ReportPage(
            selectedDateListenable: _selectedReportDate,
            onDateChanged: _updateSelectedReportDate,
            avatarRefreshListenable: _avatarRefreshNotifier,
          ),
          ProfilePage(onAvatarChanged: _notifyAvatarChanged),
        ];
        _isRoleChecked = true;
      });
    }
  }

  ///管理者強制補充資料彈窗
  Future<void> _showAdminMandatoryProfileDialog(Map<String, dynamic> profileResult) async {
    if (_hasShownAdminDialog) return;
    _hasShownAdminDialog = true;

    if (!shouldShowAdminMandatoryProfileDialog(profileResult)) { return;}

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final rawProfileData = profileResult['data'];
    final profileData = rawProfileData is Map
        ? Map<String, dynamic>.from(rawProfileData)
        : <String, dynamic>{
            'email': prefs.getString('user_email'),
            'role': prefs.getString('user_role'),
          };

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
            child: Container(color: Colors.black.withValues(alpha: 0.54)),
          ),
          Center(
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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

    if (mounted) { setState(() { _selectedIndex = 0;});}
  }

  ///底部導覽列點擊事件
  void _onItemTapped(int index) {
    setState(() { _selectedIndex = index;});
  }

  ///更新選取日期
  void _updateSelectedReportDate(DateTime date) {
    _selectedReportDate.value = DateTime(date.year, date.month, date.day);
  }

  ///通知頭像已更改
  void _notifyAvatarChanged() {
    _avatarRefreshNotifier.value++;
  }

  ///資源釋放
  @override
  void dispose() {
    _selectedReportDate.dispose();
    _avatarRefreshNotifier.dispose();
    super.dispose();
  }

  ///主框架頁面
  @override
  Widget build(BuildContext context) {
    if (!_isRoleChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 3.9,
              offset: const Offset(0, -1.17),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textPrimary.withValues(
            alpha: 0.4,
          ),
          backgroundColor: AppColors.background,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_outlined),
              label: '米粒',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_note),
              label: '飲食紀錄',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              label: '飲食報告',
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
