import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget createWebModelView({
  required String colorScheme,
  required bool autoSpin,
  required double scale,
  String? src,
  bool cameraControls = true,
  String? cameraOrbit = '0deg 75deg auto',
  String? animationName,
  bool autoPlay = true,
  String instanceId = 'default',
}) {
  _ensureModelViewerScriptLoaded();

  final safeId = instanceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final viewType = 'model-viewer-custom-$safeId';
  final elementId = 'model-viewer-pet-$safeId';

  void applyAttributes(html.Element element) {
    element
      ..setAttribute('alt', '3D Mascot Pet')
      ..setAttribute('shadow-intensity', '1.0')
      ..setAttribute('shadow-softness', '0.5')
      ..setAttribute('environment-image', 'neutral')
      ..setAttribute('exposure', '1.0')
      ..setAttribute('interaction-prompt', 'none')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.backgroundColor = 'transparent';

    final resolvedSrc = src?.isNotEmpty == true ? src! : 'assets/images/dog_rigged.glb';
    element.setAttribute('src', resolvedSrc);

    if (autoSpin) {
      element.setAttribute('auto-rotate', '');
    } else {
      element.removeAttribute('auto-rotate');
    }

    if (cameraControls) {
      element.setAttribute('camera-controls', '');
    } else {
      element.removeAttribute('camera-controls');
    }

    if (cameraOrbit != null) {
      element.setAttribute('camera-orbit', cameraOrbit);
    } else {
      element.removeAttribute('camera-orbit');
    }

    final fovDeg = (45.0 / scale).clamp(15.0, 90.0);
    element.setAttribute('field-of-view', '${fovDeg.toInt()}deg');

    if (animationName != null) {
      element.setAttribute('animation-name', animationName);
    } else {
      element.removeAttribute('animation-name');
    }

    if (autoPlay) {
      element.setAttribute('autoplay', '');
      try {
        (element as dynamic).play();
      } catch (_) {
        // The model-viewer element may not be upgraded yet on first creation.
      }
    } else {
      element.removeAttribute('autoplay');
    }
  }

  final existingElement = html.document.getElementById(elementId);
  if (existingElement != null) {
    applyAttributes(existingElement);
  }

  if (!_registeredViewTypes.contains(viewType)) {
    try {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final element = html.Element.tag('model-viewer')..id = elementId;
        applyAttributes(element);
        return element;
      });
      _registeredViewTypes.add(viewType);
    } catch (e) {
      debugPrint('View factory registration bypassed or already exists: $e');
    }
  }

  return HtmlElementView(
    key: ValueKey('web_mascot_3d_viewer_${safeId}_${src}_$scale'),
    viewType: viewType,
  );
}

void _ensureModelViewerScriptLoaded() {
  final existingScript = html.document.querySelector('script[src*="model-viewer"]');
  if (existingScript != null) return;

  final script = html.ScriptElement()
    ..src = 'https://cdn.jsdelivr.net/npm/@google/model-viewer@3.4.0/dist/model-viewer.min.js'
    ..type = 'module';
  html.document.head?.append(script);
}
