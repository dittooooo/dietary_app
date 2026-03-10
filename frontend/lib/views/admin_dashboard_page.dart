import 'package:flutter/material.dart';
import 'admin_user_list_page.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理員中控台'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: GridView.count(
          crossAxisCount: 2, // 一列放兩個按鈕
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          children: [
            _buildMenuButton(
              context,
              icon: Icons.people_alt,
              label: '使用者管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminUserListPage()),
              ),
            ),
            _buildMenuButton(
              context,
              icon: Icons.restaurant,
              label: '餐廳管理',
              color: Colors.grey, // 尚未開放
              onTap: () => _showNotImplemented(context),
            ),
            _buildMenuButton(
              context,
              icon: Icons.menu_book,
              label: '菜單管理',
              color: Colors.grey,
              onTap: () => _showNotImplemented(context),
            ),
            _buildMenuButton(
              context,
              icon: Icons.bar_chart,
              label: '數據統計',
              color: Colors.grey,
              onTap: () => _showNotImplemented(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, {
    required IconData icon, 
    required String label, 
    required VoidCallback onTap,
    Color color = Colors.blue,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showNotImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('功能開發中，敬請期待！')),
    );
  }
}