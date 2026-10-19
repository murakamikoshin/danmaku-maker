import AVFoundation
import Foundation

/// BGM と効果音。マナーモード中は鳴らさず(.ambient)、他のアプリの音とも邪魔しない。設定でオン・オフできる
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    enum Track: String {
        case menu = "bgm_menu", stage = "bgm_stage", boss = "bgm_boss", bright = "bgm_bright", mystery = "bgm_mystery"
        /// ステージの BGM 番号(0=ビビッド 1=ダーク 2=ゆったり 3=キラキラ 4=ミステリアス)の曲
        static func forNumber(_ n: Int) -> Track { [Track.stage, .boss, .menu, .bright, .mystery][min(max(n, 0), 4)] }
    }
    enum Effect: String, CaseIterable { case tap = "se_tap", hit = "se_hit", clear = "se_clear", fail = "se_fail", get = "se_get", lifeLost = "se_life", warning = "se_warning", boom = "se_boom", sparkle = "se_sparkle" }

    @Published var bgmOn: Bool { didSet { UserDefaults.standard.set(bgmOn, forKey: "audio.bgm"); if bgmOn { resume() } else { fadeOut() } } }
    @Published var seOn: Bool { didSet { UserDefaults.standard.set(seOn, forKey: "audio.se") } }

    private var player: AVAudioPlayer?
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

    /// BGM を切り替える(同じ曲なら、そのまま)
    func play(_ track: Track) {
        guard track != current || player?.isPlaying != true else { return }
        current = track
        guard bgmOn, let u = url(track.rawValue), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        let old = player
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        p.setVolume(bgmVolume, fadeDuration: 0.8)
        old?.setVolume(0, fadeDuration: 0.6)
        player = p
        if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { old.stop() } }
    }

    /// 試聴(BGM の設定がオフでも、選んだ曲を聴けるようにする)
    func preview(_ track: Track) {
        current = track
        guard let u = url(track.rawValue), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        let old = player
        p.numberOfLoops = -1
        p.volume = bgmVolume
        p.prepareToPlay(); p.play()
        old?.stop()
        player = p
    }

    func stopBGM() { current = nil; fadeOut() }

    /// アプリが裏に回ったときに止め、戻ったら続きから鳴らす
    func pause() { player?.pause() }
    func resumeIfNeeded() { if bgmOn, let p = player, !p.isPlaying { p.play() } else if bgmOn, player == nil { resume() } }

    private func fadeOut() {
        guard let p = player else { return }
        p.setVolume(0, fadeDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { p.stop() }
        player = nil
    }

    private func resume() { if let c = current { current = nil; play(c) } }

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
