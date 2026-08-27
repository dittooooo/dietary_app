import 'package:flutter/material.dart';
import '../../color/app_colors.dart'; // 匯入自訂的顏色設定檔（AppColors）

class UserDetailPage extends StatelessWidget {
  // 定義一個靜態的用戶詳細資訊頁面類別，繼承自 StatelessWidget
  final Map<String, String> userData; // 定義一個用來接收外部傳入使用者資料的 Map 物件
  const UserDetailPage({
    super.key,
    required this.userData,
  }); // 建構子，要求必須傳入 userData 資料

  @override // 覆寫父類別的 build 方法來建構畫面
  Widget build(BuildContext context) {
    // 建立畫面的核心 BuildContext 上下文方法
    return Scaffold(
      // 回傳 Scaffold 頁面結構，提供導航欄與主體結構
      backgroundColor: AppColors.surface, // 設定頁面背景顏色為自訂的表面顏色（AppColors.surface）
      appBar: AppBar(
        // 設定頂部的導航欄（AppBar）
        title: Text(
          userData['name']!,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ), // 設定導航欄標題為該使用者姓名，使用粗體深色字
        backgroundColor: AppColors.background, // 設定導航欄背景色為 AppColors.background
        elevation: 0, // 設定陰影高度為 0，使其呈現平面簡約風格
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
        ), // 設定導航欄按鈕圖示（如返回鍵）的顏色為深色
      ), // 導航欄結束
      body: SingleChildScrollView(
        // 頁面主體：支援滾動的單一子元件滾動視圖
        padding: const EdgeInsets.all(20), // 設定四周的內邊距（Padding）為 20 像素
        child: Column(
          // 使用垂直排列（Column）佈局
          children: [
            // 子元件清單開始
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

  Widget _buildDetailField(String label, String value) {
    // 封裝一個用來快速生成資訊展示欄位的方法，傳入標題標籤與值
    return Padding(
      // 回傳 Padding 元件，控制每個欄位的上下間距
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ), // 設定垂直方向（上下）的內邊距為 10 像素
      child: TextFormField(
        // 使用文字輸入框（TextFormField）來優美地展示數據
        initialValue: value, // 設定輸入框的初始數值為傳入的 value
        readOnly: true, // 將輸入框設為「唯讀」狀態，使用者無法編輯此欄位
        style: const TextStyle(
          color: AppColors.textPrimary,
        ), // 設定內容字體顏色為 AppColors.textPrimary
        decoration: InputDecoration(
          // 設定輸入框的樣式與裝飾（InputDecoration）
          labelText: label, // 設定輸入框上方的提示標題為 label
          labelStyle: const TextStyle(color: Colors.black54), // 設定標籤字體的顏色樣式
          filled: true, // 開啟背景填充色
          fillColor: AppColors.background, // 設定輸入框背景填滿色為 AppColors.background
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ), // 設定預設的外邊框圓角與邊框線顏色
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ), // 設定啟用狀態下的外邊框樣式
        ), // 裝飾結束
      ), // 文字輸入框結束
    ); // Padding 結束
  } // _buildDetailField 方法結束
} // UserDetailPage 類別結束
