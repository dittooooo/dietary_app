import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
import 'admin_add_item_page.dart'; // 匯入 admin_add_item_page.dart 元件庫或套件
import '../../color/app_colors.dart'; // 匯入 app_colors.dart 元件庫或套件
import '../../services/admin_service.dart'; // 匯入 admin_service.dart

class GenericAdminListPage extends StatefulWidget { // 定義 GenericAdminListPage 類別，繼承自 StatefulWidget
  final String title; // 宣告類別成員或方法內部的區域變數
  final String searchHint; // 宣告類別成員或方法內部的區域變數

  const GenericAdminListPage({ // 建立編譯期常數，優化 Flutter 渲染效能
    super.key, // 執行相對應的邏輯計算或設定屬性參數
    required this.title, // 執行相對應的邏輯計算或設定屬性參數
    this.searchHint = '輸入關鍵字查詢...', // 執行相對應的邏輯計算或設定屬性參數
  }); // 程式碼區塊或元件結構結束

  @override // 標記此方法為覆寫父類別之方法
  State<GenericAdminListPage> createState() => _GenericAdminListPageState(); // 執行相對應的邏輯計算或設定屬性參數
} // 程式碼區塊或元件結構結束

class _GenericAdminListPageState extends State<GenericAdminListPage> { // 定義 _GenericAdminListPageState 類別，繼承自 State
  final TextEditingController _searchController = TextEditingController(); // 宣告類別成員或方法內部的區域變數
  bool _isDeleteMode = false; // 宣告類別成員或方法內部的區域變數
  bool _isLoading = false; // 宣告類別成員或方法內部的區域變數

  List<dynamic> _dataList = []; // 從後端獲取的原始資料列表

  @override // 標記此方法為覆寫父類別之方法
  void initState() { // 初始化狀態生命週期方法，頁面建立時執行一次
    super.initState(); // 執行相對應的邏輯計算或設定屬性參數
    _fetchData(); // 執行相對應的邏輯計算或設定屬性參數
  } // 程式碼區塊或元件結構結束

  Future<void> _fetchData() async { // 定義非同步方法（Future），執行耗時操作
    setState(() => _isLoading = true); // 更新狀態數據並通知 UI 重新渲染畫面
    try {
      final query = _searchController.text.trim();
      List<dynamic> results = [];
      
      if (widget.title.contains('餐廳')) {
        results = await AdminService().listRestaurants(name: query);
      } else if (widget.title.contains('菜單')) {
        results = await AdminService().listMenuItems(dishName: query);
      } else if (widget.title.contains('飲食紀錄')) {
        // 飲食紀錄監控：使用 nickname 或 dishName 搜尋
        results = await AdminService().listDietRecords(dishName: query, nickname: query);
      }
      
      setState(() {
        _dataList = results;
      });
    } catch (e) {
      debugPrint('管理端加載資料出錯: $e');
    } finally {
      setState(() => _isLoading = false); // 更新狀態數據並通知 UI 重新渲染畫面
    }
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
    final isDietRecord = widget.title.contains('飲食紀錄');
    return Scaffold( // 建立頁面的基礎 Scaffold 骨架，提供頁面基本版面佈局
      backgroundColor: AppColors.surface, // 設定顏色數值（Color）
      appBar: AppBar( // 設定頂部的導航欄（AppBar）
        title: Text(_isDeleteMode ? '點擊以刪除' : widget.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
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
              onChanged: (value) => _fetchData(), // 執行相對應的邏輯計算或設定屬性參數
              decoration: InputDecoration( // 建立輸入框樣式裝飾（InputDecoration）
                filled: true, // 執行相對應的邏輯計算或設定屬性參數
                fillColor: AppColors.background, // 設定顏色數值（Color）
                hintText: widget.title.contains('飲食紀錄') ? '輸入餐點名稱或暱稱搜尋...' : widget.searchHint, // 執行相對應的邏輯計算或設定屬性參數
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary), // 設定顏色數值（Color）
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none), // 設定容器的圓角弧度半徑大小
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.border)), // 設定容器的圓角弧度半徑大小
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.primary)), // 設定容器的圓角弧度半徑大小
              ), // 執行相對應的邏輯計算或設定屬性參數
            ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
          Expanded( // 建立填充元件（Expanded），自動佔滿 Row 或 Column 的剩餘空間
            child: _isLoading // 執行相對應的邏輯計算或設定屬性參數
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) // 建立置中對齊元件（Center），將子元件居中顯示
                : _dataList.isEmpty // 執行相對應的邏輯計算或設定屬性參數
                    ? const Center(child: Text('查無資料', style: TextStyle(fontSize: 18, color: Colors.black54))) // 建立文字顯示元件（Text）
                    : ListView.builder( // 建立滾動清單元件（ListView），支援多個子元件滾動瀏覽
                        itemCount: _dataList.length, // 執行相對應的邏輯計算或設定屬性參數
                        itemBuilder: (context, index) { // 執行相對應的邏輯計算或設定屬性參數
                          final item = _dataList[index]; // 宣告類別成員或方法內部的區域變數
                          String name = '未命名';
                          String desc = '';
                          
                          if (widget.title.contains('餐廳')) {
                            name = item['name'] ?? '';
                            desc = '地址: ${item['address'] ?? ''} • 評分: ${item['stars'] ?? 0} 星';
                          } else if (widget.title.contains('菜單')) {
                            name = '${item['dishName'] ?? ''} (${item['restaurantName'] ?? ''})';
                            desc = '食材: ${item['ingredients'] ?? ''} • 推薦: ${item['recommendLevel'] ?? ''}';
                          } else if (widget.title.contains('飲食紀錄')) {
                            final userObj = item['user'] ?? {};
                            final nickname = userObj['userProfile']?.containsKey('nickname') == true
                                ? userObj['userProfile']['nickname']
                                : userObj['email']?.split('@')[0];
                            name = '${item['dishName'] ?? ''} (${nickname ?? ''})';
                            
                            final dateStr = item['createdAt'] != null
                                ? DateTime.parse(item['createdAt']).toLocal().toString().substring(0, 16)
                                : '無日期';
                            desc = '時段: ${item['mealType'] ?? ''} • 時間: $dateStr\n備註: ${item['description'] ?? ''}';
                          }

                          return Card( // 回傳建構完成的元件或方法計算結果
                            color: AppColors.background, // 設定顏色數值（Color）
                            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), // 設定外邊距或內邊距的數值大小（EdgeInsets）
                            elevation: 2, // 執行相對應的邏輯計算或設定屬性參數
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // 設定容器的圓角弧度半徑大小
                            child: ListTile( // 執行相對應的邏輯計算或設定屬性參數
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
                              subtitle: Text(desc, style: const TextStyle(color: Colors.black54)), // 建立文字顯示元件（Text）
                              trailing: Icon(
                                _isDeleteMode ? Icons.delete : Icons.edit,
                                size: 20,
                                color: _isDeleteMode ? AppColors.danger : AppColors.secondary,
                              ), // 設定顏色數值（Color）
                              onTap: () { // 執行相對應的邏輯計算或設定屬性參數
                                if (_isDeleteMode) { // 執行相對應的邏輯計算或設定屬性參數
                                  _showDeleteDialog(item); // 執行相對應的邏輯計算或設定屬性參數
                                } else { // 程式碼區塊或元件結構結束
                                  // 進入編輯畫面
                                  if (isDietRecord) {
                                    _showEditDietRecordDialog(item);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AdminAddItemPage(title: widget.title, editItem: item),
                                      ),
                                    ).then((value) {
                                      if (value == true) _fetchData();
                                    });
                                  }
                                } // 程式碼區塊或元件結構結束
                              }, // 程式碼區塊或元件結構結束
                            ), // 執行相對應的邏輯計算或設定屬性參數
                          ); // 程式碼區塊或元件結構結束
                        }, // 程式碼區塊或元件結構結束
                      ), // 執行相對應的邏輯計算或設定屬性參數
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
      floatingActionButton: FloatingActionButton( // 執行相對應的邏輯計算或設定屬性參數
              backgroundColor: AppColors.primary, // 設定顏色數值（Color）
              onPressed: () { // 執行相對應的邏輯計算或設定屬性參數
                if (isDietRecord) {
                  _showCreateDietRecordDialog();
                } else {
                  Navigator.push( // 導航路由跳轉：開啟並推入新頁面
                    context, // 執行相對應的邏輯計算或設定屬性參數
                    MaterialPageRoute( // 執行相對應的邏輯計算或設定屬性參數
                      builder: (context) => AdminAddItemPage(title: widget.title), // 執行相對應的邏輯計算或設定屬性參數
                    ), // 執行相對應的邏輯計算或設定屬性參數
                  ).then((value) { // 執行相對應的邏輯計算或設定屬性參數
                    if (value == true) _fetchData(); // 若新增成功則刷新
                  }); // 程式碼區塊或元件結構結束
                }
              }, // 程式碼區塊或元件結構結束
              child: const Icon(Icons.add, color: AppColors.background), // 設定顏色數值（Color）
            ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showDeleteDialog(dynamic item) { // 執行相對應的邏輯計算或設定屬性參數
    final int id = item['id'];
    showDialog( // 執行相對應的邏輯計算或設定屬性參數
      context: context, // 執行相對應的邏輯計算或設定屬性參數
      builder: (ctx) => AlertDialog( // 執行相對應的邏輯計算或設定屬性參數
        backgroundColor: AppColors.background, // 設定顏色數值（Color）
        title: const Text('確定刪除？', style: TextStyle(color: AppColors.textPrimary)), // 建立文字顯示元件（Text）
        content: const Text('此動作將會永久從後端資料庫物理移除這項資料。', style: TextStyle(color: Colors.black54)), // 建立文字顯示元件（Text）
        actions: [ // 執行相對應的邏輯計算或設定屬性參數
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.black54))), // 導航路由返回：關閉當前頁面並返回上一頁
          TextButton( // 執行相對應的邏輯計算或設定屬性參數
            onPressed: () async { // 執行相對應的邏輯計算或設定屬性參數
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在執行物理刪除...')));
              
              bool success = false;
              if (widget.title.contains('餐廳')) {
                success = await AdminService().deleteRestaurant(id);
              } else if (widget.title.contains('菜單')) {
                success = await AdminService().deleteMenuItem(id);
              } else if (widget.title.contains('飲食紀錄')) {
                success = await AdminService().deleteDietRecord(id);
              }

              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除成功！')));
                  _fetchData();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請檢查管理權限')));
                }
              }
            }, // 程式碼區塊或元件結構結束
            child: const Text('確定', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)), // 建立文字顯示元件（Text）
          ), // 執行相對應的邏輯計算或設定屬性參數
        ], // 執行相對應的邏輯計算或設定屬性參數
      ), // 執行相對應的邏輯計算或設定屬性參數
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  void _showEditDietRecordDialog(dynamic record) {
    final nameController = TextEditingController(text: record['dishName']);
    final descController = TextEditingController(text: record['description'] ?? '');
    final nutritionController = TextEditingController(text: record['nutrition'] ?? '');
    String mealType = record['mealType'] ?? 'LUNCH';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          title: const Text('編輯飲食監控數據', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '餐點名稱')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: '描述備註')),
                TextField(controller: nutritionController, decoration: const InputDecoration(labelText: '營養資訊')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('餐別時段：'),
                    DropdownButton<String>(
                      value: mealType,
                      dropdownColor: AppColors.background,
                      items: const [
                        DropdownMenuItem(value: 'BREAKFAST', child: Text('早餐')),
                        DropdownMenuItem(value: 'LUNCH', child: Text('午餐')),
                        DropdownMenuItem(value: 'DINNER', child: Text('晚餐')),
                      ],
                      onChanged: (val) => setDialogState(() => mealType = val!),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在保存更新...')));
                
                final payload = {
                  'dishName': nameController.text.trim(),
                  'description': descController.text.trim(),
                  'nutrition': nutritionController.text.trim(),
                  'mealType': mealType,
                };
                
                final res = await AdminService().updateDietRecord(record['id'], payload);
                if (mounted) {
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('飲食紀錄更新成功！')));
                    _fetchData();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失敗: ${res['message']}')));
                  }
                }
              },
              child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDietRecordDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final nutritionController = TextEditingController();
    String mealType = 'LUNCH';
    int? selectedUserId;
    List<dynamic> users = [];
    bool loadingUsers = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loadingUsers) {
            AdminService().listUsers().then((list) {
              setDialogState(() {
                users = list;
                loadingUsers = false;
                if (users.isNotEmpty) {
                  final firstUser = users[0];
                  final userObj = firstUser['user'] ?? {};
                  selectedUserId = userObj['id'];
                }
              });
            }).catchError((e) {
              setDialogState(() {
                loadingUsers = false;
              });
            });
            return const AlertDialog(
              backgroundColor: AppColors.background,
              title: Text('讀取使用者清單中...'),
              content: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Text('新增飲食紀錄', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('選擇使用者：'),
                      Expanded(
                        child: users.isEmpty
                            ? const Text('無使用者')
                            : DropdownButton<int>(
                                value: selectedUserId,
                                isExpanded: true,
                                dropdownColor: AppColors.background,
                                items: users.map((u) {
                                  final userObj = u['user'] ?? {};
                                  final int uId = userObj['id'] ?? 0;
                                  final String nick = u['nickname'] ?? (userObj['email'] != null ? userObj['email'].split('@')[0] : '無名稱');
                                  return DropdownMenuItem<int>(
                                    value: uId,
                                    child: Text('$nick (ID: $uId)'),
                                  );
                                }).toList(),
                                onChanged: (val) => setDialogState(() => selectedUserId = val),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '餐點名稱')),
                  TextField(controller: descController, decoration: const InputDecoration(labelText: '描述備註')),
                  TextField(controller: nutritionController, decoration: const InputDecoration(labelText: '營養資訊', hintText: '例：熱量: 500 kcal, 蛋白質: 20 g')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('餐別時段：'),
                      DropdownButton<String>(
                        value: mealType,
                        dropdownColor: AppColors.background,
                        items: const [
                          DropdownMenuItem(value: 'BREAKFAST', child: Text('早餐')),
                          DropdownMenuItem(value: 'LUNCH', child: Text('午餐')),
                          DropdownMenuItem(value: 'DINNER', child: Text('晚餐')),
                        ],
                        onChanged: (val) => setDialogState(() => mealType = val!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: () async {
                  if (selectedUserId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇要指派的使用者')));
                    return;
                  }
                  if (nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入餐點名稱')));
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在新增記錄...')));

                  final payload = {
                    'dishName': nameController.text.trim(),
                    'description': descController.text.trim(),
                    'nutrition': nutritionController.text.trim(),
                    'mealType': mealType,
                  };

                  final res = await AdminService().createDietRecord(selectedUserId!, payload);
                  if (mounted) {
                    if (res['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('飲食紀錄新增成功！')));
                      _fetchData();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失敗: ${res['message']}')));
                    }
                  }
                },
                child: const Text('新增', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
} // 程式碼區塊或元件結構結束
