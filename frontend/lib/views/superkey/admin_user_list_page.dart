//檔案功用：實作管理員搜尋過濾邏輯，支援透過 ID、姓名或帳號即時篩選使用者。
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

  // 透過搜尋目前顯示的資料 (Filtered List)
  List<Map<String, String>> _foundUsers = [];
  @override
  void initState() {
    // 初始狀態下，顯示清單等於全部清單
    _foundUsers = _allUsers;
    super.initState();
  }

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
              onChanged: (value) => _runFilter(value), // 打字時即時過濾
              decoration: InputDecoration(
                hintText: '輸入名稱、帳號或 ID 查詢...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),

          // 使用者卡片列表
          Expanded(
            child: _foundUsers.isNotEmpty
                ? ListView.builder(
                    itemCount: _foundUsers.length,
                    itemBuilder: (context, index) {
                      final user = _foundUsers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(user['id']!)),
                          title: Text(
                            user['name']!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(user['email']!),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () {
                            if (_isDeleteMode) {
                              _showDeleteConfirmDialog(user); // 刪除模式：彈出確認
                            } else {
                              Navigator.push(
                                // 一般模式：進入詳情
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      UserDetailPage(userData: user),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Text('找不到該使用者', style: TextStyle(fontSize: 18)),
                  ), // 搜尋不到結果時
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

  // 過濾函數(過濾出查詢的使用者)
  void _runFilter(String enteredKeyword) {
    List<Map<String, String>> results = [];
    if (enteredKeyword.isEmpty) {
      // 若搜尋框為空，恢復顯示全部
      results = _allUsers;
    } else {
      // 透過 ID、姓名或 Email 進行比對 (不分大小寫)
      results = _allUsers
          .where(
            (user) =>
                user["name"]!.toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ) ||
                user["id"]!.toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ) ||
                user["email"]!.toLowerCase().contains(
                  enteredKeyword.toLowerCase(),
                ),
          )
          .toList();
    }

    // 重新整理 UI
    setState(() {
      _foundUsers = results;
    });
  }
}
