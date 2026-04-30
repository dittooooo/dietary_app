import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart'; // 引入相簿套件
import 'dart:typed_data'; // 處理圖片數據
import '../../config/api_config.dart';
import '../superkey/admin_user_list_page.dart'; 
import '../superkey/generic_admin_page.dart'; // 引入通用管理頁面
import '../home/home_page.dart';
import 'edit_profile_page.dart';

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
  Uint8List? _imageBytes; // 儲存圖片的記憶體數據，相容 Web 與手機

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final savedEmail = prefs.getString('user_email');

      if (savedEmail != null) {
        setState(() => _email = savedEmail);
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/user/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final userData = result['data'];
          setState(() {
            _fullUserData = userData;
            _nickname = userData['nickname'] ?? '未設定姓名';
            // 根據暱稱、角色或特定測試帳號判斷管理員
            _isAdmin = userData['role'] == 'ADMIN' || 
                       userData['nickname'] == '管理員' || 
                       _email == 'aaa@aaa.aaa'; 
          });
        }
      }
    } catch (e) {
      debugPrint('載入個人資料失敗: $e');
      setState(() => _nickname = '載入失敗');
    }
  }

  // 選擇圖片的功能
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
      }
    } catch (e) {
      debugPrint('選取圖片失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, // 移除左上角預設返回鍵
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => HomePage(initialIndex: widget.returnIndex)),
              (route) => false,
            );
          },
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Text(
            '個人首頁',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.black, size: 40), // 管理者放大 2 倍
              onPressed: () {
                // 管理員設定
              },
            )
          else
            const SizedBox(width: 48), // 保持間距平衡
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            // 1. 頭像區域 (包含相機按鈕)
            Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 70,
                      backgroundColor: Colors.white,
                      backgroundImage: _imageBytes != null 
                          ? MemoryImage(_imageBytes!) 
                          : null,
                      child: _imageBytes == null 
                          ? const Icon(Icons.person, size: 80, color: Colors.grey) 
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 5,
                    right: 5,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(side: BorderSide(color: Colors.black, width: 1.5)),
                      child: InkWell(
                        onTap: _pickImage,
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.camera_alt, color: Colors.black, size: 22),
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
              style: const TextStyle(color: Colors.black87, fontSize: 18),
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
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: OutlinedButton.icon(
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
                    label: const Text('修改個人檔案', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.black, width: 1.5),
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
                      child: Text('--- 管理員選單 ---', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                    _buildAdminButton('使用者管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminUserListPage(),
                        ),
                      );
                    }),
                    _buildAdminButton('餐廳管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GenericAdminListPage(title: '餐廳管理'),
                        ),
                      );
                    }),
                    _buildAdminButton('菜單管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GenericAdminListPage(title: '菜單管理'),
                        ),
                      );
                    }),
                    _buildAdminButton('社群管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GenericAdminListPage(title: '社群管理'),
                        ),
                      );
                    }),
                    _buildAdminButton('登入管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GenericAdminListPage(title: '登入管理'),
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
            Container(
              margin: const EdgeInsets.all(20),
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 25,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pets, size: 100, color: Colors.blueGrey),
                    SizedBox(height: 10),
                    Text('小精靈正在休息...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
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
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Colors.black, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

}
