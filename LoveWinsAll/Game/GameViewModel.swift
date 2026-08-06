import Foundation
import Observation

/// 한 판의 대국(매치)을 진행하는 뷰모델.
/// 1인용은 AI가 상대 무브를 만들고 카드도 로컬에서 배분한다.
/// 2인용은 서버가 카드를 배분(자기 손패만 전달)하고 RoomClient가 상대 무브를 전달한다.
/// 양쪽 모두 동일한 `GameEngine`을 통해 상태가 결정된다.
@Observable
@MainActor
final class GameViewModel {
    enum Mode {
        case solo(AIPlayer.Difficulty)
        case online(RoomClient)
    }

    let mode: Mode
    /// 연습 게임 (칩 20개, 전적 미기록)
    let isPractice: Bool
    private(set) var engine: GameEngine
    private(set) var localPlayer: Player

    /// 상단 안내 문구
    private(set) var banner = ""
    /// 내 차례 남은 시간 (초)
    private(set) var secondsLeft = Int(GameEngine.turnTimeLimit)
    /// 상대가 나갔는지 (온라인)
    var opponentLeft = false

    /// 선언 단계에서 선택 중인 오픈 카드 (탭으로 선택 → 족보 선택)
    var selectedOpenCard: Card?
    /// 레이즈 입력값
    var betAmount = 1
    /// 레이즈 입력 UI 표시 여부
    var showBetControls = false

    private var ai: AIPlayer?
    private var aiTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var rng = SystemRandomNumberGenerator()
    private var statsRecorded = false
    /// (온라인) 이번 쇼다운의 공개 요청을 보냈는지
    private var revealRequested = false
    /// (온라인) 다음 라운드 준비 신호를 보냈는지
    private var readySent = false

    init(mode: Mode, practice: Bool = false) {
        self.mode = mode
        self.isPractice = practice
        engine = GameEngine(startingChips: practice ? GameEngine.practiceChips
                                                    : GameEngine.defaultChips)
        switch mode {
        case .solo(let difficulty):
            // 라운드 1의 선 추첨 = 플레이어 배정 랜덤 (엔진의 first가 선)
            localPlayer = Bool.random() ? .first : .second
            ai = AIPlayer(difficulty: difficulty, me: localPlayer.opponent)
        case .online(let client):
            if case .matched(let me) = client.state {
                localPlayer = me
            } else {
                localPlayer = .first
            }
            client.onRemoteMove = { [weak self] move in self?.applyRemote(move) }
            client.onHand = { [weak self] cards in self?.startOnlineRound(myHand: cards) }
            client.onReveal = { [weak self] hands in self?.applyServerReveal(hands) }
            client.onOpponentLeft = { [weak self] in
                guard let self, self.engine.phase != .finished else { return }
                self.opponentLeft = true
            }
        }
        banner = "라운드를 준비하는 중…"
        if case .solo = mode {
            dealSoloRound()
        }
        // 온라인은 서버의 hand 메시지를 기다린다
    }

    func cancelAllWork() {
        aiTask?.cancel()
        timerTask?.cancel()
    }

    // MARK: - 조회

    var isSolo: Bool {
        if case .solo = mode { return true }
        return false
    }
    var opponentName: String { isSolo ? "AI" : "상대" }
    var myStack: Int { engine.stacks[localPlayer.rawValue] }
    var opponentStack: Int { engine.stacks[localPlayer.opponent.rawValue] }
    var myHand: [Card] { engine.hand(of: localPlayer) ?? [] }
    var myDeclaration: Declaration? { engine.declarations[localPlayer.rawValue] }
    var opponentDeclaration: Declaration? { engine.declarations[localPlayer.opponent.rawValue] }
    var showdown: ShowdownResult? { engine.lastShowdown }
    var iAmRoundFirst: Bool { engine.firstPlayer == localPlayer }

    /// 지금 내가 행동할 차례인가 (베팅 또는 선언)
    var isMyTurn: Bool {
        engine.currentTurn == localPlayer
            && (engine.isBettingPhase || engine.phase == .declaration)
    }
    var toCall: Int { engine.toCall(for: localPlayer) }
    var maxRaise: Int { engine.maxRaise(for: localPlayer) }

    /// 쇼다운/폴드 후 상대 손패를 보여줄 수 있는가
    func visibleOpponentCard(at index: Int) -> Card? {
        let opponent = localPlayer.opponent
        if let result = engine.lastShowdown, engine.phase == .roundEnd || engine.phase == .finished {
            return result.hands[opponent.rawValue][index]
        }
        // 선언 단계 이후에는 오픈한 카드 1장만 보인다 (첫 슬롯에 표시)
        if let declaration = engine.declarations[opponent.rawValue], index == 0 {
            return declaration.open
        }
        return nil
    }

    // MARK: - 사용자 입력

    func check() { guard isMyTurn, engine.isBettingPhase else { return }; applyLocal(.check) }
    func call() { guard isMyTurn, engine.isBettingPhase else { return }; applyLocal(.call) }
    func fold() { guard isMyTurn, engine.isBettingPhase else { return }; applyLocal(.fold) }

    func bet(_ amount: Int) {
        guard isMyTurn, engine.isBettingPhase,
              amount >= 1, amount <= maxRaise else { return }
        showBetControls = false
        applyLocal(.bet(amount))
    }

    func declare(rank: HandRank) {
        guard isMyTurn, engine.phase == .declaration, let open = selectedOpenCard else { return }
        selectedOpenCard = nil
        applyLocal(.declare(open: open, rank: rank))
    }

    /// 라운드 종료 후 "다음 라운드" — 1인용은 즉시 배분, 온라인은 서버에 준비 신호
    func nextRound() {
        guard engine.phase == .roundEnd else { return }
        switch mode {
        case .solo:
            dealSoloRound()
        case .online(let client):
            guard !readySent else { return }
            readySent = true
            banner = "상대를 기다리는 중…"
            client.sendReady()
        }
    }

    func resign() {
        guard engine.phase != .finished else { return }
        applyLocal(.forfeit)
    }

    // MARK: - 라운드 시작

    private func dealSoloRound() {
        let hands = GameEngine.deal(using: &rng)
        guard let outcome = try? engine.startRound(hands: [hands[0], hands[1]]) else { return }
        ai?.startRound(hand: hands[localPlayer.opponent.rawValue])
        present(outcome)
    }

    private func startOnlineRound(myHand: [Card]) {
        var hands: [[Card]?] = [nil, nil]
        hands[localPlayer.rawValue] = myHand
        guard let outcome = try? engine.startRound(hands: hands) else { return }
        revealRequested = false
        readySent = false
        present(outcome)
    }

    private func applyServerReveal(_ hands: [[Card]]) {
        guard let outcome = try? engine.applyReveal(hands: hands) else { return }
        present(outcome)
    }

    // MARK: - 무브 적용

    private func applyLocal(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer) else { return }
        if case .online(let client) = mode {
            client.send(move: move)
        }
        present(outcome)
    }

    private func applyRemote(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer.opponent) else { return }
        present(outcome)
    }

    private func applyAI(_ move: Move) {
        guard let aiPlayer = ai,
              let outcome = try? engine.apply(move, by: aiPlayer.me) else { return }
        present(outcome)
    }

    // MARK: - 연출/상태 반영

    private func present(_ outcome: MoveOutcome) {
        ai?.observe(outcome)

        switch outcome {
        case .roundStarted(let round, let first, let pot):
            selectedOpenCard = nil
            showBetControls = false
            let firstName = name(of: first)
            banner = "라운드 \(round) — 선은 \(firstName). 팟 \(pot)."

        case .checked(let player, let phaseClosed):
            banner = phaseClosed
                ? "\(name(of: player)) 체크 — 베팅 종료"
                : "\(name(of: player)) 체크"

        case .betPlaced(let player, let added, let raised):
            banner = added > raised
                ? "\(name(of: player)) 콜 후 \(raised) 레이즈!"
                : "\(name(of: player)) \(raised) 베팅!"

        case .called(let player, let added):
            banner = "\(name(of: player)) \(added) 콜"

        case .folded(let player, let winner, let pot):
            banner = "\(name(of: player)) 폴드 — \(name(of: winner))가 팟 \(pot) 획득 (카드 비공개)"

        case .declared(let player, let declaration, _):
            banner = "\(name(of: player)): \(declaration.open.label) 오픈, 「\(declaration.rank.label)」 선언!"

        case .showdown(let result):
            banner = showdownBanner(result)

        case .forfeited(let player):
            banner = "\(name(of: player)) 기권"
        }

        // 2차 베팅이 끝났는데 상대 손패를 모르면(온라인) 서버에 공개 요청
        if engine.phase == .awaitingReveal, !revealRequested, case .online(let client) = mode {
            revealRequested = true
            client.requestShowdown()
        }

        // 쇼다운이 로컬에서 정산된 경우(1인용) 결과 배너로 교체
        if case .solo = mode, engine.phase == .roundEnd || engine.phase == .finished {
            if let result = engine.lastShowdown, isShowdownTrigger(outcome) {
                banner = showdownBanner(result)
            }
        }

        // 매치 종료 — 전적 기록 (연습 게임 제외, 1회만)
        if engine.phase == .finished, let winner = engine.matchWinner,
           !statsRecorded, !isPractice {
            statsRecorded = true
            let won = winner == localPlayer
            switch mode {
            case .solo(let difficulty):
                StatsStore.shared.recordSolo(difficulty: difficulty, won: won)
            case .online:
                StatsStore.shared.recordOnline(won: won)
            }
        }

        restartTimerIfNeeded()
        scheduleAIIfNeeded()
    }

    /// 이 outcome이 쇼다운을 촉발한 마지막 행동인지 (배너 교체 판단용)
    private func isShowdownTrigger(_ outcome: MoveOutcome) -> Bool {
        switch outcome {
        case .checked, .called, .declared: return true
        default: return false
        }
    }

    private func showdownBanner(_ result: ShowdownResult) -> String {
        if let cheater = result.disqualified {
            return "\(name(of: cheater))의 오픈 카드가 손패와 다릅니다 — 몰수패!"
        }
        let mine = result.ranks[localPlayer.rawValue].label
        let theirs = result.ranks[localPlayer.opponent.rawValue].label
        if let winner = result.winner {
            return "쇼다운! \(mine) vs \(theirs) — \(name(of: winner)) 승리, 팟 \(result.pot) 획득"
        }
        return "쇼다운! \(mine) vs \(theirs) — 무승부, 팟 \(result.pot)은 다음 라운드로"
    }

    private func name(of player: Player) -> String {
        player == localPlayer ? "나" : opponentName
    }

    // MARK: - 턴 타이머 (내 차례 60초 — 초과 시 자동 처리)

    private func restartTimerIfNeeded() {
        timerTask?.cancel()
        guard isMyTurn else { return }
        secondsLeft = Int(GameEngine.turnTimeLimit)
        let phaseAtStart = engine.phase
        let turnOwner = engine.currentTurn
        timerTask = Task { [weak self] in
            while let self, self.secondsLeft > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.secondsLeft -= 1
            }
            guard let self, !Task.isCancelled else { return }
            guard self.engine.currentTurn == turnOwner, self.engine.phase == phaseAtStart else { return }
            // 시간 초과 자동 행동: 베팅은 체크(불가하면 폴드), 선언은 첫 카드 + 실제 족보
            if self.engine.isBettingPhase {
                self.applyLocal(self.toCall == 0 ? .check : .fold)
            } else if self.engine.phase == .declaration, let first = self.myHand.first {
                self.selectedOpenCard = nil
                self.applyLocal(.declare(open: first, rank: HandEvaluator.evaluate(self.myHand)))
            }
        }
    }

    // MARK: - AI 턴 진행 (1인용)

    private func scheduleAIIfNeeded() {
        guard case .solo = mode, let aiPlayer = ai,
              engine.matchWinner == nil,
              engine.currentTurn == aiPlayer.me,
              engine.isBettingPhase || engine.phase == .declaration else { return }
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 1.0...2.2)))
            guard let self, !Task.isCancelled else { return }
            guard self.engine.currentTurn == aiPlayer.me, self.engine.matchWinner == nil else { return }

            if self.engine.isBettingPhase {
                let move = self.ai!.chooseBettingAction(engine: self.engine)
                self.applyAI(move)
            } else if self.engine.phase == .declaration {
                let move = self.ai!.chooseDeclaration(engine: self.engine)
                self.applyAI(move)
            }
        }
    }
}
