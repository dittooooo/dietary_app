import 'package:flutter/material.dart';
import '../../color/app_colors.dart'; // 匯入自訂的顏色設定檔（AppColors）

/// 管理者檢視特定單一使用者詳細個人資料與歷史飲食總覽頁面。
class UserDetailPage extends StatelessWidget {

  final Map<String, String> userData; // 定義一個用來接收外部傳入使用者資料的 Map 物件
  const UserDetailPage({
    super.key,
    required this.userData,
  }); // 建構子，要求必須傳入 userData 資料

  @override
  /// 建立 UserDetailPage 區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          userData['name']!,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
        ),
      ), // 導航欄結束
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailField(
              '使用者 ID',
              userData['id']!,
            ), // 建立並顯示使用者 ID 的唯讀輸入框欄位
            _buildDetailField(
              '姓名 / 別名',
              userData['name']!,
            ), // 建立並顯示使用者姓名的唯讀輸入框欄位
            _buildDetailField(
              '電子郵件 (帳號)',
              userData['email']!,
            ), // 建立並顯示使用者電子信箱的唯讀輸入框欄位
            _buildDetailField(
              '帳號狀態',
              userData['status'] ?? '啟用中',
            ), // 建立並顯示使用者帳號狀態
            _buildDetailField('性別', userData['gender']!), // 建立並顯示使用者性別的唯讀輸入框欄位
            _buildDetailField(
              '身高 (cm)',
              userData['height']!,
            ), // 建立並顯示使用者身高的唯讀輸入框欄位
            _buildDetailField(
              '體重 (kg)',
              userData['weight']!,
            ), // 建立並顯示使用者體重的唯讀輸入框欄位
            _buildDetailField(
              '個人目標',
              userData['goal'] ?? '養成健康飲食習慣',
            ), // 建立並顯示使用者預設目標的唯讀輸入框欄位
            _buildDetailField(
              '特殊疾病',
              userData['healthConditions'] ?? '無',
            ), // 建立並顯示使用者特殊疾病資訊的唯讀輸入框欄位
          ], // 子元件清單結束
        ), // 垂直佈局結束
      ), // 滾動視圖結束
    ); // Scaffold 結構結束
  } // build 方法結束

  /// 建立 DetailField 區塊之視覺 UI 視圖元件。
  Widget _buildDetailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      child: TextFormField(
        initialValue: value,
        readOnly: true, // 將輸入框設為「唯讀」狀態，使用者無法編輯此欄位
        style: const TextStyle(
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black54),
          filled: true, // 開啟背景填充色
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ), // 裝飾結束
      ), // 文字輸入框結束
    ); // Padding 結束
  } // _buildDetailField 方法結束
} // UserDetailPage 類別結束
