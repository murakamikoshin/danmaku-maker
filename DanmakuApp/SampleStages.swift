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
        let lang = Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
        return entries.map {
            SampleStage(id: $0.id, title: $0.name[lang] ?? $0.name["en"] ?? $0.id, difficulty: $0.difficulty,
                        aim: $0.aim[lang] ?? "", stage: $0.stage.sanitized())
        }
    }()
}
