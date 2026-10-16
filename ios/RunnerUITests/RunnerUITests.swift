import XCTest
import UIKit

final class RunnerUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  private func capture(_ name: String) {
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }

  func testNavigationMenuKeyboardAndReaderPanel() throws {
    let app = XCUIApplication()
    app.launch()
    let discover = app.buttons["发现"]
    let settings = app.buttons["设置"]
    XCTAssertTrue(discover.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(settings.isHittable)
    XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
    XCTAssertLessThanOrEqual(settings.frame.maxY, app.frame.maxY)
    if UIDevice.current.userInterfaceIdiom == .pad {
      XCTAssertLessThan(settings.frame.maxY, app.frame.midY)
    } else { XCTAssertGreaterThan(settings.frame.minY, app.frame.midY) }
    capture("home-portrait")

    let sort = app.buttons["分类与排序"]
    XCTAssertTrue(sort.waitForExistence(timeout: 30))
    XCTAssertTrue(sort.isHittable)
    sort.tap()
    let recent = app.buttons["最近更新"].firstMatch
    XCTAssertTrue(recent.waitForExistence(timeout: 5), app.debugDescription)
    capture("system-sort-menu")
    recent.tap()
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    let appearance = app.buttons["选择外观模式"].firstMatch
    XCTAssertTrue(appearance.waitForExistence(timeout: 10), app.debugDescription)
    appearance.tap()
    let system = app.buttons["跟随系统"].firstMatch
    XCTAssertTrue(system.waitForExistence(timeout: 5))
    capture("system-appearance-menu")
    system.tap()
    XCTAssertTrue(app.switches["内置思源宋体"].waitForExistence(timeout: 5))
    capture("settings-native-controls")

    discover.tap()
    app.buttons["搜索"].tap()
    let search = app.textFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(settings.isHittable)
    capture("search-keyboard")
    app.buttons["收起搜索"].tap()
    XCTAssertTrue(discover.waitForExistence(timeout: 5))

    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertTrue(settings.isHittable)
    capture("home-landscape")
    XCUIDevice.shared.orientation = .portrait

    let book = app.descendants(matching: .any)["archive-shelf-open"].firstMatch
    XCTAssertTrue(book.waitForExistence(timeout: 30), app.debugDescription)
    if !book.isHittable { app.swipeUp() }
    XCTAssertTrue(book.isHittable)
    book.tap()
    let read = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")).firstMatch
    XCTAssertTrue(read.waitForExistence(timeout: 30), app.debugDescription)
    if !read.isHittable { app.swipeUp() }
    XCTAssertTrue(read.isHittable)
    read.tap()
    let tools = app.buttons["阅读设置"]
    XCTAssertTrue(tools.waitForExistence(timeout: 15), app.debugDescription)
    tools.tap()
    XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.sliders.firstMatch.exists)
    capture("reader-native-panel")
    app.segmentedControls.buttons["书签"].tap()
    capture("reader-bookmarks-panel")
    app.buttons["关闭阅读设置"].tap()
    XCTAssertTrue(app.toolbars.firstMatch.waitForExistence(timeout: 5))
    capture("reader-system-toolbar")
  }
}
