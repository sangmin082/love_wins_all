import Foundation
import Observation

/// 전적 저장소 — 난이도별 1인용 전적과 온라인 대전 전적을 기기에 보관한다.
/// (연습 게임은 기록하지 않는다)
@Observable
@MainActor
final class StatsStore {
    static let shared = StatsStore()

    struct Record: Equatable {
        var wins = 0
        var losses = 0

        var games: Int { wins + losses }
        var winRatePercent: Int {
            games == 0 ? 0 : Int((Double(wins) / Double(games) * 100).rounded())
        }
    }

    private(set) var solo: [AIPlayer.Difficulty: Record] = [:]
    private(set) var online = Record()

    var total: Record {
        var record = online
        for r in solo.values {
            record.wins += r.wins
            record.losses += r.losses
        }
        return record
    }

    private init() {
        load()
    }

    func recordSolo(difficulty: AIPlayer.Difficulty, won: Bool) {
        var record = solo[difficulty] ?? Record()
        if won { record.wins += 1 } else { record.losses += 1 }
        solo[difficulty] = record
        save(record, prefix: "solo.\(difficulty.rawValue)")
    }

    func recordOnline(won: Bool) {
        if won { online.wins += 1 } else { online.losses += 1 }
        save(online, prefix: "online")
    }

    func reset() {
        let defaults = UserDefaults.standard
        for difficulty in AIPlayer.Difficulty.allCases {
            defaults.removeObject(forKey: key("solo.\(difficulty.rawValue).wins"))
            defaults.removeObject(forKey: key("solo.\(difficulty.rawValue).losses"))
        }
        defaults.removeObject(forKey: key("online.wins"))
        defaults.removeObject(forKey: key("online.losses"))
        load()
    }

    // MARK: - 저장/로드

    private func key(_ suffix: String) -> String { "stats.\(suffix)" }

    private func load() {
        let defaults = UserDefaults.standard
        for difficulty in AIPlayer.Difficulty.allCases {
            solo[difficulty] = Record(
                wins: defaults.integer(forKey: key("solo.\(difficulty.rawValue).wins")),
                losses: defaults.integer(forKey: key("solo.\(difficulty.rawValue).losses"))
            )
        }
        online = Record(
            wins: defaults.integer(forKey: key("online.wins")),
            losses: defaults.integer(forKey: key("online.losses"))
        )
    }

    private func save(_ record: Record, prefix: String) {
        let defaults = UserDefaults.standard
        defaults.set(record.wins, forKey: key("\(prefix).wins"))
        defaults.set(record.losses, forKey: key("\(prefix).losses"))
    }
}
