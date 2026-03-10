import 'package:flutter/material.dart';

class UserDetailPage extends StatefulWidget {
  final Map<String, String> userData;
  const UserDetailPage({super.key, required this.userData});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  bool _isEditing = false; // 新增：追蹤是否開啟編輯模式
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userData['name']!),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit), // 切換編輯或打勾圖示
            onPressed: () {
              setState(() {
                if (_isEditing) {
                  // 這裡未來可以放「儲存到 DB」的 API 呼叫
                }
                _isEditing = !_isEditing;
              });
            },
          ),
          if (_isEditing) // 編輯模式時顯示取消按鈕
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _isEditing = false),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailField('使用者 ID', widget.userData['id']!,isPrimaryKey: true),
            _buildDetailField('姓名 / 別名', widget.userData['name']!,isPrimaryKey: true),
            _buildDetailField('電子郵件 (帳號)', widget.userData['email']!,isPrimaryKey: true),
            _buildDetailField('性別', widget.userData['gender']!),
            _buildDetailField('身高 (cm)', widget.userData['height']!),
            _buildDetailField('體重 (kg)', widget.userData['weight']!),
            _buildDetailField('個人目標', '養成健康飲食習慣'), // 規格書範例 [cite: 9]
            _buildDetailField('特殊疾病', '無'),
            const SizedBox(height: 30),
            const Text('向右滑動可返回清單', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailField(String label, String value, {bool isPrimaryKey = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        initialValue: value,
        // 規則：如果是 PK (ID/Name/Mail) 則永遠 readOnly；其餘則跟隨 _isEditing 狀態
        readOnly: isPrimaryKey ? true : !_isEditing, 
        decoration: InputDecoration(
          labelText: label,
          filled: isPrimaryKey || (!_isEditing), // 唯讀時加上背景色提示
          fillColor: isPrimaryKey ? Colors.grey[200] : Colors.grey[50],
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}