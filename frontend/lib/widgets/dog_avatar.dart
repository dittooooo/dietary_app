import 'package:flutter/material.dart';

import '../controllers/dog_state_controller.dart';
import '../views/auth/model_viewer_web_stub.dart'
    if (dart.library.html) '../views/auth/model_viewer_web_impl.dart';

class DogAvatar extends StatelessWidget {
  final DogStateController controller;
  final double scale;
  final bool cameraControls;
  final String? cameraOrbit;
  final String instanceId;

  DogAvatar({
    super.key,
    DogStateController? controller,
    this.scale = 1.6,
    this.cameraControls = false,
    this.cameraOrbit = '0deg 75deg auto',
    required this.instanceId,
  }) : controller = controller ?? DogStateController.instance;

  double _bodyTypeScaleMultiplier(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return 1.65;
      case DogBodyType.normal:
      case DogBodyType.muscle:
      case DogBodyType.heavy:
        return 1.0;
    }
  }

  Offset _bodyTypeOffset(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return const Offset(0, 38);
      case DogBodyType.normal:
      case DogBodyType.muscle:
      case DogBodyType.heavy:
        return Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bodyTypeScale = _bodyTypeScaleMultiplier(controller.bodyType);
        final bodyTypeOffset = _bodyTypeOffset(controller.bodyType);
        final adjustedScale = scale * bodyTypeScale;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: bodyTypeOffset,
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
