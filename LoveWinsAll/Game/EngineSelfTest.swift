import Foundation

/// 엔진 규칙 검증 — 족보 판정·비교 전수 테스트와 라운드 시나리오 리플레이,
/// AI 대량 자동 대국 불변식 검사. DEBUG 빌드에서 앱 시작 시 1회 실행된다.
enum EngineSelfTest {
    static func run() {
        #if DEBUG
        do {
            try runAllTests()
            print("[EngineSelfTest] 족보·베팅·시나리오 검증 통과 ✅")
        } catch {
            assertionFailure("[EngineSelfTest] 엔진 규칙 검증 실패: \(error)")
        }
        #endif
    }

    enum TestError: Error, CustomStringConvertible {
        case mismatch(String)
        var description: String {
            if case .mismatch(let message) = self { return message }
            return "unknown"
        }
    }

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw TestError.mismatch(message()) }
    }

    static func runAllTests() throws {
        try evaluateTests()
        try compareTruthTable()
        try compareConsistency()
        try scenarioBasicRound()
        try scenarioFold()
        try scenarioDrawCarryover()
        try scenarioAllIn()
        try scenarioZeroStackCarryover()
        try scenarioOnlineReveal()
        try scenarioCheatDetection()
        try randomPlayouts()
    }

    // MARK: - 족보 판정

    private static let S = Card.scissors, R = Card.rock, P = Card.paper, L = Card.love

    private static func evaluateTests() throws {
        let cases: [([Card], HandRank)] = [
            ([L, L, L], .loveWinsAll),
            ([S, S, S], .triple), ([R, R, R], .triple), ([P, P, P], .triple),
            ([L, L, S], .twoLove), ([L, S, L], .twoLove), ([P, L, L], .twoLove),
            ([S, R, P], .mix), ([P, S, R], .mix),
            ([S, S, R], .double), ([R, P, P], .double), ([R, S, S], .double),
            ([L, S, R], .oneLove), ([S, P, L], .oneLove),
            // 핵심: 러브 1장 + 페어는 더블이 아니라 원 러브 ("더블은 러브 없이")
            ([S, S, L], .oneLove), ([L, R, R], .oneLove), ([P, L, P], .oneLove),
        ]
        for (hand, expected) in cases {
            let got = HandEvaluator.evaluate(hand)
            try expect(got == expected, "evaluate(\(hand)) = \(got) ≠ \(expected)")
        }
    }

    // MARK: - 족보 비교 진리표

    private static func compareTruthTable() throws {
        // (a, b, 기대 부호) — 양수 a승 / 음수 b승 / 0 무승부
        let cases: [([Card], [Card], Int)] = [
            // 족보 순위가 다르면 높은 쪽 승
            ([L, L, L], [S, S, S], 1),      // 러브 윈즈 올 > 트리플
            ([S, S, S], [L, L, P], 1),      // 트리플 > 투 러브
            ([L, L, S], [S, R, P], 1),      // 투 러브 > 믹스
            ([S, R, P], [S, S, R], 1),      // 믹스 > 더블
            ([S, S, R], [L, S, R], 1),      // 더블 > 원 러브
            ([L, S, S], [S, S, R], -1),     // 원 러브(페어 포함) < 더블
            // 트리플: 타입 상성, 같은 타입이면 무승부
            ([S, S, S], [P, P, P], 1),      // 가위 > 보
            ([S, S, S], [R, R, R], -1),     // 가위 < 바위
            ([P, P, P], [R, R, R], 1),      // 보 > 바위
            ([S, S, S], [S, S, S], 0),
            // 투 러브: 나머지 1장 상성
            ([L, L, S], [L, L, P], 1),
            ([L, L, R], [L, L, S], 1),
            ([L, L, P], [L, L, R], 1),
            ([L, L, S], [L, L, S], 0),
            // 믹스: 항상 무승부
            ([S, R, P], [P, R, S], 0),
            // 더블: 페어 상성 → 같으면 나머지 1장 상성
            ([S, S, R], [P, P, R], 1),      // 가위 페어 > 보 페어
            ([R, R, S], [P, P, S], -1),     // 바위 페어 < 보 페어
            ([S, S, P], [S, S, R], 1),      // 페어 동률 → 보 > 바위
            ([S, S, R], [S, S, R], 0),
            // 원 러브: 나머지를 비교하지 않고 즉시 무승부
            ([L, S, S], [L, R, R], 0),
            ([L, S, R], [L, P, P], 0),
        ]
        for (a, b, expected) in cases {
            let got = HandEvaluator.compare(a, b)
            try expect(got.signum() == expected.signum(),
                       "compare(\(a), \(b)) = \(got) ≠ 기대 부호 \(expected)")
        }
    }

    /// 반대칭성: 가능한 모든 손패 조합 쌍에서 compare(a,b) == -compare(b,a)
    private static func compareConsistency() throws {
        var multisets: [[Card]] = []
        let all = Card.allCases
        for i in 0..<all.count {
            for j in i..<all.count {
                for k in j..<all.count {
                    multisets.append([all[i], all[j], all[k]])
                }
            }
        }
        try expect(multisets.count == 20, "3장 멀티셋은 20가지여야 함 (\(multisets.count))")
        for a in multisets {
            for b in multisets {
                let ab = HandEvaluator.compare(a, b)
                let ba = HandEvaluator.compare(b, a)
                try expect(ab.signum() == -ba.signum(), "반대칭성 위반: \(a) vs \(b)")
            }
            try expect(HandEvaluator.compare(a, a) == 0, "자기 자신과 무승부가 아님: \(a)")
        }
    }

    // MARK: - 라운드 시나리오

    /// 기본 라운드: 앤티 → 체크-체크 → 선언 → 벳-콜 → 쇼다운
    private static func scenarioBasicRound() throws {
        var engine = GameEngine()
        try engine.startRound(hands: [[S, S, S], [R, R, P]])
        try expect(engine.stacks == [24, 24] && engine.pot == 2, "앤티 후 24/24, 팟 2")
        try expect(engine.phase == .betting1 && engine.currentTurn == .first, "1차 베팅, 선부터")

        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try expect(engine.phase == .declaration, "체크-체크 → 선언 단계")

        try engine.apply(.declare(open: S, rank: .triple), by: .first)
        try engine.apply(.declare(open: R, rank: .triple), by: .second) // 거짓 선언 (실제 더블)
        try expect(engine.phase == .betting2, "양쪽 선언 → 2차 베팅")

        try engine.apply(.bet(3), by: .first)
        try expect(engine.toCall(for: .second) == 3, "후는 3 콜해야 함")
        try engine.apply(.call, by: .second)

        try expect(engine.phase == .roundEnd, "쇼다운 후 라운드 종료")
        let result = try require(engine.lastShowdown)
        try expect(result.ranks == [.triple, .double] && result.winner == .first && result.pot == 8,
                   "가위 트리플이 더블을 이기고 팟 8 획득")
        try expect(engine.stacks == [29, 21], "정산 후 29/21")

        // 승자가 다음 라운드 선
        try engine.startRound(hands: [[L, S, R], [P, P, R]])
        try expect(engine.firstPlayer == .first && engine.round == 2, "라운드 2의 선 = 직전 승자")
    }

    /// 폴드: 팟은 상대에게, 카드는 공개하지 않는다
    private static func scenarioFold() throws {
        var engine = GameEngine()
        try engine.startRound(hands: [[S, S, R], [L, L, L]])
        try engine.apply(.bet(5), by: .first)
        let outcome = try engine.apply(.fold, by: .second)
        try expect(outcome == .folded(player: .second, winner: .first, pot: 7), "폴드 팟 7")
        try expect(engine.stacks == [26, 24] && engine.lastShowdown == nil,
                   "폴드 정산 26/24, 쇼다운 없음(카드 비공개)")
        try expect(engine.phase == .roundEnd, "라운드 종료")
    }

    /// 무승부: 팟 이월, 선 유지, 다음 라운드 승자가 이월 팟까지 획득
    private static func scenarioDrawCarryover() throws {
        var engine = GameEngine()
        try engine.startRound(hands: [[S, R, P], [P, R, S]]) // 믹스 vs 믹스 = 무승부
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try engine.apply(.declare(open: S, rank: .mix), by: .first)
        try engine.apply(.declare(open: P, rank: .mix), by: .second)
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        let draw = try require(engine.lastShowdown)
        try expect(draw.winner == nil && engine.carryover == 2 && engine.stacks == [24, 24],
                   "무승부 — 팟 2 이월")

        try engine.startRound(hands: [[R, R, R], [S, S, P]])
        try expect(engine.firstPlayer == .first, "무승부 후 선 유지")
        try expect(engine.totalPot == 4, "이월 2 + 앤티 2")
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try engine.apply(.declare(open: R, rank: .triple), by: .first)
        try engine.apply(.declare(open: S, rank: .double), by: .second)
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try expect(engine.stacks == [27, 23] && engine.carryover == 0,
                   "다음 라운드 승자가 이월 팟까지 획득 (27/23)")
    }

    /// 올인: 베팅 한도는 양쪽 스택의 실효 한도, 올인 뒤 베팅 단계는 자동 생략
    private static func scenarioAllIn() throws {
        var engine = GameEngine(startingChips: 3)
        try engine.startRound(hands: [[S, S, S], [P, P, P]])
        try expect(engine.stacks == [2, 2], "앤티 후 2/2")

        // 한도 초과 베팅은 거부
        do {
            try engine.apply(.bet(5), by: .first)
            try expect(false, "한도 초과 베팅이 허용됨")
        } catch let error as EngineError {
            try expect(error == .invalidBet, "invalidBet이어야 함 (\(error))")
        }

        try engine.apply(.bet(2), by: .first) // 올인
        try expect(engine.maxRaise(for: .second) == 0, "상대는 레이즈 불가(스택 한도)")
        try engine.apply(.call, by: .second)
        try expect(engine.stacks == [0, 0] && engine.phase == .declaration,
                   "양쪽 올인 → 선언 단계로")

        try engine.apply(.declare(open: S, rank: .triple), by: .first)
        try engine.apply(.declare(open: P, rank: .triple), by: .second)
        // 2차 베팅은 올인 상태라 자동 생략 → 즉시 쇼다운
        try expect(engine.phase == .finished, "가위 트리플 승리로 매치 종료")
        try expect(engine.matchWinner == .first && engine.stacks == [6, 0], "승자가 전부 획득")
    }

    /// 양쪽 올인 무승부 → 스택 0인 채로 이월 팟을 두고 앤티·베팅 없이 계속 진행
    private static func scenarioZeroStackCarryover() throws {
        var engine = GameEngine(startingChips: 2)
        try engine.startRound(hands: [[S, R, P], [P, R, S]])
        try engine.apply(.bet(1), by: .first) // 올인
        try engine.apply(.call, by: .second)
        try engine.apply(.declare(open: S, rank: .mix), by: .first)
        try engine.apply(.declare(open: P, rank: .mix), by: .second)
        // 믹스 vs 믹스 무승부 → 이월. 스택 0이지만 매치는 계속
        try expect(engine.phase == .roundEnd && engine.carryover == 4 && engine.stacks == [0, 0],
                   "올인 무승부 — 팟 4 이월, 매치 계속")

        try engine.startRound(hands: [[R, R, S], [P, P, S]])
        // 앤티 없음, 베팅 자동 생략 → 바로 선언
        try expect(engine.phase == .declaration && engine.totalPot == 4, "앤티·베팅 생략")
        try engine.apply(.declare(open: R, rank: .double), by: .first)
        try engine.apply(.declare(open: P, rank: .double), by: .second)
        try expect(engine.phase == .finished && engine.matchWinner == .second,
                   "보 페어 > 바위 페어 — 이월 팟 획득으로 매치 종료")
        try expect(engine.stacks == [0, 4], "최종 0/4")
    }

    /// 온라인: 상대 손패를 모른 채 진행 → awaitingReveal → 서버 공개로 정산
    private static func scenarioOnlineReveal() throws {
        var engine = GameEngine()
        try engine.startRound(hands: [[S, S, S], nil])
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try engine.apply(.declare(open: S, rank: .triple), by: .first)
        try engine.apply(.declare(open: P, rank: .triple), by: .second) // 상대 선언은 검증 불가(손패 모름)
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try expect(engine.phase == .awaitingReveal, "손패를 모르면 공개 대기")

        // 내 손패와 다른 공개는 거부
        do {
            try engine.applyReveal(hands: [[S, S, R], [P, P, P]])
            try expect(false, "불일치 공개가 허용됨")
        } catch let error as EngineError {
            try expect(error == .invalidHands, "invalidHands여야 함 (\(error))")
        }

        try engine.applyReveal(hands: [[S, S, S], [P, P, P]])
        let result = try require(engine.lastShowdown)
        try expect(result.winner == .first && engine.stacks == [26, 24],
                   "가위 트리플 승리 — 26/24")
    }

    /// 변조 감지: 오픈했던 카드가 공개된 손패에 없으면 해당 플레이어 즉시 패배
    private static func scenarioCheatDetection() throws {
        var engine = GameEngine()
        try engine.startRound(hands: [[S, S, S], nil])
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try engine.apply(.declare(open: S, rank: .triple), by: .first)
        try engine.apply(.declare(open: L, rank: .loveWinsAll), by: .second) // 러브를 오픈했다고 주장
        try engine.apply(.check, by: .first)
        try engine.apply(.check, by: .second)
        try engine.applyReveal(hands: [[S, S, S], [P, P, P]]) // 실제 손패에 러브 없음
        let result = try require(engine.lastShowdown)
        try expect(result.disqualified == .second && result.winner == .first,
                   "변조 플레이어 즉시 패배")
    }

    // MARK: - AI 자동 대국 불변식

    /// AI vs AI 자동 대국: 칩 총량 보존, 모든 무브 유효, 매치 종결 보장
    private static func randomPlayouts() throws {
        var rng = SystemRandomNumberGenerator()
        let difficulties = AIPlayer.Difficulty.allCases
        for matchIndex in 0..<60 {
            let chips = matchIndex % 2 == 0 ? GameEngine.defaultChips : GameEngine.practiceChips
            let total = chips * 2
            var engine = GameEngine(startingChips: chips)
            var ais = [
                AIPlayer(difficulty: difficulties[matchIndex % 3], me: .first),
                AIPlayer(difficulty: difficulties[(matchIndex + 1) % 3], me: .second),
            ]
            var steps = 0
            while engine.matchWinner == nil {
                steps += 1
                try expect(steps < 100_000, "매치가 종결되지 않음 (\(matchIndex))")
                switch engine.phase {
                case .idle, .roundEnd:
                    let hands = GameEngine.deal(using: &rng)
                    try engine.startRound(hands: [hands[0], hands[1]])
                    ais[0].startRound(hand: hands[0])
                    ais[1].startRound(hand: hands[1])
                case .betting1, .betting2:
                    let player = engine.currentTurn
                    let move = ais[player.rawValue].chooseBettingAction(engine: engine)
                    let outcome = try engine.apply(move, by: player)
                    ais[0].observe(outcome)
                    ais[1].observe(outcome)
                case .declaration:
                    let player = engine.currentTurn
                    let move = ais[player.rawValue].chooseDeclaration(engine: engine)
                    let outcome = try engine.apply(move, by: player)
                    ais[0].observe(outcome)
                    ais[1].observe(outcome)
                case .awaitingReveal:
                    try expect(false, "1인용 대국에서 공개 대기 발생")
                case .finished:
                    break
                }
                let sum = engine.stacks[0] + engine.stacks[1] + engine.pot + engine.carryover
                try expect(sum == total, "칩 총량 위반: \(sum) ≠ \(total)")
            }
            let winnerStack = engine.stacks[engine.matchWinner!.rawValue]
            if !engine.endedByForfeit {
                try expect(winnerStack == total, "승자가 전체 칩을 획득하지 못함 (\(engine.stacks))")
            }
        }
    }

    /// 옵셔널 언랩 헬퍼
    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestError.mismatch("nil이 아니어야 함") }
        return value
    }
}
