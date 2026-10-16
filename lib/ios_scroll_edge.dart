import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'easy_glass.dart';
import 'ios_glass.dart';
import 'ios_gaussian_plane.dart';

/// One untinted Gaussian with the upstream continuous alpha feather. Native
/// iOS uses a full edge plane, preserving content across control boundaries.
class IOSScrollEdge extends StatelessWidget {
  const IOSScrollEdge({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
    required this.child,
  }) : _legacy = false;

  /// Retains the previous per-control transfer for regression diagnostics.
  const IOSScrollEdge.legacy({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
    required this.child,
  }) : _legacy = true;
  final bool _legacy;
  final double blur, plateau;
  final bool fromBottom;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (blur <= 0) return child;
    if (!_legacy && sharedIOSGaussianEnabled && blur > 0) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IOSGaussianPlane(
              blur: blur,
              plateau: plateau,
              fromBottom: fromBottom,
            ),
          ),
          child,
        ],
      );
    }
    final edge = EasyScrollEdge(
      blur: blur,
      plateau: plateau,
      fromBottom: fromBottom,
      child: child,
    );
    if (!nativeIOSGlassEnabled) return edge;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: _EdgeGeometry(
            blur: blur,
            plateau: plateau,
            bottom: fromBottom,
            child: EasyScrollEdge(
              blur: blur,
              plateau: plateau,
              fromBottom: fromBottom,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Only vertical ramp geometry crosses the bridge. The app's pinned edges
/// retain this geometry throughout horizontal Cupertino push/pop animations.
/// A retained scene layer observes ancestor transforms without rebuilding the
/// edge or reading back pixels; unchanged geometry sends no platform message.
class _EdgeGeometry extends SingleChildRenderObjectWidget {
  const _EdgeGeometry({
    required this.blur,
    required this.plateau,
    required this.bottom,
    required super.child,
  });
  final double blur, plateau;
  final bool bottom;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEdgeGeometry(blur, plateau, bottom);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEdgeGeometry renderObject,
  ) => renderObject.configure(blur, plateau, bottom);
}

class _EdgeSceneLayer extends ContainerLayer {
  _EdgeSceneLayer(this.observed, this.admitted);
  final VoidCallback observed;
  final bool Function() admitted;
  @override
  bool get alwaysNeedsAddToScene => true;
  @override
  void addToScene(ui.SceneBuilder builder) {
    observed();
    // Ancestor transforms can change without repainting this retained child.
    if (admitted()) super.addToScene(builder);
  }
}

class _RenderEdgeGeometry extends RenderProxyBox {
  _RenderEdgeGeometry(this.blur, this.plateau, this.bottom);
  static const _channel = MethodChannel('org.mewx.wenku8/glass_presentation');
  static int _nextId = 0;
  final int id = _nextId++;
  late final _edgeLayer = LayerHandle<_EdgeSceneLayer>(
    _EdgeSceneLayer(_observed, () => _same(_geometry(), _confirmed)),
  );
  double blur, plateau;
  bool bottom;
  bool _queued = false;
  int _revision = 0;
  Map<String, Object>? _last;
  Map<String, Object>? _confirmed;
  Map<String, Object>? _attemptGeometry;
  int _attempts = 0;
  @override
  bool get alwaysNeedsCompositing => true;
  void configure(double sigma, double full, bool fromBottom) {
    if (blur == sigma && plateau == full && bottom == fromBottom) return;
    blur = sigma;
    plateau = full;
    bottom = fromBottom;
    markNeedsPaint();
  }

  Future<bool> _send(String method, Map<String, Object> args) async {
    try {
      final accepted = await _channel.invokeMethod<Object?>(method, args);
      return method != 'edgeSet' || accepted == true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Wenku8 native edge geometry',
        ),
      );
      return false;
    }
  }

  void _remove() {
    final wasSent = _attemptGeometry != null;
    _last = null;
    _confirmed = null;
    _attemptGeometry = null;
    _attempts = 0;
    _revision++;
    if (wasSent) unawaited(_send('edgeRemove', {'id': id}));
  }

  Map<String, Object>? _geometry() {
    if (!attached || !hasSize || size.isEmpty) return null;
    final origin = localToGlobal(Offset.zero);
    final down = localToGlobal(const Offset(0, 1)) - origin;
    final across = localToGlobal(const Offset(1, 0)) - origin;
    if (!origin.dy.isFinite ||
        down.dx.abs() > .0001 ||
        (down.dy - 1).abs() > .0001 ||
        across.dy.abs() > .0001) {
      return null;
    }
    return <String, Object>{
      'id': id,
      'y': origin.dy,
      'height': size.height,
      'plateau': plateau,
      'sigma': blur + (bottom ? .01 : 0),
      'fromBottom': bottom,
    };
  }

  bool _same(Map<String, Object>? a, Map<String, Object>? b) =>
      a != null && b != null && a.keys.every((k) => a[k] == b[k]);

  void _observed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _queued = false;
      final geometry = _geometry();
      if (geometry == null) {
        _remove();
        return;
      }
      if (_same(_last, geometry)) return;
      if (!_same(_attemptGeometry, geometry)) {
        _attemptGeometry = geometry;
        _attempts = 0;
      }
      if (_attempts >= 2) return;
      _attempts++;
      _last = geometry;
      final revision = ++_revision;
      final accepted = await _send('edgeSet', geometry);
      if (accepted &&
          revision == _revision &&
          attached &&
          _same(_last, geometry) &&
          _same(_geometry(), geometry)) {
        _confirmed = geometry;
        markNeedsPaint();
        WidgetsBinding.instance.ensureVisualUpdate();
      } else if (!accepted && attached && revision == _revision) {
        _last = null;
        // A transient host rejection gets one bounded retry, never an idle
        // frame loop on an incompatible engine or invalid profile.
        if (_attempts < 2) {
          markNeedsPaint();
          WidgetsBinding.instance.ensureVisualUpdate();
        }
      }
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Admit the Gaussian only after its native mask profile is registered.
    // Initial layout/changed insets wait for the ACK; they never expose an
    // unfeathered native rectangle. Foreground content is outside this plane.
    final ready = _same(_geometry(), _confirmed);
    context.pushLayer(
      _edgeLayer.layer!,
      ready ? super.paint : (_, _) {},
      offset,
    );
  }

  @override
  void detach() {
    _remove();
    super.detach();
  }

  @override
  void dispose() {
    _edgeLayer.layer = null;
    super.dispose();
  }
}
