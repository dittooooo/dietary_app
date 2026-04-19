//檔案功用：整合管理員特殊權限按鈕與一般使用者資訊的個人首頁介面。
import 'package:flutter/material.dart';
import '../superkey/admin_user_list_page.dart'; // 引入先前完成的使用者管理清單

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 模擬身份權限：目前設定為 true 以便開發展示
  bool isAdmin = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('個人首頁'),
        centerTitle: true,
        leading: const Icon(Icons.arrow_back), // 返回按鈕
        actions: [
          IconButton(
            icon: const Icon(Icons.settings), // 設置圖示
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 1. 使用者基本資訊區
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.transparent,
              backgroundImage: NetworkImage(
                'https://via.placeholder.com/150',
              ), // 預留小精靈或個人照
            ),
            const SizedBox(height: 10),
            const Text(
              '我是瘦子', // 依草圖顯示姓名
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'aaa@example.com', // 依草圖顯示 Email
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // 2. 管理員專屬功能區 (僅在 isAdmin 為 true 時顯示)
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    _buildAdminButton('使用者管理', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminUserListPage(),
                        ),
                      );
                    }),
                    _buildAdminButton('餐廳管理', () => _notAvailable(context)),
                    _buildAdminButton('菜單管理', () => _notAvailable(context)),
                    _buildAdminButton('社群管理', () => _notAvailable(context)),
                    _buildAdminButton('登入管理', () => _notAvailable(context)),
                    _buildAdminButton('飲食紀錄', () => _notAvailable(context)),
                  ],
                ),
              ),

            // 3. 小精靈展示區
            const SizedBox(height: 30),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.catching_pokemon,
                      size: 100,
                      color: Colors.blueGrey,
                    ), // 小精靈位置 [cite: 70]
                    Text('小精靈正在休息...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // 4. 底部導覽列
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2, // 目前在個人首頁
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁地圖'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.person_pin), label: '個人首頁'),
        ],
      ),
    );
  }

  // 管理員按鈕組件
  Widget _buildAdminButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.black, width: 1.5),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ), // 方形邊框
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _notAvailable(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('功能開發中，敬請期待！')));
  }
}
