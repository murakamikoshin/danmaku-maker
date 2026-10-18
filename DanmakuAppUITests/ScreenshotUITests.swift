import XCTest

/// App Store 用スクリーンショットを撮る。使い方（言語ごとに実行）:
///   TEST_RUNNER_SHOT_LANG=ja TEST_RUNNER_SHOT_DIR=/tmp/shots xcodebuild test -scheme DanmakuApp -only-testing:DanmakuAppUITests/ScreenshotUITests \
///     -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
final class ScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var lang: String { ProcessInfo.processInfo.environment["SHOT_LANG"] ?? "ja" }
    private var dir: String { ProcessInfo.processInfo.environment["SHOT_DIR"] ?? "/tmp/danmaku-shots" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        app = XCUIApplication()
        let locale = lang == "ja" ? "ja_JP" : "en_US"
        app.launchArguments += ["-uitest-invincible", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        app.launch()
    }

    private func shot(_ name: String) throws {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(lang)_\(name).png"))
    }

    private func title(_ ja: String, _ en: String) -> String { lang == "ja" ? ja : en }

    private func startStage(_ name: String) {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        var tries = 0
        while !row.isHittable && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    func testStoreScreenshots() throws {
        sleep(3)
        try shot("01_home")

        startStage(title("弾幕地獄", "Danmaku Hell"))
        sleep(14)
        try shot("02_play_hell")
        app.buttons["play.quit"].tap()

        startStage(title("三段変化のボス", "Three-Phase Boss"))
        sleep(12)
        try shot("03_play_boss")
        app.buttons["play.quit"].tap()

        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        app.buttons["home.create"].tap()
        sleep(4)
        try shot("04_editor")
        app.swipeUp()
        sleep(2)
        try shot("05_editor_cards")
    }
}
