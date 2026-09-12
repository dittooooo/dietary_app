import 'package:flutter/foundation.dart';

/// 狗的身體類型。 
enum DogBodyType {  thin, normal, muscle, heavy,}
/// 狗的動畫狀態。 
enum DogAnimationState { idle, thinking, response, eating,}

/// 狗的狀態控制器。 
class DogStateController extends ChangeNotifier {
  /// 環境變數中的狗的身體類型。 
  static const String _envBodyType = String.fromEnvironment('DOG_BODY_TYPE');
  /// 狗的身體類型。 
  DogBodyType _bodyType;
  /// 狗的動畫狀態。 
  DogAnimationState _state;

  /// 預設建構元 
  DogStateController({ DogBodyType? bodyType, DogAnimationState state = DogAnimationState.idle, })  : _bodyType = bodyType ?? parseBodyType(_envBodyType), _state = state;

  /// 預設單例實例 
  static final DogStateController instance = DogStateController();

  /// 取得狗的身體類型。 
  DogBodyType get bodyType => _bodyType;
  /// 取得狗的動畫狀態。 
  DogAnimationState get state => _state;

  /// 取得模型資源路徑。
  String get modelAsset {
    switch (_bodyType) {
      case DogBodyType.thin:
        return 'assets/models/Dog_Thin_Animation_Collection.glb';
      case DogBodyType.muscle:
        return 'assets/models/Dog_Muscle_Animation_Collection.glb';
      case DogBodyType.heavy:
        return 'assets/models/Dog_Heavy_Animation_Collection.glb';
      case DogBodyType.normal:
        return 'assets/models/Dog_Normal_Animation_Collection.glb';
    }
  }

  /// 取得動畫名稱。 
  String get animationName {
    switch (_state) {
      case DogAnimationState.thinking:
        return 'Thinking';
      case DogAnimationState.response:
        return 'Response';
      case DogAnimationState.eating:
        return 'Eating';
      case DogAnimationState.idle:
        return 'Idle';
    }
  }

  /// 設定動畫狀態。
  void setState(DogAnimationState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  /// 設定狗的身體類型。
  void setBodyType(DogBodyType bodyType) {
    if (_bodyType == bodyType) return;
    _bodyType = bodyType;
    notifyListeners();
  }

  /// 從後端設定狗的身體類型。 
  void setBodyTypeFromBackend(dynamic value) {
    if (_envBodyType.trim().isNotEmpty) {
      setBodyType(parseBodyType(_envBodyType));
      return;
    }
    setBodyType(parseBodyType(value));
  }

  /// 解析狗的身體類型。 
  static DogBodyType parseBodyType(dynamic value) {
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text.isEmpty) return DogBodyType.normal;

    if (text.contains('thin') ||  text.contains('slim') || text.contains('lean') ||text.contains('light') ||
        text.contains('under') || text.contains('\u6e1b\u91cd') || text.contains('\u7626')) {
      return DogBodyType.thin;
    }

    if (text.contains('muscle') || text.contains('muscular') ||text.contains('fit') ||text.contains('strong') ||text.contains('gain') ||
        text.contains('\u589e\u808c') || text.contains('\u5065\u8eab')) {
      return DogBodyType.muscle;
    }

    if (text.contains('heavy') || text.contains('fat') || text.contains('large') || text.contains('over') ||
        text.contains('bulk') || text.contains('\u589e\u91cd') || text.contains('\u80d6')) {
      return DogBodyType.heavy;
    }

    return DogBodyType.normal;
  }
}
