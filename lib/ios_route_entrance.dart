import 'package:flutter/widgets.dart';

/// Keep UIKit view/effect creation out of a new page's entrance frames.
/// The original Flutter controls draw during entrance. Once admitted, native
/// controls stay mounted through later pushes, pops and cancelled back swipes.
class IOSRouteEntrance extends StatefulWidget {
  const IOSRouteEntrance({super.key, required this.child});
  final Widget child;

  static bool readyOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IOSRouteReadiness>()?.ready ??
      true;

  @override
  State<IOSRouteEntrance> createState() => _IOSRouteEntranceState();
}

class _IOSRouteEntranceState extends State<IOSRouteEntrance> {
  Animation<double>? _animation;
  bool _ready = false;
  bool _queued = false;
  final _pointers = <int>{};

  void _pointerEnded(PointerEvent event) {
    _pointers.remove(event.pointer);
    _queueAdmission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final route = ModalRoute.of(context);
    if (route == null || route.isFirst) {
      _ready = true;
      return;
    }
    if (_animation != route.animation) {
      _animation?.removeStatusListener(_changed);
      _animation = route.animation;
      _animation?.addStatusListener(_changed);
    }
    _queueAdmission();
  }

  void _changed(AnimationStatus status) {
    if (status == AnimationStatus.completed) _queueAdmission();
  }

  void _queueAdmission() {
    if (_ready || _queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      // A route's proxy can briefly report completed before Navigator starts
      // its first push. Check after layout, and never admit an exiting page.
      if (!mounted ||
          _ready ||
          _pointers.isNotEmpty ||
          _animation?.status != AnimationStatus.completed ||
          ModalRoute.isCurrentOf(context) == false) {
        return;
      }
      _animation?.removeStatusListener(_changed);
      setState(() => _ready = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _IOSRouteReadiness(
    ready: _ready,
    child: Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerUp: _pointerEnded,
      onPointerCancel: _pointerEnded,
      child: widget.child,
    ),
  );
}

class _IOSRouteReadiness extends InheritedWidget {
  const _IOSRouteReadiness({required this.ready, required super.child});
  final bool ready;
  @override
  bool updateShouldNotify(_IOSRouteReadiness oldWidget) =>
      ready != oldWidget.ready;
}
