import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Firebase の初期化。GoogleService-Info.plist が無い場合はオフライン動作（サンプルだけ遊べる）になる
enum Backend {
    private(set) static var isAvailable = false
    static let region = "asia-northeast1"

    static var functions: Functions { Functions.functions(region: region) }

    /// 弾幕バトルの通信用(Realtime Database、シンガポール)。エミュレーターのときは configure で差し替える
    static let databaseURL = "https://danmaku-maker-default-rtdb.asia-southeast1.firebasedatabase.app"
    static var database: Database { Database.database(url: databaseURL) }

    static func configure() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-use-emulator") {
            // エミュレーター用のダミー設定（ホストは `-emulator-host <host>`、既定は localhost）
            let options = FirebaseOptions(googleAppID: "1:1234567890:ios:abcdef", gcmSenderID: "1234567890")
            options.projectID = "demo-danmaku"
            // Firebase の部品(Installations など)は、API キーの形(AIza で始まる 39 文字)を起動時に確かめて、違うと落ちる。形だけ本物に合わせた偽物にする
            options.apiKey = "AIzaSyDemoDemoDemoDemoDemoDemoDemo00000"
            FirebaseApp.configure(options: options)
            let host = args.firstIndex(of: "-emulator-host").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "localhost"
            Auth.auth().useEmulator(withHost: host, port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "\(host):8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
            functions.useEmulator(withHost: host, port: 5001)
            database.useEmulator(withHost: host, port: 9000)
            isAvailable = true
        } else if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            isAvailable = true
        }
    }
}
