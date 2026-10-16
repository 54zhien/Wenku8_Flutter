import Flutter
import UIKit
import CoreVideo
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

  @MainActor
  func testPinnedEngineGaussianReceivesContinuousFeatherWithoutTintOrLostHitTarget() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 180, height: 260)
    let controller = UIViewController()
    window.rootViewController = controller
    controller.view.backgroundColor = .white
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let access = WenkuGaussianTestAccess(root: controller.view)
    XCTAssertTrue(access.compatible, "Pinned engine ABI must match; incompatible is a failure")
    let clip = try XCTUnwrap(access.clip(CGRect(x: 20, y: 20, width: 128, height: 180)))
    let button = UIButton(frame: clip.bounds)
    button.backgroundColor = .white
    for x in stride(from: 0, to: 128, by: 4) {
      let stripe = UIView(frame: CGRect(x: CGFloat(x), y: 0, width: 2, height: 180))
      stripe.backgroundColor = .black; stripe.isUserInteractionEnabled = false
      button.addSubview(stripe)
    }
    clip.addSubview(button)
    controller.view.addSubview(clip)
    XCTAssertTrue(access.apply(clip, sigma: 8))
    func contrasts() async throws -> [Int] {
      await withCheckedContinuation { continuation in
        CaptureDisplayFrames.wait(2) { continuation.resume() }
      }
      let texture = WenkuControlTexture()
      XCTAssertTrue(texture.capture(clip, allowExternalBlur: true))
      let buffer = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
      XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
      defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
      let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
      let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
      let stride = CVPixelBufferGetBytesPerRow(buffer)
      var tintDifference = 0, minimumAlpha: UInt8 = 255
      let rows = (0..<height).map { y in
        var low = 255, high = 0
        for x in (width / 4)..<(width * 3 / 4) {
          let p = y * stride + x * 4
          tintDifference = max(tintDifference, abs(Int(bytes[p]) - Int(bytes[p + 2])))
          minimumAlpha = min(minimumAlpha, bytes[p + 3])
          low = min(low, Int(bytes[p])); high = max(high, Int(bytes[p]))
        }
        return high - low
      }
      XCTAssertLessThanOrEqual(tintDifference, 2, "Gaussian must not introduce tint")
      XCTAssertEqual(minimumAlpha, 255)
      return rows
    }
    let rectangular = try await contrasts()
    XCTAssertLessThan(rectangular[rectangular.count / 10], 35)
    XCTAssertLessThan(rectangular[rectangular.count * 9 / 10], 35,
                      "Baseline demonstrates the engine's unmasked rectangular Gaussian")
    access.track(button)
    clip.removeFromSuperview()
    XCTAssertTrue(access.set(["id": 1, "y": 20, "height": 180, "plateau": 60, "sigma": 8, "fromBottom": false]))
    XCTAssertTrue(access.apply(clip, sigma: 8), "First composition occurs before native insertion")
    XCTAssertEqual(access.maskCount, 1)
    controller.view.addSubview(clip)
    XCTAssertFalse(WenkuControlTexture().capture(clip),
                   "A normal route snapshot must refuse a Gaussian already baked into its crop")
    let top = try await contrasts()
    XCTAssertLessThan(top[top.count / 10], 35)
    XCTAssertGreaterThan(top[top.count * 98 / 100], 225)
    XCTAssertLessThan(zip(top, top.dropFirst()).map { abs($0 - $1) }.max() ?? 256, 12,
                      "The feather must be continuous, without radius bands")
    let hit = window.hitTest(clip.convert(CGPoint(x: 64, y: 70), to: window), with: nil)
    XCTAssertTrue(hit === button, "Native initial touch must reach the actual control under the feather")
    access.set(["id": 1, "y": 20, "height": 180, "plateau": 60, "sigma": 8, "fromBottom": true])
    let bottom = try await contrasts()
    XCTAssertGreaterThan(bottom[bottom.count / 100], 225)
    XCTAssertLessThan(bottom[bottom.count * 9 / 10], 35)
    XCTAssertTrue(access.set(["id": 1, "y": 20, "height": 180, "plateau": 60, "sigma": 8, "fromBottom": false]))
    // A scrolling native control sees only the middle portion of the edge.
    // Its mask must retain the full profile's coordinates, not restart at 1.
    clip.frame = CGRect(x: 20, y: 80, width: 128, height: 80)
    button.frame = clip.bounds
    XCTAssertTrue(access.apply(clip, sigma: 8))
    let partial = try await contrasts()
    XCTAssertLessThan(partial[partial.count / 20], 40)
    XCTAssertGreaterThan(partial[partial.count * 19 / 20], 150)
    let effect = try XCTUnwrap(clip.subviews.compactMap { $0 as? UIVisualEffectView }.first)
    let mask = try XCTUnwrap(effect.mask)
    XCTAssertEqual(mask.frame.minY, -60, accuracy: .001)
    XCTAssertEqual(mask.frame.height, 180, accuracy: .001)
    let gradient = try XCTUnwrap(mask.layer as? CAGradientLayer)
    let colors = try XCTUnwrap(gradient.colors as? [CGColor])
    XCTAssertEqual(colors.count, 8)
    for i in 0..<8 {
      let x = max(0, min(1, (Double(i) / 7 - 1.0 / 3) / (2.0 / 3)))
      XCTAssertEqual(colors[i].alpha, 1 - x * x * (3 - 2 * x), accuracy: .00001)
    }
    // Reusing the control at a different position keeps its original mask view.
    clip.frame.origin.y = 90
    XCTAssertTrue(access.apply(clip, sigma: 8))
    XCTAssertTrue(effect.mask === mask)
    XCTAssertEqual(mask.frame.minY, -70, accuracy: .001)
    XCTAssertFalse(access.set(["id": 1, "y": 20, "height": -1, "plateau": 60, "sigma": 8, "fromBottom": false]))
    XCTAssertEqual(access.maskCount, 0, "A rejected revision must remove the stale mask")
    XCTAssertTrue(access.set(["id": 1, "y": 100, "height": 80, "plateau": 20, "sigma": 8, "fromBottom": false]))
    let unmatched = try await contrasts()
    XCTAssertGreaterThan(unmatched[unmatched.count / 2], 225,
                         "A known edge with mismatched geometry must not expose rectangular blur")
    XCTAssertEqual(access.maskCount, 0)
    XCTAssertTrue(access.set(["id": 1, "y": 20, "height": 180, "plateau": 60, "sigma": 8, "fromBottom": false]))
    XCTAssertTrue(access.set(["id": 2, "y": 20, "height": 180, "plateau": 100, "sigma": 8, "fromBottom": false]))
    let ambiguous = try await contrasts()
    XCTAssertGreaterThan(ambiguous[ambiguous.count / 2], 225,
                         "Ambiguous edge profiles must fail closed, without a raw Gaussian rectangle")
    XCTAssertEqual(access.maskCount, 0)
    access.remove(2)
    XCTAssertEqual(access.maskCount, 1)
    access.remove(1)
    XCTAssertEqual(access.maskCount, 0)
    let removed = try await contrasts()
    XCTAssertLessThan(removed[removed.count * 9 / 10], 35)
  }

  @MainActor
  func testLiquidGlassTextureIncludesEffectsInTheFlutterHostingWindow() async throws {
    let window = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
      .first { $0.rootViewController is FlutterViewController })
    let flutter = try XCTUnwrap(window.rootViewController as? FlutterViewController)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      flutter.isDisplayingFlutterUI
    }, object: nil)
    await fulfillment(of: [ready], timeout: 10)
    let background = UIView(frame: CGRect(x: 40, y: 180, width: 160, height: 100))
    for index in 0..<50 {
      let stripe = UIView(frame: CGRect(x: 0, y: CGFloat(index * 2), width: 160, height: 2))
      stripe.backgroundColor = index.isMultiple(of: 2) ? .red : .blue
      background.addSubview(stripe)
    }
    let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    glass.frame = CGRect(x: 10, y: 10, width: 140, height: 80)
    window.addSubview(background)
    background.addSubview(glass)
    defer { background.removeFromSuperview() }
    await withCheckedContinuation { continuation in
      CaptureDisplayFrames.wait(2) { continuation.resume() }
    }
    let texture = WenkuControlTexture()
    XCTAssertTrue(texture.capture(glass), "The real Flutter/Metal window must support effect capture")
    let buffer = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
    XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let data = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer) * (CVPixelBufferGetHeight(buffer) / 2)
    let pixel = row + (CVPixelBufferGetWidth(buffer) / 2) * 4
    XCTAssertGreaterThan(data[pixel], 20, "Glass must include the blue backdrop, not transparent/black pixels")
    XCTAssertGreaterThan(data[pixel + 2], 20, "Glass must blend the red stripes, not capture an unfiltered subtree")
    XCTAssertEqual(data[pixel + 3], 255)
  }

  @MainActor
  func testNativeControlTextureKeepsBGRAOrientationAndLastValidFrame() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 80, height: 60)
    let controller = UIViewController()
    window.rootViewController = controller
    let view = UIView(frame: window.bounds)
    view.backgroundColor = .blue
    let top = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 30))
    top.backgroundColor = .red
    view.addSubview(top)
    controller.view.addSubview(view)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.view.layoutIfNeeded()
    let texture = WenkuControlTexture()
    XCTAssertTrue(texture.capture(view))
    let pixels = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
    XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixels), kCVPixelFormatType_32BGRA)
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    let data = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    let height = CVPixelBufferGetHeight(pixels)
    XCTAssertGreaterThan(data[stride * (height / 4) + 2], 240, "Top must remain red")
    XCTAssertLessThan(data[stride * (height / 4)], 15)
    XCTAssertGreaterThan(data[stride * (height * 3 / 4)], 240, "Bottom must remain blue")
    CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
    view.removeFromSuperview()
    XCTAssertFalse(texture.capture(view), "Detached native views cannot refresh an effect")
    let retained = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
    XCTAssertTrue(retained === pixels, "A failed refresh must retain the visible frame")
  }

  func testNumericAndChallengeBodiesAreRejected() {
    for text in ["4", "20", "", "<html>challenge</html>"] {
      XCTAssertThrowsError(try WenkuProtocol.validateBody(text))
    }
    XCTAssertEqual(try WenkuProtocol.validateBody("正文\n下一段"), "正文\n下一段")
  }

  func testLogoutRejectsAnOlderSessionResponse() {
    var state = WenkuSessionState(cookie: "oldsession123")
    let old = state.revision
    state.invalidate()
    XCTAssertFalse(state.accept("stalesession123", expectedRevision: old))
    XCTAssertNil(state.cookie)
  }

  func testImageRedirectRejectsUnapprovedHostAndPreservesEscapedPath() throws {
    let origin = URL(string: "https://img.wenku8.com/a")!
    XCTAssertThrowsError(try WenkuProtocol.imageRedirect(from: origin, location: "https://attacker.test/a"))
    XCTAssertEqual(try WenkuProtocol.imageRedirect(from: origin, location: "http://img.wenku8.com/a%2Fb?q=%2F").absoluteString,
                   "https://img.wenku8.com/a%2Fb?q=%2F")
  }

  func testReviewEncodingMatchesStrictAndroidGBKContract() {
    let done = expectation(description: "GBK review")
    let bridge = WenkuBridge()
    bridge.handle(FlutterMethodCall(methodName: "encodeReview", arguments: ["text": "中文 空格+~"])) { value in
      let encoded = value as? String
      let decoded = encoded.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }
      XCTAssertEqual(decoded, "%D6%D0%CE%C4+%BF%D5%B8%F1%2B%7E")
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
  }

  func testReviewEncodingRejectsEmojiWithoutLossyReplacement() {
    let done = expectation(description: "unsupported GBK character")
    let bridge = WenkuBridge()
    bridge.handle(FlutterMethodCall(methodName: "encodeReview", arguments: ["text": "😀"])) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "REVIEW_ENCODING")
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
  }

}

@MainActor
private final class CaptureDisplayFrames: NSObject {
  private var remaining: Int
  private var link: CADisplayLink?
  private let completion: () -> Void
  private init(_ count: Int, completion: @escaping () -> Void) {
    remaining = count; self.completion = completion
  }
  static func wait(_ count: Int, completion: @escaping () -> Void) {
    let target = CaptureDisplayFrames(count, completion: completion)
    let link = CADisplayLink(target: target, selector: #selector(tick))
    target.link = link
    link.add(to: .main, forMode: .common)
  }
  @objc private func tick() {
    remaining -= 1
    if remaining == 0 { link?.invalidate(); link = nil; completion() }
  }
}
