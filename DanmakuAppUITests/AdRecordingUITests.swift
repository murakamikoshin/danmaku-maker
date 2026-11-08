import XCTest

/// 広告動画の収録用(ci/ad-recording ブランチだけ。main には入れない)。
/// エミュレーターにつないで「作る → テストプレイ → 投稿 → 世界のステージ」を操作し、各場面の時刻を marks.txt に書く。
/// 画面収録はワークフロー側の `simctl io recordVideo` で行う。途中で見つからない部品があっても、止めずに先へ進む
final class AdRecordingUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dir: String { ProcessInfo.processInfo.environment["AD_DIR"] ?? "/tmp/ad-recording" }
    private var marks = ""
    private let stageName = "星くずの渦"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments += ["-use-emulator", "-emulator-host", "127.0.0.1", "-ad-member", "-ad-autopilot", "-no-ads", "-no-debug-overlay",
                                "-ad-name", stageName, "-ad-author", "Koshin",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    }

    private func mark(_ s: String) {
        marks += String(format: "%.3f %@\n", Date().timeIntervalSince1970, s)
        try? marks.write(toFile: "\(dir)/marks.txt", atomically: true, encoding: .utf8)
    }

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func dump(_ name: String) {
        try? app.debugDescription.write(toFile: "\(dir)/tree_\(name).txt", atomically: true, encoding: .utf8)
    }

    /// 画面を少しだけスクロールする(大きく飛ばないように、指でゆっくりなぞる)。up=true で下の内容を出す
    private func nudge(up: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.72 : 0.38))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.38 : 0.72))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    /// 見つかるまでスクロールして、画面に出す。部品が画面より上にあれば上へ、下(またはまだ作られていない)なら下へ
    @discardableResult
    private func reveal(_ e: XCUIElement, tries: Int = 14, timeout: Double = 4) -> Bool {
        _ = e.waitForExistence(timeout: timeout)
        var n = 0
        while !(e.exists && e.isHittable) && n < tries {
            let h = app.frame.height
            if e.exists && e.frame.maxY < h * 0.25 { nudge(up: false) } else { nudge(up: true) }
            n += 1
        }
        return e.exists && e.isHittable
    }

    @discardableResult
    private func tap(_ e: XCUIElement, _ label: String, timeout: Double = 5, pause: UInt32 = 0) -> Bool {
        guard reveal(e, timeout: timeout) else { mark("MISSING \(label)"); dump(label); shot("missing_\(label)"); return false }
        let f = e.frame, a = app.frame
        mark(String(format: "tap %@ @%.4f,%.4f", label, f.midX / a.width, f.midY / a.height))
        e.tap()
        if pause > 0 { sleep(pause) }
        return true
    }

    private func btn(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }

    func testRecordAd() throws {
        app.launch()
        sleep(5)
        mark("home"); shot("01_home")

        // 作る
        tap(btn("home.create"), "create", pause: 3)
        mark("editor"); shot("02_editor")
        sleep(2)
        tap(btn("emitter.color.0.1"), "color0", pause: 2)
        tap(btn("emitter.pattern.toggle.0"), "patternToggle0", pause: 1)
        shot("03_pattern_tiles")
        tap(btn("emitter.pattern.0.spiral"), "pattern0.spiral", pause: 2)
        tap(btn("editor.add"), "add1", pause: 2)
        reveal(app.otherElements["emitter.card.1"].firstMatch)
        tap(btn("emitter.color.1.2"), "color1", pause: 2)
        shot("04_editor_two")
        tap(btn("editor.add"), "add2", pause: 1)
        tap(btn("emitter.pattern.toggle.2"), "patternToggle2", pause: 1)
        tap(btn("emitter.pattern.2.rain"), "pattern2.rain", pause: 1)
        tap(btn("emitter.color.2.3"), "color2", pause: 2)
        shot("05_editor_three")

        // テストプレイ(自動操縦で本当によける。無敵ではない)
        var cleared = false
        for attempt in 0..<3 {
            if attempt == 0 { tap(btn("editor.test"), "test", pause: 0) } else { tap(btn("result.retry"), "retry\(attempt)") }
            mark("testplay.start")
            sleep(6); shot("06_testplay_\(attempt)")
            let headline = app.staticTexts["result.headline"]
            _ = headline.waitForExistence(timeout: 45)
            mark("testplay.result \(headline.exists ? headline.label : "none")")
            shot("07_result_\(attempt)")
            sleep(2)
            if app.staticTexts["editor.status.ok"].exists { cleared = true }
            if headline.exists && !headline.label.contains("被弾") && !headline.label.contains("時間切れ") { cleared = true; break }
        }
        mark("cleared \(cleared)")
        tap(btn("result.back"), "back", pause: 2)
        shot("08_editor_verified")

        // 投稿
        tap(btn("editor.post"), "post", pause: 2)
        mark("publish"); shot("09_publish")
        let accept = btn("publish.terms.accept")
        if accept.waitForExistence(timeout: 3) { tap(accept, "terms", pause: 2) }
        shot("10_publish_ready")
        tap(btn("publish.submit"), "submit", pause: 0)
        let done = btn("publish.done.close")
        _ = done.waitForExistence(timeout: 30)
        mark("published \(done.exists)")
        sleep(1); shot("11_published")
        sleep(3)
        tap(done, "doneClose", pause: 2)
        tap(btn("editor.close"), "editorClose", pause: 2)

        // 世界のステージ
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        tap(btn("home.tab.world"), "worldTab", pause: 3)
        mark("world"); shot("12_world")
        tap(btn("home.sort.new"), "sortNew", pause: 3)
        mark("world.new"); shot("13_world_new")
        sleep(2)
        app.swipeUp(velocity: .slow); sleep(2)
        shot("14_world_scrolled")
        app.swipeDown(velocity: .slow); sleep(1)
        tap(btn("home.sort.popular"), "sortPopular", pause: 3)
        mark("world.popular"); shot("15_world_popular")
        app.swipeUp(velocity: .slow); sleep(2)
        app.swipeDown(velocity: .slow); sleep(1)
        tap(btn("home.sort.new"), "sortNew2", pause: 3)

        // 自分のステージの詳細 → 遊ぶ
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", stageName)).firstMatch
        tap(row, "myRow", pause: 3)
        mark("detail"); shot("16_detail")
        sleep(2)
        app.swipeUp(velocity: .slow); sleep(2); shot("17_detail_scrolled")
        app.swipeDown(velocity: .slow); sleep(1)
        tap(btn("detail.play"), "detailPlay", pause: 0)
        mark("myplay"); sleep(8); shot("18_myplay")
        if !tap(btn("play.quit"), "quitMine", timeout: 2, pause: 2) { tap(btn("result.back"), "backMine", pause: 2) }
        tap(btn("detail.close"), "detailCloseMine", pause: 2)

        // 世界のステージ(ほかの人が作ったもの)を遊ぶ
        tap(btn("home.sort.popular"), "sortPopular2", pause: 3)
        for (i, name) in ["ねじれ銀河", "ピンクの悪夢"].enumerated() {
            let r = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            tap(r, "worldRow\(i)", pause: 3)
            mark("worlddetail\(i)"); shot("19_worlddetail_\(i)")
            tap(btn("detail.play"), "worldPlay\(i)", pause: 0)
            mark("worldplay\(i) \(name)"); sleep(5); shot("20_worldplay_\(i)a"); sleep(9); shot("20_worldplay_\(i)b")
            mark("worldplay\(i).end")
            if !tap(btn("play.quit"), "worldQuit\(i)", timeout: 2, pause: 2) { tap(btn("result.back"), "worldBack\(i)", pause: 2) }
            tap(btn("detail.close"), "worldDetailClose\(i)", pause: 2)
            app.swipeDown(velocity: .fast); sleep(1)
        }
        mark("end")
        dump("end")
    }
}
