import Flutter
import UIKit
import CoreVideo

#if DEBUG
/// Fixed hosted-test seam. Release builds have neither the fixture nor these
/// entry points; application code obtains filters only from engine composition.
final class WenkuGaussianTestAccess {
  private let bridge = WenkuGaussianEdgeBridge()
  init(root: UIView) { bridge.flutterView = root }
  var compatible: Bool { bridge.compatible }
  var maskCount: UInt { bridge.maskedFilterCount }
  @discardableResult func set(_ edge: [String: Any]) -> Bool { bridge.setEdge(edge) }
  func remove(_ id: NSNumber) { bridge.removeEdge(id) }
  func track(_ view: UIView) { bridge.trackView(view) }
  func clip(_ frame: CGRect) -> UIView? { WenkuGaussianProbeClip(frame) }
  func apply(_ clip: UIView, sigma: CGFloat) -> Bool { WenkuGaussianProbeApply(clip, sigma) }
  func clear(_ clip: UIView) -> Bool { WenkuGaussianProbeClear(clip) }
}
#endif

/// Explicitly enabled by the benchmark only; contains counts, never content.
private enum WenkuGlassWork {
  static var recording = false
  static var counts: [String: Int] = [:]
  static func add(_ event: String) {
    if recording { counts[event, default: 0] += 1 }
  }
  static func snapshotDuration(_ start: CFTimeInterval) {
    guard recording else { return }
    let elapsed = Int((CACurrentMediaTime() - start) * 1_000_000)
    counts["window_snapshot_total_us", default: 0] += elapsed
    counts["window_snapshot_max_us"] = max(counts["window_snapshot_max_us", default: 0], elapsed)
  }
  static func captureDuration(_ start: CFTimeInterval) {
    guard recording else { return }
    let elapsed = Int((CACurrentMediaTime() - start) * 1_000_000)
    counts["control_capture_total_us", default: 0] += elapsed
    counts["control_capture_max_us"] = max(counts["control_capture_max_us", default: 0], elapsed)
  }
}

/// Native-only prototype. Flutter owns state/routes; this view owns controls.
final class WenkuGlassFactory: NSObject, FlutterPlatformViewFactory, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private let textures: FlutterTextureRegistry
  private weak var registrar: FlutterPluginRegistrar?
  private var menuButton: WenkuMenuButton?
  private var menuResult: FlutterResult?
  private let edgeBridge = WenkuGaussianEdgeBridge()
  init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    self.messenger = messenger; self.textures = textures
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = WenkuGlassFactory(messenger: registrar.messenger(), textures: registrar.textures())
    factory.registrar = registrar
    registrar.register(factory, withId: "org.mewx.wenku8/glass_controls")
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_presentation", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(factory, channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "edgeSet", let edge = call.arguments as? [String: Any] {
      WenkuGlassWork.add("edge_profiles_registered")
      edgeBridge.flutterView = registrar?.viewController?.view
      result(edgeBridge.setEdge(edge)); return
    }
    if call.method == "edgeRemove", let args = call.arguments as? [String: Any],
      let identifier = args["id"] as? NSNumber {
      edgeBridge.removeEdge(identifier); result(nil); return
    }
#if DEBUG
    if call.method == "probeEdgeStatus" {
      result(["compatible": edgeBridge.compatible, "maskedFilters": edgeBridge.maskedFilterCount]); return
    }
#endif
    if call.method == "probeStart" {
      WenkuGlassWork.counts = [:]; WenkuGlassWork.recording = true; result(nil); return
    }
    if call.method == "probeEnd" {
      WenkuGlassWork.recording = false; result(WenkuGlassWork.counts); return
    }
    if call.method == "layout" {
      let environment: [String: Any] = ["isPad": UIDevice.current.userInterfaceIdiom == .pad,
        "systemVersion": UIDevice.current.systemVersion,
        "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        "reduceMotion": UIAccessibility.isReduceMotionEnabled]
      result(environment); return
    }
    guard call.method == "menu", let args = call.arguments as? [String: Any],
      let items = args["items"] as? [[String: Any]], !items.isEmpty else {
      result(FlutterMethodNotImplemented); return
    }
    guard menuResult == nil, var presenter = registrar?.viewController else {
      result(FlutterError(code: "PRESENTATION_BUSY", message: "菜单暂时无法打开", details: nil)); return
    }
    while let next = presenter.presentedViewController { presenter = next }
    let button = WenkuMenuButton(type: .system)
    button.overrideUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    let anchor = args["anchor"] as? [String: NSNumber] ?? [:]
    let windowRect = CGRect(x: anchor["x"]?.doubleValue ?? 0, y: anchor["y"]?.doubleValue ?? 0,
      width: max(1, anchor["width"]?.doubleValue ?? 44), height: max(1, anchor["height"]?.doubleValue ?? 44))
    button.frame = presenter.view.convert(windowRect, from: presenter.view.window)
    button.menu = UIMenu(children: items.enumerated().map { index, item in
      UIAction(title: item["label"] as? String ?? "", attributes:
        item["destructive"] as? Bool == true ? .destructive : [], state:
        item["selected"] as? Bool == true ? .on : .off) { [weak button] _ in button?.selection = index }
    })
    button.showsMenuAsPrimaryAction = true
    button.dismissed = { [weak self] in
      guard let self else { return }
      let selection = self.menuButton?.selection
      self.menuButton?.removeFromSuperview()
      self.menuButton = nil
      let callback = self.menuResult
      self.menuResult = nil
      callback?(selection)
    }
    menuButton = button
    menuResult = result
    presenter.view.addSubview(button)
    button.performPrimaryAction()
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
#if DEBUG
    if (args as? [String: Any])?["kind"] as? String == "sharedEdgeProbe" {
      return WenkuSharedGaussianProbeView(frame: frame, id: viewId,
        messenger: messenger, flutterView: registrar?.viewController?.view)
    }
#endif
    let control = WenkuGlassView(frame: frame, id: viewId, args: args as? [String: Any] ?? [:], messenger: messenger, textures: textures)
    edgeBridge.flutterView = registrar?.viewController?.view
    edgeBridge.trackView(control.view())
    return control
  }
}

private final class WenkuMenuButton: UIButton {
  var selection: Int?
  var dismissed: (() -> Void)?
  override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    if let animator { animator.addCompletion { [weak self] in self?.dismissed?() } }
    else { dismissed?() }
  }
}

private final class WenkuGlassRoot: UIView {
  private var captureBounds = CGRect.null
  var layout: (() -> Void)?
  var attached: (() -> Void)?
#if DEBUG
  var probeDetached: (() -> Void)?
#endif
  override func layoutSubviews() {
    super.layoutSubviews()
    if captureBounds != bounds { captureBounds = bounds; WenkuWindowCapture.invalidate() }
    layout?()
  }
  override func didMoveToWindow() {
    super.didMoveToWindow(); WenkuWindowCapture.invalidate(); setNeedsLayout()
    if window != nil { attached?() }
#if DEBUG
    else { probeDetached?() }
#endif
  }
}

/// Apple requires the hosting WINDOW to be captured for visual effects to
/// appear. Reuse that image for all control requests in the same main-loop
/// batch. Expire before sleep or at the next display callback, with a maximum
/// age check if that callback is delayed. The callback is one-shot, never idle.
private struct WenkuWindowImage {
  let window: UIWindow
  let bounds: CGRect
  let image: CGImage?
  let revision: Int
  let expiresAt: CFTimeInterval
}
private final class WenkuCaptureFrameExpiry: NSObject {
  private var link: CADisplayLink?
  init(expired: @escaping () -> Void) {
    self.expired = expired
    super.init()
    let link = CADisplayLink(target: self, selector: #selector(tick))
    self.link = link
    link.add(to: .main, forMode: .common)
  }
  private let expired: () -> Void
  func invalidate() { link?.invalidate(); link = nil }
  @objc private func tick() { invalidate(); expired() }
}
private enum WenkuWindowCapture {
  // Cache failed attempts as well: an incomplete Metal/window render must not
  // trigger the same full-window readback separately for every control.
  static var images: [ObjectIdentifier: WenkuWindowImage] = [:]
  static var observer: CFRunLoopObserver?
  static var frameExpiry: WenkuCaptureFrameExpiry?
  static var revision = 0
  static func invalidate() {
    images.removeAll()
    if let observer { CFRunLoopObserverInvalidate(observer) }
    observer = nil
    frameExpiry?.invalidate(); frameExpiry = nil
  }
  static func image(_ window: UIWindow) -> WenkuWindowImage? {
    let key = ObjectIdentifier(window)
    if let cached = images[key], cached.bounds == window.bounds,
      CACurrentMediaTime() < cached.expiresAt { return cached }
    if images[key] != nil { invalidate() }
    guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false; format.preferredRange = .standard
    format.scale = min(window.traitCollection.displayScale,
      sqrt(4_194_304 / (window.bounds.width * window.bounds.height)))
    let started = CACurrentMediaTime()
    defer { WenkuGlassWork.snapshotDuration(started) }
    var rendered = false
    let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
      rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    WenkuGlassWork.add("window_snapshots")
    let cg = rendered ? image.cgImage : nil
    revision += 1
    // Bound age from capture START, so a slow synchronous window readback
    // cannot extend the lifetime while blocking the expiry callback itself.
    let maximumFPS = max(1, window.windowScene?.screen.maximumFramesPerSecond ?? 60)
    let captured = WenkuWindowImage(window: window, bounds: window.bounds, image: cg,
      revision: revision, expiresAt: started + 1 / Double(maximumFPS))
    images[key] = captured
    // drawHierarchy(afterScreenUpdates:) can run a nested run loop. Arm only
    // AFTER storing the frame, otherwise the observer can fire during capture
    // and leave the newly stored image without any expiry mechanism.
    if observer == nil {
      observer = CFRunLoopObserverCreateWithHandler(nil,
        CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue,
        false, 0) { _, _ in invalidate() }
      CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
      frameExpiry = WenkuCaptureFrameExpiry { invalidate() }
    }
    return captured
  }
}

/// One bounded, immutable native render per state/layout change. The raster
/// thread only retains the last pixel buffer; it never asks UIKit to render.
final class WenkuControlTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixels: CVPixelBuffer?
#if DEBUG
  private(set) var probeCaptureRevision = 0
#endif
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock(); defer { lock.unlock() }
    return pixels.map { Unmanaged.passRetained($0) }
  }
  func capture(_ view: UIView, allowExternalBlur: Bool = false) -> Bool {
    let started = CACurrentMediaTime()
    defer { WenkuGlassWork.captureDuration(started) }
    guard Thread.isMainThread, let window = view.window,
      view.bounds.width.isFinite, view.bounds.height.isFinite,
      view.bounds.width > 0, view.bounds.height > 0 else { return false }
    // A window crop under an external edge already contains its Gaussian.
    // Filtering that texture in Flutter during motion would blur it twice.
    // Keep these few controls live under the ONE native Gaussian instead.
    guard allowExternalBlur || !WenkuGaussianEdgeBridge.viewHasExternalFilter(view) else { return false }
    view.layoutIfNeeded()
    guard let captured = WenkuWindowCapture.image(window), let image = captured.image else { return false }
#if DEBUG
    probeCaptureRevision = captured.revision
#endif
    let windowScale = CGFloat(image.width) / window.bounds.width
    let rect = view.convert(view.bounds, to: window).offsetBy(dx: -window.bounds.minX, dy: -window.bounds.minY)
    let source = CGRect(x: rect.minX * windowScale, y: rect.minY * windowScale,
      width: rect.width * windowScale, height: rect.height * windowScale).integral
    let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !visible.isEmpty, let cg = image.cropping(to: visible) else { return false }
    let scale = min(view.traitCollection.displayScale, sqrt(1_048_576 / (view.bounds.width * view.bounds.height)))
    let width = max(1, Int(ceil(view.bounds.width * scale)))
    let height = max(1, Int(ceil(view.bounds.height * scale)))
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA,
      [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferCGImageCompatibilityKey: true,
       kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else { return false }
    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer),
      let context = CGContext(data: base, width: width,
      height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return false }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let x = (visible.minX - source.minX) / source.width * CGFloat(width)
    let y = (source.maxY - visible.maxY) / source.height * CGFloat(height)
    context.draw(cg, in: CGRect(x: x, y: y,
      width: visible.width / source.width * CGFloat(width),
      height: visible.height / source.height * CGFloat(height)))
    lock.lock(); pixels = buffer; lock.unlock()
    return true
  }
#if DEBUG
  func probePixelBGRA(x: CGFloat, y: CGFloat) -> [UInt8]? {
    guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
      let buffer = copyPixelBuffer()?.takeRetainedValue(),
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let px = min(CVPixelBufferGetWidth(buffer) - 1, Int(x * CGFloat(CVPixelBufferGetWidth(buffer))))
    let py = min(CVPixelBufferGetHeight(buffer) - 1, Int(y * CGFloat(CVPixelBufferGetHeight(buffer))))
    let index = py * CVPixelBufferGetBytesPerRow(buffer) + px * 4
    let bytes = base.assumingMemoryBound(to: UInt8.self).advanced(by: index)
    return Array(UnsafeBufferPointer(start: bytes, count: 4))
  }
  /// Read only a fixed diagnostic sample from test-generated colour patterns.
  func centerPixelBGRA() -> [UInt8]? {
    guard let buffer = copyPixelBuffer()?.takeRetainedValue(),
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let offset = CVPixelBufferGetBytesPerRow(buffer) * (CVPixelBufferGetHeight(buffer) / 2)
      + (CVPixelBufferGetWidth(buffer) / 2) * 4
    let pointer = address.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
    return Array(UnsafeBufferPointer(start: pointer, count: 4))
  }
  func stripeContrastRows() -> [[Int]]? {
    guard let buffer = copyPixelBuffer()?.takeRetainedValue(),
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let bytes = address.assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    return (0...32).map { index in
      let y = (height - 1) * index / 32
      var low = 255, high = 0, tint = 0, alpha = 255
      for x in (width / 4)..<(width * 3 / 4) {
        let p = y * stride + x * 4
        low = min(low, Int(bytes[p])); high = max(high, Int(bytes[p]))
        tint = max(tint, abs(Int(bytes[p]) - Int(bytes[p + 2])))
        alpha = min(alpha, Int(bytes[p + 3]))
      }
      return [high - low, tint, alpha]
    }
  }
#endif
}

#if DEBUG
/// Isolated full-width Gaussian experiment. Not selected by application widgets.
/// Tests verify Metal/native painter order and the REAL wrapper hit path before
/// considering this plane for production. No ancestor-mask hook is installed.
private final class WenkuSharedGaussianProbeView: NSObject, FlutterPlatformView {
  private let root: WenkuGlassRoot
  private let channel: FlutterMethodChannel
  private weak var flutterView: UIView?
  private var surface: UIVisualEffectView?
  private var lastSize = CGSize.zero
  private var bottom = false
  private var renderedBottom = false
  private var safeAncestors = false

  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, flutterView: UIView?) {
    root = WenkuGlassRoot(frame: frame)
    channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_controls/\(id)", binaryMessenger: messenger)
    self.flutterView = flutterView
    super.init()
    root.backgroundColor = .clear; root.isUserInteractionEnabled = false
    root.layout = { [weak self] in self?.refresh() }
    root.attached = { [weak self] in self?.refresh() }
    root.probeDetached = { [weak self] in
      self?.surface?.removeFromSuperview(); self?.surface = nil; self?.lastSize = .zero
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "state", let state = call.arguments as? [String: Any] {
        self.bottom = state["fromBottom"] as? Bool == true
        self.refresh(); result(nil); return
      }
      if call.method == "ancestors" {
        self.refresh(); result(["safeAncestors": self.safeAncestors]); return
      }
      guard call.method == "snapshot" else { result(FlutterMethodNotImplemented); return }
      self.refresh()
      let texture = WenkuControlTexture()
      guard self.surface != nil, self.safeAncestors,
        texture.capture(self.root, allowExternalBlur: true) else {
        result(["safeAncestors": self.safeAncestors]); return
      }
      let point = self.root.convert(CGPoint(x: 30, y: 30), to: self.root.window)
      let hit = self.root.window?.hitTest(point, with: nil)
      guard let background = texture.probePixelBGRA(x: 0.8, y: 0.2),
        let metalBlack = texture.probePixelBGRA(x: 30.5 / self.root.bounds.width, y: 30 / self.root.bounds.height),
        let metalWhite = texture.probePixelBGRA(x: 32.5 / self.root.bounds.width, y: 30 / self.root.bounds.height),
        let black = texture.probePixelBGRA(x: 250.5 / self.root.bounds.width, y: 30 / self.root.bounds.height),
        let white = texture.probePixelBGRA(x: 252.5 / self.root.bounds.width, y: 30 / self.root.bounds.height) else {
        result(FlutterError(code: "PROBE_PIXELS", message: "Fixed Gaussian probe pixels unavailable", details: nil)); return
      }
      result(["safeAncestors": self.safeAncestors,
        "flutterHitThrough": hit === self.flutterView,
        "backgroundPixelBGRA": background,
        "metalBlackBGRA": metalBlack,
        "metalWhiteBGRA": metalWhite,
        "foregroundBlackBGRA": black,
        "foregroundWhiteBGRA": white])
    }
  }
  deinit { channel.setMethodCallHandler(nil) }
  func view() -> UIView { root }
  private func refresh() {
    guard root.window != nil, let flutterView, root.bounds.width > 0, root.bounds.height > 0,
      let interceptor = root.superview, let clip = interceptor.superview,
      NSStringFromClass(type(of: interceptor)) == "FlutterTouchInterceptingView",
      NSStringFromClass(type(of: clip)) == "ChildClippingView" else { safeAncestors = false; return }
    interceptor.isUserInteractionEnabled = false; clip.isUserInteractionEnabled = false
    var ancestor: UIView? = root
    var reachedFlutter = false
    safeAncestors = true
    while let view = ancestor {
      if view.mask != nil || view.alpha != 1 { safeAncestors = false }
      if view === flutterView { reachedFlutter = true; break }
      ancestor = view.superview
    }
    safeAncestors = safeAncestors && reachedFlutter
    guard safeAncestors else { surface?.removeFromSuperview(); surface = nil; return }
    if surface != nil, root.bounds.size == lastSize, bottom == renderedBottom { return }
    surface?.removeFromSuperview()
    surface = WenkuGaussianProbePlaneEffect(root.bounds, bottom ? 8.01 : 8, 60, bottom)
    if let surface {
      root.addSubview(surface)
      if let mask = surface.mask { surface.mask = nil; surface.mask = mask }
      WenkuGlassWork.add("shared_plane_rebuilt")
    }
    lastSize = root.bounds.size; renderedBottom = bottom
  }
}
#endif

private final class WenkuGlassView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate, UITabBarControllerDelegate {
  private let root: WenkuGlassRoot
  private let channel: FlutterMethodChannel
  private let textures: FlutterTextureRegistry
  private var controlTexture: WenkuControlTexture?
  private var textureId: Int64?
  private var state: [String: Any]
  private var buttons: [UIButton] = []
  private var slider: UISlider?
  private var toggle: UISwitch?
  private var previewIndex: Int?
  private var tabs: UITabBarController?
  private var toolbar: UIToolbar?
  private var segmented: UISegmentedControl?
  private var lastHeight: CGFloat = 0
  private var surface: UIVisualEffectView?

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    WenkuGlassWork.add("platform_views_created")
    state = args
    self.textures = textures
    root = WenkuGlassRoot(frame: frame)
    channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_controls/\(id)", binaryMessenger: messenger)
    super.init()
    root.attached = { [weak self] in self?.channel.invokeMethod("attached", arguments: nil) }
    root.backgroundColor = .clear
    createControls()
    update(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "state", let value = call.arguments as? [String: Any] { self.update(value); result(nil) }
      else if call.method == "snapshot" {
        guard self.slider?.isTracking != true, self.toggle?.isTracking != true,
          !self.buttons.contains(where: { $0.isTracking }) else { result(nil); return }
        var probe = false
#if DEBUG
        probe = (call.arguments as? [String: Any])?["probe"] as? Bool == true
#endif
        if !probe && WenkuGaussianEdgeBridge.viewHasExternalFilter(self.root) {
          WenkuGlassWork.add("edge_snapshots_refused")
          result(["underEdge": true]); return
        }
        let texture = self.controlTexture ?? WenkuControlTexture()
        WenkuGlassWork.add("snapshot_requests")
        guard texture.capture(self.root, allowExternalBlur: probe) else { result(nil); return }
        self.controlTexture = texture
        let id = self.textureId ?? self.textures.register(texture)
        self.textureId = id
        self.textures.textureFrameAvailable(id)
        WenkuGlassWork.add("snapshots_captured")
        var response: [String: Any] = ["textureId": id, "width": self.root.bounds.width, "height": self.root.bounds.height]
#if DEBUG
        if (call.arguments as? [String: Any])?["probe"] as? Bool == true {
          response["captureRevision"] = texture.probeCaptureRevision
          response["centerPixelBGRA"] = texture.centerPixelBGRA()
          if self.state["kind"] as? String == "edgeProbe" {
            response["stripeContrastRows"] = texture.stripeContrastRows()
            let point = CGPoint(x: self.root.bounds.midX, y: self.root.bounds.midY)
            let hit = self.root.window?.hitTest(self.root.convert(point, to: self.root.window), with: nil)
            response["nativeHitTarget"] = hit?.isDescendant(of: self.root) == true
          }
        }
#endif
        result(response)
      }
      else { result(FlutterMethodNotImplemented) }
    }
  }

  deinit {
    if let textureId { textures.unregisterTexture(textureId) }
    channel.setMethodCallHandler(nil)
    root.layout = nil
    root.attached = nil
    tabs?.willMove(toParent: nil)
    tabs?.view.removeFromSuperview()
    tabs?.removeFromParent()
  }
  func view() -> UIView { root }

  private func pin(_ child: UIView, to parent: UIView, inset: CGFloat = 0) {
    parent.addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
  }

  private func createControls() {
#if DEBUG
    if state["kind"] as? String == "edgeProbe" {
      let button = UIButton(type: .custom)
      button.backgroundColor = .white
      for x in stride(from: 0, to: 128, by: 4) {
        let stripe = UIView(frame: CGRect(x: CGFloat(x), y: 0, width: 2, height: 1))
        stripe.backgroundColor = .black; stripe.isUserInteractionEnabled = false
        button.addSubview(stripe)
      }
      buttons = [button]; pin(button, to: root)
      root.layout = { [weak button] in
        guard let button else { return }
        for stripe in button.subviews { stripe.frame.size.height = button.bounds.height }
      }
      return
    }
#endif
    switch state["kind"] as? String {
    case "surface":
      root.isUserInteractionEnabled = false
      let opaque = state["opaque"] as? Bool == true
      let glass = UIVisualEffectView(effect: opaque ? nil : UIGlassEffect(style: .regular))
      if !opaque { WenkuGlassWork.add("surface_effects_created") }
      glass.backgroundColor = opaque ? .systemBackground : .clear
      surface = glass
      glass.layer.cornerRadius = (state["radius"] as? NSNumber)?.doubleValue ?? 28
      glass.clipsToBounds = true
      pin(glass, to: root)
    case "tabbar":
      let controller = UITabBarController()
      controller.delegate = self
      controller.view.backgroundColor = .clear
      let items = state["items"] as? [[String: Any]] ?? []
      controller.viewControllers = items.enumerated().map { index, item in
        let page = UIViewController()
        page.view.backgroundColor = .clear
        let name = item["symbol"] as? String ?? ""
        page.tabBarItem = UITabBarItem(title: item["label"] as? String,
          image: UIImage(systemName: name + ".fill") ?? UIImage(systemName: name), tag: index)
        page.tabBarItem.accessibilityIdentifier = "wenku-tab-\(index)"
        return page
      }
      tabs = controller
      root.layout = { [weak self] in
        guard let self else { return }
        if controller.parent == nil, self.root.window != nil {
          var responder: UIResponder? = self.root.superview
          while let value = responder {
            if let parent = value as? UIViewController {
              parent.addChild(controller)
              self.pin(controller.view, to: self.root)
              controller.didMove(toParent: parent)
              break
            }
            responder = value.next
          }
        }
        guard controller.parent != nil else { return }
        controller.view.frame = self.root.bounds
        controller.view.layoutIfNeeded()
        let height = controller.traitCollection.userInterfaceIdiom == .pad
          ? max(controller.tabBar.frame.maxY, controller.selectedViewController?.view.safeAreaInsets.top ?? 0)
          : controller.tabBar.frame.height
        self.reportHeight(height)
      }
    case "toolbar":
      let bar = UIToolbar()
      toolbar = bar
      root.addSubview(bar)
      let items = state["items"] as? [[String: Any]] ?? []
      var barItems: [UIBarButtonItem] = []
      for (index, item) in items.enumerated() {
        if index > 0 { barItems.append(UIBarButtonItem(systemItem: .flexibleSpace)) }
        let action = UIBarButtonItem(title: item["label"] as? String, image:
          index == 1 ? nil : (item["symbol"] as? String).flatMap { UIImage(systemName: $0) },
          primaryAction: UIAction { [weak self] _ in self?.channel.invokeMethod("action", arguments: ["index": index]) })
        action.accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
        action.accessibilityIdentifier = "wenku-reader-action-\(index)"
        barItems.append(action)
      }
      bar.items = barItems
      root.layout = { [weak self] in
        guard let self else { return }
        let height = bar.sizeThatFits(self.root.bounds.size).height
        bar.frame = CGRect(x: 0, y: 0, width: self.root.bounds.width, height: height)
        self.reportHeight(height + self.root.safeAreaInsets.bottom)
      }
    case "segmented":
      let control = UISegmentedControl(items: (state["items"] as? [[String: Any]] ?? []).map { $0["label"] as? String ?? "" })
      segmented = control
      pin(control, to: root, inset: 4)
      control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    case "dock":
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = true
      let glass = UIVisualEffectView(effect: effect)
      glass.layer.cornerRadius = 27
      glass.clipsToBounds = true
      pin(glass, to: root)
      let stack = UIStackView()
      stack.axis = .horizontal
      stack.distribution = .fillEqually
      stack.spacing = 2
      pin(stack, to: glass.contentView, inset: 4)
      let count = (state["items"] as? [[String: Any]])?.count ?? 0
      for index in 0..<count {
        let button = UIButton(type: .system)
        button.tag = index
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
        buttons.append(button)
        stack.addArrangedSubview(button)
      }
      let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
      pan.delegate = self
      root.addGestureRecognizer(pan)
    case "slider":
      let control = UISlider()
      control.addTarget(self, action: #selector(sliderBegan), for: .touchDown)
      control.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
      control.addTarget(self, action: #selector(sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
      slider = control
      pin(control, to: root, inset: 6)
    case "switch":
      let control = UISwitch()
      control.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(control)
      NSLayoutConstraint.activate([control.centerXAnchor.constraint(equalTo: root.centerXAnchor), control.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
      control.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
      toggle = control
    default:
      let button = UIButton(type: .system)
      if state["kind"] as? String != "selection" {
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
      }
      buttons = [button]
      pin(button, to: root)
    }
  }

  private func update(_ args: [String: Any]) {
    WenkuWindowCapture.invalidate()
    WenkuGlassWork.add("state_updates")
    let previousOpaque = state["opaque"] as? Bool == true
    state = args
    let style: UIUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    if root.overrideUserInterfaceStyle != style { root.overrideUserInterfaceStyle = style }
    let enabled = args["enabled"] as? Bool ?? true
#if DEBUG
    if args["kind"] as? String == "edgeProbe" { return }
#endif
    if let surface {
      surface.layer.cornerRadius = (args["radius"] as? NSNumber)?.doubleValue ?? 28
      let opaque = args["opaque"] as? Bool == true
      if opaque != previousOpaque {
        surface.effect = opaque ? nil : UIGlassEffect(style: .regular)
        if !opaque { WenkuGlassWork.add("surface_effects_created") }
        surface.backgroundColor = opaque ? .systemBackground : .clear
      }
    }
    if let tabs {
      tabs.overrideUserInterfaceStyle = style
      tabs.selectedIndex = max(0, min((tabs.viewControllers?.count ?? 1) - 1, args["selectedIndex"] as? Int ?? 0))
    }
    if let toolbar {
      let items = args["items"] as? [[String: Any]] ?? []
      for (index, item) in items.enumerated() {
        let position = index * 2
        guard let actions = toolbar.items, position < actions.count else { continue }
        actions[position].title = item["label"] as? String
        actions[position].isEnabled = enabled && (item["enabled"] as? Bool ?? true)
        actions[position].accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
      }
    }
    if let segmented {
      segmented.selectedSegmentIndex = args["selectedIndex"] as? Int ?? UISegmentedControl.noSegment
      segmented.isEnabled = enabled
    }
    if tabs != nil || toolbar != nil { lastHeight = 0; root.setNeedsLayout() }
    if let slider {
      slider.minimumValue = (args["min"] as? NSNumber)?.floatValue ?? 0
      slider.maximumValue = (args["max"] as? NSNumber)?.floatValue ?? 1
      if !slider.isTracking { slider.value = (args["value"] as? NSNumber)?.floatValue ?? 0 }
      slider.accessibilityLabel = args["label"] as? String
      slider.isEnabled = enabled
    }
    if let toggle {
      toggle.setOn(args["value"] as? Bool ?? false, animated: false)
      toggle.accessibilityLabel = args["label"] as? String
      toggle.isEnabled = enabled
    }
    let items = args["items"] as? [[String: Any]]
    let selected = previewIndex ?? (args["selectedIndex"] as? Int ?? 0)
    for (index, button) in buttons.enumerated() {
      let item = items.flatMap { index < $0.count ? $0[index] : nil } ?? args
      let active = items != nil && selected == index
      var config: UIButton.Configuration = active ? .prominentGlass() : (items == nil ? .glass() : .plain())
      config.cornerStyle = .capsule
      config.showsActivityIndicator = item["loading"] as? Bool ?? false
      config.image = (item["symbol"] as? String).flatMap { UIImage(systemName: $0) }
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: items == nil ? 20 : 17)
      if items != nil || item["showLabel"] as? Bool == true { config.title = item["label"] as? String }
      config.imagePlacement = args["kind"] as? String == "selection" ? .trailing : (items == nil ? .leading : .top)
      config.imagePadding = 3
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        let base = UIFont.systemFont(ofSize: items == nil ? 14 : 10, weight: .medium)
        outgoing.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
        return outgoing
      }
      button.configuration = config
      WenkuGlassWork.add("button_configurations")
      if let menuItems = args["menu"] as? [[String: Any]] {
        button.menu = UIMenu(children: menuItems.enumerated().map { option, item in
          UIAction(title: item["label"] as? String ?? "", state:
            item["selected"] as? Bool == true ? .on : .off) { [weak self] _ in
              self?.channel.invokeMethod("action", arguments: ["index": option])
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
      }
      button.accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
      button.isEnabled = enabled && (item["enabled"] as? Bool ?? true)
      button.accessibilityTraits = active ? [.button, .selected] : .button
    }
  }

  private func reportHeight(_ height: CGFloat) {
    guard height >= 44, height <= 180, abs(height - lastHeight) > 0.5 else { return }
    lastHeight = height
    channel.invokeMethod("metrics", arguments: ["height": height])
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    channel.invokeMethod("action", arguments: ["index": tabBarController.selectedIndex])
  }

  @objc private func segmentChanged() {
    if let segmented { channel.invokeMethod("action", arguments: ["index": segmented.selectedSegmentIndex]) }
  }

  @objc private func tap(_ sender: UIButton) {
    guard sender.isEnabled else { return }
    channel.invokeMethod("action", arguments: ["index": sender.tag])
  }

  @objc private func pan(_ gesture: UIPanGestureRecognizer) {
    guard !buttons.isEmpty, root.bounds.width > 0 else { return }
    let index = max(0, min(buttons.count - 1, Int(gesture.location(in: root).x / root.bounds.width * CGFloat(buttons.count))))
    switch gesture.state {
    case .began, .changed:
      previewIndex = index
      update(state)
    case .ended:
      previewIndex = nil
      update(state)
      let items = state["items"] as? [[String: Any]] ?? []
      if buttons[index].isEnabled, index < items.count, items[index]["selectableOnDrag"] as? Bool != false { tap(buttons[index]) }
    case .cancelled, .failed:
      previewIndex = nil
      update(state)
    default: break
    }
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: root)
    return WenkuControlPolicy.shouldBeginPan(horizontal: Double(velocity.x), vertical: Double(velocity.y))
  }

  @objc private func sliderBegan() { channel.invokeMethod("action", arguments: ["phase": "start"]) }
  @objc private func sliderChanged() { sendSlider(phase: slider?.isTracking == true ? "change" : "end") }
  @objc private func sliderEnded() { sendSlider(phase: "end") }
  private func sendSlider(phase: String) {
    guard let slider, slider.isEnabled else { return }
    var value = Double(slider.value)
    if let steps = state["divisions"] as? Int, steps > 0 {
      let min = Double(slider.minimumValue), span = Double(slider.maximumValue - slider.minimumValue)
      if span > 0 { value = min + ((value - min) / span * Double(steps)).rounded() / Double(steps) * span }
    }
    channel.invokeMethod("action", arguments: ["phase": phase, "value": value])
  }
  @objc private func toggleChanged() {
    guard let toggle, toggle.isEnabled else { return }
    channel.invokeMethod("action", arguments: ["value": toggle.isOn])
  }
}
