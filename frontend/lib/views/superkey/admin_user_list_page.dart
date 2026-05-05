import 'package:flutter/material.dart';
import 'user_detail_page.dart';
import '../../color/app_colors.dart';

class AdminUserListPage extends StatefulWidget {
  const AdminUserListPage({super.key});

  @override
  State<AdminUserListPage> createState() => _AdminUserListPageState();
}

class _AdminUserListPageState extends State<AdminUserListPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isDeleteMode = false;
  
  final List<Map<String, String>> _allUsers = [
    {
      'id': '#01',
      'name': '王小明',
      'email': 'ming@mail.com',
      'gender': '男',
      'height': '175',
      'weight': '70',
    },
    {
      'id': '#02',
      'name': '李華',
      'email': 'hua@mail.com',
      'gender': '女',
      'height': '160',
      'weight': '50',
    },
    {
      'id': '#03',
      'name': '陳大天',
      'email': 'sky@mail.com',
      'gender': '男',
      'height': '182',
      'weight': '90',
    },
  ];

  List<Map<String, String>> _foundUsers = [];
  @override
  void initState() {
    _foundUsers = _allUsers;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_isDeleteMode ? '請點擊欲刪除的對象' : '使用者管理清單', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: _isDeleteMode ? AppColors.danger.withOpacity(0.1) : AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: Icon(_isDeleteMode ? Icons.close : Icons.delete),
            onPressed: () => setState(() => _isDeleteMode = !_isDeleteMode),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _runFilter(value),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                hintText: '輸入名稱、帳號或 ID 查詢...',
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
          ),

          Expanded(
            child: _foundUsers.isNotEmpty
                ? ListView.builder(
                    itemCount: _foundUsers.length,
                    itemBuilder: (context, index) {
                      final user = _foundUsers[index];
                      return Card(
                        color: AppColors.background,
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.secondary,
                            child: Text(user['id']!, style: const TextStyle(color: AppColors.background)),
                          ),
                          title: Text(
                            user['name']!,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          subtitle: Text(user['email']!, style: const TextStyle(color: AppColors.textSecondary)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.secondary),
                          onTap: () {
                            if (_isDeleteMode) {
                              _showDeleteConfirmDialog(user);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserDetailPage(userData: user),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Text('找不到該使用者', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {},
        child: const Icon(Icons.add, color: AppColors.background),
      ),
    );
  }

  void _showDeleteConfirmDialog(Map<String, String> user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          title: const Text('確認刪除', style: TextStyle(color: AppColors.textPrimary)),
          content: Text('您確定要刪除使用者「${user['name']}」嗎？\n此動作將無法復原。', style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _allUsers.removeWhere((u) => u['id'] == user['id']);
                  _isDeleteMode = false;
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已成功刪除使用者：${user['name']}')),
                );
              },
              child: const Text('確認刪除', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, String>> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allUsers;
    } else {
      results = _allUsers
          .where(
            (user) =>
                user["name"]!.toLowerCase().contains(enteredKeyword.toLowerCase()) ||
                user["id"]!.toLowerCase().contains(enteredKeyword.toLowerCase()) ||
                user["email"]!.toLowerCase().contains(enteredKeyword.toLowerCase()),
          )
          .toList();
    }

    setState(() {
      _foundUsers = results;
    });
  }
}
