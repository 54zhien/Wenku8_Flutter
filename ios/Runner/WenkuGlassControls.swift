import Flutter
import UIKit

/// Native-only prototype. Flutter owns state/routes; this view owns controls.
final class WenkuGlassFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    WenkuGlassView(frame: frame, id: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private final class WenkuGlassView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate {
  private let root: UIView
  private let channel: FlutterMethodChannel
  private var state: [String: Any]
  private var buttons: [UIButton] = []
  private var slider: UISlider?
  private var toggle: UISwitch?
  private var previewIndex: Int?

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    state = args
    root = UIView(frame: frame)
    channel = FlutterMethodChannel(name: "org.mewx.wenku8/glass_controls/\(id)", binaryMessenger: messenger)
    super.init()
    root.backgroundColor = .clear
    createControls()
    update(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "state", let value = call.arguments as? [String: Any] { self.update(value); result(nil) }
      else { result(FlutterMethodNotImplemented) }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }
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
    switch state["kind"] as? String {
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
      button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
      buttons = [button]
      pin(button, to: root)
    }
  }

  private func update(_ args: [String: Any]) {
    state = args
    root.overrideUserInterfaceStyle = args["dark"] as? Bool == true ? .dark : .light
    let enabled = args["enabled"] as? Bool ?? true
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
      config.imagePlacement = items == nil ? .leading : .top
      config.imagePadding = 3
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        let base = UIFont.systemFont(ofSize: items == nil ? 14 : 10, weight: .medium)
        outgoing.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
        return outgoing
      }
      button.configuration = config
      button.accessibilityLabel = item["semanticLabel"] as? String ?? item["label"] as? String
      button.isEnabled = enabled && (item["enabled"] as? Bool ?? true)
      button.accessibilityTraits = active ? [.button, .selected] : .button
    }
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
