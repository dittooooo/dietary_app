import 'dart:convert';
import 'dart:ui';
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart'; // 引入相簿套件
import 'dart:typed_data'; // 處理圖片數據
import '../../config/api_config.dart';
import '../../color/app_colors.dart';
import '../superkey/admin_user_list_page.dart'; 
import '../superkey/generic_admin_page.dart'; // 引入通用管理頁面
import '../home/home_page.dart';
import 'edit_profile_page.dart';
import 'login_page.dart';
import '../../services/auth_service.dart';

class ProfilePage extends StatefulWidget {
  final int returnIndex;
  const ProfilePage({super.key, this.returnIndex = 0});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isAdmin = false; 
  String _nickname = '載入中...';
  String _email = '...';
  Map<String, dynamic>? _fullUserData;
  Uint8List? _imageBytes;
  final DogStateController _dogController = DogStateController.instance; // 儲存圖片的記憶體數據，相容 Web 與手機

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // 1. 優先從本地快取讀取 (前端輔助，立即響應)
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _email = prefs.getString('user_email') ?? '...';
      _nickname = prefs.getString('user_nickname') ?? '載入中...';
    });

    // 2. 向後端請求最新資料 (後端為主，更新快取)
    final result = await AuthService().getUserProfile();
    
    if (mounted) {
      if (result['success'] == true) {
        setState(() {
          _fullUserData = result['data'];
          _email = _fullUserData?['email'] ?? _fullUserData?['user']?['email'] ?? _email;
          final bodyValue = _fullUserData?['dogBodyType'] ?? _fullUserData?['bodyType'] ?? _fullUserData?['mascotBodyType'] ?? _fullUserData?['avatarBodyType'] ?? _fullUserData?['dietGoal'] ?? _fullUserData?['diet_goal'];
          _dogController.setBodyTypeFromBackend(bodyValue);
          _dogController.setState(DogAnimationState.idle);
          _nickname = _fullUserData?['nickname'] ?? '未設定姓名';
          
          // 修正後的權限判斷：
          // 1. 檢查嵌套路徑 (符合 Spring Boot/Jackson 預設序列化)
          // 2. 檢查字串是否包含 ROLE_ADMIN
          final String? role = _fullUserData?['user']?['role'] ?? _fullUserData?['role'];
          _isAdmin = role == 'ROLE_ADMIN';
        });
      } else {
        debugPrint('更新資料失敗: ${result['message']}');
        // 如果完全沒資料且報錯，才顯示失敗
        if (_nickname == '載入中...') {
          setState(() => _nickname = '連線失敗');
        }
      }
    }
  }

  // 登出功能
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

  // 根據小精靈名稱獲取對應圖標
  IconData _getPetIcon(String? petType) {
    switch (petType) {
      case '狗兒':
      case '奶油皮丘': return Icons.pets;
      case '薄荷兔兔': return Icons.eco;
      case '草莓狐狸': return Icons.star;
      default: return Icons.help_outline;
    }
  }

  // 根據小精靈名稱獲取對應顏色
  Color _getPetColor(String? petType) {
    switch (petType) {
      case '狗兒':
      case '奶油皮丘': return const Color.fromARGB(255, 181, 181, 60); // Muted orange (retro)
      case '薄荷兔兔': return const Color.fromARGB(255, 110, 215, 154); // Muted sage (retro)
      case '草莓狐狸': return const Color.fromARGB(255, 186, 84, 84); // Muted terracotta (retro)
      default: return const Color.fromARGB(255, 66, 92, 65);
    }
  }

  // 選擇圖片與上傳頭像功能
  Future<void> _pickImage() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在開啟圖庫...'), duration: Duration(seconds: 1)));
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512, // 限制尺寸
        maxHeight: 512,
        imageQuality: 85, // 壓縮畫質
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
            _loadUserData(); // 重新載入最新資料
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('頭像上傳失敗：${uploadResult['message']}')));
          }
        }
      }
    } catch (e) {
      debugPrint('選取圖片或上傳失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('選取或上傳圖片失敗: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false, 
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background.withOpacity(0.5), 
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
            const SizedBox(width: 48), // 保持間距平衡
        ],
      ),
      body: Container(
        color: AppColors.surface, // 確保底色覆蓋全螢幕
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20), // 預留標題列高度
              // 1. 頭像區域 (包含相機按鈕)
            Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
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
                      shadowColor: Colors.black.withOpacity(0.5),
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

            // 2. 修改個人檔案按鈕 (一般使用者才顯示)
            if (!_isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 2.925,
                        offset: const Offset(0, 1.17),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_fullUserData != null) {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfilePage(
                              initialData: {
                                ..._fullUserData!,
                                'email': _email,
                              },
                            ),
                          ),
                        );
                        if (updated == true) _loadUserData();
                      }
                    },
                    icon: const Icon(Icons.edit, color: Colors.black, size: 18),
                    label: const Text('修改個人檔案', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                    ),
                  ),
                ),
              ),

            // 3. 管理員專屬功能區
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
                    _buildAdminButton('飲食紀錄管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GenericAdminListPage(title: '飲食紀錄管理'),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // 4. 小精靈展示區
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
                      color: AppColors.primary.withOpacity(0.3),
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
                              '狗兒',
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
            // 5. 登出按鈕
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
      bottomNavigationBar: (ModalRoute.of(context)?.canPop ?? false)
          ? BottomNavigationBar(
              currentIndex: 2,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textPrimary.withOpacity(0.4),
              backgroundColor: AppColors.background,
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              onTap: (index) => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)),
                (route) => false,
              ),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'),
                BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),
                BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: '個人首頁')
              ],
            )
          : null,
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
              color: Colors.black.withOpacity(0.25),
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
                if (states.contains(WidgetState.pressed)) return AppColors.secondary.withOpacity(0.1);
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
