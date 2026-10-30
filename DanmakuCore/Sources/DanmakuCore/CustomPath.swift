import Foundation

/// 弾幕作成モードで描いた軌道。発射位置を原点にした (x, y) を、step 秒ごとに並べた [x0, y0, x1, y1, ...]。
/// 線を描く速さは、点と点の間隔になる(速く描いた所は間隔が広く、弾も速く進む)
public enum PathData {
    /// 点と点の時間の間隔(秒)
    public static let step = 0.1
    /// 点の数の範囲(最長 6 秒)
    public static let pointRange = 2...60
    /// 座標の範囲(±論理px)。画面(360×540)を十分にまたげる大きさ
    public static let limit = 600.0

    /// 0.1 刻みの丸め。0.5 のときは 0 から遠いほうへ(サーバーと同じ規則)
    static func round1(_ v: Double) -> Double { (abs(v) * 10).rounded(.toNearestOrAwayFromZero) / 10 * (v < 0 ? -1 : 1) }

    /// 安全な軌道に整える。形が不正(奇数個・点が少なすぎる/多すぎる・数でない)なら nil。範囲外は範囲内に収め、0.1 刻みに丸める。
    /// サーバーの検証は、収めずに拒否する(アプリは必ず先にこれで整えてから送る)
    public static func sanitized(_ path: [Double]?) -> [Double]? {
        guard let p = path, p.count % 2 == 0, pointRange.contains(p.count / 2), p.allSatisfy(\.isFinite) else { return nil }
        return p.map { round1(min(limit, max(-limit, $0))) }
    }

    /// 時刻 time(秒)の位置。最後の点を過ぎたら、最後の速さのまま進み続ける
    public static func position(_ p: [Double], at time: Double) -> (x: Double, y: Double) {
        let n = p.count / 2
        guard n >= 1 else { return (0, 0) }
        if n == 1 || time <= 0 { return (p[0], p[1]) }
        let f = time / step
        if f >= Double(n - 1) {
            let extra = time - Double(n - 1) * step
            let vx = (p[2 * n - 2] - p[2 * n - 4]) / step, vy = (p[2 * n - 1] - p[2 * n - 3]) / step
            return (p[2 * n - 2] + vx * extra, p[2 * n - 1] + vy * extra)
        }
        let i = Int(f)
        let u = f - Double(i)
        return (p[2 * i] + (p[2 * i + 2] - p[2 * i]) * u, p[2 * i + 1] + (p[2 * i + 3] - p[2 * i + 1]) * u)
    }
}

/// 弾が従う軌道(弾ごとに持たない、共有する入れ物)
public final class PathRef: Equatable, @unchecked Sendable {
    public let points: [Double]
    public init(_ points: [Double]) { self.points = points }
    public static func == (a: PathRef, b: PathRef) -> Bool { a === b }
}

/// 軌道に沿って進む弾の設定: 軌道・発射位置・回した向き(cos, sin)・時間の速さの倍率
public struct PathFollow: Equatable, Sendable {
    public var ref: PathRef
    public var ox: Double, oy: Double
    public var cosR: Double, sinR: Double
    public var scale: Double
    public init(ref: PathRef, ox: Double, oy: Double, cosR: Double, sinR: Double, scale: Double) {
        self.ref = ref; self.ox = ox; self.oy = oy; self.cosR = cosR; self.sinR = sinR; self.scale = scale
    }
}
