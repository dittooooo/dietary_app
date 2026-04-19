import 'package:flutter/material.dart';

class UserDetailPage extends StatelessWidget {
  final Map<String, String> userData;
  const UserDetailPage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(userData['name']!)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailField('使用者 ID', userData['id']!),
            _buildDetailField('姓名 / 別名', userData['name']!),
            _buildDetailField('電子郵件 (帳號)', userData['email']!),
            _buildDetailField('性別', userData['gender']!),
            _buildDetailField('身高 (cm)', userData['height']!),
            _buildDetailField('體重 (kg)', userData['weight']!),
            _buildDetailField('個人目標', '養成健康飲食習慣'), // 規格書範例 [cite: 9]
            _buildDetailField('特殊疾病', '無'),
            const SizedBox(height: 30),
            const Text('向右滑動可返回清單', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        initialValue: value,
        readOnly: true, // 所有欄位都設為唯讀
        decoration: InputDecoration(
          labelText: label,
          filled: true, // 加上背景色提示
          fillColor: Colors.grey[200],
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
