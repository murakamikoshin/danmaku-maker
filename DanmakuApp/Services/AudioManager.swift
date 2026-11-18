import AVFoundation
import Foundation

/// BGM と効果音。マナーモード中は鳴らさず(.ambient)、他のアプリの音とも邪魔しない。設定でオン・オフできる
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    enum Track: String {
        case menu = "bgm_menu", stage = "bgm_stage", boss = "bgm_boss", bright = "bgm_bright", mystery = "bgm_mystery", swipe = "bgm_swipe", battle = "bgm_battle"
        /// 竜王の曲(竜王を持っている人がステージに選べる。遊ぶ人は誰でも聴ける)。イントロを1回流してから、このループへ
        case ryuou = "bgm_ryuou_loop", ryuou2 = "bgm_ryuou2_loop"
        /// ステージの BGM 番号(0=ビビッド 1=ダーク 2=ゆったり 3=キラキラ 4=ミステリアス 5=竜王・烈火 6=竜王・終焉)の曲
        static func forNumber(_ n: Int) -> Track { [Track.stage, .boss, .menu, .bright, .mystery, .ryuou, .ryuou2][min(max(n, 0), 6)] }
        /// 最初に1回だけ流すイントロ(無い曲は nil)
        var intro: String? {
            switch self {
            case .ryuou: return "bgm_ryuou_intro"
            case .ryuou2: return "bgm_ryuou2_intro"
            default: return nil
            }
        }
    }
    enum Effect: String, CaseIterable {
        case tap = "se_tap", hit = "se_hit", clear = "se_clear", fail = "se_fail", get = "se_get", lifeLost = "se_life", warning = "se_warning", boom = "se_boom", sparkle = "se_sparkle", match = "se_match"
        /// 必殺技の名前を出すときの音(1.4.0。ステージを作る人が選ぶ)
        case specialIssen = "se_special_issen", specialTodoroki = "se_special_todoroki", specialKakusei = "se_special_kakusei", specialWa = "se_special_wa", specialMaga = "se_special_maga"

        /// 必殺技の効果音の番号(DanmakuCore の PhaseInfo.se)から、鳴らす音。0・範囲の外は鳴らさない
        static func special(_ n: Int) -> Effect? {
            switch n {
            case 1: return .specialIssen
            case 2: return .specialTodoroki
            case 3: return .specialKakusei
            case 4: return .specialWa
            case 5: return .specialMaga
            case 6: return .sparkle
            case 7: return .boom
            default: return nil
            }
        }
    }

    @Published var bgmOn: Bool { didSet { UserDefaults.standard.set(bgmOn, forKey: "audio.bgm"); if bgmOn { resume() } else { fadeOut() } } }
    @Published var seOn: Bool { didSet { UserDefaults.standard.set(seOn, forKey: "audio.se") } }

    /// いまの曲(ループ)。イントロのある曲では、イントロが終わる時刻に始まるよう予約してある
    private var player: AVAudioPlayer?
    /// イントロ(鳴っている間だけ)。止める・裏に回る・オフにする・ほかの曲に替えるときは、必ずいっしょに止める
    private var introPlayer: AVAudioPlayer?
    private var current: Track?
    private var effects: [Effect: AVAudioPlayer] = [:]
    private let bgmVolume: Float = 0.5

    init() {
        let d = UserDefaults.standard
        bgmOn = d.object(forKey: "audio.bgm") as? Bool ?? true
        seOn = d.object(forKey: "audio.se") as? Bool ?? true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #if DEBUG
        // 画面確認用の起動では、勝手に音を出さない
        if ProcessInfo.processInfo.arguments.contains("-no-audio") { bgmOn = false; seOn = false }
        #endif
    }

    private func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "caf") }

    /// 曲が鳴っている(イントロの最中も含む)
    private var sounding: Bool { player?.isPlaying == true || introPlayer?.isPlaying == true }

    /// BGM を切り替える(同じ曲なら、そのまま。リトライでも続きから)
    func play(_ track: Track) { play(track, withIntro: true) }

    private func play(_ track: Track, withIntro: Bool) {
        guard track != current || !sounding else { return }
        current = track
        guard bgmOn else { return }
        // 全画面広告の最中に曲が替わったら、いまの曲は止めておき、広告を閉じたときに新しい曲から鳴らす
        if adShowing { stopIntro(); player?.stop(); player = nil; return }
        start(track, withIntro: withIntro, fade: true)
    }

    /// 全画面広告が出ている(広告の音と重ねないよう、その間は BGM を止める)
    private var adShowing = false

    /// 全画面広告を出す直前に呼ぶ。BGM を一時停止する
    func adWillShow() {
        adShowing = true
        pause()
    }

    /// 全画面広告を閉じた(または出せなかった)ときに呼ぶ。止めていた BGM を続きから鳴らす
    func adDidClose() {
        guard adShowing else { return }
        adShowing = false
        resumeIfNeeded()
    }

    /// 試聴(BGM の設定がオフでも、選んだ曲を聴けるようにする)。イントロのある曲は、イントロから
    func preview(_ track: Track) {
        current = track
        start(track, withIntro: true, fade: false)
    }

    /// 曲を鳴らし始める。前の曲(とイントロ)は止める
    private func start(_ track: Track, withIntro: Bool, fade: Bool) {
        guard let u = url(track.rawValue), let loop = try? AVAudioPlayer(contentsOf: u) else { return }
        let old = player
        stopIntro()
        loop.numberOfLoops = -1
        loop.prepareToPlay()
        if withIntro, let name = track.intro, let iu = url(name), let intro = try? AVAudioPlayer(contentsOf: iu) {
            // イントロとループを同じ時計で予約するので、イントロの終わりとループの頭がずれない(重ねない・空けない・フェードしない)
            intro.volume = bgmVolume; loop.volume = bgmVolume
            intro.prepareToPlay()
            let at = intro.deviceCurrentTime + 0.1
            intro.play(atTime: at)
            loop.play(atTime: at + intro.duration)
            introPlayer = intro
        } else if fade {
            loop.volume = 0
            loop.play()
            loop.setVolume(bgmVolume, fadeDuration: 0.8)
        } else {
            loop.volume = bgmVolume
            loop.play()
        }
        player = loop
        if let old {
            if fade {
                old.setVolume(0, fadeDuration: 0.6)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { old.stop() }
            } else {
                old.stop()
            }
        }
    }

    private func stopIntro() {
        introPlayer?.stop()
        introPlayer = nil
    }

    func stopBGM() { current = nil; fadeOut() }

    /// アプリが裏に回ったときに止め、戻ったら続きから鳴らす。
    /// イントロの最中なら、イントロも予約したループも止める(戻ったらループから。裏にいた間に予約の時刻がずれるため)
    func pause() {
        if introPlayer?.isPlaying == true {
            stopIntro()
            player?.stop()
            player = nil
            return
        }
        player?.pause()
    }
    /// 広告の最中(広告をタップして裏に回り、戻ってきたときなど)は鳴らさない。広告を閉じたら adDidClose が鳴らす
    func resumeIfNeeded() {
        guard !adShowing else { return }
        if bgmOn, let p = player, !p.isPlaying { p.play() } else if bgmOn, player == nil { resume() }
    }

    private func fadeOut() {
        stopIntro()
        guard let p = player else { return }
        p.setVolume(0, fadeDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { p.stop() }
        player = nil
    }

    /// BGM をオンに戻した・裏から戻ったとき。イントロは飛ばして、ループから
    private func resume() { if let c = current { current = nil; play(c, withIntro: false) } }

    func se(_ e: Effect) {
        guard seOn else { return }
        if effects[e] == nil, let u = url(e.rawValue) {
            let p = try? AVAudioPlayer(contentsOf: u)
            p?.prepareToPlay()
            effects[e] = p
        }
        guard let p = effects[e] else { return }
        p.currentTime = 0
        p.volume = e == .tap ? 0.5 : 0.9
        p.play()
    }
}
