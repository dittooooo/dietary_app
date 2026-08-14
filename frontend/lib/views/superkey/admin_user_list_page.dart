import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'user_detail_page.dart'; // 匯入 user_detail_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/admin_service.dart'; // 匯入 admin_service.dart
import '../../utils/profile_value_mapper.dart'; // 匯入 ProfileValueMapper 進行字串對應轉換

class AdminUserListPage extends StatefulWidget { // 定義 AdminUserListPage 類別，繼承自 StatefulWidget
  const AdminUserListPage({super.key}); // 建立編譯期常數，優化 Flutter 渲染效能

  @override // 標記此方法為覆寫父類別之方法
  State<AdminUserListPage> createState() => _AdminUserListPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _AdminUserListPageState extends State<AdminUserListPage> { // 定義 _AdminUserListPageState 類別，繼承自 State
  final TextEditingController _searchController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  bool _isDeleteMode = false; // 宣告類別成員或方法內部的區域變數
  bool _isLoading = false;

  List<dynamic> _users = []; // 儲存後端獲取的使用者列表

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁年建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _fetchUsers(); // 獲取後端使用者清單
  } // 程式碼區塊或元件結構結束

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final list = await AdminService().listUsers(keyword: _searchController.text.trim());
      setState(() {
        _users = list;
      });
    } catch (e) {
      debugPrint('管理員獲取用戶清單錯誤: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: Text(_isDeleteMode ? '請點擊欲刪除的對象' : '使用者管理清單', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
        backgroundColor: _isDeleteMode ? AppColors.danger.withOpacity(0.1) : AppColors.background, // 設定顏色數值（Color）
        elevation: 0, // 執行相對應的邏輯計算或設定屬性參數
        iconTheme: const IconThemeData(color: AppColors.textPrimary), // 設定顏色數值（Color）
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          IconButton( // 建立點擊圖示按鈕（IconButton）
            icon: Icon(_isDeleteMode ? Icons.close : Icons.delete), // 顯示預設的圖示元件（Icon）
            onPressed: () => setState(() => _isDeleteMode = !_isDeleteMode), // 更新狀態數據並通知 UI 重新渲染畫面
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      body: Column( // 設定頁面的主要內容區域（body）
        children: [ // 執行相對應的邏輯計算或設定屬性參數
          Padding( // 建立間距容器（Padding），用於設定內部邊距
            padding: const EdgeInsets.all(15.0), // 設定外邊距或內邊距的數值大小（EdgeInsets）
            child: TextField( // 建立文字輸入框元件（TextField）
              controller: _searchController, // 執行相對應的邏輯計算或設定屬性參數
              onChanged: (value) => _fetchUsers(), // 輸入變更時重新查詢 API
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                filled: true, // 執行相對應的邏輯計算或設定屬性參數
                fillColor: AppColors.background, // 設定顏色數值（Color）
                hintText: '輸入名稱、帳號或 ID 查詢...', // 執行相對應的邏輯計算或設定屬性參數
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary), // 設定顏色數值（Color）
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none), // 設定容器的圓角弧度半徑大小
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.border)), // 設定容器的圓角弧度半徑大小
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.primary)), // 設定容器的圓角弧度半徑大小
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數

          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _users.isNotEmpty // 執行相對應的邏輯計算或設定屬性參數
                  ? ListView.builder( // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
                      itemCount: _users.length, // 執行相對應的邏輯計算或設定屬性參數
                      itemBuilder: (context, index) { // 執行相對應的邏輯計算或設定屬性參數
                        final userProfile = _users[index]; // 這是 UserProfile 物件
                        final userObj = userProfile['user'] ?? {}; // 內嵌的 User 物件
                        final int profileId = userProfile['id'] ?? 0;
                        final String email = userObj['email'] ?? '';
                        final String displayName = userProfile['nickname'] ?? (email.isNotEmpty ? email.split('@')[0] : '使用者');
                        
                        return Card( // 回傳建構完成的元件或方法計算結果
                          color: AppColors.background, // 設定顏色數值（Color）
                          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), // 設定外邊距或內边距的數值大小（EdgeInsets）
                          elevation: 2, // 執行相對應的邏輯計算或設定屬性參數
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // 設定容器的圓角弧度半徑大小
                          child: ListTile( // 執行相對應的邏輯計算或設定屬性參數
                            leading: CircleAvatar( // 執行相對應的邏輯計算或設定屬性參數
                              backgroundColor: AppColors.secondary, // 設定顏色數值（Color）
                              child: Text("#$profileId", style: const TextStyle(color: AppColors.background, fontSize: 12)), // 建立文字顯示元件（Text）
                            ), // 執行相對應的邏輯計算或設定屬性參數
                            title: Text( // 建立文字顯示元件（Text）
                              displayName, // 執行相對應的邏輯計算或設定屬性參數
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), // 設定文字字體大小、顏色與粗細等字型樣式（TextStyle）
                            ), // 執行相對應的邏輯計算或設定屬性參數
                            subtitle: Text(email.isNotEmpty ? email : '無電子郵件', style: const TextStyle(color: Colors.black54)), // 建立文字顯示元件（Text）
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.secondary), // 設定顏色數值（Color）
                            onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                              if (_isDeleteMode) { // 執行相對應的邏輯計算或設定屬性參數
                                _showDeleteConfirmDialog(profileId, displayName); // 執行相對應的邏輯計算或設定屬性參數
                              } else { // 程式碼區塊或元件結構結束
                                // 跳轉至使用者詳情頁，並將目標與疾病統一轉換為中文顯示
                                final String goalText = ProfileValueMapper.dietGoalsToDisplaySet(userProfile['dietGoal']).join(', ');
                                final String healthText = ProfileValueMapper.healthConditionsToDisplaySet(userProfile['healthConditions']).join(', ');

                                final Map<String, String> mappedDetail = {
                                  'id': "#$profileId",
                                  'name': displayName,
                                  'email': email,
                                  'gender': userProfile['gender'] ?? '未填',
                                  'height': "${userProfile['height'] ?? '未填'}",
                                  'weight': "${userProfile['weight'] ?? '未填'}",
                                  'goal': goalText.isNotEmpty ? goalText : '養成健康飲食習慣',
                                  'healthConditions': healthText.isNotEmpty ? healthText : '無疾病',
                                };
                                Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                                  context, // 執行相對應的邏輯計算或設定屬性參數
                                  MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                                    builder: (context) => UserDetailPage(userData: mappedDetail), // 執行相對應的邏輯計算或設定屬性參數
                                  ), // 執行相對應的邏輯計算或設定屬性參數
                                ); // 程式碼區塊或元件結構結束
                              } // 程式碼區塊或元件結構結束
                            }, // 程式碼區塊或元件結構結束
                          ), // 執行相對應的邏輯計算或設定屬性參數
                        ); // 程式碼區塊或元件結構結束
                      }, // 程式碼區塊或元件結構結束
                    ) // 執行相對應的邏輯計算或設定屬性參數
                  : const Center( // 建立置中對齊元件（Center），將子元件居中顯示
                      child: Text('找不到該使用者', style: TextStyle(fontSize: 18, color: Colors.black54)), // 建立文字顯示元件（Text）
                    ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      floatingActionButton: FloatingActionButton( // 執行相對應的邏輯計算或設定屬性參數
        backgroundColor: AppColors.primary, // 設定顏色數值（Color）
        onPressed: _showCreateUserDialog, // 新增使用者彈出對話框
        child: const Icon(Icons.add, color: AppColors.background), // 設定顏色數值（Color）
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showDeleteConfirmDialog(int userId, String name) { // 執行相對應的邏輯計算或設定屬性參數
    showDialog( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (BuildContext context) { // 執行相對應的邏輯計算或設定屬性參數
        return AlertDialog( // 回傳建構完成的元件或方法計算結果
          backgroundColor: AppColors.background, // 設定顏色數值（Color）
          title: const Text('確認刪除', style: TextStyle(color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
          content: Text('您確定要刪除使用者「$name」嗎？\\n此動作將會從資料庫中物理刪除該帳號及其關聯資料。', style: const TextStyle(color: Colors.black54)), // 建立文字顯示元件（Text）
          actions: [ // 執行相對應的邏輯計算或設定屬性參數
            TextButton( // 執行相對應的邏輯計算或設定屬性參數
              onPressed: () => Navigator.of(context).pop(), // 執行相對應的邏輯計算或設定屬性參數
              child: const Text('取消', style: TextStyle(color: Colors.black54)), // 建立文字顯示元件（Text）
            ), // 執行相對應的邏輯計算或設定屬性參數
            TextButton( // 執行相對應的邏輯計算或設定屬性參數
              onPressed: () async { // 執行相對應的邏輯計算或設定屬性參數
                Navigator.of(context).pop(); // 關閉對話框
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在執行物理刪除...')));
                
                final success = await AdminService().deleteUser(userId);
                
                if (mounted) {
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已成功刪除使用者：$name')));
                    _fetchUsers(); // 重新整理清單
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請檢查權限')));
                  }
                }
              }, // 程式碼區塊或元件結構結束
              child: const Text('確認刪除', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
            ), // 執行相對應的邏輯計算或設定屬性參數
          ], // 執行相對應的邏輯計算或設定屬性參數
        ); // 程式碼區塊或元件結構結束
      }, // 程式碼區塊或元件結構結束
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showCreateUserDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    final heightController = TextEditingController();
    final weightController = TextEditingController();
    final ageController = TextEditingController();
    
    String gender = '男';
    final Set<String> selectedDiseases = {'無疾病'};
    final Set<String> selectedGoals = {'養生'};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          title: const Text('新增使用者帳戶 (管理員特權)', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: emailController, decoration: const InputDecoration(labelText: '電子郵件 (帳號)')),
                TextField(controller: passwordController, decoration: const InputDecoration(labelText: '密碼'), obscureText: true),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '暱稱 / 姓名')),
                TextField(controller: heightController, decoration: const InputDecoration(labelText: '身高 (cm)'), keyboardType: TextInputType.number),
                TextField(controller: weightController, decoration: const InputDecoration(labelText: '體重 (kg)'), keyboardType: TextInputType.number),
                TextField(controller: ageController, decoration: const InputDecoration(labelText: '年齡'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),

                // 性別選擇
                Row(
                  children: [
                    const Text('性別：'),
                    Radio<String>(
                      value: '男',
                      groupValue: gender,
                      onChanged: (val) => setDialogState(() => gender = val!),
                    ),
                    const Text('男'),
                    Radio<String>(
                      value: '女',
                      groupValue: gender,
                      onChanged: (val) => setDialogState(() => gender = val!),
                    ),
                    const Text('女'),
                  ],
                ),
                const SizedBox(height: 10),

                // 疾病選擇 (多選)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('特殊疾病：'),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: ['無疾病', '糖尿病', '高血壓'].map((disease) {
                          final isSelected = selectedDiseases.contains(disease);
                          return FilterChip(
                            label: Text(disease),
                            selected: isSelected,
                            backgroundColor: Colors.transparent,
                            selectedColor: AppColors.secondary.withOpacity(0.2),
                            onSelected: (bool selected) {
                              setDialogState(() {
                                if (disease == '無疾病') {
                                  selectedDiseases.clear();
                                  selectedDiseases.add('無疾病');
                                } else {
                                  selectedDiseases.remove('無疾病');
                                  if (selectedDiseases.contains(disease)) {
                                    selectedDiseases.remove(disease);
                                    if (selectedDiseases.isEmpty) {
                                      selectedDiseases.add('無疾病');
                                    }
                                  } else {
                                    selectedDiseases.add(disease);
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 飲食目標選擇 (多選)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text('飲食目標：'),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: ['養生', '減脂', '增肌'].map((goal) {
                          final isSelected = selectedGoals.contains(goal);
                          return FilterChip(
                            label: Text(goal),
                            selected: isSelected,
                            backgroundColor: Colors.transparent,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            onSelected: (bool selected) {
                              setDialogState(() {
                                if (selectedGoals.contains(goal)) {
                                  if (selectedGoals.length > 1) {
                                    selectedGoals.remove(goal);
                                  }
                                } else {
                                  selectedGoals.add(goal);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),


              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                if (emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('帳號與密碼為必填欄位')));
                  return;
                }

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在創建帳戶...')));

                final Map<String, dynamic> payload = {
                  'email': emailController.text.trim(),
                  'password': passwordController.text,
                  'role': 'ROLE_USER', // 只能新增一般使用者
                  'name': nameController.text.trim().isNotEmpty ? nameController.text.trim() : null,
                  'gender': gender,
                  'age': int.tryParse(ageController.text),
                  'height': double.tryParse(heightController.text),
                  'weight': double.tryParse(weightController.text),
                  'petType': '狗兒', // 預設小精靈
                  'dietGoal': selectedGoals.join(', '),
                  'specialDisease': selectedDiseases.join(', '),
                };

                final res = await AdminService().createUser(payload);

                if (mounted) {
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('帳戶建立成功！')));
                    _fetchUsers(); // 刷新清單
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('帳戶建立失敗: ${res['message']}')));
                  }
                }
              },
              child: const Text('確認創建', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
