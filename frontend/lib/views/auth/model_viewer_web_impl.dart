import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Set<String> _registeredViewTypes = <String>{};
final Map<String, VoidCallback?> _modelLoadedCallbacks =
    <String, VoidCallback?>{};
const String _modelViewerLoadingStyleId = 'model-viewer-loading-style';
const String _modelViewerLoadingClass = 'model-viewer-loading';

const String _modelViewerLoadingCss = '''
.$_modelViewerLoadingClass {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  transition: opacity 180ms ease;
}
.$_modelViewerLoadingClass.is-hidden {
  opacity: 0;
}
.${_modelViewerLoadingClass}__spinner {
  width: 42px;
  height: 42px;
  border: 4px solid rgba(238, 238, 238, 0.92);
  border-top-color: #202808;
  border-radius: 50%;
  animation: modelViewerSpin 900ms linear infinite;
}
@keyframes modelViewerSpin {
  to { transform: rotate(360deg); }
}
''';

/// createWebModelView 業務邏輯處理方法。
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
  VoidCallback? onModelLoaded,
}) {
  _ensureModelViewerScriptLoaded();
  _ensureModelViewerLoadingStyles();

  final safeId = instanceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final viewType = 'model-viewer-custom-$safeId';
  final elementId = 'model-viewer-pet-$safeId';
  _modelLoadedCallbacks[elementId] = onModelLoaded;

  /// 執行 applyAttributes 業務邏輯處理方法。
  void applyAttributes(html.Element element) {
    element
      ..setAttribute('alt', '3D Mascot Pet')
      ..setAttribute('shadow-intensity', '1.0')
      ..setAttribute('shadow-softness', '0.5')
      ..setAttribute('environment-image', 'neutral')
      ..setAttribute('exposure', '1.0')
      ..setAttribute('loading', 'eager')
      ..setAttribute('reveal', 'auto')
      ..setAttribute('interaction-prompt', 'none')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.backgroundColor = 'transparent';

    final resolvedSrc =
        src?.isNotEmpty == true ? src! : 'assets/images/dog_rigged.glb';
    element.dataset['currentModelSrc'] = resolvedSrc;
    if (element.dataset['loadedModelSrc'] != resolvedSrc) {
      element.dataset['loadedModelSrc'] = '';
    }
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

    _ensureModelViewerLoadingIndicator(element);
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

/// _ensureModelViewerLoadingIndicator 業務邏輯處理方法。
void _ensureModelViewerLoadingIndicator(html.Element element) {
  if (element.querySelector('.$_modelViewerLoadingClass') == null) {
    final spinner = html.DivElement()
      ..className = '${_modelViewerLoadingClass}__spinner';
    final loading = html.DivElement()
      ..className = _modelViewerLoadingClass
      ..setAttribute('slot', 'progress-bar');
    loading.append(spinner);
    element.append(loading);
  }

  /// 執行 notifyModelLoaded 業務邏輯處理方法。
  void notifyModelLoaded() {
    final currentSrc = element.dataset['currentModelSrc'] ?? '';
    if (currentSrc.isEmpty || element.dataset['loadedModelSrc'] == currentSrc) {
      return;
    }

    element.dataset['loadedModelSrc'] = currentSrc;
    _modelLoadedCallbacks[element.id]?.call();
  }

  /// 執行 hideLoading 業務邏輯處理方法。
  void hideLoading(html.Event _) {
    element
        .querySelector('.$_modelViewerLoadingClass')
        ?.classes
        .add('is-hidden');
    notifyModelLoaded();
  }

  /// 執行 showOrHideLoading 業務邏輯處理方法。
  void showOrHideLoading(html.Event event) {
    final loading = element.querySelector('.$_modelViewerLoadingClass');
    if (loading == null) return;

    final detail = event is html.CustomEvent ? event.detail : null;
    final totalProgress = detail?.totalProgress;
    if (totalProgress != null && totalProgress >= 1) {
      loading.classes.add('is-hidden');
      notifyModelLoaded();
    } else {
      loading.classes.remove('is-hidden');
    }
  }

  if (element.dataset['loadingIndicatorReady'] == 'true') return;
  element.dataset['loadingIndicatorReady'] = 'true';
  element.addEventListener('load', hideLoading);
  element.addEventListener('error', hideLoading);
  element.addEventListener('progress', showOrHideLoading);

  try {
    if ((element as dynamic).loaded == true) {
      element
          .querySelector('.$_modelViewerLoadingClass')
          ?.classes
          .add('is-hidden');
      notifyModelLoaded();
    }
  } catch (_) {
    // The model-viewer element may not be upgraded yet on first creation.
  }
}

/// _ensureModelViewerLoadingStyles 業務邏輯處理方法。
void _ensureModelViewerLoadingStyles() {
  if (html.document.getElementById(_modelViewerLoadingStyleId) != null) return;

  final style = html.StyleElement()
    ..id = _modelViewerLoadingStyleId
    ..text = _modelViewerLoadingCss;
  html.document.head?.append(style);
}

/// _ensureModelViewerScriptLoaded 業務邏輯處理方法。
void _ensureModelViewerScriptLoaded() {
  final existingScript = html.document.querySelector('script[src*="model-viewer"]');
  if (existingScript != null) return;

  final script = html.ScriptElement()
    ..src = 'https://cdn.jsdelivr.net/npm/@google/model-viewer@3.4.0/dist/model-viewer.min.js'
    ..type = 'module';
  html.document.head?.append(script);
}
