import Foundation

// MARK: - 기본 타입

/// 대국의 두 플레이어.
/// 라운드 1의 선(先)은 추첨 — 로컬(1인용)/서버(2인용)가 플레이어 배정을 랜덤으로 하는 것으로 갈음하며,
/// 배정 결과 `first`가 라운드 1의 선을 맡는다. 2라운드부터는 직전 라운드 승자가 선이 된다.
enum Player: Int, Codable, Equatable, Sendable, CaseIterable {
    case first = 0
    case second = 1

    var opponent: Player { self == .first ? .second : .first }
}

/// 카드 — 가위 12, 바위 7, 보 7, 러브 4장으로 총 30장.
enum Card: Int, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case scissors = 0
    case rock = 1
    case paper = 2
    case love = 3

    var isLove: Bool { self == .love }

    var label: String {
        switch self {
        case .scissors: return "가위"
        case .rock: return "바위"
        case .paper: return "보"
        case .love: return "러브"
        }
    }

    var emoji: String {
        switch self {
        case .scissors: return "✌️"
        case .rock: return "✊"
        case .paper: return "✋"
        case .love: return "💖"
        }
    }

    /// 게임에 쓰는 30장 전체 덱
    static let fullDeck: [Card] =
        Array(repeating: Card.scissors, count: 12)
        + Array(repeating: Card.rock, count: 7)
        + Array(repeating: Card.paper, count: 7)
        + Array(repeating: Card.love, count: 4)
}

/// 족보 — 값이 작을수록 높다.
enum HandRank: Int, Codable, Equatable, Sendable, CaseIterable {
    case loveWinsAll = 1
    case triple = 2
    case twoLove = 3
    case mix = 4
    case double = 5
    case oneLove = 6

    var label: String {
        switch self {
        case .loveWinsAll: return "러브 윈즈 올"
        case .triple: return "트리플"
        case .twoLove: return "투 러브"
        case .mix: return "믹스"
        case .double: return "더블"
        case .oneLove: return "원 러브"
        }
    }

    var summary: String {
        switch self {
        case .loveWinsAll: return "러브 카드 3장"
        case .triple: return "같은 가위바위보 3장"
        case .twoLove: return "러브 카드 2장"
        case .mix: return "가위·바위·보 각 1장"
        case .double: return "러브 없이 같은 가위바위보 2장"
        case .oneLove: return "러브 카드 1장"
        }
    }

    /// `open` 카드를 공개한 상태에서 모순 없이 선언할 수 있는 족보들.
    /// (러브를 공개하면 러브가 없는 족보는 선언할 수 없고,
    ///  가위바위보를 공개하면 러브 윈즈 올은 선언할 수 없다)
    static func plausible(open: Card) -> [HandRank] {
        if open.isLove {
            return [.loveWinsAll, .twoLove, .oneLove]
        }
        return [.triple, .twoLove, .mix, .double, .oneLove]
    }
}

/// 게임 진행 단계
enum Phase: String, Codable, Equatable, Sendable {
    /// 첫 라운드 시작 전
    case idle
    /// 카드 배분 후 1차 베팅
    case betting1
    /// 카드 1장 오픈 + 족보 선언 (선 → 후)
    case declaration
    /// 2차 베팅
    case betting2
    /// (온라인) 서버의 손패 공개를 기다리는 중
    case awaitingReveal
    /// 라운드 정산 완료 — 다음 라운드 대기
    case roundEnd
    /// 매치 종료
    case finished
}

/// 플레이어가 취할 수 있는 행동
enum Move: Codable, Equatable, Sendable {
    /// 체크 (콜할 금액이 없을 때)
    case check
    /// 콜 — 상대 베팅에 맞춘다
    case call
    /// 벳/레이즈 — 콜 위에 얹는 칩 수 (콜할 금액이 없으면 순수 벳)
    case bet(Int)
    /// 폴드 — 라운드 포기 (카드는 공개하지 않는다)
    case fold
    /// 카드 1장 오픈 + 족보 선언 (거짓 선언 가능)
    case declare(open: Card, rank: HandRank)
    /// 기권 — 매치 포기
    case forfeit

    private enum CodingKeys: String, CodingKey { case kind, amount, open, rank }
    private enum Kind: String, Codable { case check, call, bet, fold, declare, forfeit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .check: self = .check
        case .call: self = .call
        case .bet: self = .bet(try c.decode(Int.self, forKey: .amount))
        case .fold: self = .fold
        case .declare: self = .declare(open: try c.decode(Card.self, forKey: .open),
                                       rank: try c.decode(HandRank.self, forKey: .rank))
        case .forfeit: self = .forfeit
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .check: try c.encode(Kind.check, forKey: .kind)
        case .call: try c.encode(Kind.call, forKey: .kind)
        case .bet(let amount):
            try c.encode(Kind.bet, forKey: .kind)
            try c.encode(amount, forKey: .amount)
        case .fold: try c.encode(Kind.fold, forKey: .kind)
        case .declare(let open, let rank):
            try c.encode(Kind.declare, forKey: .kind)
            try c.encode(open, forKey: .open)
            try c.encode(rank, forKey: .rank)
        case .forfeit: try c.encode(Kind.forfeit, forKey: .kind)
        }
    }
}

/// 카드 1장 오픈 + 족보 선언 내용
struct Declaration: Codable, Equatable, Sendable {
    let open: Card
    let rank: HandRank
}

/// 쇼다운 결과
struct ShowdownResult: Codable, Equatable, Sendable {
    let hands: [[Card]]
    let ranks: [HandRank]
    /// nil = 무승부 (팟은 다음 라운드로 이월)
    let winner: Player?
    /// 이번 쇼다운에 걸려 있던 총 칩 (이월 팟 포함)
    let pot: Int
    /// 오픈했던 카드가 실제 손패에 없던 플레이어 (온라인 변조 감지 — 즉시 패배 처리)
    let disqualified: Player?
}

/// 무브 적용 결과 — UI 연출과 AI 관찰에 사용
enum MoveOutcome: Equatable, Sendable {
    /// 라운드 시작 (앤티 납부·카드 배분 완료). `pot`은 이월 포함 총 걸린 칩.
    case roundStarted(round: Int, first: Player, pot: Int)
    case checked(player: Player, phaseClosed: Bool)
    /// `added` = 이번에 실제로 낸 칩(콜 포함), `raised` = 콜 위에 얹은 칩
    case betPlaced(player: Player, added: Int, raised: Int)
    case called(player: Player, added: Int)
    /// 폴드 — 라운드 즉시 종료, 카드는 공개하지 않는다
    case folded(player: Player, winner: Player, pot: Int)
    case declared(player: Player, declaration: Declaration, phaseClosed: Bool)
    /// 쇼다운 정산 완료
    case showdown(ShowdownResult)
    case forfeited(player: Player)
}

enum EngineError: Error, Equatable {
    case gameFinished
    case notYourTurn
    case wrongPhase
    case roundInProgress
    case cannotCheck        // 콜할 금액이 있는데 체크 시도
    case nothingToCall      // 콜할 금액이 없는데 콜 시도
    case invalidBet         // 0 이하이거나 실효 한도(양쪽 스택) 초과
    case cardNotInHand      // 손패에 없는 카드를 오픈 시도
    case alreadyDeclared
    case invalidHands       // 손패 형식 오류 또는 공개 손패가 아는 손패와 불일치
}

// MARK: - 게임 엔진

/// 「러브 윈즈 올」 규칙 상태기계.
/// 순수 값 타입이라 온라인 대전에서 양쪽 기기가 같은 무브 스트림으로 동일 상태를 재현한다.
/// 온라인에서는 상대 손패를 모른 채(nil) 진행하다가 쇼다운에서 서버가 공개한다.
struct GameEngine: Codable, Equatable {
    static let handSize = 3
    static let ante = 1
    static let defaultChips = 25
    /// 연습 게임 시작 칩
    static let practiceChips = 20
    /// 행동 제한 시간 (온라인 잠수 방지 — 방송 규칙에는 없음)
    static let turnTimeLimit: TimeInterval = 60

    private(set) var stacks: [Int]
    /// 이번 라운드에 걸린 칩 (앤티 + 베팅)
    private(set) var pot = 0
    /// 무승부로 이월된 팟
    private(set) var carryover = 0
    private(set) var round = 0
    /// 이번 라운드의 선
    private(set) var firstPlayer: Player = .first
    private(set) var phase: Phase = .idle
    private(set) var currentTurn: Player = .first
    /// 손패 — 모르는 손패(온라인 상대)는 nil
    private(set) var hands: [[Card]?] = [nil, nil]
    /// 현재 베팅 단계에서 각자 커밋한 칩
    private(set) var committed = [0, 0]
    /// 현재 베팅 단계에서 행동을 마쳤는지 (벳이 나오면 상대는 다시 행동해야 한다)
    private(set) var hasActed = [false, false]
    private(set) var declarations: [Declaration?] = [nil, nil]
    private(set) var lastShowdown: ShowdownResult?
    /// 직전 라운드 승자 — 다음 라운드의 선 (무승부면 선 유지)
    private(set) var roundWinner: Player?
    private(set) var matchWinner: Player?
    private(set) var endedByForfeit = false

    init(startingChips: Int = GameEngine.defaultChips) {
        stacks = [startingChips, startingChips]
    }

    // MARK: 조회

    func hand(of player: Player) -> [Card]? { hands[player.rawValue] }

    var isBettingPhase: Bool { phase == .betting1 || phase == .betting2 }

    /// 이월 팟을 포함해 지금 걸려 있는 총 칩
    var totalPot: Int { pot + carryover }

    /// 지금 콜하려면 내야 하는 칩
    func toCall(for player: Player) -> Int {
        max(0, committed[player.opponent.rawValue] - committed[player.rawValue])
    }

    /// 콜 위에 얹을 수 있는 최대 칩 — 상대가 콜할 수 있어야 하므로 양쪽 스택의 실효 한도로 제한
    func maxRaise(for player: Player) -> Int {
        max(0, min(stacks[player.rawValue] - toCall(for: player),
                   stacks[player.opponent.rawValue]))
    }

    // MARK: 라운드 시작

    /// 30장 전체를 섞어 3장씩 나눈다 (매 라운드 리셔플)
    static func deal(using rng: inout some RandomNumberGenerator) -> [[Card]] {
        let deck = Card.fullDeck.shuffled(using: &rng)
        return [Array(deck[0..<handSize]), Array(deck[handSize..<(handSize * 2)])]
    }

    /// 라운드 시작 — 앤티를 걷고 손패를 배정한다.
    /// 1인용은 양쪽 손패를 모두 넘기고, 온라인은 자기 손패만 넘긴다(상대는 nil).
    @discardableResult
    mutating func startRound(hands newHands: [[Card]?]) throws -> MoveOutcome {
        guard matchWinner == nil else { throw EngineError.gameFinished }
        guard phase == .idle || phase == .roundEnd else { throw EngineError.roundInProgress }
        guard newHands.count == 2 else { throw EngineError.invalidHands }
        for hand in newHands where hand != nil {
            guard hand!.count == Self.handSize else { throw EngineError.invalidHands }
        }

        if let roundWinner { firstPlayer = roundWinner }
        round += 1
        hands = newHands
        declarations = [nil, nil]
        lastShowdown = nil

        // 앤티 — 스택이 0이면(이월 팟 올인 상황) 내지 않고 진행한다
        for index in stacks.indices {
            let ante = min(Self.ante, stacks[index])
            stacks[index] -= ante
            pot += ante
        }
        beginBetting(.betting1)
        return .roundStarted(round: round, first: firstPlayer, pot: totalPot)
    }

    // MARK: 무브 적용

    @discardableResult
    mutating func apply(_ move: Move, by player: Player) throws -> MoveOutcome {
        guard phase != .finished else { throw EngineError.gameFinished }

        // 기권은 상대 턴 중에도 가능
        if case .forfeit = move {
            phase = .finished
            matchWinner = player.opponent
            endedByForfeit = true
            return .forfeited(player: player)
        }

        guard player == currentTurn else { throw EngineError.notYourTurn }
        let me = player.rawValue
        let opponent = player.opponent

        switch move {
        case .check:
            guard isBettingPhase else { throw EngineError.wrongPhase }
            guard toCall(for: player) == 0 else { throw EngineError.cannotCheck }
            hasActed[me] = true
            let closed = hasActed[opponent.rawValue]
            if closed {
                closeBettingPhase()
            } else {
                currentTurn = opponent
            }
            return .checked(player: player, phaseClosed: closed)

        case .call:
            guard isBettingPhase else { throw EngineError.wrongPhase }
            let owed = toCall(for: player)
            guard owed > 0 else { throw EngineError.nothingToCall }
            stacks[me] -= owed
            pot += owed
            committed[me] += owed
            closeBettingPhase()
            return .called(player: player, added: owed)

        case .bet(let raised):
            guard isBettingPhase else { throw EngineError.wrongPhase }
            guard raised >= 1, raised <= maxRaise(for: player) else { throw EngineError.invalidBet }
            let added = toCall(for: player) + raised
            stacks[me] -= added
            pot += added
            committed[me] += added
            hasActed[me] = true
            hasActed[opponent.rawValue] = false // 상대는 콜/레이즈/폴드로 응수해야 한다
            currentTurn = opponent
            return .betPlaced(player: player, added: added, raised: raised)

        case .fold:
            guard isBettingPhase else { throw EngineError.wrongPhase }
            let winnings = totalPot
            stacks[opponent.rawValue] += winnings
            pot = 0
            carryover = 0
            roundWinner = opponent
            finishRound()
            return .folded(player: player, winner: opponent, pot: winnings)

        case .declare(let open, let rank):
            guard phase == .declaration else { throw EngineError.wrongPhase }
            guard declarations[me] == nil else { throw EngineError.alreadyDeclared }
            if let hand = hands[me], !hand.contains(open) { throw EngineError.cardNotInHand }
            let declaration = Declaration(open: open, rank: rank)
            declarations[me] = declaration
            let closed = declarations[opponent.rawValue] != nil
            if closed {
                beginBetting(.betting2)
            } else {
                currentTurn = opponent
            }
            return .declared(player: player, declaration: declaration, phaseClosed: closed)

        case .forfeit:
            fatalError("위에서 처리됨")
        }
    }

    /// (온라인) 서버가 공개한 양쪽 손패로 쇼다운을 정산한다.
    @discardableResult
    mutating func applyReveal(hands revealedHands: [[Card]]) throws -> MoveOutcome {
        guard phase == .awaitingReveal else { throw EngineError.wrongPhase }
        guard revealedHands.count == 2,
              revealedHands.allSatisfy({ $0.count == Self.handSize }) else {
            throw EngineError.invalidHands
        }
        // 내가 아는 손패와 서버 공개가 일치해야 한다
        for player in Player.allCases {
            if let known = hands[player.rawValue],
               known.sorted(by: { $0.rawValue < $1.rawValue })
                != revealedHands[player.rawValue].sorted(by: { $0.rawValue < $1.rawValue }) {
                throw EngineError.invalidHands
            }
        }
        resolveShowdown(with: revealedHands)
        return .showdown(lastShowdown!)
    }

    // MARK: - 내부 전이

    private mutating func beginBetting(_ bettingPhase: Phase) {
        phase = bettingPhase
        committed = [0, 0]
        hasActed = [false, false]
        currentTurn = firstPlayer
        // 어느 한 쪽이 올인(스택 0)이면 베팅이 성립하지 않으므로 자동으로 건너뛴다
        if stacks[0] == 0 || stacks[1] == 0 {
            closeBettingPhase()
        }
    }

    private mutating func closeBettingPhase() {
        if phase == .betting1 {
            phase = .declaration
            currentTurn = firstPlayer
        } else {
            // 2차 베팅 종료 → 쇼다운. 상대 손패를 모르면(온라인) 서버 공개를 기다린다.
            if let first = hands[0], let second = hands[1] {
                resolveShowdown(with: [first, second])
            } else {
                phase = .awaitingReveal
            }
        }
    }

    private mutating func resolveShowdown(with revealedHands: [[Card]]) {
        let ranks = revealedHands.map(HandEvaluator.evaluate)

        // 오픈했던 카드가 실제 손패에 없으면(변조된 클라이언트) 해당 플레이어 즉시 패배
        var invalid: [Player] = []
        for player in Player.allCases {
            if let declaration = declarations[player.rawValue],
               !revealedHands[player.rawValue].contains(declaration.open) {
                invalid.append(player)
            }
        }

        let winner: Player?
        let disqualified: Player?
        if invalid.count == 1 {
            disqualified = invalid[0]
            winner = invalid[0].opponent
        } else {
            disqualified = nil // 양쪽 모두 변조면 무승부 처리
            if invalid.isEmpty {
                let comparison = HandEvaluator.compare(revealedHands[0], revealedHands[1])
                winner = comparison > 0 ? .first : (comparison < 0 ? .second : nil)
            } else {
                winner = nil
            }
        }

        let winnings = totalPot
        if let winner {
            stacks[winner.rawValue] += winnings
            carryover = 0
            roundWinner = winner
        } else {
            carryover += pot // 무승부 — 이월, 선 유지
        }
        pot = 0
        hands = [revealedHands[0], revealedHands[1]]
        lastShowdown = ShowdownResult(hands: revealedHands, ranks: ranks,
                                      winner: winner, pot: winnings,
                                      disqualified: disqualified)
        finishRound()
    }

    private mutating func finishRound() {
        // 다음 라운드 앤티조차 낼 수 없는 쪽이 있으면 매치 종료.
        // (이월 팟이 남아 있으면 그 팟을 두고 계속 진행한다 — 앤티·베팅 없이 쇼다운만)
        if carryover == 0, let loser = Player.allCases.first(where: { stacks[$0.rawValue] == 0 }) {
            phase = .finished
            matchWinner = loser.opponent
        } else {
            phase = .roundEnd
        }
    }
}
