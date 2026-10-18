import XCTest

/// エディタの流れ。実機（またはシミュレーター）で `-uitest-invincible` 付きで起動し、DEBUG ビルドの無敵フラグでクリアさせる
final class EditorFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-invincible", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["home.create"].tap()
    }

    func testAddAndDeleteEmitters() {
        XCTAssertTrue(app.otherElements["emitter.card.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["emitter.delete.0"].exists, "発射台が1つのときは削除できない")
        app.buttons["editor.add"].tap()
        XCTAssertTrue(app.otherElements["emitter.card.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["emitter.delete.1"].exists)
        app.buttons["emitter.delete.1"].tap()
        XCTAssertFalse(app.otherElements["emitter.card.1"].exists)
    }

    func testChangePattern() {
        let picker = app.buttons["emitter.pattern.0"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Rain"].tap()
        XCTAssertTrue(app.buttons["emitter.pattern.0"].label.contains("Rain"))
    }

    func testTestPlayEnablesPublish() {
        XCTAssertFalse(app.buttons["editor.post"].isEnabled)
        XCTAssertTrue(app.staticTexts["editor.status.need"].waitForExistence(timeout: 5))
        app.buttons["editor.test"].tap()
        XCTAssertTrue(app.staticTexts["result.headline"].waitForExistence(timeout: 40), "無敵なのでクリアするはず")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["editor.post"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.post"].isEnabled)
        // 内容を変えるとクリア確認がリセットされる
        app.buttons["editor.add"].tap()
        XCTAssertFalse(app.buttons["editor.post"].isEnabled)
    }
}
