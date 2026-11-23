import XCTest

/// 1.4.2 で足したものを、ロボットが実際に画面を押して確かめる(弾幕パック3・弾の形「棒」・左右からの高さ・段階なし/2段階・
/// 発射台のコピー/貼り付け/初期値に戻す・連戦のエディタ・竜王の見本・ショップのパック3・テーマ名)。
/// 1 画面進むごとにスクリーンショットを撮る(CI が画像にして保存する。崩れは画像で見る)。
/// 課金は `-unlock-all` で全部使える状態にする(購入ボタンは押さない)。投稿もしない。
final class Release142UITests: XCTestCase {
    private var app: XCUIApplication!
    private var lang: String { ProcessInfo.processInfo.environment["UI_LANG"] ?? "ja" }
    private var step = 0
    private let pack3 = ["radialLaser", "lightning", "carpetBomb", "dashShot", "implode", "pincer", "whirlwind", "bounceBall", "needle", "trackLaser", "blinkShot"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-uitest-invincible", "-no-ads", "-no-audio", "-no-debug-overlay", "-no-update-check", "-unlock-all",
                    "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "ja" ? "ja_JP" : lang]
        if ProcessInfo.processInfo.environment["UI_BACKEND"] == "emulator" { args.append("-use-emulator") }
        if let size = ProcessInfo.processInfo.environment["UI_TEXT_SIZE"] { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments += args
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["許可しない", "Don’t Allow", "Don't Allow", "Appに追跡しないように要求", "Ask App Not to Track", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()
        let ok = app.buttons["reward.notice.ok"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
    }

    // MARK: - 部品(FlowUITests と同じ)

    private func snap(_ name: String) {
        step += 1
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = String(format: "%@_%02d_%@", lang, step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    private func tap(_ id: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = el(id)
        if !e.waitForExistence(timeout: timeout) {
            snap("missing-\(id)")
            XCTFail("「\(id)」が見つからない", file: file, line: line)
            return e
        }
        if !e.isHittable { scrollTo(e) }
        e.tap()
        return e
    }

    private func exists(_ id: String, timeout: TimeInterval = 8) -> Bool { el(id).waitForExistence(timeout: timeout) }

    private func scrollTo(_ e: XCUIElement, up: Bool = true) {
        for _ in 0..<15 where !e.isHittable { up ? app.swipeUp(velocity: .slow) : app.swipeDown(velocity: .slow) }
    }

    /// 下へ送りながら探す(エディタは、画面の近くのカードだけを作る)
    private func find(_ id: String) -> XCUIElement {
        let e = el(id)
        for _ in 0..<15 where !e.exists { app.swipeUp(velocity: .slow) }
        if e.exists { scrollTo(e) }
        return e
    }

    private func openEditor() {
        tap("home.create", timeout: 20)
        if exists("editor.namePrompt.go", timeout: 3) { tap("editor.namePrompt.go") }
        XCTAssertTrue(exists("editor.close"), "エディタが開かない")
    }

    /// 発射台 index のパターンを選ぶ(一覧を開いて、そのパターンのタイルを押す)
    private func choosePattern(_ raw: String, index: Int = 0) {
        let toggle = find("emitter.pattern.toggle.\(index)")
        XCTAssertTrue(toggle.exists, "パターンの一覧を開くボタンがない")
        toggle.tap()
        let tile = find("emitter.pattern.\(index).\(raw)")
        XCTAssertTrue(tile.exists, "パターン \(raw) のタイルがない")
        tile.tap()
    }

    /// テストプレイを数秒流して、撮ってから戻る(落ちない・止まらないことを確かめる)
    private func testPlay(_ name: String, seconds: UInt32 = 4) {
        let test = find("editor.test")
        XCTAssertTrue(test.exists, "テストプレイのボタンがない")
        test.tap()
        XCTAssertTrue(exists("play.quit", timeout: 20), "\(name): テストプレイが始まらない")
        sleep(seconds)
        snap("play-\(name)")
        sleep(2)
        snap("play-\(name)-later")
        if el("play.quit").exists { el("play.quit").tap() } else if el("result.back").exists { el("result.back").tap() }
        XCTAssertTrue(exists("editor.close", timeout: 15), "\(name): テストプレイからエディタへ戻れない(落ちた?)")
    }

    private func scrollToTop() { for _ in 0..<15 { app.swipeDown(velocity: .fast) } }

    // MARK: - テスト

    /// 弾幕パック3の 11 種類: 一覧に出る・選べる・エディタの見本・テストプレイ(生き残り)
    func testPack3PatternsInSurvive() {
        openEditor()
        tap("editor.level.true")
        let toggle = find("emitter.pattern.toggle.0")
        toggle.tap()
        let first = find("emitter.pattern.0.radialLaser")
        XCTAssertTrue(first.exists, "パック3の欄がない")
        snap("pattern-list-pack3")
        first.tap()
        for raw in pack3 {
            if raw != "radialLaser" { scrollToTop(); choosePattern(raw) }
            scrollToTop()
            snap("card-\(raw)")
            testPlay("survive-\(raw)")
        }
    }

    /// 弾幕パック3を、ボス戦(ボスから撃つ・好きな場所から撃つ)で
    func testPack3PatternsInBoss() {
        openEditor()
        tap("editor.mode.boss")
        tap("editor.level.true")
        for raw in pack3 {
            scrollToTop()
            choosePattern(raw)
            testPlay("boss-\(raw)", seconds: 3)
        }
        // 好きな場所から撃つ
        let point = find("emitter.origin.0.1")
        if point.exists { point.tap(); snap("boss-from-point") }
        testPlay("boss-from-point-blinkShot", seconds: 3)
    }

    /// 弾の形「棒」・左から/右からの高さ・発射台のコピー/貼り付け・初期値に戻す
    func testEditorNewControls() {
        openEditor()
        // かんたんでも、弾の形を選べる
        let bar = find("emitter.shape.0.3")
        XCTAssertTrue(bar.exists, "「かんたん」で弾の形が選べない")
        bar.tap()
        snap("shape-bar-simple")
        testPlay("shape-bar")
        // 左からの高さ
        scrollToTop()
        choosePattern("sideL")
        let full = find("emitter.height.0.1")
        XCTAssertTrue(full.exists, "左からの高さの選択がない")
        full.tap(); snap("height-full")
        testPlay("sideL-full")
        scrollToTop()
        let lower = find("emitter.height.0.2")
        lower.tap(); snap("height-lower")
        testPlay("sideL-lower")
        // 右からにしても高さの選択が出る。ほかのパターンでは出ない
        scrollToTop(); choosePattern("sideR")
        XCTAssertTrue(find("emitter.height.0.0").exists, "右からで高さの選択が出ない")
        scrollToTop(); choosePattern("ring")
        XCTAssertFalse(el("emitter.height.0.0").exists, "放射なのに高さの選択が出ている")

        // コピー → 貼り付け
        scrollToTop()
        let menu = find("emitter.menu.0")
        XCTAssertTrue(menu.exists, "発射台のメニューがない")
        menu.tap()
        snap("emitter-menu")
        app.buttons["コピー"].firstMatch.tap()
        let paste = find("editor.paste")
        XCTAssertTrue(paste.exists, "コピーしたのに貼り付けボタンが出ない")
        snap("paste-button")
        paste.tap()
        XCTAssertTrue(find("emitter.card.1").exists, "貼り付けても、2つ目の発射台ができない")
        snap("pasted")

        // 初期値に戻す(まとめて): 棒の形が標準に戻る
        scrollToTop()
        find("emitter.menu.0").tap()
        app.buttons["初期値に戻す"].firstMatch.tap()
        XCTAssertTrue(exists("dialog.action", timeout: 5), "初期値に戻すの確認が出ない")
        snap("reset-dialog")
        tap("dialog.action")
        XCTAssertTrue(find("emitter.shape.0.0").isSelected, "初期値に戻しても、弾の形が標準に戻らない")
        snap("after-reset")

        // 項目ごとの「戻す」: 向きを 1° 動かすと出て、押すと消える
        tap("editor.level.true")
        scrollToTop()
        let up = app.buttons.matching(NSPredicate(format: "label == '少し上げる'"))
        XCTAssertGreaterThan(up.count, 0, "− / + のボタンがない")
        let rotateUp = up.element(boundBy: min(1, up.count - 1))
        scrollTo(rotateUp)
        rotateUp.tap()
        let one = el("slider.reset")
        XCTAssertTrue(one.waitForExistence(timeout: 5), "値を変えても、項目ごとの「戻す」が出ない")
        snap("reset-one-visible")
        one.tap()
        snap("reset-one-done")
    }

    /// ボスの段階「なし」「2段階」(ボス戦・ダメージ勝負)
    func testBossPhasesNoneAndTwo() {
        openEditor()
        tap("editor.mode.boss")
        let none = find("editor.phases.1")
        XCTAssertTrue(none.exists, "段階の数に「なし」がない")
        none.tap()
        snap("phases-none")
        tap("editor.level.true")
        snap("phases-none-advanced")
        testPlay("boss-phases-none", seconds: 6)
        scrollToTop()
        find("editor.phases.2").tap()
        snap("phases-two")
        testPlay("boss-phases-two", seconds: 6)
        scrollToTop()
        tap("editor.mode.damage")
        find("editor.phases.1").tap()
        snap("damage-phases-none")
        testPlay("damage-phases-none", seconds: 4)
    }

    /// 連戦: 場面と発射台を増やして、下までスクロールする(崩れ・重さを画像で見る)。貼り付けも場面へ
    func testSequenceEditor() {
        openEditor()
        tap("editor.mode.sequence")
        tap("editor.level.true")
        for kind in ["boss", "survive", "boss", "boss"] {
            let add = find("editor.wave.add.\(kind)")
            if add.exists && add.isEnabled { add.tap() }
        }
        scrollToTop()
        // 最初の場面の発射台をコピーして、ほかの場面へ貼り付ける
        find("emitter.menu.0").tap()
        app.buttons["コピー"].firstMatch.tap()
        let pastes = app.descendants(matching: .any).matching(identifier: "editor.paste")
        XCTAssertGreaterThan(pastes.count, 0, "連戦で貼り付けボタンが出ない")
        var shots = 0
        for _ in 0..<14 {
            app.swipeUp(velocity: .default)
            if shots < 6 { snap("sequence-scroll-\(shots)"); shots += 1 }
        }
        let last = pastes.element(boundBy: max(0, pastes.count - 1))
        if last.exists { scrollTo(last); last.tap(); snap("sequence-pasted") }
        testPlay("sequence", seconds: 5)
    }

    /// 竜王の技の見本: 技を選び替えると、選んだ技の見本になる(画像で確かめる)
    func testDragonPreview() {
        openEditor()
        tap("editor.mode.boss")
        tap("editor.level.true")
        let dragon = find("editor.boss.look.13")
        XCTAssertTrue(dragon.exists, "ボスの見た目に竜王がない")
        dragon.tap()
        snap("dragon-selected")
        scrollToTop()
        for raw in ["dragonBreath", "dragonRaid", "dragonGale", "dragonWings"] {
            scrollToTop()
            choosePattern(raw)
            scrollToTop()
            sleep(3)
            snap("dragon-preview-\(raw)")
        }
    }

    /// ショップの弾幕パック3と、設定のテーマ名(ファンタジー)
    func testShopAndSettings() {
        tap("tab.shop", timeout: 20)
        tap("shop.tab.patterns")
        let title = app.staticTexts[lang == "ja" ? "弾幕パック3" : "Bullet patterns 3"].firstMatch
        for _ in 0..<20 where !title.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(title.exists, "ショップに弾幕パック3がない")
        scrollTo(title)
        snap("shop-pack3")
        app.swipeUp(velocity: .slow); snap("shop-pack3-items")
        app.swipeUp(velocity: .slow); snap("shop-pack3-items2")
        tap("tab.settings")
        let theme = find("settings.theme.gensou")
        XCTAssertTrue(theme.exists, "テーマの選択がない")
        snap("settings-theme")
        if lang == "ja" { XCTAssertTrue(app.staticTexts["ファンタジー"].exists, "テーマ名が「ファンタジー」になっていない") }
    }
}
