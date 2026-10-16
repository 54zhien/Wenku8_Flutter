import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A single untinted Gaussian over both Flutter and UIKit, with the upstream
/// eight-stop alpha feather. Foreground widgets paint separately above it.
class IOSGaussianPlane extends StatefulWidget {
  const IOSGaussianPlane({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
  });
  final double blur, plateau;
  final bool fromBottom;
  @override
  State<IOSGaussianPlane> createState() => _IOSGaussianPlaneState();
}

class _IOSGaussianPlaneState extends State<IOSGaussianPlane> {
  MethodChannel? _channel;
  Map<String, Object>? _initialConfiguration;
  Map<String, Object> get _configuration => {
    'sigma': widget.blur + (widget.fromBottom ? .01 : 0),
    'plateau': widget.plateau,
    'fromBottom': widget.fromBottom,
  };
  @override
  void didUpdateWidget(IOSGaussianPlane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blur == widget.blur &&
        oldWidget.plateau == widget.plateau &&
        oldWidget.fromBottom == widget.fromBottom) {
      return;
    }
    final channel = _channel;
    if (channel != null) unawaited(_update(channel));
  }

  Future<void> _update(MethodChannel channel) async {
    try {
      await channel.invokeMethod<void>('state', _configuration);
    } on MissingPluginException catch (error, stack) {
      // Native route teardown can remove the per-view handler before a pending
      // message completes. A missing handler on a live plane is still an error.
      if (mounted) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Wenku8 native Gaussian plane',
          ),
        );
      }
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Wenku8 native Gaussian plane',
        ),
      );
    }
  }

  void _created(int id) {
    if (!mounted) return;
    final channel = MethodChannel('org.mewx.wenku8/glass_controls/$id');
    _channel = channel;
    if (!mapEquals(_initialConfiguration, _configuration)) {
      unawaited(_update(channel));
    }
  }

  @override
  Widget build(BuildContext context) {
    _initialConfiguration ??= _configuration;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: UiKitView(
          viewType: 'org.mewx.wenku8/glass_controls',
          creationParams: {'kind': 'gaussianEdge', ..._initialConfiguration!},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _created,
        ),
      ),
    );
  }
}
