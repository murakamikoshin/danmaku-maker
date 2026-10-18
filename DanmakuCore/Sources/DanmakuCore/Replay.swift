import Foundation
#if canImport(Compression)
import Compression
#endif

/// 各ステップの自機移動量の記録。(同じ移動が続く区間を RLE で縮め、さらに zlib 圧縮して Base64 にする)
public struct Replay: Equatable, Sendable {
    public var moves: [Move]
    public init(moves: [Move]) { self.moves = moves }

    private static let rawFlag: UInt8 = 0
    private static let zlibFlag: UInt8 = 1

    public func encoded() -> String {
        var rle = Data()
        var i = 0
        while i < moves.count {
            var n = 1
            while i + n < moves.count, n < 255, moves[i + n] == moves[i] { n += 1 }
            rle.append(UInt8(n))
            rle.append(UInt8(bitPattern: moves[i].dx))
            rle.append(UInt8(bitPattern: moves[i].dy))
            i += n
        }
        var out = Data()
        #if canImport(Compression)
        if let z = try? (rle as NSData).compressed(using: .zlib) as Data {
            out.append(Replay.zlibFlag)
            out.append(z)
            return out.base64EncodedString()
        }
        #endif
        out.append(Replay.rawFlag)
        out.append(rle)
        return out.base64EncodedString()
    }

    public init?(encoded: String) {
        guard let data = Data(base64Encoded: encoded), let flag = data.first else { return nil }
        var rle = data.dropFirst()
        if flag == Replay.zlibFlag {
            #if canImport(Compression)
            guard let d = try? (Data(rle) as NSData).decompressed(using: .zlib) as Data else { return nil }
            rle = d[...]
            #else
            return nil
            #endif
        } else if flag != Replay.rawFlag {
            return nil
        }
        guard rle.count % 3 == 0 else { return nil }
        var moves: [Move] = []
        let bytes = Array(rle)
        var i = 0
        while i < bytes.count {
            let n = Int(bytes[i])
            guard n > 0 else { return nil }
            let m = Move(dx: Int8(bitPattern: bytes[i + 1]), dy: Int8(bitPattern: bytes[i + 2]))
            moves.append(contentsOf: repeatElement(m, count: n))
            i += 3
        }
        self.moves = moves
    }
}
