import AVFoundation
import Foundation

/// スワイプ弾幕の音（仕様書 6.4 章）。試作と同じく、矩形波・三角波・のこぎり波・ノイズをその場で作って鳴らす。
/// かすりの音の高さがコンボで変わるので、録音した効果音ではなく合成する。音量全体は 0.7。設定の効果音オフに従う
@MainActor
final class SwipeAudio {
    static let shared = SwipeAudio()
    enum Wave { case square, triangle, saw }

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    private var lastGraze = 0.0, lastCoin = 0.0

    private func start() {
        guard !started else { return }
        started = true
        for _ in 0..<10 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            nodes.append(n)
        }
        engine.mainMixerNode.outputVolume = 0.7
        do { try engine.start() } catch { started = false }
    }

    func stop() { engine.pause(); started = false }

    private func play(_ buffer: AVAudioPCMBuffer, after delay: Double) {
        guard AudioManager.shared.seOn else { return }
        start()
        guard started else { return }
        let node = nodes[next % nodes.count]; next += 1
        if !engine.isRunning { try? engine.start() }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if delay <= 0 { node.play() } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if self.engine.isRunning { node.play() } }
            // 遅らせて鳴らす音は、再生を始めるまでノードを使い回さない
        }
    }

    private func tone(_ f0: Double, _ f1: Double? = nil, dur: Double, vol: Double, wave: Wave, delay: Double = 0) {
        let key = "t\(Int(f0))-\(Int(f1 ?? f0))-\(Int(dur * 1000))-\(wave)-\(Int(vol * 1000))"
        let buf: AVAudioPCMBuffer
        if let c = cache[key] { buf = c } else {
            let n = Int(dur * 22050)
            buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            let d = buf.floatChannelData![0]
            var phase = 0.0
            for i in 0..<n {
                let p = Double(i) / Double(n)
                let f = f0 + ((f1 ?? f0) - f0) * p
                phase += f / 22050
                let x = phase - floor(phase)
                var s: Double
                switch wave {
                case .square: s = x < 0.5 ? 1 : -1
                case .triangle: s = 4 * abs(x - 0.5) - 1
                case .saw: s = 2 * x - 1
                }
                d[i] = Float(s * vol * pow(1 - p, 1.5))
            }
            cache[key] = buf
        }
        play(buf, after: delay)
    }

    private func noise(dur: Double, vol: Double, from: Double, to: Double) {
        let key = "n\(Int(dur * 1000))-\(Int(from))-\(Int(to))-\(Int(vol * 1000))"
        let buf: AVAudioPCMBuffer
        if let c = cache[key] { buf = c } else {
            let n = Int(dur * 22050)
            buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            let d = buf.floatChannelData![0]
            var lp = 0.0
            var seed: UInt32 = 12345
            for i in 0..<n {
                let p = Double(i) / Double(n)
                seed = seed &* 1664525 &+ 1013904223
                let r = Double(seed >> 8) / Double(1 << 24) * 2 - 1
                let cutoff = from + (to - from) * p
                let a = min(1, 2 * .pi * cutoff / 22050)
                lp += a * (r - lp)
                d[i] = Float(lp * vol * 2 * pow(1 - p, 1.5))
            }
            cache[key] = buf
        }
        play(buf, after: 0)
    }

    // MARK: できごと

    func graze(combo: Int, now: Double) {
        guard now - lastGraze > 0.028 else { return }
        lastGraze = now
        tone(520 * pow(2, Double(min(combo, 36)) / 14), dur: 0.05, vol: 0.035, wave: .square)
    }
    func multiplier(level: Int) {
        let k = 1 + Double(level - 2) * 0.06
        tone(523 * k, dur: 0.12, vol: 0.12, wave: .triangle)
        tone(659 * k, dur: 0.12, vol: 0.12, wave: .triangle, delay: 0.04)
        tone(784 * k, dur: 0.14, vol: 0.12, wave: .triangle, delay: 0.08)
    }
    func bomb() { noise(dur: 0.7, vol: 0.35, from: 4000, to: 120); tone(110, 40, dur: 0.6, vol: 0.2, wave: .saw) }
    func coin(n: Int, now: Double) {
        guard now - lastCoin > 0.022 else { return }
        lastCoin = now
        tone(1046 * pow(2, Double(n % 24) / 12), dur: 0.05, vol: 0.05, wave: .triangle)
    }
    func go() { tone(880, 1320, dur: 0.12, vol: 0.1, wave: .square) }
    func clear() {
        for (i, f) in [523.0, 659, 784, 1047].enumerated() { tone(f, dur: 0.1, vol: 0.12, wave: .square, delay: Double(i) * 0.07) }
        tone(1568, dur: 0.3, vol: 0.1, wave: .square, delay: 0.3)
    }
    func record() { tone(1319, dur: 0.12, vol: 0.1, wave: .square); tone(1760, dur: 0.2, vol: 0.1, wave: .square, delay: 0.12) }
    func fail() { noise(dur: 0.5, vol: 0.3, from: 1800, to: 80); tone(220, 55, dur: 0.5, vol: 0.2, wave: .saw) }
    func whoosh() { noise(dur: 0.18, vol: 0.12, from: 900, to: 3000) }
    func tick(high: Bool) { tone(high ? 1320 : 880, dur: 0.07, vol: 0.08, wave: .square) }
}
