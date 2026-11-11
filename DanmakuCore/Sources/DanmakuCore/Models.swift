import Foundation

/// 論理画面・固定ステップなどの定数
public enum DanmakuConfig {
    public static let formatVersion = 1
    /// このアプリが遊べる内容のレベル(1=1.1.2 まで、2=1.2.0〜の新しいボス)。サーバーが、これより高いレベルのステージに needs を付けたら、遊ばせずにアップデートを案内する
    public static let contentLevel = 2
    public static let width = 360.0
    public static let height = 540.0
    /// 固定ステップ（秒）。描画フレームとは無関係に、必ずこの刻みで進める
    public static let step = 1.0 / 120.0
    public static let readySeconds = 1.2
    public static let maxBullets = 1600
    public static let maxEmitters = 8
    /// 追尾弾が曲がり続ける時間(秒)
    public static let homingSeconds = 2.5
    /// ボスの大きさ(0=小 1=中 2=大)ごとの、プレイヤーの弾が当たる半径(論理px)。見た目の大きさも同じ比率で変わる
    public static let bossRadii: [Double] = [17, 24, 34]
    /// ボスの大きさの指定(Stage.bossSize)。0〜2 は小・中・大(上の半径)。10〜44 は、半径そのもの(px)。スライダーで細かく決める
    public static let bossRadiusRange = 10...44
    /// 倒せる雑魚の体力(ふつうの撃ち方で、当て続けて約1秒)
    public static let mookHp = 20
    /// キャラクターのボスの大きさ(当たり判定の半径 px)。標準は 40(これまでの大きさ)。絵と技の出る場所も、同じ倍率で変わる
    public static let characterRadiusRange = 20...60
    public static let characterBaseRadius = 40.0
    /// 大きさの指定から、弾が当たる半径(論理px)を出す。範囲外は中
    public static func bossRadius(size: Int) -> Double {
        if bossRadiusRange.contains(size) { return Double(size) }
        return bossRadii[min(max(size, 0), 2)]
    }
    /// 半径(px)から、保存する大きさの指定にする。小・中・大と同じ半径は、これまでの 0・1・2 に戻す(古いアプリでも遊べる)
    public static func bossSize(forRadius px: Int) -> Int {
        let r = min(bossRadiusRange.upperBound, max(bossRadiusRange.lowerBound, px))
        if let i = bossRadii.firstIndex(of: Double(r)) { return i }
        return r
    }
    /// ボス・雑魚の見た目の種類の数(0 は標準)。見た目だけで、計算には関わらない
    public static let enemyLooks = 5
    /// ボスの見た目の番号の数(0〜4 が図形、5 以降が BossCharacter)。雑魚の見た目は enemyLooks のまま
    public static var bossLooks: Int { BossCharacter.maxLook + 1 }
    /// 停止弾: 進む秒数 / 止まっている秒数 / 飛び出すときの速さの倍率
    public static let stopGoMove = 0.55
    public static let stopGoHold = 0.6
    public static let stopGoBoost = 1.3
    /// 分裂弾: はじけるまでの秒数 / 散る弾の数 / 散る弾の速さの倍率
    public static let splitAfter = 0.7
    public static let splitCount = 6
    public static let splitSpeed = 0.7
    /// 時差弾: 止まっている秒数
    public static let timedHold = 1.1
    /// チャージビーム: ためる(予告線だけで当たらない)時間と、撃っている(当たる)時間(秒)
    public static let beamCharge = 1.0
    public static let beamFire = 0.5
    /// チャージビームの当たる太さ(光線の中心からの距離の2乗。自機の当たり判定の大きさも含む)
    public static let beamHitRadiusSquared = 81.0
    /// 巨大弾の当たる範囲(中心からの距離の2乗。自機の当たり判定の大きさも含む)と、見た目の半径
    public static let giantHitRadiusSquared = 400.0
    public static let giantDrawRadius = 18.0
    /// ふつうの弾の当たる半径(hitRadiusSquared の平方根)。広さを持つ弾(膨らむ泡など)は、これに広さを足す
    public static let hitRadius = 5.5
    /// 爆風(隕石・地雷の爆発)が当たる時間(秒)。予告のあとに、この間だけ当たる
    public static let blastActive = 0.35
    /// 地雷が爆発したときの、爆風の半径と、散る弾の数
    public static let mineBlastRadius = 30.0
    public static let mineRing = 8
    /// 判定距離の2乗（5.5 未満で被弾）
    public static let hitRadiusSquared = 30.25
    /// スワイプ弾幕のかすり: その弾の当たり判定から、さらにこの距離まで近づいたら 1 かすり(ふつうの弾なら 5.5 + 12.5 = 18px)
    public static let grazeMargin = 12.5
    public static let grazeRadius = hitRadius + grazeMargin
    public static let grazeRadiusSquared = grazeRadius * grazeRadius
}

public enum Pattern: String, Codable, CaseIterable, Sendable {
    // 並びを変えない(乱数シードに順番を使っているので、新しいものは必ず後ろに足す)
    case ring, spiral, aim, rain, sweep
    /// 左の端から、右へ向かって飛んでくる(高さはばらばら)
    case sideL
    /// 右の端から、左へ向かって飛んでくる(高さはばらばら)
    case sideR
    /// 四隅から、自機に向けて扇状に飛んでくる
    case corner
    /// 追尾弾: 自機に向かって曲がりながら飛んでくる(曲がるのは最初の数秒だけ)。課金で作れる(遊ぶのは誰でもできる)
    case homing
    // ここから下も、課金で作れる(遊ぶのは誰でもできる)。並びは変えない
    /// 花: 5枚の花びらの形に広がる輪(花びらの先ほど速い)
    case flower
    /// 星: 5つの角をもつ星の形に広がる輪
    case star
    /// ハート: ハートの形に広がる輪
    case heart
    /// 光線: 自機に向けて、速さの違う弾が一直線に伸びる
    case beam
    /// 十字: 上下左右の4方向に、弾が列になって伸びる
    case cross
    /// 加速弾: ゆっくり出て、どんどん速くなる(自機狙いの扇)
    case accel
    /// 反射弾: 左右の壁で2回はね返る(自機狙いの扇)
    case bounce
    /// 停止弾: 前に進んでぴたっと止まり、少しして自機に向かって飛び出す
    case stopgo
    /// 分裂弾: 少し進むと、小さな弾にはじけて散る
    case split
    /// 時差弾: 輪になったまま止まっていて、合図でいっせいに動き出す
    case timed
    // ここから下は、広告を見て解放するパターン(弾の出し方は AdPatterns.swift。並びは変えない)
    case twinRing, tripleRing, pinwheel, ripple, whirl, slither, curtain, swayFan, drizzle, comet, shotgun, sniper, twinAim, zigzagAim, accelRing, homingRing, bounceRing, freezeRing, shatterRing, pulseRing, freezeCurtain, splitCurtain, wavyRing, petalFan, waveSpiral, tide, ladder, helix, rapidFan, lightRain
    // ここから下は、弾幕作成モード(有料)で自分で描いたパターン。弾の動きは Emitter.path(描いた軌道)に入っている
    case custom
    // ここから下は、あとから足した、広告を見て解放するパターン(乱数シードに順番を使うので、custom より後ろに足す)
    /// チャージビーム: 細い予告線をためてから、太い光線を撃つ
    case chargeBeam
    /// ブーメラン: 弧を描いて、戻ってくる
    case boomerang
    /// 巨大弾: 大きくて当たる範囲も広い弾を、1発ずつ撃つ
    case giantOrb
    /// なぎ払いレーザー: ためてから、光線が首を振って画面をなぎ払う
    case sweepLaser
    // ここから下は、弾幕パック2(課金)だけのパターン(弾の出し方は AdPatterns.swift)
    /// 地雷: ばらまかれて止まり、少しして爆発する(爆風と弾の輪)
    case mine
    /// 隕石: 自機のいる場所に予告の円が出て、そこに大きな衝撃が落ちる
    case meteor
    /// 格子レーザー: 縦と横の光線を、格子の形にためてから撃つ
    case gridLaser
    /// 重力弾: 投げ上げられて、放物線を描いて落ちてくる
    case gravity
    /// 衛星: 発射口のまわりを回ってから、外へ飛び出す
    case orbit
    /// スネーク: 列になって、自機を追いかけてくる
    case snake
    /// 膨らむ泡: ゆっくり進みながら、だんだん大きくなる
    case bubble
    /// 渦巻き: 弾が少しずつ曲がって、渦の腕のように広がる(無料)。
    /// これまでの spiral は放射(ring)と同じ計算だったので、投稿済みのステージの動きを変えないように残し、エディタには出さない
    case swirl
    // ここから下は、堕天使(ボスのキャラクター)だけが使える技。その見た目を選んでいるときだけ、ステージ作りで置ける(遊ぶのは誰でもできる)
    /// 双月「紅き双環」: 両手のオーブから、逆回転の螺旋を撃つ
    case angelTwin
    /// 堕羽「フォールン・フェザー」: 翼から羽の弾を扇状に撃つ。減速して止まり、揺れながら落ちる
    case angelFeather
    /// 輪符「砕けし光輪」: 光輪から破片が輪になって広がり、回ったあと、端から順に自機へ突進する
    case angelHalo
    /// 審判「逆さ十字の裁き」: 胸を中心にした逆さ十字のレーザーが、ためてから回りながら撃たれる
    case angelCross
    /// 終焉「失楽園」: 自機を中心にした弾の輪が閉じてくる。抜け道は1か所だけ
    case angelParadise
    // 九尾の巫女だけが使える技(並びは変えない。足すときは必ず後ろへ)
    /// 狐火「九つの灯」: 九本の尻尾の先に狐火が灯り、順に自機へ飛ぶ
    case kitsuneLanterns
    /// 御札「直角結界」: 御札が輪になって広がり、直角に曲がって格子の結界になる
    case kitsuneBarrier
    /// 狐雨「天気雨」: 空から狐火が降り、自機狙いの御札が混ざる
    case kitsuneSunshower
    /// 鳥居「千本鳥居」: 御札の壁が下りてくる。通り道は1か所
    case kitsuneTorii
    /// 九尾「玉藻の舞」: 九本の尻尾の先から、扇に狐火を撃ち続ける
    case kitsuneDance
    // 雪の女王だけが使える技
    /// 六花「結晶の檻」: 六方向の氷片が、枝分かれして雪の結晶の形に広がる
    case iceCage
    /// 氷柱「アイシクル・フォール」: 画面の上で氷柱が待ち、だんだん速く落ちてくる
    case iceIcicles
    /// 吹雪「ホワイトアウト」: 横風に流される雪の結晶が降り続く
    case iceBlizzard
    /// 凍結「時の氷結」: 氷片の輪が止まって結晶になり、砕けて散る
    case iceFreeze
    /// 氷鏡「ダイヤモンドダスト」: 自機狙いの氷片の扇が、壁で跳ね返る
    case iceMirror
    // 死神だけが使える技
    /// 刈取「三日月の大鎌」: 刃が弧の形に並んで止まり、いっせいに落ちてくる
    case reaperScythe
    /// 魂魄「さまよう魂」: 魂が死神のまわりを回って広がり、自機のほうへ漂ってくる
    case reaperSouls
    /// 鎖「冥府の鎖」: 画面の端から、自機のいた場所へ鎖が伸びる
    case reaperChains
    /// 宣告「デッドライン」: 刃の壁がゆっくり下りてくる。通り道は1か所
    case reaperDeadline
    /// 冥途「三途の渡し」: 魂の流れが、1本ごとに逆向きに流れる
    case reaperRiver
    // 深海の魔女だけが使える技
    /// 深淵「提灯の誘い」: 画面が暗くなり、提灯と自機のまわりしか見えない
    case witchAbyss
    /// 泡沫「膨らむ泡」: 触手の先の泡が膨らみ、弾けて夜光虫が散る
    case witchBubbles
    /// 触手「八腕の抱擁」: 八本の触手から、夜光虫が波打つ列になって伸びる
    case witchTentacles
    /// 渦潮「メイルシュトローム」: 渦の腕が回りながら伸びる
    case witchMaelstrom
    /// 墨「黒潮の帳」: 大きな墨のしずくが落ちて、弾ける
    case witchInk
    // 機神だけが使える技
    /// 照準「コアアイ・ロックオン」: 照準が自機を追って固定され、極太ビームと追尾ミサイル
    case mechLockOn
    /// 弾幕「マイクロミサイル」: 小型ミサイルを上向きにばらまき、自機へ向かって加速する
    case mechMissiles
    /// 掃射「ガトリング・スイープ」: 両肩のキャノンが速い砲弾を連射しながら首を振る
    case mechGatling
    /// 放射「ヘキサ・レーザー」: コアアイから放射状のレーザーがゆっくり回る
    case mechGrid
    /// 制圧「オーバーロード」: 光子弾の輪が加速する
    case mechOverload
    // ぷにまるだけが使える技(通常は「ぷに弾」を落とすだけ。覚醒すると、同じ枠の技が別物になる)
    /// ぽよん(覚醒: 凝視)
    case puniPoyon
    /// ぷにぷにシャワー(覚醒: 螺旋の腕)
    case puniShower
    /// ころころ(覚醒: 歯の環)
    case puniKorokoro
    /// ぷるぷる(覚醒: 二色の眼光)
    case puniPurupuru
    /// おすそわけ(覚醒: 位相のずれ)
    case puniOsusowake
    // 金魚姫だけが使える技
    /// 金魚すくい(覚醒: 群れが増える)
    case hireSukui
    /// ヨーヨー釣り(覚醒: 自機を狙う泡)
    case hireYoyo
    /// 打ち上げ花火(覚醒: 玉が増える)
    case hireHanabi
    /// 波紋(覚醒: 2か所)
    case hireRipple
    /// ぐるぐる回遊(覚醒: 二重の輪)
    case hireKaiyu

    var index: Int32 { Int32(Pattern.allCases.firstIndex(of: self)!) }

    /// 買わないと、ステージ作りで選べないパターン(遊ぶのは誰でもできる)
    public var isPaid: Bool { Pattern.paid.contains(self) || Pattern.pack2.contains(self) }
    public static let paid: [Pattern] = [.homing, .flower, .star, .heart, .beam, .cross, .accel, .bounce, .stopgo, .split, .timed]
    /// 弾幕パック2のパターンか(買わないと、ステージ作りで選べない)
    public var isPack2: Bool { Pattern.pack2.contains(self) }

    /// 堕天使だけが使える技(並びは、出す順)
    public static let fallenAngel: [Pattern] = [.angelFeather, .angelHalo, .angelTwin, .angelCross, .angelParadise]
    /// ボスのキャラクターの専用の技か。その見た目のボスを選んでいるときだけ、ステージに置ける
    public var bossCharacter: BossCharacter? { BossCharacter.allCases.first { Pattern.moves(of: $0).contains(self) } }
    /// 雪の女王だけが使える技(並びは、出す順)
    public static let iceQueen: [Pattern] = [.iceCage, .iceIcicles, .iceBlizzard, .iceFreeze, .iceMirror]
    /// 死神だけが使える技(並びは、出す順)
    public static let reaper: [Pattern] = [.reaperScythe, .reaperSouls, .reaperChains, .reaperDeadline, .reaperRiver]
    /// 深海の魔女だけが使える技(並びは、出す順)
    public static let witch: [Pattern] = [.witchAbyss, .witchBubbles, .witchTentacles, .witchMaelstrom, .witchInk]
    /// 機神だけが使える技(並びは、出す順)
    public static let mech: [Pattern] = [.mechLockOn, .mechMissiles, .mechGatling, .mechGrid, .mechOverload]
    /// ぷにまるだけが使える技(並びは、出す順)
    public static let puni: [Pattern] = [.puniPoyon, .puniShower, .puniKorokoro, .puniPurupuru, .puniOsusowake]
    /// 金魚姫だけが使える技(並びは、出す順)
    public static let hire: [Pattern] = [.hireSukui, .hireYoyo, .hireHanabi, .hireRipple, .hireKaiyu]
    /// そのボスの専用の技
    public static func moves(of c: BossCharacter) -> [Pattern] {
        switch c {
        case .fallenAngel: return fallenAngel
        case .kitsune: return kitsune
        case .iceQueen: return iceQueen
        case .reaper: return reaper
        case .witch: return witch
        case .mech: return mech
        case .puni: return puni
        case .hire: return hire
        }
    }
    /// 九尾の巫女だけが使える技(並びは、出す順)
    public static let kitsune: [Pattern] = [.kitsuneLanterns, .kitsuneBarrier, .kitsuneSunshower, .kitsuneTorii, .kitsuneDance]
}

public enum Mode: String, Codable, Sendable {
    case survive, boss
    /// ダメージ勝負: ボスの HP は無限。制限時間まで生き残り、与えたダメージの合計を競う
    case damage
    /// 連戦: いくつかの場面(ウェーブ)を、順番に進む(中ボス → 雑魚だけ → 大ボス、など)
    case sequence
}

/// ボスを倒したときの演出の種類(演出だけで、計算には関わらない)
public enum DefeatEffect: Int, CaseIterable, Codable, Sendable {
    /// 演出なし
    case none = 0
    /// 爆発: 火花と衝撃波
    case explosion = 1
    /// 花火: カラフルな弾が放射状に広がる
    case fireworks = 2
    /// ハート: ピンクのハートが舞い上がる
    case hearts = 3
    /// 星くず: 金色の星がきらめく
    case stardust = 4

    /// 指定がないときの演出
    public static let standard = DefeatEffect.explosion
}

/// 連戦の1つの場面の種類
public enum WaveKind: String, Codable, Sendable {
    /// ボスなし。決めた時間、生き残る
    case survive
    /// ボスを倒す(制限時間つき)
    case boss
}

/// 連戦の1つの場面。ライフ・HP は、場面をまたいで続く
public struct Wave: Codable, Equatable, Sendable {
    public var kind: WaveKind
    /// 生き残る時間、またはボスの制限時間(秒)
    public var durationSec: Int
    public var bossHp: Int?
    public var bossMove: Int?
    public var emitters: [Emitter]
    /// ボスの場面の開始前に、警告(赤い点滅とサイレン)を出す。演出だけで、計算には関わらない
    public var warning: Bool?
    /// ボスを倒したときの演出(DefeatEffect の番号)。nil は標準(爆発)
    public var defeat: Int?
    /// ボスの大きさ(0=小 1=中 2=大)。nil は中。当たる範囲も変わる
    public var bossSize: Int?
    /// 発射点に、小さな敵(雑魚)の姿を出す大きさ(0=小 1=中 2=大)。nil は出さない。見た目だけで、計算には関わらない
    public var mooks: Int?
    /// 雑魚を倒せるか(自機の弾が当たると体力が減り、倒すとその発射台は撃たなくなる)。雑魚を出すときだけ。nil は倒せない(これまで通り)
    public var mooksBreakable: Bool?
    /// ボス・雑魚の見た目(0〜4、nil は標準)。見た目だけ
    public var bossLook: Int?
    public var mookLook: Int?
    /// 覚醒する段階(2 か 3)。その段階になると、ボスが覚醒の演出とともに姿を変える。nil は覚醒しない。ボスの場面だけ
    public var awaken: Int?
    /// ボスの位置(動きの中心。画面の幅・高さに対する割合。x は 0.2〜0.8、y は 0.1〜0.3)。nil は標準(x=0.5, y=0.2)
    public var bossX: Double?
    public var bossY: Double?

    public init(kind: WaveKind, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil, emitters: [Emitter], warning: Bool? = nil, defeat: Int? = nil,
                bossSize: Int? = nil, mooks: Int? = nil, bossLook: Int? = nil, mookLook: Int? = nil, awaken: Int? = nil, bossX: Double? = nil, bossY: Double? = nil) {
        self.kind = kind; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove; self.emitters = emitters; self.warning = warning; self.defeat = defeat
        self.bossSize = bossSize; self.mooks = mooks; self.bossLook = bossLook; self.mookLook = mookLook; self.awaken = awaken
        self.bossX = bossX; self.bossY = bossY
    }

    /// 生き残りの発射台は、開始が制限時間より前で、終わりが開始より後でないと、サーバーが受け付けない。同じ決まりに揃える
    static func fixedTiming(_ list: [Emitter], limit: Int) -> [Emitter] {
        list.map { m in
            var f = m
            f.s = min(f.s, max(0, (Double(limit) - 0.5)))
            f.s = (f.s * 100).rounded() / 100
            f.e = max(f.e, f.s + 0.5)
            f.e = (min(f.e, 180) * 100).rounded() / 100
            if f.e <= f.s { f.s = max(0, f.e - 0.5) }
            return f
        }
    }

    /// 向きを回す角度は、-180〜180 度の整数
    /// キャラクターのボスの専用の技は、そのボスを選んでいるときだけ使える。そうでなければ、ふつうの輪にする
    static func allowedPattern(_ t: Pattern, look: Int?) -> Pattern {
        guard let owner = t.bossCharacter else { return t }
        return look == owner.rawValue ? t : .ring
    }

    static func sanitizedAngle(_ v: Int) -> Int { min(180, max(-180, v)) }

    /// 雑魚の見た目。標準(0)は保存しない。範囲外は標準に戻す
    static func sanitizedLook(_ v: Int?) -> Int? {
        guard let v, (1..<DanmakuConfig.enemyLooks).contains(v) else { return nil }
        return v
    }

    /// ボスの見た目(キャラクターを含む)。標準(0)は保存しない。範囲外は標準に戻す
    static func sanitizedBossLook(_ v: Int?) -> Int? {
        guard let v, (1..<DanmakuConfig.bossLooks).contains(v) else { return nil }
        if v >= BossCharacter.firstCharacterLook && BossCharacter.of(look: v) == nil { return nil }
        return v
    }

    /// 覚醒する段階(2 か 3)。それ以外は覚醒しない
    /// ボスの位置の指定を、範囲内の 0.05 刻みに丸める。標準の位置と同じなら保存しない(nil)
    static func sanitizedHome(_ v: Double?, _ lo: Double, _ hi: Double, _ standard: Double) -> Double? {
        guard let v, v.isFinite else { return nil }
        let r = (min(hi, max(lo, v)) * 20).rounded() / 20
        return abs(r - standard) < 0.001 ? nil : r
    }

    static func sanitizedAwaken(_ v: Int?) -> Int? {
        guard let v, BossCharacter.awakenPhases.contains(v) else { return nil }
        return v
    }

    /// 中(標準)は保存しない。範囲外は標準に戻す
    static func sanitizedSize(_ v: Int?) -> Int? {
        guard let v else { return nil }
        // 10〜44 は半径(px)。小・中・大と同じ半径は 0・1・2 に戻す。中(標準)は保存しない
        if DanmakuConfig.bossRadiusRange.contains(v) { let s = DanmakuConfig.bossSize(forRadius: v); return s == 1 ? nil : s }
        guard (0...2).contains(v), v != 1 else { return nil }
        return v
    }
    /// キャラクターのボスは、大きさ・動きの設定を使わない(絵と判定が決まっている)ので、保存しない
    /// キャラクターのボスの大きさ(半径 px)。範囲外と標準(40)は保存しない
    static func sanitizedCharacterSize(_ v: Int?) -> Int? {
        guard let v, DanmakuConfig.characterRadiusRange.contains(v), Double(v) != DanmakuConfig.characterBaseRadius else { return nil }
        return v
    }
    static func isCharacter(_ look: Int?) -> Bool { look.flatMap(BossCharacter.of(look:)) != nil }
    static func sanitizedMooks(_ v: Int?) -> Int? {
        guard let v, (0...2).contains(v) else { return nil }
        return v
    }

    /// 実際に使う撃破の演出
    public var defeatEffect: DefeatEffect { defeat.flatMap(DefeatEffect.init(rawValue:)) ?? .standard }

    public static let surviveDurations = [10, 20, 30, 45, 60, 90, 120]
    public static let bossDurations = [30, 60, 90, 120, 180]
    public static let maxWaves = 6
    /// 場面と場面の間(画面の弾を消して、次の準備をする)の長さ(秒)
    public static let intermissionSeconds = 1.5
    /// 場面の切り替えにかかる時間を、制限時間の計算に入れるときの長さ(整数の秒)
    public static let intermissionBudget = 2

    /// 標準(爆発)と同じ指定は保存しない。範囲外は標準に戻す
    static func sanitizedDefeat(_ d: Int?) -> Int? {
        guard let d, let e = DefeatEffect(rawValue: d), e != .standard else { return nil }
        return d
    }

    func sanitized() -> Wave {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v.isFinite ? v : 0)) }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let isBoss = kind == .boss
        let allowed = isBoss ? Wave.bossDurations : Wave.surviveDurations
        let d = allowed.contains(durationSec) ? durationSec : (isBoss ? 60 : 20)
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let look = isBoss ? Wave.sanitizedBossLook(bossLook) : nil
        let mv = isBoss ? Int(clamp(Double(bossMove ?? 0), 0, Double(Simulation.bossMoveCount - 1)).rounded()) : nil
        let ems = emitters.prefix(DanmakuConfig.maxEmitters).map { m in
            Emitter(t: Wave.allowedPattern(m.t, look: look),
                    x: r2(clamp(m.x, 0, 1)), y: r2(clamp(m.y, 0, 0.6)),
                    s: r2(clamp(m.s, 0, 180)), e: r2(clamp(m.e, 0, 180)),
                    i: r2(clamp(m.i, 0.05, Emitter.maxInterval)), c: Int(clamp(Double(m.c), 1, 36)),
                    v: r2(clamp(m.v, 1, 5)), r: clamp(m.r, -90, 90).rounded(),
                    k: Int(clamp(Double(m.k), 0, 4)), ph: isBoss ? Int(clamp(Double(m.ph), 0, 3)) : 0,
                    p: isBoss && m.p == 1 ? 1 : 0,
                    a: m.canRotate ? Wave.sanitizedAngle(m.a) : 0,
                    path: m.t == .custom ? PathData.sanitized(m.path) : nil,
                    sh: (m.sh == 1 || m.sh == 2) ? m.sh : nil, mir: m.mir == 1 ? 1 : nil)
        }
        var out = Wave(kind: kind, durationSec: d, bossHp: hp, bossMove: mv, emitters: isBoss ? Array(ems) : Wave.fixedTiming(Array(ems), limit: d), warning: (isBoss && warning == true) ? true : nil,
                    defeat: isBoss ? Wave.sanitizedDefeat(defeat) : nil,
                    bossSize: isBoss ? (Wave.isCharacter(look) ? Wave.sanitizedCharacterSize(bossSize) : Wave.sanitizedSize(bossSize)) : nil, mooks: Wave.sanitizedMooks(mooks),
                    bossLook: look, mookLook: mooks == nil ? nil : Wave.sanitizedLook(mookLook),
                    awaken: isBoss ? Wave.sanitizedAwaken(awaken) : nil,
                    bossX: isBoss ? Wave.sanitizedHome(bossX, 0.2, 0.8, 0.5) : nil,
                    bossY: isBoss ? Wave.sanitizedHome(bossY, 0.1, 0.3, 0.2) : nil)
        out.mooksBreakable = (out.mooks != nil && mooksBreakable == true) ? true : nil
        return out
    }
}

/// 自機の耐久の決め方
public enum LifeMode: String, Codable, CaseIterable, Sendable {
    /// ライフ制: 当たるとライフが1つ減り、少しの間無敵になる。0になったら失敗
    case lives
    /// HP 制: 弾に当たるたびに HP が1減り、当たった弾は消える(無敵時間なし)。0になったら失敗
    case hp
}

/// 発射台。キー名は SPEC 7章（試作のステージ形式）と同じ
public struct Emitter: Codable, Equatable, Sendable {

    public var t: Pattern
    public var x: Double
    public var y: Double
    public var s: Double
    public var e: Double
    public var i: Double
    public var c: Int
    public var v: Double
    public var r: Double
    public var k: Int
    public var ph: Int
    /// 出す場所(ボス戦・ダメージ勝負だけ): 0 = ボスの位置(これまでと同じ)、1 = x, y で決めた場所
    public var p: Int
    /// パターン全体の向きを、時計回りに回す角度(度)。0 は、これまでと同じ(データに入れない)。輪・自機狙い・形・十字などに効く
    public var a: Int
    /// 弾幕作成モードで描いた軌道(t == .custom のときだけ)。発射位置を原点にした (x, y) を、PathData.step 秒ごとに並べたもの [x0, y0, x1, y1, ...]
    public var path: [Double]?
    /// 弾の見た目(見た目だけ。当たる範囲や動きは変わらない): nil はパターンの標準、1 は「くの字」(ブーメランの形)、2 は丸
    public var sh: Int?
    /// 左右反転(線対称): 1 で、発射位置・弾の向き・回る向きを、画面の左右で反転して撃つ。nil は反転しない
    public var mir: Int?

    public init(t: Pattern, x: Double = 0.5, y: Double = 0.2, s: Double = 0, e: Double = 30,
                i: Double = 1, c: Int = 16, v: Double = 2, r: Double = 0, k: Int = 0, ph: Int = 0, p: Int = 0, a: Int = 0, path: [Double]? = nil, sh: Int? = nil, mir: Int? = nil) {
        self.t = t; self.x = x; self.y = y; self.s = s; self.e = e
        self.i = i; self.c = c; self.v = v; self.r = r; self.k = k; self.ph = ph; self.p = p; self.a = a
        self.path = path
        self.sh = sh
        self.mir = mir
    }

    /// 発射の間隔(秒)の範囲。以前は 2 秒までだったが、ゆっくり撃つ弾幕のために 15 秒まで
    public static let minInterval = 0.05
    public static let maxInterval = 15.0

    /// 向きを回せるパターンか(雨・横切り・隅・掃射は、向きが決まっているので回せない)
    public var canRotate: Bool { ![.rain, .sweep, .sideL, .sideR, .corner].contains(t) }

    /// ボス戦で、好きな場所から出すか
    public var firesFromPoint: Bool { p == 1 }

    private enum CodingKeys: String, CodingKey { case t, x, y, s, e, i, c, v, r, k, ph, p, a, path, sh, mir }

    /// 出す場所が標準(ボス)のときは、データに入れない(これまでの投稿と同じ形のまま)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        try c.encode(s, forKey: .s); try c.encode(e, forKey: .e); try c.encode(i, forKey: .i)
        try c.encode(self.c, forKey: .c); try c.encode(v, forKey: .v); try c.encode(r, forKey: .r)
        try c.encode(k, forKey: .k); try c.encode(ph, forKey: .ph)
        if p != 0 { try c.encode(p, forKey: .p) }
        if a != 0 { try c.encode(a, forKey: .a) }
        if let path { try c.encode(path, forKey: .path) }
        if let sh, sh == 1 || sh == 2 { try c.encode(sh, forKey: .sh) }
        if mir == 1 { try c.encode(1, forKey: .mir) }
    }

    public init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        t = try d.decode(Pattern.self, forKey: .t)
        x = try d.decode(Double.self, forKey: .x)
        y = try d.decode(Double.self, forKey: .y)
        s = try d.decode(Double.self, forKey: .s)
        e = try d.decode(Double.self, forKey: .e)
        i = try d.decode(Double.self, forKey: .i)
        c = try d.decode(Int.self, forKey: .c)
        v = try d.decode(Double.self, forKey: .v)
        r = try d.decode(Double.self, forKey: .r)
        k = try d.decode(Int.self, forKey: .k)
        ph = try d.decodeIfPresent(Int.self, forKey: .ph) ?? 0
        p = try d.decodeIfPresent(Int.self, forKey: .p) ?? 0
        a = try d.decodeIfPresent(Int.self, forKey: .a) ?? 0
        path = (try? d.decodeIfPresent([Double].self, forKey: .path)) ?? nil
        sh = (try? d.decodeIfPresent(Int.self, forKey: .sh)).flatMap { $0 == 1 || $0 == 2 ? $0 : nil }
        mir = (try? d.decodeIfPresent(Int.self, forKey: .mir)).flatMap { $0 == 1 ? 1 : nil }
    }
}

/// シミュレーション用の、1つの場面
struct WaveSpec {
    var boss: Bool
    var damage: Bool
    var limit: Double
    var hp: Int
    var move: Int
    var emitters: [Emitter]
    var warning = false
    var defeat = DefeatEffect.standard
    var size = 1
    /// 見た目だけ: ボスの見た目、雑魚の大きさ(nil は出さない)と見た目
    var look = 0
    var mooks: Int?
    var mookLook = 0
    /// 雑魚を倒せるか(雑魚を出すときだけ true になる)
    var mooksBreakable = false
    /// 覚醒する段階(nil は覚醒しない)
    var awaken: Int?
    /// ボスの位置のずらし量(px。標準の位置からの差)
    var homeDX = 0.0
    var homeDY = 0.0
    /// 専用の絵・動き・当たり判定を持つボス(nil は図形のボス)
    var character: BossCharacter? { BossCharacter.of(look: look) }
    /// キャラクターのボスの大きさの倍率(当たり判定の半径 ÷ 40)。指定がなければ 1。図形のボスは 1
    var characterScale: Double {
        guard character != nil, DanmakuConfig.characterRadiusRange.contains(size) else { return 1 }
        return Double(size) / DanmakuConfig.characterBaseRadius
    }
}

public struct Stage: Codable, Equatable, Sendable {
    public var name: String
    public var mode: Mode
    public var durationSec: Int
    public var bossHp: Int?
    public var bossMove: Int?
    public var emitters: [Emitter]
    public var formatVersion: Int
    /// 自機の耐久。nil は「ライフ制・ライフ1」(これまでのステージと同じ。1回当たったら失敗)
    public var lifeMode: LifeMode?
    public var lifeCount: Int?
    /// 遊ぶときに流れる BGM の番号(0〜4)。nil は、モードごとの標準の曲(生き残り=0、ボス戦・ダメージ勝負=1)
    public var bgm: Int?

    /// 連戦(mode == .sequence)の場面。ほかのモードでは nil
    public var waves: [Wave]?
    /// ボス戦・ダメージ勝負の開始前に、警告(赤い点滅とサイレン)を出す。演出だけで、計算には関わらない
    public var bossWarning: Bool?
    /// ボス戦(ダメージ勝負以外)で、ボスを倒したときの演出(DefeatEffect の番号)。nil は標準(爆発)
    public var bossDefeat: Int?
    /// ボスの大きさ(0=小 1=中 2=大)。nil は中。当たる範囲も変わる
    public var bossSize: Int?
    /// ボスの位置(動きの中心。画面に対する割合。x は 0.2〜0.8、y は 0.1〜0.3)。nil は標準(x=0.5, y=0.2)
    public var bossX: Double?
    public var bossY: Double?
    /// 発射点に、小さな敵(雑魚)の姿を出す大きさ(0=小 1=中 2=大)。nil は出さない。見た目だけ
    public var mooks: Int?
    /// 雑魚を倒せるか(Wave.mooksBreakable と同じ。連戦以外のステージ全体の設定)
    public var mooksBreakable: Bool?
    public var bossLook: Int?
    public var mookLook: Int?
    /// 覚醒する段階(2 か 3)。nil は覚醒しない。ボス戦・ダメージ勝負だけ(連戦は場面ごとの Wave.awaken)
    public var awaken: Int?
    /// 自機の撃ち方(ステージごとに、作者が決める)。nil は標準。遊ぶ全員が、この撃ち方で遊ぶ
    public var shot: ShotType?
    public var shotType: ShotType { shot ?? .standard }
    /// 作者が付けた、毎日のごほうびの演出(Reward の番号。種類ごとに1つまで)。遊ぶ全員に、この演出が出る。見た目だけで、計算やランキングには関わらない。nil は付けない
    public var rewardFx: [Int]?
    public var bossDefeatEffect: DefeatEffect { bossDefeat.flatMap(DefeatEffect.init(rawValue:)) ?? .standard }

    /// 発射位置の予告(点線のひし形)を出さない。nil は、出す(これまでと同じ)。作者が決める
    public var hideMarkers: Bool?
    public var showsMarkers: Bool { hideMarkers != true }

    /// ステージの見た目(作者が決める。遊ぶ全員に、そう見える)。nil は標準
    public var themeBullets: Theme?
    public var themeBackground: Theme?
    public var themeShip: Theme?

    public var lookBullets: Theme { themeBullets ?? .classic }
    public var lookBackground: Theme { themeBackground ?? .classic }
    public var lookShip: Theme { themeShip ?? .classic }

    /// 世界のステージ一覧の動くプレビューを始める秒(作者が決める。見た目だけで、計算やランキングには関わらない)。nil は0秒から
    public var previewStart: Int?
    /// 一覧でプレビューを見せない(ネタバレ防止)。nil は、見せる
    public var noPreview: Bool?
    /// プレビューの開始秒に選べる最大(ステージの長さの30%まで。切り捨て)
    public static func maxPreviewStart(durationSec: Int) -> Int { max(0, Int(Double(max(0, durationSec)) * 0.3)) }
    /// 保存する開始秒(範囲に丸める。0 は標準なので保存しない)
    static func sanitizedPreviewStart(_ v: Int?, durationSec: Int) -> Int? {
        guard let v else { return nil }
        let c = min(max(0, v), maxPreviewStart(durationSec: durationSec))
        return c == 0 ? nil : c
    }
    public var maxPreviewStart: Int { Stage.maxPreviewStart(durationSec: durationSec) }
    public var hidesPreview: Bool { noPreview == true }
    /// 実際に使うプレビューの開始秒
    public var effectivePreviewStart: Int { min(max(0, previewStart ?? 0), maxPreviewStart) }

    /// 選べる BGM の数
    public static let bgmCount = 5

    /// 実際に流す BGM の番号
    public var effectiveBGM: Int {
        if let b = bgm, (0..<Stage.bgmCount).contains(b) { return b }
        return mode == .survive ? 0 : 1
    }

    public init(name: String, mode: Mode, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil,
                emitters: [Emitter], formatVersion: Int = DanmakuConfig.formatVersion,
                lifeMode: LifeMode? = nil, lifeCount: Int? = nil, bgm: Int? = nil,
                themeBullets: Theme? = nil, themeBackground: Theme? = nil, themeShip: Theme? = nil,
                hideMarkers: Bool? = nil, waves: [Wave]? = nil, bossWarning: Bool? = nil, bossDefeat: Int? = nil,
                bossSize: Int? = nil, mooks: Int? = nil, bossLook: Int? = nil, mookLook: Int? = nil, shot: ShotType? = nil, rewardFx: [Int]? = nil, awaken: Int? = nil,
                previewStart: Int? = nil, noPreview: Bool? = nil, bossX: Double? = nil, bossY: Double? = nil) {
        self.name = name; self.mode = mode; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove
        self.emitters = emitters; self.formatVersion = formatVersion
        self.lifeMode = lifeMode; self.lifeCount = lifeCount; self.bgm = bgm
        self.themeBullets = themeBullets; self.themeBackground = themeBackground; self.themeShip = themeShip
        self.hideMarkers = hideMarkers
        self.waves = waves
        self.bossWarning = bossWarning
        self.bossDefeat = bossDefeat
        self.bossSize = bossSize; self.mooks = mooks; self.bossLook = bossLook; self.mookLook = mookLook; self.shot = shot
        self.rewardFx = rewardFx
        self.awaken = awaken
        self.previewStart = previewStart; self.noPreview = noPreview
        self.bossX = bossX; self.bossY = bossY
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, durationSec, bossHp, bossMove, emitters, formatVersion, lifeMode, lifeCount, bgm
        case themeBullets, themeBackground, themeShip, hideMarkers, waves, bossWarning, bossDefeat, bossSize, mooks, bossLook, mookLook, shot, rewardFx, awaken, previewStart, noPreview, bossX, bossY
        case mooksBreakable
    }

    static func homeShift(_ v: Double?, _ standard: Double, _ size: Double) -> Double { ((v ?? standard) - standard) * size }

    /// シミュレーションが使う場面の一覧。連戦以外は、これまでのステージ全体を「場面1つ」として扱う
    var waveSpecs: [WaveSpec] {
        if mode == .sequence, let ws = waves, !ws.isEmpty {
            return ws.map { w in
                WaveSpec(boss: w.kind == .boss, damage: false, limit: Double(w.durationSec), hp: w.bossHp ?? 0, move: w.bossMove ?? 0, emitters: w.emitters, warning: w.warning == true, defeat: w.defeatEffect, size: w.bossSize ?? 1, look: w.bossLook ?? 0, mooks: w.mooks, mookLook: w.mookLook ?? 0, mooksBreakable: w.mooks != nil && w.mooksBreakable == true, awaken: w.awaken, homeDX: Stage.homeShift(w.bossX, 0.5, DanmakuConfig.width), homeDY: Stage.homeShift(w.bossY, 0.2, DanmakuConfig.height))
            }
        }
        return [WaveSpec(boss: mode != .survive, damage: mode == .damage, limit: Double(timeLimitSec), hp: bossHp ?? 0, move: bossMove ?? 0, emitters: emitters, warning: bossWarning == true, defeat: bossDefeatEffect, size: bossSize ?? 1, look: bossLook ?? 0, mooks: mooks, mookLook: mookLook ?? 0, mooksBreakable: mooks != nil && mooksBreakable == true, awaken: awaken, homeDX: Stage.homeShift(bossX, 0.5, DanmakuConfig.width), homeDY: Stage.homeShift(bossY, 0.2, DanmakuConfig.height))]
    }

    /// 連戦のとき、最後まで通しての所要時間の上限(秒)。場面の合計と、切り替えの時間
    public static func sequenceTotalSeconds(_ waves: [Wave]) -> Int {
        waves.reduce(0) { $0 + $1.durationSec } + Wave.intermissionBudget * max(0, waves.count - 1)
    }

    /// ランキングに載るモードか(連戦もボス戦と同じ、クリアまでの時間で競う)
    public var ranksByTime: Bool { mode == .boss || mode == .sequence }
    public var hasRanking: Bool { mode != .survive }

    /// 時間無制限(durationSec が 0)のボス戦を、記録の大きさのために打ち切る長さ(秒)
    public static let unlimitedCapSec = 600
    /// 時間無制限か(ボス戦だけ)
    public var isUnlimitedTime: Bool { durationSec == 0 && mode == .boss }
    /// 実際に使う制限時間(秒)。無制限のときは打ち切りの長さ
    public var timeLimitSec: Int { isUnlimitedTime ? Stage.unlimitedCapSec : durationSec }

    /// 選べるライフの数と HP の範囲
    public static let livesRange = 1...5
    public static let hpRange = 3...20

    /// 実際に使う耐久の方式と数(未指定ならライフ1)
    public var effectiveLifeMode: LifeMode { lifeMode ?? .lives }
    public var effectiveLifeCount: Int {
        let range = effectiveLifeMode == .lives ? Stage.livesRange : Stage.hpRange
        return min(range.upperBound, max(range.lowerBound, lifeCount ?? 1))
    }

    public init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        name = try d.decode(String.self, forKey: .name)
        mode = try d.decode(Mode.self, forKey: .mode)
        durationSec = try d.decode(Int.self, forKey: .durationSec)
        bossHp = try d.decodeIfPresent(Int.self, forKey: .bossHp)
        bossMove = try d.decodeIfPresent(Int.self, forKey: .bossMove)
        emitters = try d.decode([Emitter].self, forKey: .emitters)
        formatVersion = try d.decodeIfPresent(Int.self, forKey: .formatVersion) ?? DanmakuConfig.formatVersion
        lifeMode = try d.decodeIfPresent(LifeMode.self, forKey: .lifeMode)
        lifeCount = try d.decodeIfPresent(Int.self, forKey: .lifeCount)
        bgm = try d.decodeIfPresent(Int.self, forKey: .bgm)
        // 知らないテーマ名(新しい版で増えたもの)は、標準として読む
        themeBullets = (try? d.decodeIfPresent(Theme.self, forKey: .themeBullets)) ?? nil
        themeBackground = (try? d.decodeIfPresent(Theme.self, forKey: .themeBackground)) ?? nil
        themeShip = (try? d.decodeIfPresent(Theme.self, forKey: .themeShip)) ?? nil
        hideMarkers = try d.decodeIfPresent(Bool.self, forKey: .hideMarkers)
        waves = try d.decodeIfPresent([Wave].self, forKey: .waves)
        bossWarning = try d.decodeIfPresent(Bool.self, forKey: .bossWarning)
        bossDefeat = try d.decodeIfPresent(Int.self, forKey: .bossDefeat)
        bossSize = try d.decodeIfPresent(Int.self, forKey: .bossSize)
        mooks = try d.decodeIfPresent(Int.self, forKey: .mooks)
        bossLook = try d.decodeIfPresent(Int.self, forKey: .bossLook)
        mookLook = try d.decodeIfPresent(Int.self, forKey: .mookLook)
        shot = (try? d.decodeIfPresent(ShotType.self, forKey: .shot)) ?? nil
        rewardFx = (try? d.decodeIfPresent([Int].self, forKey: .rewardFx)) ?? nil
        awaken = try d.decodeIfPresent(Int.self, forKey: .awaken)
        previewStart = try d.decodeIfPresent(Int.self, forKey: .previewStart)
        noPreview = try d.decodeIfPresent(Bool.self, forKey: .noPreview)
        bossX = try d.decodeIfPresent(Double.self, forKey: .bossX)
        bossY = try d.decodeIfPresent(Double.self, forKey: .bossY)
        mooksBreakable = try d.decodeIfPresent(Bool.self, forKey: .mooksBreakable)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(mode, forKey: .mode)
        try c.encode(durationSec, forKey: .durationSec)
        try c.encodeIfPresent(bossHp, forKey: .bossHp)
        try c.encodeIfPresent(bossMove, forKey: .bossMove)
        try c.encodeIfPresent(bossX, forKey: .bossX)
        try c.encodeIfPresent(bossY, forKey: .bossY)
        try c.encodeIfPresent(mooksBreakable, forKey: .mooksBreakable)
        try c.encode(emitters, forKey: .emitters)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encodeIfPresent(lifeMode, forKey: .lifeMode)
        try c.encodeIfPresent(lifeCount, forKey: .lifeCount)
        try c.encodeIfPresent(bgm, forKey: .bgm)
        try c.encodeIfPresent(themeBullets, forKey: .themeBullets)
        try c.encodeIfPresent(themeBackground, forKey: .themeBackground)
        try c.encodeIfPresent(themeShip, forKey: .themeShip)
        try c.encodeIfPresent(hideMarkers, forKey: .hideMarkers)
        try c.encodeIfPresent(waves, forKey: .waves)
        try c.encodeIfPresent(bossWarning, forKey: .bossWarning)
        try c.encodeIfPresent(bossDefeat, forKey: .bossDefeat)
        try c.encodeIfPresent(bossSize, forKey: .bossSize)
        try c.encodeIfPresent(mooks, forKey: .mooks)
        try c.encodeIfPresent(bossLook, forKey: .bossLook)
        try c.encodeIfPresent(mookLook, forKey: .mookLook)
        try c.encodeIfPresent(shot, forKey: .shot)
        try c.encodeIfPresent(rewardFx, forKey: .rewardFx)
        try c.encodeIfPresent(awaken, forKey: .awaken)
        try c.encodeIfPresent(previewStart, forKey: .previewStart)
        try c.encodeIfPresent(noPreview, forKey: .noPreview)
    }

    public static let durations: [Mode: [Int]] = [
        .survive: [10, 20, 30, 45, 60, 90, 120],
        .boss: [0, 30, 60, 90, 120, 180],   // 0 は「時間無制限」(最長 unlimitedCapSec で打ち切る)
        .damage: [30, 60, 90, 120, 180],
        .sequence: [],   // 連戦の長さは、場面の合計(sanitized が計算する)
    ]

    /// 値の範囲を丸めた安全なステージを返す（試作の sanitize と同じ。HP は 50 刻み、小数は 2 桁、角度は整数に揃える）
    /// このステージで使っている、キャラクターのボス(連戦なら、場面ごとの全部)。公開には、持っている必要がある
    public var usedBosses: [BossCharacter] {
        var list: [BossCharacter] = []
        let looks = mode == .sequence ? (waves ?? []).filter { $0.kind == .boss }.map(\.bossLook) : (mode == .boss || mode == .damage ? [bossLook] : [])
        for look in looks {
            if let b = BossCharacter.of(look: look ?? 0), !list.contains(b) { list.append(b) }
        }
        return list
    }

    public func sanitized() -> Stage {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            let f = v.isFinite ? v : 0
            return min(hi, max(lo, f))
        }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

        if mode == .sequence {
            let ws = (waves ?? []).prefix(Wave.maxWaves).map { $0.sanitized() }
            let trimmed = name.isEmpty ? "名無しステージ" : String(name.prefix(20))
            let lm = effectiveLifeMode, lc = effectiveLifeCount
            let isDefaultLife = lm == .lives && lc == 1
            let seqDur = Stage.sequenceTotalSeconds(Array(ws))
            let pStart = Stage.sanitizedPreviewStart(previewStart, durationSec: seqDur)
            return Stage(name: trimmed, mode: .sequence, durationSec: seqDur, bossHp: nil, bossMove: nil,
                         emitters: [], formatVersion: DanmakuConfig.formatVersion,
                         lifeMode: isDefaultLife ? nil : lm, lifeCount: isDefaultLife ? nil : lc,
                         bgm: (bgm.map { (0..<Stage.bgmCount).contains($0) } ?? false) && bgm != 1 ? bgm : nil,
                         themeBullets: lookBullets == .classic ? nil : lookBullets,
                         themeBackground: lookBackground == .classic ? nil : lookBackground,
                         themeShip: lookShip == .classic ? nil : lookShip,
                         hideMarkers: hideMarkers == true ? true : nil, waves: Array(ws), bossWarning: nil, bossDefeat: nil,
                         bossSize: nil, mooks: nil, bossLook: nil, mookLook: nil, shot: shot == .standard ? nil : shot, rewardFx: Reward.sanitizedFx(rewardFx),
                         previewStart: pStart, noPreview: noPreview == true ? true : nil)
        }
        let allowed = Stage.durations[mode]!
        // 選択肢にない値は、標準の長さに丸める(生き残りは20秒、ボス戦とダメージ勝負は60秒)
        let d = allowed.contains(durationSec) ? durationSec : (mode == .survive ? 20 : 60)
        let isBoss = mode == .boss
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let isBossMode = mode == .boss || mode == .damage
        let look = isBossMode ? Wave.sanitizedBossLook(bossLook) : nil
        let mv = isBossMode ? Int(clamp(Double(bossMove ?? 0), 0, Double(Simulation.bossMoveCount - 1)).rounded()) : nil
        let trimmed = name.isEmpty ? "名無しステージ" : String(name.prefix(20))
        let pStart = Stage.sanitizedPreviewStart(previewStart, durationSec: d)
        let ems = emitters.prefix(DanmakuConfig.maxEmitters).map { m in
            Emitter(t: Wave.allowedPattern(m.t, look: look),
                    x: r2(clamp(m.x, 0, 1)), y: r2(clamp(m.y, 0, 0.6)),
                    s: r2(clamp(m.s, 0, 180)), e: r2(clamp(m.e, 0, 180)),
                    i: r2(clamp(m.i, 0.05, Emitter.maxInterval)), c: Int(clamp(Double(m.c), 1, 36)),
                    v: r2(clamp(m.v, 1, 5)), r: clamp(m.r, -90, 90).rounded(),
                    k: Int(clamp(Double(m.k), 0, 4)), ph: Int(clamp(Double(m.ph), 0, 3)),
                    p: mode == .survive ? 0 : (m.p == 1 ? 1 : 0),
                    a: m.canRotate ? Wave.sanitizedAngle(m.a) : 0,
                    path: m.t == .custom ? PathData.sanitized(m.path) : nil,
                    sh: (m.sh == 1 || m.sh == 2) ? m.sh : nil, mir: m.mir == 1 ? 1 : nil)
        }
        // 耐久: 標準(ライフ1)は未指定に揃える。サーバーの検証と同じ丸め方
        let lm = effectiveLifeMode, lc = effectiveLifeCount
        let isDefaultLife = lm == .lives && lc == 1
        var out = Stage(name: trimmed, mode: mode, durationSec: d, bossHp: hp, bossMove: mv,
                     emitters: mode == .survive ? Wave.fixedTiming(Array(ems), limit: d) : Array(ems), formatVersion: DanmakuConfig.formatVersion,
                     lifeMode: isDefaultLife ? nil : lm, lifeCount: isDefaultLife ? nil : lc,
                     // 標準の曲と同じ指定は保存しない(範囲外も標準に戻す)
                     bgm: (bgm.map { (0..<Stage.bgmCount).contains($0) } ?? false) && bgm != (mode == .survive ? 0 : 1) ? bgm : nil,
                     // 標準と同じ指定は保存しない
                     themeBullets: lookBullets == .classic ? nil : lookBullets,
                     themeBackground: lookBackground == .classic ? nil : lookBackground,
                     themeShip: lookShip == .classic ? nil : lookShip,
                     // 予告を出さないときだけ保存する(出す=標準は保存しない)。出さない設定は、生き残りのステージだけ(ボス戦には予告がない)
                     hideMarkers: (hideMarkers == true && mode == .survive) ? true : nil,
                     bossWarning: (bossWarning == true && (mode == .boss || mode == .damage)) ? true : nil,
                     bossDefeat: mode == .boss ? Wave.sanitizedDefeat(bossDefeat) : nil,
                     bossSize: isBossMode ? (Wave.isCharacter(look) ? Wave.sanitizedCharacterSize(bossSize) : Wave.sanitizedSize(bossSize)) : nil,
                     mooks: Wave.sanitizedMooks(mooks),
                     bossLook: look,
                     mookLook: mooks == nil ? nil : Wave.sanitizedLook(mookLook),
                     shot: shot == .standard ? nil : shot,
                     rewardFx: Reward.sanitizedFx(rewardFx),
                     awaken: isBossMode ? Wave.sanitizedAwaken(awaken) : nil,
                     previewStart: pStart, noPreview: noPreview == true ? true : nil,
                     bossX: isBossMode ? Wave.sanitizedHome(bossX, 0.2, 0.8, 0.5) : nil,
                     bossY: isBossMode ? Wave.sanitizedHome(bossY, 0.1, 0.3, 0.2) : nil)
        out.mooksBreakable = (out.mooks != nil && mooksBreakable == true) ? true : nil
        return out
    }
}
