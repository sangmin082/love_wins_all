import Foundation

/// 족보 판정·비교 — 순수 함수만 모아 엔진에서 분리했다 (전수 테스트 대상).
enum HandEvaluator {
    /// 3장 손패는 반드시 6가지 족보 중 정확히 하나로 분류된다.
    /// 러브가 1장이면 나머지 2장이 페어여도 원 러브다 ("더블은 러브 없이"이므로).
    static func evaluate(_ hand: [Card]) -> HandRank {
        switch hand.filter(\.isLove).count {
        case 3: return .loveWinsAll
        case 2: return .twoLove
        case 1: return .oneLove
        default:
            switch Set(hand).count {
            case 1: return .triple
            case 3: return .mix
            default: return .double
            }
        }
    }

    /// 가위바위보 상성: a가 이기면 1, 지면 -1, 같으면 0. (러브는 상성이 없다)
    static func rpsCompare(_ a: Card, _ b: Card) -> Int {
        guard a != b, !a.isLove, !b.isLove else { return 0 }
        switch (a, b) {
        case (.scissors, .paper), (.paper, .rock), (.rock, .scissors): return 1
        default: return -1
        }
    }

    /// 손패 비교: 양수면 a 승, 음수면 b 승, 0이면 무승부.
    ///
    /// 족보가 다르면 높은 족보가 이기고, 같으면:
    /// - 트리플: 트리플 타입의 상성 (같은 타입이면 나머지 카드가 없으므로 무승부)
    /// - 투 러브: 나머지 1장의 상성
    /// - 믹스: 구성이 항상 같으므로 무승부
    /// - 더블: 페어 타입의 상성 → 같으면 나머지 1장의 상성
    /// - 원 러브: 규칙상 즉시 무승부 (나머지 카드를 비교하지 않는다)
    /// - 러브 윈즈 올: 러브가 4장뿐이라 맞대결이 물리적으로 불가능 (무승부 처리)
    static func compare(_ a: [Card], _ b: [Card]) -> Int {
        let rankA = evaluate(a)
        let rankB = evaluate(b)
        if rankA != rankB {
            return rankA.rawValue < rankB.rawValue ? 1 : -1
        }
        switch rankA {
        case .loveWinsAll, .oneLove, .mix:
            return 0
        case .triple:
            return rpsCompare(a[0], b[0])
        case .twoLove:
            return rpsCompare(nonLove(a), nonLove(b))
        case .double:
            let (pairA, singleA) = pairAndSingle(a)
            let (pairB, singleB) = pairAndSingle(b)
            let byPair = rpsCompare(pairA, pairB)
            return byPair != 0 ? byPair : rpsCompare(singleA, singleB)
        }
    }

    /// 투 러브의 나머지 1장 (러브가 아닌 카드)
    private static func nonLove(_ hand: [Card]) -> Card {
        hand.first { !$0.isLove }!
    }

    /// 더블의 (페어 타입, 나머지 1장)
    private static func pairAndSingle(_ hand: [Card]) -> (pair: Card, single: Card) {
        let groups = Dictionary(grouping: hand) { $0 }
        let pair = groups.first { $0.value.count == 2 }!.key
        let single = groups.first { $0.value.count == 1 }!.key
        return (pair, single)
    }
}
