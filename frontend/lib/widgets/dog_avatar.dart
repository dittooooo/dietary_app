import 'package:flutter/material.dart';

import '../controllers/dog_state_controller.dart';
import '../views/auth/model_viewer_web_stub.dart'
    if (dart.library.html) '../views/auth/model_viewer_web_impl.dart';

/// 3D 柴犬角色模型渲染 Avatar 通用視覺元件。
class DogAvatar extends StatelessWidget {
  final DogStateController controller;
  final double scale;
  final bool cameraControls;
  final String? cameraOrbit;
  final String instanceId;
  final Clip clipBehavior;
  final Offset contentOffset;
  final double? bodyTypeScaleOverride;
  final Offset? bodyTypeOffsetOverride;
  final VoidCallback? onModelLoaded;

  DogAvatar({
    super.key,
    DogStateController? controller,
    this.scale = 1.6,
    this.cameraControls = false,
    this.cameraOrbit = '0deg 75deg auto',
    this.clipBehavior = Clip.none,
    this.contentOffset = Offset.zero,
    this.bodyTypeScaleOverride,
    this.bodyTypeOffsetOverride,
    this.onModelLoaded,
    required this.instanceId,
  }) : controller = controller ?? DogStateController.instance;

  static const double _thinBodyScaleMultiplier = 1.65;
  static const double _defaultBodyScaleMultiplier = 1.0;
  static const Offset _thinBodyOffset = Offset(0, 38);
  static const Offset _defaultBodyOffset = Offset(0, 20);

  /// 依據柴犬體態（瘦、標準、壯、胖）計算模型縮放比例倍率。
  double _bodyTypeScaleMultiplier(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return _thinBodyScaleMultiplier;
      case DogBodyType.normal:
      case DogBodyType.muscle:
      case DogBodyType.heavy:
        return _defaultBodyScaleMultiplier;
    }
  }

  /// 依據柴犬體態計算模型的垂直畫布偏移量。
  Offset _bodyTypeOffset(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return _thinBodyOffset;
      case DogBodyType.normal:
      case DogBodyType.muscle:
      case DogBodyType.heavy:
        return _defaultBodyOffset;
    }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bodyTypeScale =
            bodyTypeScaleOverride ?? _bodyTypeScaleMultiplier(controller.bodyType);
        final bodyTypeOffset =
            bodyTypeOffsetOverride ?? _bodyTypeOffset(controller.bodyType);
        final adjustedScale = scale * bodyTypeScale;

        return Stack(
          clipBehavior: clipBehavior,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: bodyTypeOffset + contentOffset,
                child: Transform.scale(
                  scale: bodyTypeScale,
                  child: createWebModelView(
                    colorScheme: 'orange',
                    autoSpin: false,
                    scale: adjustedScale,
                    src: controller.modelAsset,
                    cameraControls: cameraControls,
                    cameraOrbit: cameraOrbit,
                    animationName: controller.animationName,
                    autoPlay: true,
                    instanceId: instanceId,
                    onModelLoaded: onModelLoaded,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
