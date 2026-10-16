import Flutter
import UIKit
import CoreVideo
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

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
