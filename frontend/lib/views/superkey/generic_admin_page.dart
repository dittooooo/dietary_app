import 'package:flutter/material.dart'; // 匯入 material.dart 元件庫或套件
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
      final query = _searchController.text.trim().toLowerCase();
      
      // 不直接向後端同時帶入 nickname 與 dishName (會被後端 SQL 判定為 AND 導致找不到資料)
      // 先獲取全量數據，再於前端進行 OR 模糊比對篩選
      final allRecords = await AdminService().listDietRecords();
      
      final filteredList = allRecords.where((item) {
        if (query.isEmpty) return true;
        
        final dishName = (item['dishName'] ?? '').toString().toLowerCase();
        final description = (item['description'] ?? '').toString().toLowerCase();
        final userObj = item['user'] ?? {};
        final nickname = (userObj['userProfile']?['nickname'] ?? userObj['email']?.split('@')[0] ?? '').toString().toLowerCase();
        
        return dishName.contains(query) || description.contains(query) || nickname.contains(query);
      }).toList();

      setState(() {
        _dataList = filteredList;
      });
    } catch (e) {
      debugPrint('管理端加載資料出錯: $e');
    } finally {
      setState(() => _isLoading = false); // 更新狀態數據並通知 UI 重新渲染畫面
    }
  }

  @override // 標記此方法為覆寫父類別之方法
  Widget build(BuildContext context) { // 建立畫面的主要 build 方法，返回元件樹
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
                          
                          final dishNameStr = (item['dishName'] ?? '').toString();
                          final userObj = item['user'] is Map ? item['user'] : null;
                          String nicknameStr = '';
                          if (userObj != null) {
                            if (userObj['userProfile'] is Map && userObj['userProfile']['nickname'] != null) {
                              nicknameStr = userObj['userProfile']['nickname'].toString();
                            } else if (userObj['email'] != null) {
                              nicknameStr = userObj['email'].toString().split('@')[0];
                            }
                          }
                          name = (nicknameStr.isNotEmpty && nicknameStr != '無名稱')
                              ? '$dishNameStr ($nicknameStr)'
                              : dishNameStr;
                          
                          final rawDate = item['date'] ?? item['mealDate'] ?? item['createdAt'];
                          final dateStr = rawDate != null
                              ? DateTime.parse(rawDate.toString()).toLocal().toString().substring(0, 10)
                              : '無日期';

                          String displayMealType = item['mealType'] ?? '';
                          String rawDesc = (item['description'] ?? '').toString();
                          if (rawDesc.contains('[MealType:OTHER]')) {
                            displayMealType = 'OTHER';
                          }
                          String displayNote = _cleanDescription(rawDesc);

                          final mealTypeStr = displayMealType == 'BREAKFAST'
                              ? '早餐'
                              : (displayMealType == 'LUNCH'
                                  ? '午餐'
                                  : (displayMealType == 'DINNER' ? '晚餐' : '其他'));

                          final nutMap = item['nutrition'] is Map ? item['nutrition'] : {};
                          final rawCal = item['calories'] ?? nutMap['calories'];
                          final calText = _formatNutrient(rawCal, 'kcal');
                          final displayCalText = calText.isNotEmpty ? calText : '無數據';

                          desc = '時段: $mealTypeStr • 日期: $dateStr\n熱量: $displayCalText • 份量: ${item['amount'] ?? 1} 份\n備註: ${displayNote.isEmpty ? '無' : displayNote}';

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
                                  _showEditDietRecordDialog(item);
                                } // 程式碼區塊或元件結構結束
                              }, // 程式碼區塊或元件結構結束
                            ), // 執行相對應的邏輯計算或設定屬性參數
                          ); // 程式碼區塊或元件結構結束
                        }, // 程式碼區塊或元件結構結束
          ), // 執行相對應的邏輯計算或設定屬性參數
        ),
      ],
    ), // 執行相對應的邏輯計算或設定屬性參數
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          _showCreateDietRecordDialog();
        },
        child: const Icon(Icons.add, color: AppColors.background),
      ),
    ); // 程式碼區塊或元件結構結束
  } // 程式碼區塊或元件結構結束

  String _cleanDescription(String text) {
    return text
        .replaceAll(RegExp(r'\[UserId:\d+\]'), '')
        .replaceAll('[MealType:OTHER]', '')
        .trim();
  }

  String _formatNutrient(dynamic val, String unit) {
    if (val == null) return '';
    String str = val.toString().trim();
    if (str.isEmpty || str == 'null') return '';
    if (str.toLowerCase().contains(unit.toLowerCase())) {
      return str;
    }
    return '$str $unit';
  }

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
              
              final success = await AdminService().deleteDietRecord(id);

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
    final nameController = TextEditingController(text: record['dishName'] ?? '');
    final amountController = TextEditingController(text: '${record['amount'] ?? 1} 份');
    
    final nutMap = record['nutrition'] is Map ? record['nutrition'] : {};

    String rawCalStr = _formatNutrient(record['calories'] ?? nutMap['calories'], 'kcal');
    String rawProteinStr = _formatNutrient(record['protein'] ?? nutMap['protein'], 'g');
    String rawFatStr = _formatNutrient(record['fat'] ?? nutMap['fat'], 'g');
    String rawCarbsStr = _formatNutrient(record['carbohydrates'] ?? nutMap['carbohydrates'], 'g');

    bool autoFetched = false;
    final rawDesc = (record['description'] ?? '').toString();
    final descController = TextEditingController(text: _cleanDescription(rawDesc));
    
    String mealType = record['mealType'] ?? 'LUNCH';
    if (rawDesc.contains('[MealType:OTHER]')) {
      mealType = 'OTHER';
    } else if (!['BREAKFAST', 'LUNCH', 'DINNER', 'OTHER'].contains(mealType)) {
      mealType = 'OTHER';
    }

    DateTime selectedDate = DateTime.now();
    if (record['date'] != null) {
      try {
        selectedDate = DateTime.parse(record['date']);
      } catch (_) {}
    } else if (record['createdAt'] != null) {
      try {
        selectedDate = DateTime.parse(record['createdAt']);
      } catch (_) {}
    }

    int? selectedUserId = record['user']?['id'] ?? record['userId'];
    final matchUser = RegExp(r'\[UserId:(\d+)\]').firstMatch(rawDesc);
    if (matchUser != null) {
      selectedUserId = int.tryParse(matchUser.group(1) ?? '');
    }

    List<dynamic> users = [];
    bool loadingUsers = true;
    bool userHasError = false;
    bool nameHasError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loadingUsers) {
            AdminService().listUsers().then((list) {
              setDialogState(() {
                users = list;
                loadingUsers = false;
                if (selectedUserId == null && users.isNotEmpty) {
                  final firstUser = users[0];
                  final userObj = firstUser['user'] ?? {};
                  selectedUserId = userObj['id'];
                }
              });
            }).catchError((_) {
              setDialogState(() => loadingUsers = false);
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

          if (rawCalStr.isEmpty && !autoFetched) {
            autoFetched = true;
            AdminService().fetchDishNutrition(nameController.text.trim()).then((nut) {
              if (nut['calories'] != null) {
                setDialogState(() {
                  rawCalStr = '${nut['calories']} kcal';
                  if (nut['protein'] != null) rawProteinStr = '${nut['protein']} g';
                  if (nut['fat'] != null) rawFatStr = '${nut['fat']} g';
                  if (nut['carbohydrates'] != null) rawCarbsStr = '${nut['carbohydrates']} g';
                });
              }
            });
          }

          List<String> nutParts = [];
          if (rawCalStr.isNotEmpty) nutParts.add('熱量: $rawCalStr');
          if (rawProteinStr.isNotEmpty) nutParts.add('蛋白質: $rawProteinStr');
          if (rawFatStr.isNotEmpty) nutParts.add('脂肪: $rawFatStr');
          if (rawCarbsStr.isNotEmpty) nutParts.add('碳水: $rawCarbsStr');
          if (nutParts.isEmpty) nutParts.add('熱量: 估算中...');
          String nutritionText = nutParts.join(', ');

          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Text('編輯飲食監控數據', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 選擇使用者 (可編輯)
                  const Text('選擇使用者：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: userHasError ? AppColors.danger : AppColors.border,
                        width: userHasError ? 2.0 : 1.0,
                      ),
                    ),
                    child: users.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('無使用者可選擇', style: TextStyle(color: AppColors.danger)),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
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
                              onChanged: (val) {
                                setDialogState(() {
                                  selectedUserId = val;
                                  userHasError = false;
                                });
                              },
                            ),
                          ),
                  ),
                  if (userHasError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text('請選擇使用者', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),

                  // 2. 紀錄日期 (可編輯)
                  const Text('紀錄日期：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: AppColors.secondary),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 餐點名稱 (可編輯)
                  TextField(
                    controller: nameController,
                    onChanged: (val) {
                      if (userHasError || nameHasError) {
                        setDialogState(() => nameHasError = false);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '餐點名稱',
                      hintText: '例：火腿蛋吐司',
                      errorText: nameHasError ? '此欄位為必填' : null,
                      errorStyle: const TextStyle(color: AppColors.danger),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.danger, width: 2),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.danger, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. 數量 / 份量 (可編輯)
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: '數量 / 份量',
                      hintText: '例：1 份',
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. 餐別時段 (可編輯)
                  const Text('餐別時段：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: mealType,
                        isExpanded: true,
                        dropdownColor: AppColors.background,
                        items: const [
                          DropdownMenuItem(value: 'BREAKFAST', child: Text('早餐')),
                          DropdownMenuItem(value: 'LUNCH', child: Text('午餐')),
                          DropdownMenuItem(value: 'DINNER', child: Text('晚餐')),
                          DropdownMenuItem(value: 'OTHER', child: Text('其他')),
                        ],
                        onChanged: (val) => setDialogState(() => mealType = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. 營養資訊 (唯讀)
                  TextField(
                    readOnly: true,
                    controller: TextEditingController(text: nutritionText),
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: '營養資訊',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 7. 描述備註 (唯讀)
                  TextField(
                    readOnly: true,
                    controller: descController,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: '描述備註',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  bool hasErr = false;
                  if (selectedUserId == null) {
                    userHasError = true;
                    hasErr = true;
                  }
                  if (nameController.text.trim().isEmpty) {
                    nameHasError = true;
                    hasErr = true;
                  }

                  if (hasErr) {
                    setDialogState(() {});
                    return;
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在保存更新...')));

                  final dateStr = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                  final rawAmountStr = amountController.text.replaceAll(RegExp(r'[^\d]'), '');
                  final int parsedAmount = int.tryParse(rawAmountStr) ?? 1;
                  final dishNameStr = nameController.text.trim();

                  String apiMealType = mealType;
                  String userNote = _cleanDescription(descController.text);
                  if (userNote.isEmpty) {
                    userNote = '管理員手動新增紀錄';
                  }

                  String prefix = '[UserId:$selectedUserId]';
                  if (mealType == 'OTHER') {
                    apiMealType = 'DINNER';
                    prefix += '[MealType:OTHER]';
                  }

                  String apiDescription = '$prefix$userNote';

                  final nut = await AdminService().fetchDishNutrition(dishNameStr);

                  final Map<String, dynamic> payload = {
                    'dishName': dishNameStr,
                    'amount': parsedAmount,
                    'date': dateStr,
                    'mealType': apiMealType,
                    'description': apiDescription,
                    if (nut['calories'] != null) 'calories': nut['calories'],
                    if (nut['protein'] != null) 'protein': nut['protein'],
                    if (nut['fat'] != null) 'fat': nut['fat'],
                    if (nut['carbohydrates'] != null) 'carbohydrates': nut['carbohydrates'],
                  };

                  final res = await AdminService().updateDietRecord(record['id'], payload);
                  if (mounted) {
                    if (res['success'] == true) {
                      _fetchData();
                      showDialog(
                        context: context,
                        builder: (alertCtx) => AlertDialog(
                          backgroundColor: AppColors.background,
                          title: const Text('保存成功', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: const Text('飲食紀錄已成功更新！'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(alertCtx),
                              child: const Text('確定', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    } else {
                      final errMsg = res['message'] ?? res['error'] ?? '未知錯誤';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失敗: $errMsg')));
                    }
                  }
                },
                child: const Text('保存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getAutoMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return 'BREAKFAST';
    if (hour >= 11 && hour < 17) return 'LUNCH';
    return 'DINNER';
  }

  void _showCreateDietRecordDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '1 份');
    String mealType = _getAutoMealType();
    DateTime selectedDate = DateTime.now();
    int? selectedUserId;
    List<dynamic> users = [];
    bool loadingUsers = true;
    bool userHasError = false;
    bool nameHasError = false;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 選擇使用者
                  const Text('選擇使用者：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: userHasError ? AppColors.danger : AppColors.border,
                        width: userHasError ? 2.0 : 1.0,
                      ),
                    ),
                    child: users.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('無使用者可選擇', style: TextStyle(color: AppColors.danger)),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
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
                              onChanged: (val) {
                                setDialogState(() {
                                  selectedUserId = val;
                                  userHasError = false;
                                });
                              },
                            ),
                          ),
                  ),
                  if (userHasError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text('請選擇使用者', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),

                  // 2. 紀錄日期
                  const Text('紀錄日期：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: AppColors.secondary),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 餐點名稱
                  TextField(
                    controller: nameController,
                    onChanged: (val) {
                      if (userHasError || nameHasError) {
                        setDialogState(() => nameHasError = false);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '餐點名稱',
                      hintText: '例：火腿蛋吐司',
                      errorText: nameHasError ? '此欄位為必填' : null,
                      errorStyle: const TextStyle(color: AppColors.danger),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.danger, width: 2),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.danger, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. 數量 / 份量
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: '數量 / 份量',
                      hintText: '例：1 份',
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. 餐別時段 (包含早餐、午餐、晚餐、其他)
                  const Text('餐別時段：', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: mealType,
                        isExpanded: true,
                        dropdownColor: AppColors.background,
                        items: const [
                          DropdownMenuItem(value: 'BREAKFAST', child: Text('早餐')),
                          DropdownMenuItem(value: 'LUNCH', child: Text('午餐')),
                          DropdownMenuItem(value: 'DINNER', child: Text('晚餐')),
                          DropdownMenuItem(value: 'OTHER', child: Text('其他')),
                        ],
                        onChanged: (val) => setDialogState(() => mealType = val!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  bool hasErr = false;
                  if (selectedUserId == null) {
                    userHasError = true;
                    hasErr = true;
                  }
                  if (nameController.text.trim().isEmpty) {
                    nameHasError = true;
                    hasErr = true;
                  }

                  if (hasErr) {
                    setDialogState(() {});
                    return;
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在新增紀錄...')));

                  final dateStr = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                  final rawAmountStr = amountController.text.replaceAll(RegExp(r'[^\d]'), '');
                  final int parsedAmount = int.tryParse(rawAmountStr) ?? 1;
                  final dishNameStr = nameController.text.trim();

                  String apiMealType = mealType;
                  String userNote = '管理員手動新增紀錄';
                  String prefix = '[UserId:$selectedUserId]';
                  if (mealType == 'OTHER') {
                    apiMealType = 'DINNER';
                    prefix += '[MealType:OTHER]';
                  }

                  String apiDescription = '$prefix$userNote';

                  final nut = await AdminService().fetchDishNutrition(dishNameStr);

                  final Map<String, dynamic> payload = {
                    'dishName': dishNameStr,
                    'description': apiDescription,
                    'amount': parsedAmount,
                    'date': dateStr,
                    'mealType': apiMealType,
                    if (nut['calories'] != null) 'calories': nut['calories'],
                    if (nut['protein'] != null) 'protein': nut['protein'],
                    if (nut['fat'] != null) 'fat': nut['fat'],
                    if (nut['carbohydrates'] != null) 'carbohydrates': nut['carbohydrates'],
                  };

                  final res = await AdminService().createDietRecord(selectedUserId!, payload);
                  if (mounted) {
                    if (res['success'] == true) {
                      _fetchData();
                      showDialog(
                        context: context,
                        builder: (alertCtx) => AlertDialog(
                          backgroundColor: AppColors.background,
                          title: const Text('新增成功', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: const Text('飲食紀錄已成功新增至資料庫！'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(alertCtx),
                              child: const Text('確定', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    } else {
                      final errMsg = res['message'] ?? res['error'] ?? '未知錯誤';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增失敗: $errMsg')));
                    }
                  }
                },
                child: const Text('新增', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
} // 程式碼區塊或元件結構結束
