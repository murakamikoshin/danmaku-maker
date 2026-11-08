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

    /// 画面の左端の余白から、縦になぞってスクロールする。
    /// 真ん中から始めると、エディタのスライダーが指を受け取ってしまい、スクロールにならない
    private var dragX: CGFloat = 0.025

    private func drag(up: Bool, fast: Bool) {
        let x = dragX
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.80 : 0.30))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.30 : 0.80))
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: fast ? .fast : XCUIGestureVelocity(700), thenHoldForDuration: 0)
    }

    /// 少しだけスクロールする(発射台の追加までは、この標準スワイプで成功している)
    private func nudge(up: Bool) {
        if up { app.swipeUp(velocity: XCUIGestureVelocity(260)) } else { app.swipeDown(velocity: XCUIGestureVelocity(260)) }
        usleep(400_000)
    }

    /// 部品が画面の見える帯(縦の割合)に入るまで、少しずつスクロールする。
    /// エディタは上にプレビューが固定で出ているので、帯をその下にする(isHittable は固定ヘッダーの下だと false になるので使わない)
    /// 部品の位置。見つからないときは nil(frame を直接読むと、消えた瞬間にテストが止まるので snapshot で読む)
    private func frameOf(_ e: XCUIElement) -> CGRect? {
        guard let f = try? e.snapshot().frame, !f.isEmpty else { return nil }
        return f
    }

    @discardableResult
    private func reveal(_ e: XCUIElement, band: ClosedRange<CGFloat> = 0.03...0.96, timeout: Double = 4) -> CGRect? {
        let h = app.frame.height
        var n = 0
        if !e.waitForExistence(timeout: timeout) {
            // LazyVStack の中は、画面に近づくまで作られない
            while frameOf(e) == nil && n < 10 { nudge(up: true); n += 1 }
        }
        n = 0
        while n < 16 {
            guard let f = frameOf(e) else { nudge(up: true); n += 1; continue }
            let y = f.midY / h
            if band.contains(y) { return f }
            nudge(up: y > band.upperBound); n += 1
        }
        // 帯からわずかに外れても、画面の中に見えていれば押してよい(スワイプが行き過ぎて往復するのを防ぐ)
        if let f = frameOf(e), f.midY / h > band.lowerBound - 0.04, f.midY / h < 0.975 { return f }
        return nil
    }

    @discardableResult
    private func tap(_ e: XCUIElement, _ label: String, timeout: Double = 5, band: ClosedRange<CGFloat> = 0.03...0.96, pause: UInt32 = 0) -> Bool {
        guard reveal(e, band: band, timeout: timeout) != nil else { mark("MISSING \(label)"); dump(label); shot("missing_\(label)"); return false }
        usleep(300_000)
        guard let f = frameOf(e) else { mark("MISSING \(label) (moved)"); return false }
        let a = app.frame
        mark(String(format: "tap %@ @%.4f,%.4f", label, f.midX / a.width, f.midY / a.height))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        if pause > 0 { sleep(pause) }
        return true
    }

    /// リストの一番下まで送る(テストプレイ・投稿ボタンは最後にある)。ボタンの位置が2回続けて動かなければ、止まった(=一番下)とみなす。
    /// 毎回、目印(画面上の部品)が動いたかを測り、動かなければ指を置く場所を変える(左端 → 右端 → 中央)
    @discardableResult
    private func scrollToBottom(until e: XCUIElement) -> CGRect? {
        let xs: [CGFloat] = [0.025, 0.975, 0.5]
        var k = 0
        var last: CGRect?
        for i in 0..<18 {
            let probe = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "発射台")).firstMatch
            let before = frameOf(probe)?.minY
            dragX = xs[k]
            drag(up: true, fast: true)
            usleep(900_000)
            let after = frameOf(probe)?.minY
            if let b = before, let a = after, abs(a - b) < 1, frameOf(e) == nil {
                mark("scroll did not move at x=\(xs[k]) (step \(i))")
                k = (k + 1) % xs.count
            }
            if let f = frameOf(e) {
                if let l = last, abs(l.minY - f.minY) < 2 { mark("bottom reached with x=\(xs[k])"); return f }
                last = f
            }
        }
        return frameOf(e)
    }

    /// 位置が分かっている部品を、その場で押す(スクロールしない)
    @discardableResult
    private func tapHere(_ e: XCUIElement, _ label: String, pause: UInt32 = 0) -> Bool {
        guard let f = frameOf(e), f.midY < app.frame.height * 0.985 else { mark("MISSING \(label)"); shot("missing_\(label)"); return false }
        mark(String(format: "tap %@ @%.4f,%.4f", label, f.midX / app.frame.width, f.midY / app.frame.height))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
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
        tap(btn("emitter.color.0.1"), "color0", band: 0.38...0.96, pause: 2)
        tap(btn("emitter.pattern.toggle.0"), "patternToggle0", band: 0.38...0.96, pause: 1)
        shot("03_pattern_tiles")
        tap(btn("emitter.pattern.0.swirl"), "pattern0.swirl", band: 0.38...0.96, pause: 2)
        tap(btn("editor.add"), "add1", band: 0.38...0.96, pause: 3)
        shot("04_editor_two")

        // テストプレイ(自動操縦で本当によける。無敵ではない)。ボタンは一番下
        let test = btn("editor.test")
        var tf = scrollToBottom(until: test)
        if tf == nil || tf!.midY > app.frame.height * 0.97 {
            // 保険: アプリ側の見えないボタンで、一番下まで送る(指の操作に頼らない)
            mark("fallback scrollBottom")
            let sb = btn("ad.scrollBottom")
            if let f = frameOf(sb) { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap() }
            sleep(2)
            tf = frameOf(test)
        }
        mark("bottom \(tf.map { String(format: "%.3f", $0.midY / app.frame.height) } ?? "none")")
        sleep(2); shot("05_editor_bottom")
        var cleared = false
        for attempt in 0..<3 {
            if attempt == 0 { tapHere(test, "test") } else { tap(btn("result.retry"), "retry\(attempt)") }
            mark("testplay.start")
            // プレイ中は問い合わせない(画面の問い合わせが重く、その間の描画が収録から落ちる)。ステージは20秒+準備1.2秒
            sleep(23)
            let headline = app.staticTexts["result.headline"]
            _ = headline.waitForExistence(timeout: 20)
            let label = headline.exists ? headline.label : "none"
            mark("testplay.result \(label)")
            shot("07_result_\(attempt)")
            sleep(2)
            if headline.exists && !label.contains("被弾") && !label.contains("時間切れ") { cleared = true; break }
        }
        mark("cleared \(cleared)")
        tap(btn("result.back"), "back", pause: 3)
        shot("08_editor_verified")

        // 投稿(ボタンはテストプレイの隣。戻ってもスクロール位置はそのまま)
        let post = btn("editor.post")
        if frameOf(post) == nil {
            let sb = btn("ad.scrollBottom")
            if let f = frameOf(sb) { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap(); sleep(2) }
            if frameOf(post) == nil { scrollToBottom(until: post) }
        }
        tapHere(post, "post", pause: 3)
        mark("publish"); shot("09_publish")
        let accept = btn("publish.terms.accept")
        if accept.waitForExistence(timeout: 4) { tapHere(accept, "terms", pause: 3) }
        shot("10_publish_ready")
        let submit = btn("publish.submit")
        _ = submit.waitForExistence(timeout: 10)
        tapHere(submit, "submit")
        let done = btn("publish.done.close")
        _ = done.waitForExistence(timeout: 40)
        mark("published \(done.exists)")
        sleep(1); shot("11_published")
        sleep(4)
        tapHere(done, "doneClose", pause: 2)
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

        mark("end")
        dump("end")
    }
}
