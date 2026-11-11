import XCTest

/// 導線のテスト: ロボットが実際に画面を押して、主な機能まで辿れるかを確かめる。
/// 1 画面進むごとにスクリーンショットを撮り、結果(xcresult)に残す(CI が画像にして保存する)。
/// 課金と投稿は「手前」で止める(購入ボタン・投稿ボタンは押さない)。
/// テーマは環境変数 UI_THEME(classic / arcade / gensou。CI は TEST_RUNNER_UI_THEME で渡す)、
/// サーバーは環境変数 UI_BACKEND=emulator のときだけエミュレーターにつなぐ(本番には書き込まない。偽の設定で起動する)。
final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var theme: String { ProcessInfo.processInfo.environment["UI_THEME"] ?? "classic" }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-uitest-invincible", "-no-ads", "-no-audio", "-no-debug-overlay", "-swipe-on",
                    "-ui-theme", theme, "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if ProcessInfo.processInfo.environment["UI_BACKEND"] == "emulator" { args.append("-use-emulator") }
        if let size = ProcessInfo.processInfo.environment["UI_TEXT_SIZE"] { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments += args
        // 通知の許可などのシステムのダイアログは、閉じて進む
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["許可しない", "Don’t Allow", "Don't Allow", "Appに追跡しないように要求", "Ask App Not to Track", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()
        dismissRewardNotice()
    }

    // MARK: - 部品

    /// その時点の画面を、名前つきで残す
    private func snap(_ name: String) {
        step += 1
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = String(format: "%@_%@_%02d_%@", theme, name.components(separatedBy: "_").first ?? name, step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// ID の要素を待ってから押す。見つからなければ、どこで止まったかが分かるように撮ってから失敗させる
    @discardableResult
    private func tap(_ id: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = app.descendants(matching: .any)[id].firstMatch
        if !e.waitForExistence(timeout: timeout) {
            snap("missing-\(id)")
            XCTFail("「\(id)」が見つからない(画面から辿れない)", file: file, line: line)
            return e
        }
        if !e.isHittable { scrollTo(e) }
        e.tap()
        return e
    }

    private func exists(_ id: String, timeout: TimeInterval = 8) -> Bool {
        app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: timeout)
    }

    private func scrollTo(_ e: XCUIElement) {
        for _ in 0..<12 where !e.isHittable { app.swipeUp(velocity: .slow) }
    }

    /// 起動直後に「ごほうびが届いた」が出たら閉じる
    private func dismissRewardNotice() {
        let ok = app.buttons["reward.notice.ok"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
    }

    private func closeSheet(_ id: String? = nil) {
        if let id, exists(id, timeout: 3) { tap(id); return }
        app.swipeDown(velocity: .fast)   // シートは下へ引いて閉じる
    }

    // MARK: - 導線

    /// 下の 4 つのタブと、ホームの 3 つの一覧・世界のステージの絞り込み
    func testTabsAndHome() {
        XCTAssertTrue(exists("tab.play", timeout: 20), "下のタブが出ない")
        snap("home")
        for t in ["swipe", "shop", "settings", "play"] { tap("tab.\(t)"); snap("tab-\(t)") }
        tap("home.tab.mine"); snap("home-mine")
        tap("home.tab.world"); snap("home-world")
        tap("home.filter.toggle")
        // チップの名札は「home.mode.<値>」(値が Optional のときは Optional(...) の形になる)ので、前と中身で探す
        let bossChip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.mode.' AND identifier CONTAINS 'boss'")).firstMatch
        XCTAssertTrue(bossChip.waitForExistence(timeout: 8), "絞り込みを開いても、クリア条件が出ない")
        let diffChips = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.diff.'"))
        XCTAssertGreaterThan(diffChips.count, 1, "絞り込みを開いても、難しさが出ない")
        snap("home-filter-open")
        bossChip.tap(); snap("home-filter-boss")
        tap("home.filter.toggle")
        XCTAssertFalse(bossChip.waitForExistence(timeout: 2), "畳んでも、絞り込みが消えない")
        snap("home-filter-closed")
        tap("home.tab.samples")
    }

    /// サンプルを遊んで、結果画面から戻る
    func testPlaySampleAndBack() {
        tap("home.sample.o01", timeout: 20)
        XCTAssertTrue(exists("play.quit", timeout: 15), "ステージが始まらない")
        snap("play")
        XCTAssertTrue(exists("result.headline", timeout: 60), "結果画面が出ない(無敵なのでクリアするはず)")
        snap("play-result")
        tap("result.back")
        XCTAssertTrue(exists("home.sample.o01", timeout: 10), "結果画面から一覧へ戻れない")
    }

    /// ショップの 5 つのタブ・ボスのカード(金魚姫まで)
    func testShop() {
        tap("tab.shop", timeout: 20)
        for t in ["deals", "patterns", "shots", "looks", "bosses"] { tap("shop.tab.\(t)"); snap("shop-\(t)") }
        let hire = app.descendants(matching: .any)["shop.boss.hire"].firstMatch
        XCTAssertTrue(hire.waitForExistence(timeout: 10), "金魚姫のカードがない")
        scrollTo(hire)
        snap("shop-bosses-hire")
        tap("shop.removeads", timeout: 3)   // おトクのタブに戻らなくても、広告削除の入り口は上にある
        snap("shop-removeads")
        closeSheet()
    }

    /// エディタ: ボス戦にして、金魚姫を選び、大きさを変え、テストプレイして戻る(投稿は押さない)
    func testEditorBossFlow() {
        tap("home.create", timeout: 20)
        if exists("editor.namePrompt.go", timeout: 3) { tap("editor.namePrompt.go") }
        XCTAssertTrue(exists("editor.close"), "エディタが開かない")
        snap("editor")
        tap("editor.mode.boss"); snap("editor-boss")
        tap("editor.level.true"); snap("editor-advanced")
        // 図形のボスのうちは、大きさのスライダーがある
        let size = app.descendants(matching: .any)["editor.boss.size"].firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 5), "ボスの大きさのスライダーがない")
        scrollTo(size)
        snap("editor-size")
        // キャラクターのボス(金魚姫)を選ぶ。キャラクターは大きさが決まっているので、スライダーは消える
        let hireLook = app.descendants(matching: .any)["editor.boss.look.12"].firstMatch
        if hireLook.waitForExistence(timeout: 5) { scrollTo(hireLook); hireLook.tap(); snap("editor-hire") }
        else { snap("editor-no-hire"); XCTFail("ボスの見た目に金魚姫がない") }
        tap("editor.test")
        XCTAssertTrue(exists("play.quit", timeout: 15), "テストプレイが始まらない")
        snap("editor-testplay")
        tap("play.quit")
        XCTAssertTrue(exists("editor.close", timeout: 10), "テストプレイからエディタへ戻れない")
        XCTAssertTrue(exists("editor.post"), "投稿ボタンがない")
        snap("editor-back")
        tap("editor.close")
        XCTAssertTrue(exists("tab.play", timeout: 10), "エディタを閉じてホームへ戻れない")
    }

    /// スワイプ弾幕: タイトル・スタミナ・ランキング・称号
    func testSwipe() {
        tap("tab.swipe", timeout: 20)
        XCTAssertTrue(exists("swipe.start"), "スタートがない")
        snap("swipe")
        tap("swipe.stamina"); snap("swipe-stamina"); closeSheet()
        tap("swipe.ranking"); snap("swipe-ranking")
        if exists("swipe.titles", timeout: 8) { tap("swipe.titles"); snap("swipe-titles"); closeSheet("titles.close") }
        closeSheet()
    }

    /// せってい: 名前・招待・問い合わせ・広告削除・テーマの切り替え
    func testSettings() {
        tap("tab.settings", timeout: 20)
        snap("settings")
        tap("settings.handle"); snap("settings-handle"); closeSheet()
        tap("settings.invite"); snap("settings-invite"); closeSheet("invite.close")
        tap("settings.feedback"); snap("settings-feedback"); closeSheet("feedback.close")
        tap("settings.removeads"); snap("settings-removeads"); closeSheet()
        // テーマを順に切り替える。切り替えると画面が作り直され、せっていのタブに戻ってくる
        for t in ["arcade", "gensou", "classic"] {
            tap("settings.theme.\(t)")
            XCTAssertTrue(exists("settings.theme.\(t)", timeout: 10), "テーマを変えたあと、せっていに戻らない")
            snap("settings-theme-\(t)")
        }
    }
}
