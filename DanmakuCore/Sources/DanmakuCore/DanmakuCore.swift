/// シミュレーション本体。UIKit / SpriteKit に依存しない（フェーズ2で実装）。
public enum DanmakuCore {
    public static let formatVersion = 1
    /// 論理画面のサイズ
    public static let width = 360.0
    public static let height = 540.0
    /// 固定ステップ（秒）
    public static let step = 1.0 / 120.0
}
