import Foundation

/// 1인용 모드의 AI 상대.
///
/// 이 게임의 본질인 "승률 계산과 심리전"을 모델링한다:
/// 내 손패를 제외한 27장에서 상대 손패를 몬테카를로 샘플링해 승률을 추정하고,
/// 팟 오즈와 비교해 베팅을 결정한다. 상대의 오픈 카드·족보 선언은 난이도별 신뢰도로 반영하며,
/// 난이도에 따라 블러핑(약패 베팅, 거짓 선언)을 섞는다.
/// 엔진의 비공개 상태(상대 손패)는 절대 직접 읽지 않는다.
struct AIPlayer {
    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, normal, hard

        var id: String { rawValue }
        var label: String {
            switch self {
            case .easy: return "쉬움"
            case .normal: return "보통"
            case .hard: return "어려움"
            }
        }
        /// 승률 추정에 쓰는 샘플 수 (많을수록 정확)
        var samples: Int {
            switch self {
            case .easy: return 120
            case .normal: return 400
            case .hard: return 1200
            }
        }
        /// 판단 노이즈 — 추정 승률에 더해지는 오차 폭
        var noise: Double {
            switch self {
            case .easy: return 0.18
            case .normal: return 0.08
            case .hard: return 0.03
            }
        }
        /// 약패로 베팅하는 블러프 빈도
        var bluffRate: Double {
            switch self {
            case .easy: return 0.04
            case .normal: return 0.12
            case .hard: return 0.22
            }
        }
        /// 족보를 거짓으로 선언하는 빈도
        var lieRate: Double {
            switch self {
            case .easy: return 0.05
            case .normal: return 0.18
            case .hard: return 0.35
            }
        }
        /// 상대 선언을 얼마나 믿는가 — 선언과 일치하는 샘플에 주는 가중치 배수.
        /// 쉬움은 곧이곧대로 믿고, 어려움은 블러핑 가능성을 크게 의심한다.
        var declarationTrust: Double {
            switch self {
            case .easy: return 4.0
            case .normal: return 2.0
            case .hard: return 1.3
            }
        }
    }

    let difficulty: Difficulty
    let me: Player

    private var myHand: [Card] = []
    private var opponentDeclaration: Declaration?
    private var rng = SystemRandomNumberGenerator()

    init(difficulty: Difficulty, me: Player) {
        self.difficulty = difficulty
        self.me = me
    }

    // MARK: - 관찰

    mutating func startRound(hand: [Card]) {
        myHand = hand
        opponentDeclaration = nil
    }

    /// 엔진 outcome을 흘려 넣어 상대 정보를 갱신한다
    mutating func observe(_ outcome: MoveOutcome) {
        if case .declared(let player, let declaration, _) = outcome, player != me {
            opponentDeclaration = declaration
        }
    }

    // MARK: - 승률 추정 (몬테카를로)

    /// 상대 손패를 남은 카드에서 샘플링해 승률(무승부는 0.5)을 추정한다.
    /// 상대가 오픈한 카드는 고정하고, 선언과 일치하는 샘플에는 신뢰도 가중치를 준다.
    private mutating func winProbability() -> Double {
        var remaining = Card.fullDeck
        for card in myHand {
            if let index = remaining.firstIndex(of: card) { remaining.remove(at: index) }
        }
        var fixed: [Card] = []
        if let open = opponentDeclaration?.open,
           let index = remaining.firstIndex(of: open) {
            remaining.remove(at: index)
            fixed = [open]
        }

        var score = 0.0
        var total = 0.0
        for _ in 0..<difficulty.samples {
            var sample = fixed
            var pool = remaining
            while sample.count < GameEngine.handSize {
                let index = Int.random(in: 0..<pool.count, using: &rng)
                sample.append(pool.remove(at: index))
            }
            var weight = 1.0
            if let declared = opponentDeclaration?.rank,
               HandEvaluator.evaluate(sample) == declared {
                weight = difficulty.declarationTrust
            }
            total += weight
            switch HandEvaluator.compare(myHand, sample) {
            case let c where c > 0: score += weight
            case 0: score += weight / 2
            default: break
            }
        }
        return total > 0 ? score / total : 0.5
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &rng) < probability
    }

    // MARK: - 베팅 결정

    mutating func chooseBettingAction(engine: GameEngine) -> Move {
        let toCall = engine.toCall(for: me)
        let maxRaise = engine.maxRaise(for: me)
        let potTotal = engine.totalPot
        let equity = winProbability()
            + Double.random(in: -difficulty.noise...difficulty.noise, using: &rng)

        if toCall == 0 {
            if maxRaise >= 1 {
                if equity > 0.78 {
                    return .bet(valueBet(pot: potTotal, cap: maxRaise, big: true))
                }
                if equity > 0.60 {
                    return .bet(valueBet(pot: potTotal, cap: maxRaise, big: false))
                }
                if equity < 0.45, chance(difficulty.bluffRate) {
                    return .bet(valueBet(pot: potTotal, cap: maxRaise, big: true)) // 블러프
                }
            }
            return .check
        }

        let potOdds = Double(toCall) / Double(potTotal + toCall)
        if equity > 0.80, maxRaise >= 1, chance(0.6) {
            return .bet(valueBet(pot: potTotal, cap: maxRaise, big: true)) // 재레이즈
        }
        if equity >= potOdds - 0.03 {
            return .call
        }
        if maxRaise >= 1, chance(difficulty.bluffRate * 0.4) {
            return .bet(valueBet(pot: potTotal, cap: maxRaise, big: true)) // 블러프 레이즈
        }
        return .fold
    }

    private func valueBet(pot: Int, cap: Int, big: Bool) -> Int {
        let target = big ? max(pot, 2) : max(pot / 2, 1)
        return min(max(target, 1), cap)
    }

    // MARK: - 선언 결정 (오픈할 카드 + 족보)

    mutating func chooseDeclaration(engine: GameEngine) -> Move {
        let trueRank = HandEvaluator.evaluate(myHand)
        let isStrong = trueRank.rawValue <= HandRank.twoLove.rawValue

        // 오픈할 카드 — 어려운 AI는 러브를 숨기고, 쉬운 AI는 아무거나 연다
        let open: Card
        switch difficulty {
        case .easy:
            open = myHand.randomElement(using: &rng)!
        case .normal, .hard:
            let nonLoves = myHand.filter { !$0.isLove }
            open = (nonLoves.isEmpty ? myHand : nonLoves).randomElement(using: &rng)!
        }

        // 선언할 족보 — 오픈 카드와 모순되지 않는 범위에서 거짓말을 섞는다
        var rank = trueRank
        if chance(difficulty.lieRate) {
            let plausible = HandRank.plausible(open: open).filter { $0 != trueRank }
            let lies: [HandRank]
            if isStrong {
                // 강패 → 약한 족보로 위장해 베팅을 유도
                lies = plausible.filter { $0.rawValue > trueRank.rawValue }
            } else {
                // 약패 → 강한 족보로 과장해 폴드를 유도
                lies = plausible.filter { $0.rawValue < trueRank.rawValue }
            }
            if let lie = (lies.isEmpty ? plausible : lies).randomElement(using: &rng) {
                rank = lie
            }
        }
        // 진실 선언이 오픈 카드와 모순인 경우는 없다 (오픈 카드는 실제 손패이므로)
        return .declare(open: open, rank: rank)
    }
}
