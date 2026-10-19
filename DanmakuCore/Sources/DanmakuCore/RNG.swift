/// 決定的乱数（mulberry32）。試作の `mulberry` と同じ計算
public struct Mulberry32 {
    private var a: UInt32

    public init(seed: UInt32) { a = seed }

    public mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// FNV-1a（32bit）
struct FNV1a {
    private(set) var value: UInt32 = 2_166_136_261

    mutating func add(_ byte: UInt8) {
        value ^= UInt32(byte)
        value = value &* 16_777_619
    }

    mutating func add(_ n: Int32) {
        let u = UInt32(bitPattern: n)
        for shift in stride(from: 0, to: 32, by: 8) { add(UInt8((u >> UInt32(shift)) & 0xFF)) }
    }
}

extension Stage {
    /// ステージ内容（丸めた数値列）から作る乱数シード。JSON 文字列の並び順などには依存しない
    public var seed: UInt32 {
        var h = FNV1a()
        h.add(Int32(mode == .boss ? 1 : (mode == .damage ? 2 : (mode == .sequence ? 3 : 0))))
        h.add(Int32(bossHp ?? 0))
        h.add(Int32(bossMove ?? 0))
        h.add(Int32(durationSec))
        Stage.hashEmitters(emitters, into: &h)
        if mode == .sequence {
            // 連戦は、場面ごとに(種類・時間・HP・動き・発射台)を、順番に混ぜる
            for w in waves ?? [] {
                h.add(Int32(w.kind == .boss ? 1 : 0))
                h.add(Int32(w.durationSec))
                h.add(Int32(w.bossHp ?? 0))
                h.add(Int32(w.bossMove ?? 0))
                Stage.hashEmitters(w.emitters, into: &h)
            }
        }
        return h.value
    }

    static func hashEmitters(_ list: [Emitter], into h: inout FNV1a) {
        for m in list {
            h.add(m.t.index)
            for q in [m.x, m.y, m.s, m.e, m.i, m.v] { h.add(Int32((q * 100).rounded())) }
            h.add(Int32(m.c)); h.add(Int32(m.r.rounded())); h.add(Int32(m.k)); h.add(Int32(m.ph))
            if m.p != 0 { h.add(Int32(m.p)) }   // 標準(0)のときは混ぜない: これまでのステージの乱数シードを変えないため
        }
    }
}
