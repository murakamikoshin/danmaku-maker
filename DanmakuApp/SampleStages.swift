import DanmakuCore
import Foundation

/// 公式サンプルステージ（易しい→難しい順に30本）。データは Resources/official_stages.json
/// （tools/make_official_stages.py で生成）
struct SampleStage: Identifiable {
    let id: String
    let title: String
    let difficulty: Int
    let aim: String
    let stage: Stage
}

enum SampleStages {
    private struct Entry: Decodable {
        let id: String
        let difficulty: Int
        let name: [String: String]
        let aim: [String: String]
        let stage: Stage
    }

    static let all: [SampleStage] = {
        guard let url = Bundle.main.url(forResource: "official_stages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        // アプリが対応している言語のうち、端末の設定に一番近いもの(例: "ja", "zh-Hans", "pt-BR")
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        // ja / en は official_stages.json、そのほかの言語は official_stages_i18n.json から読む(なければ英語)
        var extra: [String: [String: [String: String]]] = [:]
        if let u = Bundle.main.url(forResource: "official_stages_i18n", withExtension: "json"),
           let d = try? Data(contentsOf: u),
           let m = try? JSONDecoder().decode([String: [String: [String: String]]].self, from: d) { extra = m }
        return entries.map {
            let t = extra[$0.id]?[lang]
            return SampleStage(id: $0.id, title: t?["name"] ?? $0.name[lang] ?? $0.name["en"] ?? $0.id, difficulty: $0.difficulty,
                               aim: t?["aim"] ?? $0.aim[lang] ?? $0.aim["en"] ?? "", stage: $0.stage.sanitized())
        }
    }()
}
