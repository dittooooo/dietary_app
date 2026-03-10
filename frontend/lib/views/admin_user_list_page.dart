import 'package:flutter/material.dart';
import 'user_detail_page.dart';

class AdminUserListPage extends StatefulWidget {
  const AdminUserListPage({super.key});

  @override
  State<AdminUserListPage> createState() => _AdminUserListPageState();
}

class _AdminUserListPageState extends State<AdminUserListPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isDeleteMode = false; // 新增：追蹤是否為刪除模式
  // 模擬假資料 (對應規格書與草圖欄位)
  final List<Map<String, String>> _allUsers = [
    {'id': '#01', 'name': '王小明', 'email': 'ming@mail.com', 'gender': '男', 'height': '175', 'weight': '70'},
    {'id': '#02', 'name': '李華', 'email': 'hua@mail.com', 'gender': '女', 'height': '160', 'weight': '50'},
    {'id': '#03', 'name': '陳大天', 'email': 'sky@mail.com', 'gender': '男', 'height': '182', 'weight': '90'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isDeleteMode ? '請點擊欲刪除的對象' : '使用者管理清單'),
        backgroundColor: _isDeleteMode ? Colors.red[400] : null, // 刪除模式變色提醒
        actions: [
          IconButton(
            icon: Icon(_isDeleteMode ? Icons.close : Icons.delete),
            onPressed: () => setState(() => _isDeleteMode = !_isDeleteMode),
          ),
        ],
      ),
      // ... body 部分 ...
      body: Column(
        children: [
          // 搜尋欄
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '輸入名稱或帳號查詢使用者...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          
          // 使用者卡片列表
          Expanded(
            child: ListView.builder(
              itemCount: _allUsers.length,
              itemBuilder: (context, index) {
                final user = _allUsers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(user['id']!)),
                    title: Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(user['email']!),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      if (_isDeleteMode) {
                        _showDeleteConfirmDialog(user); // 刪除模式：彈出確認
                      } else {
                        Navigator.push( // 一般模式：進入詳情
                          context,
                          MaterialPageRoute(builder: (context) => UserDetailPage(userData: user)),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // 新增使用者按鈕
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }

//彈出一個視窗（Dialog），讓管理員在刪除使用者前進行二次確認。
void _showDeleteConfirmDialog(Map<String, String> user) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('確認刪除'),
        content: Text('您確定要刪除使用者「${user['name']}」嗎？\n此動作將無法復原。'),
        actions: [
          // 取消按鈕
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // 關閉對話框
            child: const Text('取消'),
          ),
          // 確認刪除按鈕
          TextButton(
            onPressed: () {
              setState(() {
                // 從目前的清單中移除該使用者
                _allUsers.removeWhere((u) => u['id'] == user['id']);
                // 關閉刪除模式 (如果你希望刪除一筆後自動退出刪除模式)
                _isDeleteMode = false; 
              });
              Navigator.of(context).pop(); // 關閉對話框
              
              // 提示使用者已刪除
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已成功刪除使用者：${user['name']}')),
              );
            },
            child: const Text('確認刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
    },
  );
}
}