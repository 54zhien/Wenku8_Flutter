import Foundation

@main
struct WenkuProtocolTests {
  static func main() throws {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
      precondition(condition(), name)
      checks += 1
    }
    func rejects(_ name: String, _ operation: () throws -> Void) {
      do { try operation(); preconditionFailure(name) }
      catch { checks += 1 }
    }

    let form = String(decoding: WenkuProtocol.form(action: "action=userinfo", now: 123), as: UTF8.self)
    check(form == "appver=1.13&request=YWN0aW9uPXVzZXJpbmZv&timetoken=123", "wire envelope")
    let chinese = WenkuProtocol.form(action: "书", now: 1)
    check(String(decoding: chinese, as: UTF8.self).contains("request=5Lmm"), "UTF8 action")
    let prose = try WenkuProtocol.validateBody("  正文章节\n第二行  ")
    check(prose == "  正文章节\n第二行  ", "preserve prose bytes")
    let quotedError = try WenkuProtocol.validateBody("正文引用 <error> 标签作为例子。")
    check(quotedError == "正文引用 <error> 标签作为例子。", "literal tag inside prose is not an API error")
    for body in ["", " 4\n", "20", "<html>challenge</html>", "<!DOCTYPE html><html></html>", "<?xml version=\"1.0\"?><error>failed</error>"] {
      rejects("reject invalid body") { _ = try WenkuProtocol.validateBody(body) }
    }
    for raw in ["https://img.wenku8.com/a.jpg", "https://wenku8.net/a", "https://pic.777743.xyz/a?x=%2F"] {
      let url = try WenkuProtocol.imageURL(raw)
      check(url.absoluteString == raw, "approved image address")
    }
    for raw in ["http://img.wenku8.com/a", "https://wenku8.com.attacker.test/a", "https://user@wenku8.com/a", "https://wenku8.com:444/a", "file:///a"] {
      rejects("reject unsafe image address") { _ = try WenkuProtocol.imageURL(raw) }
    }
    let redirected = try WenkuProtocol.imageRedirect(from: URL(string: "https://img.wenku8.com/a")!, location: "http://img.wenku8.com/x%2Fy?q=%2F")
    check(redirected.absoluteString == "https://img.wenku8.com/x%2Fy?q=%2F", "redirect preserves escapes and upgrades HTTP")
    rejects("cross-domain redirect") { _ = try WenkuProtocol.imageRedirect(from: redirected, location: "https://attacker.test/x") }
    check(WenkuProtocol.sessionCookie(in: ["PHPSESSID=abcdefgh1234; Path=/; HttpOnly"]) == "abcdefgh1234", "extract cookie")
    check(WenkuProtocol.sessionCookie(in: ["OTHER=abcdefgh1234"]) == nil, "do not accept another cookie")
    check(WenkuProtocol.sessionCookie(in: ["PHPSESSID=abcdefgh1234; Max-Age=0"]) == nil, "expired cookie")
    var session = WenkuSessionState(cookie: "oldsession123")
    let oldRevision = session.revision
    session.invalidate()
    check(!session.accept("stalesession123", expectedRevision: oldRevision), "logout rejects delayed response")
    check(session.cookie == nil, "logout stays logged out")
    check(session.accept("newsession123", expectedRevision: session.revision), "current login accepted")
    check(session.cookie == "newsession123", "current login becomes active")
    check(WenkuControlPolicy.shouldBeginPan(horizontal: 80, vertical: 10), "horizontal dock drag")
    check(WenkuControlPolicy.shouldBeginPan(horizontal: -80, vertical: 10), "reverse horizontal dock drag")
    check(!WenkuControlPolicy.shouldBeginPan(horizontal: 10, vertical: 80), "vertical scroll does not select a tab")
    check(!WenkuControlPolicy.shouldBeginPan(horizontal: 0, vertical: 0), "stationary touch is not a pan")
    check(!WenkuControlPolicy.shouldBeginPan(horizontal: .infinity, vertical: 0), "nonfinite pan is rejected")
    print("WenkuProtocol: \(checks) checks passed")
  }
}
