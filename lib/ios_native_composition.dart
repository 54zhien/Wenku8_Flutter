import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One page's boundary between live UIKit and Flutter's animated/filtered plane.
class IOSNativeComposition extends StatefulWidget {
  const IOSNativeComposition({super.key, required this.child});
  final Widget child;
  static IOSNativeScene? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IOSNativeScope>()?.scene;
  @override
  State<IOSNativeComposition> createState() => _IOSNativeCompositionState();
}

class _IOSNativeCompositionState extends State<IOSNativeComposition> {
  final _scene = IOSNativeScene();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _scene.bind(route?.animation, route?.secondaryAnimation);
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _IOSNativeScope(
    scene: _scene,
    child: NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _scene.scrolled();
        return false;
      },
      child: widget.child,
    ),
  );
}

class _IOSNativeScope extends InheritedWidget {
  const _IOSNativeScope({required this.scene, required super.child});
  final IOSNativeScene scene;
  @override
  bool updateShouldNotify(_IOSNativeScope oldWidget) =>
      scene != oldWidget.scene;
}

class IOSNativeScene extends ChangeNotifier {
  Animation<double>? _primary, _secondary;
  final _edges = <_RenderIOSBlurRegion>{};
  bool moving = false;
  static bool _inFlight(Animation<double>? animation) =>
      animation != null &&
      (animation.isAnimating || (animation.value > 0 && animation.value < 1));
  void bind(Animation<double>? primary, Animation<double>? secondary) {
    if (primary == _primary && secondary == _secondary) return;
    for (final animation in [_primary, _secondary]) {
      animation?.removeListener(_changed);
      animation?.removeStatusListener(_status);
    }
    _primary = primary;
    _secondary = secondary;
    for (final animation in [_primary, _secondary]) {
      animation?.addListener(_changed);
      animation?.addStatusListener(_status);
    }
    _changed();
  }

  void _status(AnimationStatus _) => _changed();
  void _changed() {
    final value = _inFlight(_primary) || _inFlight(_secondary);
    if (moving == value) return;
    moving = value;
    notifyListeners();
  }

  void scrolled() => notifyListeners();
  bool intersectsEdge(RenderBox box) {
    if (!box.attached || !box.hasSize) return false;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return _edges.any(
      (edge) =>
          edge.attached &&
          edge.hasSize &&
          bounds.overlaps(
            MatrixUtils.transformRect(
              edge.getTransformTo(null),
              Offset.zero & edge.size,
            ),
          ),
    );
  }

  @override
  void dispose() {
    for (final animation in [_primary, _secondary]) {
      animation?.removeListener(_changed);
      animation?.removeStatusListener(_status);
    }
    _edges.clear();
    super.dispose();
  }
}

/// Marks only controls painted above a page's edge, not generic glass labels.
class IOSNativeForeground extends InheritedWidget {
  const IOSNativeForeground({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IOSNativeForeground>() != null;
  @override
  bool updateShouldNotify(IOSNativeForeground oldWidget) => false;
}

class IOSNativeBlurRegion extends SingleChildRenderObjectWidget {
  const IOSNativeBlurRegion({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIOSBlurRegion(IOSNativeComposition.maybeOf(context));
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) => (renderObject as _RenderIOSBlurRegion).scene =
      IOSNativeComposition.maybeOf(context);
}

class _RenderIOSBlurRegion extends RenderProxyBox {
  _RenderIOSBlurRegion(this._scene);
  IOSNativeScene? _scene;
  set scene(IOSNativeScene? value) {
    if (value == _scene) return;
    if (attached) _scene?._edges.remove(this);
    _scene = value;
    if (attached) _scene?._edges.add(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scene?._edges.add(this);
  }

  @override
  void detach() {
    _scene?._edges.remove(this);
    super.detach();
  }
}

/// Retains the UIKit child and its state, but omits its PlatformViewLayer when
/// Flutter must feather or move it. The texture is a cached native render, not
/// a Flutter imitation, and painting never requests another capture.
class IOSNativeControlPlane extends SingleChildRenderObjectWidget {
  const IOSNativeControlPlane({
    super.key,
    required this.textureId,
    required this.interacting,
    required super.child,
  });
  final int? textureId;
  final bool interacting;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIOSControlPlane(
        IOSNativeComposition.maybeOf(context),
        textureId,
        interacting,
        IOSNativeForeground.of(context),
      );
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) => (renderObject as _RenderIOSControlPlane).configure(
    IOSNativeComposition.maybeOf(context),
    textureId,
    interacting,
    IOSNativeForeground.of(context),
  );
}

class _RenderIOSControlPlane extends RenderProxyBox {
  _RenderIOSControlPlane(
    this._scene,
    this._textureId,
    this._interacting,
    this._foreground,
  );
  IOSNativeScene? _scene;
  int? _textureId;
  bool _interacting, _foreground;
  bool get _raster =>
      _textureId != null &&
      !_interacting &&
      ((_scene?.moving ?? false) ||
          (!_foreground && (_scene?.intersectsEdge(this) ?? false)));
  void configure(
    IOSNativeScene? scene,
    int? textureId,
    bool interacting,
    bool foreground,
  ) {
    if (scene == _scene &&
        textureId == _textureId &&
        interacting == _interacting &&
        foreground == _foreground) {
      return;
    }
    if (attached) _scene?.removeListener(markNeedsPaint);
    _scene = scene;
    _textureId = textureId;
    _interacting = interacting;
    _foreground = foreground;
    if (attached) _scene?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scene?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scene?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_raster) {
      context.addLayer(
        TextureLayer(
          rect: offset & size,
          textureId: _textureId!,
          filterQuality: FilterQuality.low,
        ),
      );
    } else {
      super.paint(context, offset);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_raster && super.hitTest(result, position: position);
}
