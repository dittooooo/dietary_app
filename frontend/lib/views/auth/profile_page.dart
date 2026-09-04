import 'dart:ui';
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../config/api_config.dart';
import '../../color/app_colors.dart';
import '../superkey/admin_user_list_page.dart'; 
import '../superkey/admin_problem_feedback_page.dart';
import '../superkey/admin_test_tools_page.dart';
import '../home/home_page.dart';
import 'edit_profile_page.dart';
import 'login_page.dart';
import 'settings_page.dart';
import '../../services/auth_service.dart';
import '../../utils/friendly_error_message.dart';

/// 個人中心主頁面 Widget，展示用戶頭像、暱稱、熱量目標與設定功能選單。
class ProfilePage extends StatefulWidget {
  final int returnIndex;
  final VoidCallback? onAvatarChanged;

  const ProfilePage({
    super.key,
    this.returnIndex = 0,
    this.onAvatarChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

/// 內部使用的 _ProfilePageState 元件與狀態處理類別。
class _ProfilePageState extends State<ProfilePage> {
  bool _isAdmin = false; 
  String _nickname = '載入中...';
  String _email = '...';
  Map<String, dynamic>? _fullUserData;
  Uint8List? _imageBytes;
  final DogStateController _dogController = DogStateController.instance;

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    final cachedEmail = prefs.getString('user_email') ?? '...';
    final cachedNickname = prefs.getString('user_nickname') ?? '管理員';
    final bool isCachedAdmin = cachedRole == 'ROLE_ADMIN' ||
        cachedRole == 'ADMIN' ||
        cachedEmail.trim().toLowerCase() == 'admin@gmail.com';

    setState(() {
      _email = cachedEmail;
      _isAdmin = isCachedAdmin;
      if (isCachedAdmin && (cachedNickname == 'aaa' || cachedNickname == '載入中...' || cachedNickname == '使用者' || cachedNickname == '管理員')) {
        _nickname = '系統管理員';
      } else {
        _nickname = cachedNickname;
      }
    });

    final result = await AuthService().getUserProfile();
    
    if (mounted) {
      if (result['success'] == true) {
        setState(() {
          _fullUserData = result['data'];
          _email = _fullUserData?['email'] ?? _fullUserData?['user']?['email'] ?? _email;
          final bodyValue = _fullUserData?['dogBodyType'] ?? _fullUserData?['bodyType'] ?? _fullUserData?['mascotBodyType'] ?? _fullUserData?['avatarBodyType'] ?? _fullUserData?['dietGoal'] ?? _fullUserData?['diet_goal'];
          _dogController.setBodyTypeFromBackend(bodyValue);
          _dogController.setState(DogAnimationState.idle);

          final String? role = _fullUserData?['user']?['role'] ?? _fullUserData?['role'];
          _isAdmin = role == 'ROLE_ADMIN' || role == 'ADMIN' || _email.trim().toLowerCase() == 'admin@gmail.com';

          final fetchedNickname = _fullUserData?['nickname']?.toString().trim();
          if (_isAdmin && (fetchedNickname == null || fetchedNickname.isEmpty || fetchedNickname == 'aaa' || fetchedNickname == '使用者')) {
            _nickname = '系統管理員';
          } else if (fetchedNickname != null && fetchedNickname.isNotEmpty) {
            _nickname = fetchedNickname;
          }
        });
        prefs.setString('user_nickname', _nickname);
      } else {
        if (isCachedAdmin || _email.trim().toLowerCase() == 'admin@gmail.com') {
          setState(() {
            _isAdmin = true;
            if (_nickname == '載入中...' || _nickname == 'aaa') _nickname = '系統管理員';
          });
        } else if (_nickname == '載入中...') {
          setState(() => _nickname = '連線失敗');
        }
      }
    }
  }

  Future<void> _handleLogout() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  /// 啟動圖片選擇器以選取回饋照片附件。
  Future<void> _pickImage() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在開啟圖庫...'), duration: Duration(seconds: 1)));
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上傳頭像至伺服器...')));
        }
        
        final uploadResult = await AuthService().uploadAvatar(bytes, pickedFile.name);
        
        if (mounted) {
          if (uploadResult['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('頭像上傳成功！')));
            _loadUserData();
            widget.onAvatarChanged?.call();
          } else {
            setState(() {
              _imageBytes = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(FriendlyErrorMessage.upload)),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('選取圖片或上傳失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.upload)),
        );
      }
    }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, 
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7), 
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
            ),
          ),
        ),
        leading: null,
        title: const Text(
          '個人首頁',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isAdmin)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.settings, color: AppColors.textPrimary, size: 40),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
      body: Container(
        color: AppColors.surface,
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 80 + MediaQuery.of(context).padding.top + 20),
            Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 3.9,
                          offset: const Offset(0, 1.95),
                        ),
                      ],
                    ),
                    child: Builder(
                      builder: (context) {
                        ImageProvider? avatarImage;
                        final String? avatarPath = _fullUserData?['avatarUrl'] ?? _fullUserData?['user']?['avatarUrl'];
                        if (avatarPath != null && avatarPath.isNotEmpty) {
                          final serverBase = ApiConfig.baseUrl.replaceAll('/api', '');
                          final fullUrl = avatarPath.startsWith('http') ? avatarPath : '$serverBase$avatarPath';
                          avatarImage = NetworkImage(fullUrl);
                        } else if (_imageBytes != null) {
                          avatarImage = MemoryImage(_imageBytes!);
                        }

                        return CircleAvatar(
                          radius: 70,
                          backgroundColor: AppColors.background,
                          backgroundImage: avatarImage,
                          child: avatarImage == null 
                              ? const Icon(Icons.person, size: 80, color: Colors.black) 
                              : null,
                        );
                      }
                    ),
                  ),
                  Positioned(
                    bottom: 5,
                    right: 5,
                    child: Material(
                      color: AppColors.background,
                      shape: const CircleBorder(),
                      elevation: 0.975,
                      shadowColor: Colors.black.withValues(alpha: 0.5),
                      child: InkWell(
                        onTap: _pickImage,
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.camera_alt, color: AppColors.textPrimary, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _nickname, 
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              _email, 
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 2.925,
                          offset: const Offset(0, 1.17),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final initialDataToPass = _fullUserData ?? {
                          'nickname': _nickname,
                          'email': _email,
                        };
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfilePage(
                              initialData: {
                                ...initialDataToPass,
                                'email': _email,
                              },
                            ),
                          ),
                        );
                        if (updated == true) _loadUserData();
                      },
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.black,
                          size: 18,
                        ),
                        label: const Text(
                          '修改個人檔案',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.background,
                          foregroundColor: AppColors.textPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: AppColors.background,
                      shape: const CircleBorder(),
                      elevation: 2.925,
                      shadowColor: Colors.black.withValues(alpha: 0.25),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsPage(),
                            ),
                          );
                        },
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.settings,
                            color: AppColors.textPrimary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 15),
                      child: Text('--- 管理員選單 ---', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
                    ),
                    _buildAdminButton('使用者管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminUserListPage(),
                        ),
                      );
                    }),
                    _buildAdminButton('問題回饋管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminProblemFeedbackPage(),
                        ),
                      );
                    }),
                    _buildAdminButton('測試工具', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminTestToolsPage(),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pushAndRemoveUntil(
                context, 
                MaterialPageRoute(builder: (context) => const HomePage(initialIndex: 0, showChat: true)), 
                (route) => false
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                height: 550,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 4.875,
                      offset: const Offset(0, 2.34),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double modelSize = constraints.maxWidth.clamp(0.0, 390.0);
                    return AnimatedBuilder(
                      animation: _dogController,
                      builder: (context, _) {
                        final bool isThin = _dogController.bodyType == DogBodyType.thin;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: modelSize - 20,
                              height: modelSize + 80,
                              child: DogAvatar(
                                controller: _dogController,
                                instanceId: 'profile-card',
                                scale: isThin ? 1.15 : 1.4,
                                cameraControls: false,
                                clipBehavior: Clip.none,
                                contentOffset: Offset(isThin ? -20 : -16, isThin ? 16 : 0),
                              ),
                            ),
                            const Text(
                              '米粒(Mili)',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, color: AppColors.background),
                label: const Text('登出帳號', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 0, 0, 0),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildAdminButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        height: 45,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 1.95,
              offset: const Offset(0, 0.975),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textPrimary,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) {
                if (states.contains(WidgetState.pressed)) return AppColors.secondary.withValues(alpha: 0.1);
                return null;
              },
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

}
