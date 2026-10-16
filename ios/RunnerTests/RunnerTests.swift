import Flutter
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

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
