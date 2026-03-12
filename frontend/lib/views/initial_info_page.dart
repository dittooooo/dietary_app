import 'dart:math'; // 導入數學庫（用於計算旋轉與弧度）
import 'package:flutter/material.dart'; // 導入 Flutter 材質設計組件庫

class InitialInfoPage extends StatefulWidget {
  // 定義初始資訊填寫頁面 StatefulWidget
  const InitialInfoPage({super.key}); // 建構子

  @override
  State<InitialInfoPage> createState() => _InitialInfoPageState(); // 建立頁面狀態
}

class _InitialInfoPageState extends State<InitialInfoPage>
    with TickerProviderStateMixin {
  // 注入 Ticker 以支援動畫
  late PageController _pageController; // 宣告分頁控制器
  late AnimationController _pacmanController; // 宣告小精靈嘴巴動畫控制器
  int _currentPage = 0; // 追蹤當前所在頁碼

  static const TextStyle _titleStyle = TextStyle(
    // 標題風格定義
    fontSize: 20, // 字體大小
    fontWeight: FontWeight.bold, // 粗體
    color: Colors.black, // 黑色
  );

  static const TextStyle _inputTextStyle = TextStyle(
    // 輸入框字體風格
    fontWeight: FontWeight.bold, // 粗體
    fontSize: 16, // 中型字體
  );

  static const TextStyle _buttonTextStyle = TextStyle(
    // 按鈕文字風格
    fontSize: 16, // 字體大小
    fontWeight: FontWeight.bold, // 粗體
    color: Colors.black, // 黑色
  );

  final Map<int, String> _pageErrors = {}; // 儲存各頁面的錯誤訊息

  String _name = ''; // 保存：姓名
  String _gender = ''; // 保存：性別
  String _age = ''; // 保存：年齡
  String _height = ''; // 保存：身高
  String _weight = ''; // 保存：體重
  Set<String> _diseases = {}; // 保存：疾病集
  Set<String> _goals = {}; // 保存：目標集

  final List<String> _diseaseOptions = ['糖尿病', '高血壓', '無疾病']; // 疾病選項清單
  final List<String> _goalOptions = ['減脂', '增肌', '養生']; // 目標選項清單

  @override
  void initState() {
    // 狀態初始化
    super.initState(); // 執行父類初始化
    _pageController = PageController(); // 建立分頁控制器實體
    _pacmanController = AnimationController(
      // 初始化嘴巴動畫
      vsync: this, // 綁定 Ticker
      duration: const Duration(milliseconds: 300), // 動畫週期
    )..repeat(reverse: true); // 循環往復播放
  }

  @override
  void dispose() {
    // 狀態銷毀時執行
    _pageController.dispose(); // 釋放分頁控制器資源
    _pacmanController.dispose(); // 釋放嘴巴動畫控制器
    super.dispose(); // 執行父類銷毀
  }

  void _nextPage() {
    // 下一頁處理邏輯
    if (!_canProceed()) {
      // 檢查當前頁面是否完成
      final msg = _validationMessage(); // 獲取報錯訊息
      setState(() {
        // 更新 UI
        _pageErrors[_currentPage] = msg; // 記錄該頁錯誤
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg))); // 顯示錯誤提示
      return; // 停止執行
    }

    if (_currentPage < 6) {
      // 若非最後一頁
      _pageController.nextPage(
        // 執行翻頁動畫
        duration: const Duration(milliseconds: 500), // 設定動畫時長
        curve: Curves.easeInOut, // 設定動畫曲線
      );
    } else {
      // 若為最後一頁
      _completeSetup(); // 執行完成設置
    }
  }

  void _previousPage() {
    // 上一頁處理邏輯
    if (_currentPage > 0) {
      // 若非第一頁
      _pageController.previousPage(
        // 執行回翻動畫
        duration: const Duration(milliseconds: 400), // 動畫時長
        curve: Curves.easeInOut, // 動畫曲線
      );
    }
  }

  bool _isNumeric(String? s) {
    // 判斷是否為有效數字的輔助函式
    if (s == null || s.trim().isEmpty) return false;
    return double.tryParse(s.trim()) != null; // 使用 double.tryParse 嘗試轉換
  }

  bool _canProceed() {
    // 頁面校驗判斷
    switch (_currentPage) {
      // 根據頁碼判斷
      case 0:
        return _name.trim().isNotEmpty; // 頁面0：名字必填
      case 1:
        return _gender.isNotEmpty; // 頁面1：性別必選
      case 2:
        return _isNumeric(_age); // 頁面2：年齡必須是數字
      case 3:
        return _isNumeric(_height) && _isNumeric(_weight); // 頁面3：身高體重必須是數字
      case 4:
        return _diseases.isNotEmpty; // 頁面4：疾病必選
      case 5:
        return _goals.isNotEmpty; // 頁面5：目標必選
      case 6:
        return true; // 頁面6：精靈選擇暫不強制
      default:
        return true; // 預設返回 True
    }
  }

  String _validationMessage() {
    // 錯誤訊息生成器
    switch (_currentPage) {
      // 根據頁碼返回對應文字
      case 0:
        return '請輸入您的名字'; // 姓名報錯
      case 1:
        return '請選擇性別'; // 性別報錯
      case 2:
        if (_age.trim().isEmpty) return '請輸入年齡';
        return '年齡必須為數字'; // 年齡非數字報錯
      case 3:
        if (_height.trim().isEmpty || _weight.trim().isEmpty) return '請輸入身高與體重';
        if (!_isNumeric(_height)) return '身高必須為數字';
        if (!_isNumeric(_weight)) return '體重必須為數字';
        return '請輸入正確的身高與體重'; // 身高體重格式報錯
      case 4:
        return '請選擇是否有特殊疾病'; // 疾病報錯
      case 5:
        return '請選擇至少一個飲食目標'; // 目標報錯
      default:
        return '請完成本頁內容'; // 其他通用報錯
    }
  }

  void _completeSetup() {
    // 完成設置邏輯
    final Map<String, dynamic> userSetupData = {
      // 封裝用戶數據為 Map
      'name': _name, // 名字
      'gender': _gender, // 性別
      'age': double.tryParse(_age)?.toInt() ?? 0, // 年齡 (轉型)
      'height': double.tryParse(_height) ?? 0, // 身高 (轉型)
      'weight': double.tryParse(_weight) ?? 0, // 體重 (轉型)
      'diseases': _diseases.toList(), // 疾病列表
      'goals': _goals.toList(), // 目標列表
      'timestamp': DateTime.now().toIso8601String(), // 提交時間戳
    };

    debugPrint('提交使用者資料: $userSetupData'); // 使用數據以消除 Lint 警告，並供後續 API 調試

    // ===== 預留後端 API 對接點 =====
    // TODO: 整合 http 套件提交 userSetupData

    Navigator.pushReplacementNamed(context, '/home'); // 跳轉至首頁 (暫定)
  }

  @override
  Widget build(BuildContext context) {
    // 建立畫面 UI
    return Container(
      // 主容器
      color: const Color(0xFFF5F0EB), // 米色背景
      child: Stack(
        // 疊層佈局
        children: [
          AnimatedBuilder(
            // 監聽進度與動畫以平滑移動小精靈
            animation: Listenable.merge([
              _pageController,
              _pacmanController,
            ]), // 整合兩個動畫源
            builder: (context, child) {
              return CustomPaint(
                // 背景手繪筆記本畫布
                painter: HandDrawnNotebookPainter(
                  scrollProgress: _pageController.hasClients
                      ? (_pageController.page ?? 0)
                      : 0, // 傳遞平滑滾動進度
                  mouthProgress: _pacmanController.value, // 傳遞嘴巴張合值
                ),
                size: Size.infinite, // 鋪滿全屏
              );
            },
          ),
          PageView.builder(
            // 分頁滾動組件
            controller: _pageController, // 控制器連結
            scrollDirection: Axis.vertical, // 垂直捲動模式
            onPageChanged: (index) {
              // 頁面切換後動作
              setState(() {
                // 更新狀態
                _currentPage = index; // 刷新頁碼
              });
            },
            pageSnapping: true, // 啟用頁面捕捉 (整頁對齊)
            physics: const PageScrollPhysics(), // 設定分頁物理效果
            itemCount: 7, // 總頁數
            itemBuilder: (context, index) {
              // 構建分頁內容
              return _buildPageByIndex(index); // 根據索引調用子頁面
            },
          ),
          AnimatedBuilder(
            // 動畫建構器
            animation: _pageController, // 監聽控制器
            builder: (context, child) {
              // 建置邏輯
              if (_pageController.positions.isEmpty) {
                // 檢查位置是否初始化
                return Container(); // 未初始化則不顯示
              }

              double pageValue =
                  _pageController.page ?? _currentPage.toDouble(); // 獲取當前偏移值

              if ((pageValue - pageValue.floor()).abs() > 0.01 && // 若正在翻頁過渡中
                  (pageValue - pageValue.floor()).abs() < 0.99) {
                // 判定過渡區間
                return CustomPaint(
                  // 顯示翻頁特效畫布
                  painter: PageFlipPainter(
                    progress: pageValue - pageValue.floor(),
                  ), // 同步翻頁進度
                  size: Size.infinite, // 鋪滿全屏
                );
              }

              return Container(); // 靜態狀態返回空
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPageContainer({
    // 封裝頁面通用容器
    required String title, // 頁面標題
    required Widget content, // 內容組件
    bool scrollable = true, // 是否可捲動
  }) {
    return Padding(
      // 內容邊距設定
      padding: const EdgeInsets.fromLTRB(60, 140, 60, 70), // 設定四邊間距
      child: Stack(
        // 頁面內部疊層
        clipBehavior: Clip.none, // 允許裝飾物溢出
        children: [
          Column(
            // 垂直排列
            crossAxisAlignment: CrossAxisAlignment.start, // 靠左對齊
            children: [
              Material(
                // 標題文字層
                color: Colors.transparent, // 背景透明
                child: Text(
                  // 顯示標題
                  title, // 標題內容
                  style: _titleStyle, // 標題風格
                ),
              ),
              const SizedBox(height: 20), // 標題與內容間距
              Expanded(
                // 撐開剩餘空間
                child:
                    scrollable // 根據設定決定捲動性
                    ? SingleChildScrollView(child: content) // 啟動捲動
                    : content, // 靜態展示
              ),
              SizedBox(height: scrollable ? 60 : 20), // 底部保留緩衝空間
            ],
          ),
          Positioned(
            // 按鈕定位
            bottom: 0, // 固定底部
            left: 0, // 靠左
            right: 0, // 靠右
            child: Row(
              // 水平排列按鈕
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // 兩端對齊
              children: [
                if (_currentPage > 0) // 若非第一頁顯示返回鍵
                  GestureDetector(
                    // 手勢檢測
                    onTap: _previousPage, // 點擊返回
                    child: CustomPaint(
                      // 繪製紙膠帶按鈕
                      painter: WashiTapeButtonPainter(text: '返回修改'), // 按鈕文字
                      size: const Size(120, 45), // 按鈕尺寸
                    ),
                  )
                else
                  const SizedBox(width: 120), // 第一頁則留白佔位

                GestureDetector(
                  // 下一頁手勢檢測
                  onTap: _nextPage, // 點擊下一頁
                  child: CustomPaint(
                    // 繪製紙膠帶按鈕
                    painter: WashiTapeButtonPainter(
                      text: _currentPage == 6 ? '完成' : '下一頁 >',
                    ), // 文字切換
                    size: const Size(120, 45), // 按鈕尺寸
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageByIndex(int index) {
    // 頁面導引邏輯
    switch (index) {
      // 分頁控制
      case 0:
        return _buildNamePage(); // 0號頁：名字
      case 1:
        return _buildGenderPage(); // 1號頁：性別
      case 2:
        return _buildAgePage(); // 2號頁：年齡
      case 3:
        return _buildHeightWeightPage(); // 3號頁：身高體重
      case 4:
        return _buildDiseasesPage(); // 4號頁：疾病
      case 5:
        return _buildGoalsPage(); // 5號頁：目標
      case 6:
        return _buildElfSelectionPage(); // 6號頁：精靈選擇
      default:
        return _buildNamePage(); // 預設返回名字頁
    }
  }

  Widget _buildNamePage() {
    // 建構名字頁面
    return _buildPageContainer(
      // 調用通用組件
      title: '嗨！您想我如何稱呼您呢?', // 設定標題
      content: Column(
        // 內容區域
        crossAxisAlignment: CrossAxisAlignment.start, // 靠左
        children: [
          _buildHandDrawnTextField(
            '輸入您的名字',
            (value) => setState(() {
              // 建立手繪輸入框
              _name = value; // 同步資料
              _pageErrors.remove(0); // 清除錯誤標記
            }),
            initialValue: _name,
          ), // 初始值
          if (_pageErrors.containsKey(0)) // 若有錯誤
            Padding(
              padding: const EdgeInsets.only(top: 8.0), // 錯誤文字邊距
              child: Text(
                _pageErrors[0]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ), // 顯示錯誤紅字
            ),
        ],
      ),
    );
  }

  Widget _buildGenderPage() {
    // 建構性別頁面
    return _buildPageContainer(
      // 調用容器
      title: '您的性別是?', // 標題
      content: Column(
        // 垂直內容
        crossAxisAlignment: CrossAxisAlignment.start, // 靠左
        children: [
          Row(
            // 水平排列按鈕
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 平均分配
            children: [
              _buildHandDrawnButton(
                '男',
                _gender == '男',
                () => setState(() {
                  // 建立男按鈕
                  _gender = '男'; // 選中男
                  _pageErrors.remove(1); // 清除錯誤
                }),
              ),
              _buildHandDrawnButton(
                '女',
                _gender == '女',
                () => setState(() {
                  // 建立女按鈕
                  _gender = '女'; // 選中女
                  _pageErrors.remove(1); // 清除錯誤
                }),
              ),
            ],
          ),
          if (_pageErrors.containsKey(1)) // 顯示錯誤訊息
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _pageErrors[1]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAgePage() {
    // 建構年齡頁面
    return _buildPageContainer(
      // 容器
      title: '請輸入您的年齡', // 標題
      content: Column(
        // 內容
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHandDrawnTextField(
            '年齡',
            (value) => setState(() {
              // 建立輸入框
              _age = value; // 同步資料
              _pageErrors.remove(2); // 清除錯誤
            }),
            isNumber: true,
            initialValue: _age,
          ), // 設定為數字模式
          if (_pageErrors.containsKey(2)) // 報錯處理
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _pageErrors[2]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeightWeightPage() {
    // 建構身高體重頁面
    return _buildPageContainer(
      // 容器
      title: '請輸入您的身高與體重', // 標題
      content: Column(
        // 內容
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // 水平兩欄
            children: [
              Expanded(
                // 身高欄
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '身高',
                      style: _buttonTextStyle.copyWith(fontSize: 16),
                    ), // 標籤
                    const SizedBox(height: 12),
                    _buildHandDrawnTextField(
                      'cm',
                      (value) => setState(() {
                        // 輸入框
                        _height = value; // 同步身高
                        _pageErrors.remove(3); // 清除錯誤
                      }),
                      isNumber: true,
                      initialValue: _height,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20), // 欄位間距
              Expanded(
                // 體重欄
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '體重',
                      style: _buttonTextStyle.copyWith(fontSize: 16),
                    ), // 標籤
                    const SizedBox(height: 12),
                    _buildHandDrawnTextField(
                      'kg',
                      (value) => setState(() {
                        // 輸入框
                        _weight = value; // 同步體重
                        _pageErrors.remove(3); // 清除錯誤
                      }),
                      isNumber: true,
                      initialValue: _weight,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_pageErrors.containsKey(3)) // 報錯處理
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _pageErrors[3]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiseasesPage() {
    // 建構疾病頁面
    return _buildPageContainer(
      // 容器
      title: '您是否患有特殊疾病?', // 標題
      content: Column(
        // 內容
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            // 自動換行列表
            spacing: 12, // 間距
            runSpacing: 12, // 行間距
            children:
                _diseaseOptions // 對映疾病清單
                    .map(
                      (disease) => _buildHandDrawnToggleButton(
                        // 建立選取鈕
                        disease, // 選項文字
                        _diseases.contains(disease), // 是否選中
                        () {
                          // 點擊切換
                          setState(() {
                            if (_diseases.contains(disease)) {
                              _diseases.remove(disease); // 移出
                            } else {
                              _diseases.add(disease); // 加入
                            }
                            if (_diseases.isNotEmpty)
                              _pageErrors.remove(4); // 清除錯誤
                          });
                        },
                      ),
                    )
                    .toList(),
          ),
          if (_pageErrors.containsKey(4)) // 報錯處理
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _pageErrors[4]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoalsPage() {
    // 建構目標頁面
    return _buildPageContainer(
      // 容器
      title: '您的飲食目標是?', // 標題
      content: Column(
        // 內容
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            // 換行列表
            spacing: 12, // 間距
            runSpacing: 12, // 行間距
            children:
                _goalOptions // 對映目標清單
                    .map(
                      (goal) => _buildHandDrawnToggleButton(
                        // 選取鈕
                        goal, // 文字
                        _goals.contains(goal), // 狀態
                        () {
                          // 切換動作
                          setState(() {
                            if (_goals.contains(goal)) {
                              _goals.remove(goal); // 移除
                            } else {
                              _goals.add(goal); // 新增
                            }
                            if (_goals.isNotEmpty)
                              _pageErrors.remove(5); // 清除錯誤
                          });
                        },
                      ),
                    )
                    .toList(),
          ),
          if (_pageErrors.containsKey(5)) // 報錯處理
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _pageErrors[5]!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildElfSelectionPage() {
    // 建構精靈選擇頁面
    return _buildPageContainer(
      // 調用容器
      title: '請選擇您專屬的小精靈', // 標題
      scrollable: false, // 禁止捲動以保持置中
      content: SizedBox.expand(
        // 撐滿全屏
        child: Stack(
          // 疊層佈局
          alignment: Alignment.center, // 內部元件置中
          clipBehavior: Clip.none, // 允許溢出
          children: [
            Align(
              // 絕對置對對齊
              alignment: Alignment.center,
              child: _buildHandDrawnBox(
                // 手繪展示方框
                width: 220, // 寬度
                height: 220, // 高度
                child: const Center(
                  // 內容置中
                  child: Icon(
                    Icons.favorite,
                    color: Color(0xFFFFA500),
                    size: 120,
                  ), // 精靈佔位符
                ),
              ),
            ),
            Positioned(
              // 左側導航按鈕定位
              left: -20,
              child: _buildSideNavButton('left', () {}), // 左箭頭
            ),
            Positioned(
              // 右側導航按鈕定位
              right: -20,
              child: _buildSideNavButton('right', () {}), // 右箭頭
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavButton(String direction, VoidCallback onTap) {
    // 側邊導航組件
    return GestureDetector(
      // 手勢
      onTap: onTap, // 點擊動作
      child: Container(
        // 裝飾容器
        width: 55,
        height: 100, // 尺寸
        decoration: BoxDecoration(
          // 風格
          color: const Color(0xFF444444), // 深灰色
          borderRadius: BorderRadius.circular(6), // 圓角
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ], // 陰影
        ),
        alignment: Alignment.center, // 內部置中
        child: CustomPaint(
          painter: ArrowPainter(direction: direction),
          size: const Size(25, 25),
        ), // 繪製箭頭
      ),
    );
  }

  Widget _buildHandDrawnTextField(
    String hint,
    Function(String) onChanged, {
    bool isNumber = false,
    String initialValue = '',
  }) {
    // 手繪输入框
    return CustomPaint(
      // 畫布
      painter: HandDrawnBoxPainter(), // 手繪框畫筆
      child: Material(
        // 材質層
        color: Colors.transparent, // 透明
        child: Container(
          // 內距容器
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: TextField(
            // 文字輸入組件
            controller: TextEditingController.fromValue(
              // 設定初始值與游標
              TextEditingValue(
                text: initialValue,
                selection: TextSelection.fromPosition(
                  TextPosition(offset: initialValue.length),
                ),
              ),
            ),
            keyboardType: isNumber
                ? TextInputType.number
                : TextInputType.text, // 鍵盤模式
            onChanged: onChanged, // 回呼函數
            style: _inputTextStyle, // 字體風格
            decoration: InputDecoration(
              // 內部裝飾
              hintText: hint, // 提示
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none, // 取消原生邊框
              isDense: true, // 緊湊佈局
              contentPadding: EdgeInsets.zero, // 無內距
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandDrawnButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    // 手繪普通按鈕
    return GestureDetector(
      // 手勢
      onTap: onTap, // 點擊回呼
      child: CustomPaint(
        // 畫布
        painter: HandDrawnBoxPainter(isSelected: isSelected), // 框畫筆 (帶選中狀態)
        child: Material(
          // 材質底層
          color: Colors.transparent, // 透明
          child: Container(
            // 按鈕佈局
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            child: Text(
              // 標籤文字
              label,
              style: _buttonTextStyle.copyWith(
                // 動態變色
                color: isSelected ? const Color(0xFFFFA500) : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandDrawnToggleButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    // 手繪切換圓角按鈕
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: HandDrawnRoundedBoxPainter(isSelected: isSelected), // 圓角框畫筆
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: _buttonTextStyle.copyWith(
                fontSize: 14,
                color: isSelected ? const Color(0xFFFFA500) : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandDrawnBox({
    required Widget child,
    double width = 200,
    double height = 200,
  }) {
    // 純飾性手繪框
    return CustomPaint(
      painter: HandDrawnBoxPainter(), // 畫筆
      child: Container(
        width: width, // 寬度
        height: height, // 高度
        alignment: Alignment.center, // 置中
        child: child, // 所含內容
      ),
    );
  }
}

// ===== 手繪筆記本整體背景繪製器 =====
class HandDrawnNotebookPainter extends CustomPainter {
  // 定義畫筆類別
  final double scrollProgress; // 保存平滑滾動偏移量
  final double mouthProgress; // 保存嘴巴張合進度 (0~1)
  HandDrawnNotebookPainter({
    required this.scrollProgress,
    required this.mouthProgress,
  }); // 建構子

  @override
  void paint(Canvas canvas, Size size) {
    // 執行繪製邏輯
    final Rect rect = Offset.zero & size; // 定義全屏矩形
    final Paint paint = Paint()..color = const Color(0xFFF5F0EB); // 設定底色 (米白色)
    canvas.drawRect(rect, paint); // 填滿畫布底色

    // 計算「紙張」的範圍 (留出邊緣)
    double margin = 20; // 邊距
    double paperW = size.width - margin * 2; // 紙張寬度
    double paperH = size.height - margin * 2; // 紙張高度
    Offset paperOrigin = Offset(margin, margin); // 紙張起點

    // 1. 繪製紙張底色 (白色，帶一點手繪不規則感)
    Paint paperPaint = Paint()..color = Colors.white; // 白色畫筆
    Path paperPath = _getHandDrawnRectPath(
      paperOrigin,
      paperW,
      paperH,
    ); // 獲取手繪路徑

    // 繪製紙張陰影
    canvas.drawShadow(
      paperPath,
      Colors.black.withOpacity(0.1),
      10.0,
      true,
    ); // 加上淡淡投影
    canvas.drawPath(paperPath, paperPaint); // 畫出白色紙面

    // 2. 橫線已依需求移除，保持白色頁面純度

    // 3. 繪製活頁孔位與圈環 (位於頂部，製造筆記本感)
    _drawBinderRings(canvas, paperOrigin, paperW); // 調用子函數繪製

    // 4. 繪製頁面進度 UI (Pac-Man 升級版：大尺寸 + 動畫)
    _drawPacManProgress(canvas, paperOrigin, paperW); // 調用子函數繪製

    // 5. 繪製右下角的裝飾性山丘與小人 (最後一頁精靈選擇頁不顯示，且上移避免被按鈕擋住)
    if (scrollProgress < 5.5) {
      // 判斷是否接近最後一頁
      _drawHillAndFigure(canvas, paperOrigin, paperW, paperH); // 調用子函數繪製
    }
  }

  // 生成不規則的手繪感矩形路徑
  Path _getHandDrawnRectPath(Offset origin, double w, double h) {
    // 計算路徑
    Path path = Path(); // 建立路徑實體
    Random rand = Random(); // 亂數產生器

    path.moveTo(origin.dx, origin.dy); // 移動到左上角

    // 頂邊 (由左向右，每 20 像素抖動一次)
    for (double x = 0; x < w; x += 20) {
      // 迴圈分段
      double nextX = origin.dx + x + 20; // 下一點 X
      path.quadraticBezierTo(
        // 使用二次貝茲曲線製造彎曲
        origin.dx + x + 10 + rand.nextDouble() * 2, // 控制點 X
        origin.dy - 2 + rand.nextDouble() * 2, // 控制點 Y (抖動)
        nextX, // 終點 X
        origin.dy, // 終點 Y
      );
    }

    // 右邊 (由上向下)
    for (double y = 0; y < h; y += 20) {
      // 迴圈分段
      double nextY = origin.dy + y + 20; // 下一點 Y
      path.quadraticBezierTo(
        // 彎曲路徑
        origin.dx + w + 2 + rand.nextDouble() * 2, // 抖動
        origin.dy + y + 10, // 控制點 Y
        origin.dx + w, // 終點 X
        nextY, // 終點 Y
      );
    }

    // 底邊 (由右向左)
    for (double x = w; x > 0; x -= 20) {
      // 迴圈分段
      double nextX = origin.dx + x - 20; // 下一點 X
      path.quadraticBezierTo(
        // 彎曲路徑
        origin.dx + x - 10 + rand.nextDouble() * 2, // 抖動
        origin.dy + h + 2 + rand.nextDouble() * 2, // 控制點 Y
        nextX, // 終點 X
        origin.dy + h, // 終點 Y
      );
    }

    // 左邊 (由下向上)
    for (double y = h; y > 0; y -= 20) {
      // 迴圈分段
      double nextY = origin.dy + y - 20; // 下一點 Y
      path.quadraticBezierTo(
        // 彎曲路徑
        origin.dx - 2 + rand.nextDouble() * 2, // 控制點 X (抖動)
        origin.dy + y - 10, // 控制點 Y
        origin.dx, // 終點 X
        nextY, // 終點 Y
      );
    }

    path.close(); // 封閉路徑
    return path; // 返回生成的路徑
  }

  // 繪製活頁線圈 (金屬風格)
  void _drawBinderRings(Canvas canvas, Offset origin, double w) {
    // 子函數邏輯
    int ringCount = 18; // 線圈數量
    double yPos = origin.dy; // 紙張頂邊位置
    double ringSpacing = w / (ringCount + 1); // 線圈間距

    Paint ringPaint =
        Paint() // 金屬色畫筆
          ..color =
              const Color(0xFF707070) // 灰色
          ..style = PaintingStyle
              .stroke // 描邊
          ..strokeWidth = 2.5; // 線寬

    Paint shadowPaint =
        Paint() // 陰影畫筆
          ..color = Colors.black
              .withOpacity(0.2) // 黑色透明
          ..style = PaintingStyle
              .stroke // 描邊
          ..strokeWidth = 2.5;

    for (int i = 1; i <= ringCount; i++) {
      // 根據數量繪製
      double cx = origin.dx + ringSpacing * i; // 計算圓心 X

      canvas.drawArc(
        // 繪製陰影弧線 (稍微偏移)
        Rect.fromCircle(center: Offset(cx + 1, yPos + 1), radius: 12),
        -0.8 * pi,
        1.6 * pi,
        false,
        shadowPaint,
      );

      Rect ringRect = Rect.fromCenter(
        center: Offset(cx, yPos),
        width: 10,
        height: 24,
      ); // 線圈橢圓範圍
      canvas.drawArc(
        ringRect,
        -0.8 * pi,
        1.6 * pi,
        false,
        ringPaint,
      ); // 繪製主要金屬圈

      Paint holePaint = Paint()..color = Colors.black; // 孔位畫筆
      canvas.drawCircle(Offset(cx, yPos + 15), 3, holePaint); // 畫出穿紙的小黑洞
    }
  }

  // 繪製 Pac-Man 進度點 (升級：雙倍大小 + 嘴巴張合動畫 + 平滑移動)
  void _drawPacManProgress(Canvas canvas, Offset origin, double w) {
    double yPos = origin.dy + 75; // 稍微下移，適配更大的尺寸
    int dotCount = 7; // 進度點數量
    double dotSpacing = w / (dotCount + 1); // 點間距

    for (int i = 1; i <= dotCount; i++) {
      // 繪製豆子
      double dotX = origin.dx + dotSpacing * i; // 座標 X
      // 根據小精靈當前位置判斷豆子是否被吃掉
      if (i > scrollProgress + 1.2) {
        Paint dotPaint = Paint()..color = Colors.black;
        canvas.drawCircle(Offset(dotX, yPos), 7, dotPaint); // 豆子放大一倍 (3.5 -> 7)
      }
    }

    // 小精靈位置隨捲動平滑計算
    double pacX = origin.dx + dotSpacing * (scrollProgress + 1);
    Paint pacPaint = Paint()
      ..color = const Color(0xFFFFA500)
      ..style = PaintingStyle.fill;

    // 計算嘴巴開合角度 (動態張合)
    double openingAngle = 0.1 * pi + (0.25 * pi * mouthProgress); // 嘴巴張開的弧度
    double startAngle = openingAngle; // 起始角
    double sweepAngle = 2 * pi - (2 * openingAngle); // 掃描角 (剩下的圓)

    Path pacPath = Path(); // 建立 Pac-Man 形狀
    pacPath.moveTo(pacX, yPos); // 移至圓心以畫出扇形
    pacPath.arcTo(
      Rect.fromCircle(
        center: Offset(pacX, yPos),
        radius: 14,
      ), // 半徑放大一倍 (7 -> 14)
      startAngle,
      sweepAngle,
      false,
    );
    pacPath.close(); // 封閉形成嘴巴
    canvas.drawPath(pacPath, pacPaint); // 填色

    Paint pacStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // 描邊加粗
    canvas.drawPath(pacPath, pacStroke); // 描邊
  }

  // 繪製山丘與打招呼的小人 (裝飾性內容)
  void _drawHillAndFigure(Canvas canvas, Offset origin, double w, double h) {
    // 子函數邏輯
    // 將中心點 Y 座標從 h - 70 上移至 h - 160，避免被底部「下一頁」按鈕擋住
    Offset hillCenter = Offset(
      origin.dx + w - 80,
      origin.dy + h - 160,
    ); // 山丘中心定位
    double hillRadius = 35; // 半徑

    Paint hillPaint = Paint()..color = const Color(0xFFD4E5D9); // 水綠色山丘
    canvas.drawArc(
      Rect.fromCircle(center: hillCenter, radius: hillRadius),
      pi,
      pi,
      false,
      hillPaint,
    ); // 畫半圓

    Paint hillBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // 黑邊
    canvas.drawArc(
      Rect.fromCircle(center: hillCenter, radius: hillRadius),
      pi,
      pi,
      false,
      hillBorder,
    ); // 描邊

    Offset headPos = hillCenter.translate(0, -hillRadius / 2 - 5); // 小人頭部位置
    Paint headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill; // 白色填充
    Paint headStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2; // 黑描邊

    canvas.drawCircle(headPos, 7, headPaint); // 畫圓圈頭部 (內部)
    canvas.drawCircle(headPos, 7, headStroke); // 畫圓圈頭部 (邊緣)

    Paint footPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2; // 腳部畫筆
    canvas.drawLine(
      headPos.translate(-3, 7),
      headPos.translate(-3, 14),
      footPaint,
    ); // 左腳
    canvas.drawLine(
      headPos.translate(3, 7),
      headPos.translate(3, 14),
      footPaint,
    ); // 右腳

    TextPainter helloText = TextPainter(
      // Hello 文字
      text: const TextSpan(
        text: 'Hello!',
        style: TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    helloText.layout(); // 文字排版
    helloText.paint(canvas, headPos.translate(15, -5)); // 在小人右手邊繪製文字
  }

  @override
  bool shouldRepaint(HandDrawnNotebookPainter oldDelegate) {
    // 當平滑滾動進度或嘴巴張合值改變時都需要重繪
    return oldDelegate.scrollProgress != scrollProgress ||
        oldDelegate.mouthProgress != mouthProgress;
  }
}

// ===== 手繪風格方框繪製器 =====
class HandDrawnBoxPainter extends CustomPainter {
  // 方框畫筆類
  final bool isSelected; // 選中狀態
  HandDrawnBoxPainter({this.isSelected = false}); // 建構子

  @override
  void paint(Canvas canvas, Size size) {
    // 繪製邏輯
    Path boxPath = Path(); // 建立路徑
    Random rand = Random(); // 隨機數
    boxPath.moveTo(3, 2); // 起點

    for (double x = 0; x < size.width - 3; x += 15) {
      // 頂邊繪製
      double nextX = (x + 15 > size.width - 3) ? size.width - 3 : x + 15;
      boxPath.quadraticBezierTo(
        x + 7.5 + rand.nextDouble() * 2 - 1,
        1 + rand.nextDouble() * 1.5,
        nextX,
        2,
      );
    }
    for (double y = 0; y < size.height - 3; y += 15) {
      // 右邊繪製
      double nextY = (y + 15 > size.height - 3) ? size.height - 3 : y + 15;
      boxPath.quadraticBezierTo(
        size.width - 1 + rand.nextDouble() * 1,
        y + 7.5 + rand.nextDouble() * 2 - 1,
        size.width - 3,
        nextY,
      );
    }
    for (double x = size.width - 3; x > 3; x -= 15) {
      // 底邊繪製 (逆向)
      double nextX = (x - 15 < 3) ? 3 : x - 15;
      boxPath.quadraticBezierTo(
        x - 7.5 + rand.nextDouble() * 2 - 1,
        size.height - 1 + rand.nextDouble() * 1,
        nextX,
        size.height - 3,
      );
    }
    for (double y = size.height - 3; y > 3; y -= 15) {
      // 左邊繪製 (逆向)
      double nextY = (y - 15 < 3) ? 3 : y - 15;
      boxPath.quadraticBezierTo(
        1 + rand.nextDouble() * 1,
        y - 7.5 + rand.nextDouble() * 2 - 1,
        3,
        nextY,
      );
    }
    boxPath.close(); // 封閉

    Paint fillPaint = Paint()
      ..color = isSelected ? const Color(0xFFFFE4B5) : Colors.white
      ..style = PaintingStyle.fill; // 背景筆
    canvas.drawPath(boxPath, fillPaint); // 畫填充
    Paint borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0; // 邊框筆
    canvas.drawPath(boxPath, borderPaint); // 寫黑邊
  }

  @override
  bool shouldRepaint(HandDrawnBoxPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected; // 狀態改變重繪
}

// ===== 圓角手繪方框繪製器 =====
class HandDrawnRoundedBoxPainter extends CustomPainter {
  // 圓角方框類
  final bool isSelected;
  HandDrawnRoundedBoxPainter({this.isSelected = false});

  @override
  void paint(Canvas canvas, Size size) {
    Random rand = Random();
    Path path = Path();
    const double cornerRadius = 12;

    path.moveTo(cornerRadius + 2, 2);
    for (
      double x = cornerRadius + 2;
      x < size.width - cornerRadius - 2;
      x += 12
    ) {
      // 頂邊
      double nextX = (x + 12 > size.width - cornerRadius - 2)
          ? size.width - cornerRadius - 2
          : x + 12;
      path.quadraticBezierTo(
        x + 6 + rand.nextDouble(),
        1 + rand.nextDouble(),
        nextX,
        2,
      );
    }
    path.quadraticBezierTo(
      size.width - 2,
      2,
      size.width - 3,
      cornerRadius + 2,
    ); // 右上角
    for (
      double y = cornerRadius + 2;
      y < size.height - cornerRadius - 2;
      y += 12
    ) {
      // 右邊
      double nextY = (y + 12 > size.height - cornerRadius - 2)
          ? size.height - cornerRadius - 2
          : y + 12;
      path.quadraticBezierTo(
        size.width - 1 + rand.nextDouble(),
        y + 6 + rand.nextDouble(),
        size.width - 3,
        nextY,
      );
    }
    path.quadraticBezierTo(
      size.width - 2,
      size.height - 2,
      size.width - cornerRadius - 2,
      size.height - 3,
    ); // 右下角
    for (
      double x = size.width - cornerRadius - 2;
      x > cornerRadius + 2;
      x -= 12
    ) {
      // 底邊
      double nextX = (x - 12 < cornerRadius + 2) ? cornerRadius + 2 : x - 12;
      path.quadraticBezierTo(
        x - 6 + rand.nextDouble(),
        size.height - 1 + rand.nextDouble(),
        nextX,
        size.height - 3,
      );
    }
    path.quadraticBezierTo(
      2,
      size.height - 2,
      3,
      size.height - cornerRadius - 2,
    ); // 左下角
    for (
      double y = size.height - cornerRadius - 2;
      y > cornerRadius + 2;
      y -= 12
    ) {
      // 左邊
      double nextY = (y - 12 < cornerRadius + 2) ? cornerRadius + 2 : y - 12;
      path.quadraticBezierTo(
        1 + rand.nextDouble(),
        y - 6 + rand.nextDouble(),
        3,
        nextY,
      );
    }
    path.quadraticBezierTo(2, 2, cornerRadius + 2, 2); // 左上角返航
    path.close();

    Paint fillPaint = Paint()
      ..color = isSelected ? const Color(0xFFFFE4B5) : Colors.white;
    canvas.drawPath(path, fillPaint);
    Paint borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(HandDrawnRoundedBoxPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected;
}

// ===== 手寫風格箭頭繪製器 =====
class ArrowPainter extends CustomPainter {
  // 箭頭繪製類
  final String direction; // 'left' 或 'right'
  ArrowPainter({required this.direction});

  @override
  void paint(Canvas canvas, Size size) {
    Paint arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round; // 採用白色加粗箭頭以突顯
    double cx = size.width / 2; // 中心 X
    double cy = size.height / 2; // 中心 Y

    if (direction == 'left') {
      // 左箭頭
      canvas.drawLine(Offset(cx + 6, cy - 10), Offset(cx - 6, cy), arrowPaint);
      canvas.drawLine(Offset(cx - 6, cy), Offset(cx + 6, cy + 10), arrowPaint);
    } else {
      // 右箭頭
      canvas.drawLine(Offset(cx - 6, cy - 10), Offset(cx + 6, cy), arrowPaint);
      canvas.drawLine(Offset(cx + 6, cy), Offset(cx - 6, cy + 10), arrowPaint);
    }
  }

  @override
  bool shouldRepaint(ArrowPainter oldDelegate) =>
      oldDelegate.direction != direction;
}

// ===== 翻頁動畫繪製器 =====
class PageFlipPainter extends CustomPainter {
  // 翻頁視覺效果
  final double progress; // 進度 0~1
  PageFlipPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    double y = size.height * (1 - progress); // 翻轉邊緣線 Y
    Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(progress * 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRect(
      Rect.fromLTWH(0, y - 30, size.width, 60),
      shadowPaint,
    ); // 畫出滾動陰影
    Paint edgePaint = Paint()
      ..color = Colors.white.withOpacity(progress * 0.4)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), edgePaint); // 手繪邊緣光澤
  }

  @override
  bool shouldRepaint(PageFlipPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ===== 紙膠帶按鈕繪製器 =====
class WashiTapeButtonPainter extends CustomPainter {
  // 紙膠帶組件
  final String text;
  WashiTapeButtonPainter({this.text = '下一頁 >'});

  @override
  void paint(Canvas canvas, Size size) {
    Path baseShape = Path();
    Random rand = Random();
    double w = size.width;
    double h = size.height;

    baseShape.moveTo(0, 0); // 起點
    for (double y = 0; y < h; y += 6) {
      if (y + 6 < h) {
        baseShape.lineTo(4 + rand.nextDouble() * 2, y + 3);
        baseShape.lineTo(0, y + 6);
      }
    } // 左端鋸齒
    baseShape.lineTo(w, h); // 底邊
    for (double y = h; y > 0; y -= 6) {
      if (y - 6 > 0) {
        baseShape.lineTo(w - 4 - rand.nextDouble() * 2, y - 3);
        baseShape.lineTo(w, y - 6);
      }
    } // 右端鋸齒
    baseShape.close();

    canvas.drawPath(baseShape, Paint()..color = Colors.white); // 填充
    canvas.drawPath(
      baseShape,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    ); // 描邊

    TextPainter textPainter = TextPainter(
      // 文字標註
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((w - textPainter.width) / 2, (h - textPainter.height) / 2),
    ); // 置中繪製
  }

  @override
  bool shouldRepaint(WashiTapeButtonPainter oldDelegate) =>
      oldDelegate.text != text;
}

// ===== 紙膠帶紋理繪製器 (裝飾用，可選) =====
class WashiPainter extends CustomPainter {
  // 紋理背景實作
  @override
  void paint(Canvas canvas, Size size) {
    /* 可擴充紙膠帶條紋圖案的邏輯 */
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
// ===== 檔案結束 =====