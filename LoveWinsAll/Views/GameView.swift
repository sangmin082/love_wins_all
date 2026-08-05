import SwiftUI

/// 대국 화면 — 상대/내 카드, 팟, 베팅·선언 UI, 턴 타이머.
struct GameView: View {
    @State var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AdsManager.self) private var ads
    @State private var showResignAlert = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.12),
                                    Color(red: 0.20, green: 0.07, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                opponentArea
                potArea
                banner
                Spacer(minLength: 0)
                myArea
                actionArea
            }
            .padding()

            if viewModel.engine.phase == .finished {
                gameOverOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .onDisappear { viewModel.cancelAllWork() }
        .onChange(of: viewModel.engine.phase) { _, newPhase in
            if newPhase == .finished { ads.gameDidEnd() }
        }
        .alert("기권하시겠습니까?", isPresented: $showResignAlert) {
            Button("기권", role: .destructive) { viewModel.resign() }
            Button("계속하기", role: .cancel) {}
        }
        .alert("상대가 나갔습니다", isPresented: $viewModel.opponentLeft) {
            Button("나가기") { dismiss() }
        }
        .confirmationDialog(
            declarationDialogTitle,
            isPresented: declarationDialogBinding,
            titleVisibility: .visible
        ) {
            if let open = viewModel.selectedOpenCard {
                ForEach(HandRank.plausible(open: open), id: \.rawValue) { rank in
                    Button("\(rank.label) — \(rank.summary)") {
                        viewModel.declare(rank: rank)
                    }
                }
            }
            Button("취소", role: .cancel) { viewModel.selectedOpenCard = nil }
        } message: {
            Text("족보는 거짓으로 선언할 수 있습니다.")
        }
    }

    private var declarationDialogTitle: String {
        if let open = viewModel.selectedOpenCard {
            return "\(open.label) \(open.emoji) 오픈 — 어떤 족보를 선언할까요?"
        }
        return ""
    }

    private var declarationDialogBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedOpenCard != nil },
            set: { if !$0 { viewModel.selectedOpenCard = nil } }
        )
    }

    // MARK: 상단 바

    private var topBar: some View {
        HStack {
            Button {
                showResignAlert = true
            } label: {
                Label("기권", systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text("라운드 \(max(viewModel.engine.round, 1))")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            if viewModel.isPractice {
                Text("연습")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.yellow.opacity(0.25)))
                    .foregroundStyle(.yellow)
            } else {
                // 기권 버튼과 좌우 균형
                Label("기권", systemImage: "flag.fill").font(.caption).hidden()
            }
        }
    }

    // MARK: 상대 영역

    private var opponentArea: some View {
        VStack(spacing: 8) {
            playerBadge(name: opponentTitle,
                        chips: viewModel.opponentStack,
                        active: !viewModel.isMyTurn && viewModel.engine.phase != .finished
                            && viewModel.engine.phase != .roundEnd)
            HStack(spacing: 10) {
                ForEach(0..<GameEngine.handSize, id: \.self) { index in
                    CardView(card: viewModel.visibleOpponentCard(at: index),
                             selected: false)
                }
            }
            declarationBubble(viewModel.opponentDeclaration, mine: false)
        }
    }

    private var opponentTitle: String {
        let firstMark = viewModel.iAmRoundFirst ? "" : " · 선"
        return "\(viewModel.opponentName)\(firstMark)"
    }

    // MARK: 팟 & 배너

    private var potArea: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("팟")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Label("\(viewModel.engine.totalPot)", systemImage: "circlebadge.2.fill")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.yellow)
            }
            if viewModel.engine.carryover > 0 {
                Text("이월 \(viewModel.engine.carryover) 포함")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.9))
            }
            if viewModel.isMyTurn, viewModel.toCall > 0 {
                Text("콜 \(viewModel.toCall)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.red.opacity(0.3)))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }

    private var banner: some View {
        VStack(spacing: 6) {
            Text(viewModel.banner)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

            if viewModel.isMyTurn {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    ProgressView(value: Double(viewModel.secondsLeft),
                                 total: GameEngine.turnTimeLimit)
                        .tint(viewModel.secondsLeft <= 10 ? .red : .yellow)
                    Text("\(viewModel.secondsLeft)초")
                        .font(.caption.monospacedDigit().bold())
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: 내 영역

    private var myArea: some View {
        VStack(spacing: 8) {
            declarationBubble(viewModel.myDeclaration, mine: true)
            HStack(spacing: 10) {
                ForEach(Array(viewModel.myHand.enumerated()), id: \.offset) { index, card in
                    CardView(card: card,
                             selected: canSelectOpenCard && viewModel.selectedOpenCard == card
                                && firstIndexOfSelected == index)
                        .onTapGesture {
                            guard canSelectOpenCard else { return }
                            viewModel.selectedOpenCard = card
                        }
                }
            }
            playerBadge(name: myTitle,
                        chips: viewModel.myStack,
                        active: viewModel.isMyTurn)
        }
    }

    /// 같은 카드가 여러 장일 때 첫 장만 하이라이트하기 위한 인덱스
    private var firstIndexOfSelected: Int? {
        guard let selected = viewModel.selectedOpenCard else { return nil }
        return viewModel.myHand.firstIndex(of: selected)
    }

    private var canSelectOpenCard: Bool {
        viewModel.isMyTurn && viewModel.engine.phase == .declaration
    }

    private var myTitle: String {
        let firstMark = viewModel.iAmRoundFirst ? " · 선" : ""
        return "나\(firstMark)"
    }

    private func playerBadge(name: String, chips: Int, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption.bold())
            Label("\(chips)", systemImage: "circlebadge.2.fill")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(active ? .yellow : .white.opacity(0.65))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.white.opacity(active ? 0.14 : 0.05))
                .overlay(Capsule().stroke(active ? .yellow.opacity(0.7) : .clear, lineWidth: 1.5))
        )
    }

    private func declarationBubble(_ declaration: Declaration?, mine: Bool) -> some View {
        Group {
            if let declaration {
                Text("\(declaration.open.emoji) 오픈 · 「\(declaration.rank.label)」 선언")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(mine ? Color.blue.opacity(0.3) : Color.pink.opacity(0.3)))
                    .foregroundStyle(.white)
            } else {
                Text(" ").font(.caption.bold()).padding(.vertical, 4).hidden()
            }
        }
    }

    // MARK: 행동 바

    @ViewBuilder
    private var actionArea: some View {
        if viewModel.engine.phase == .roundEnd {
            Button {
                viewModel.nextRound()
            } label: {
                Label("다음 라운드", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        } else if viewModel.isMyTurn, viewModel.engine.isBettingPhase {
            bettingControls
        } else if canSelectOpenCard {
            Text("오픈할 카드 1장을 선택하세요")
                .font(.subheadline.bold())
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Text(waitingText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var waitingText: String {
        switch viewModel.engine.phase {
        case .awaitingReveal: return "쇼다운 — 카드 공개 중…"
        case .finished: return ""
        default: return viewModel.isMyTurn ? "" : "\(viewModel.opponentName)의 차례입니다…"
        }
    }

    @ViewBuilder
    private var bettingControls: some View {
        if viewModel.showBetControls {
            raiseControls
        } else {
            HStack(spacing: 10) {
                if viewModel.toCall > 0 {
                    actionButton("폴드", icon: "xmark", tint: .red) { viewModel.fold() }
                    actionButton("콜 \(viewModel.toCall)", icon: "equal", tint: .green) { viewModel.call() }
                    if viewModel.maxRaise >= 1 {
                        actionButton("레이즈", icon: "arrow.up", tint: .orange) {
                            viewModel.betAmount = 1
                            viewModel.showBetControls = true
                        }
                    }
                } else {
                    actionButton("체크", icon: "hand.raised", tint: .green) { viewModel.check() }
                    if viewModel.maxRaise >= 1 {
                        actionButton("베팅", icon: "arrow.up", tint: .orange) {
                            viewModel.betAmount = 1
                            viewModel.showBetControls = true
                        }
                    }
                }
            }
        }
    }

    private var raiseControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.toCall > 0
                     ? "콜 \(viewModel.toCall) + 레이즈 \(viewModel.betAmount)"
                     : "베팅 \(viewModel.betAmount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("올인") { viewModel.betAmount = viewModel.maxRaise }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            if viewModel.maxRaise > 1 {
                Slider(
                    value: Binding(
                        get: { Double(viewModel.betAmount) },
                        set: { viewModel.betAmount = Int($0.rounded()) }
                    ),
                    in: 1...Double(viewModel.maxRaise),
                    step: 1
                )
                .tint(.orange)
            }
            HStack(spacing: 10) {
                actionButton("취소", icon: "xmark", tint: .gray) {
                    viewModel.showBetControls = false
                }
                actionButton("확정", icon: "checkmark", tint: .orange) {
                    viewModel.bet(viewModel.betAmount)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
    }

    private func actionButton(_ title: String, icon: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    // MARK: 게임 종료 오버레이

    private var gameOverOverlay: some View {
        VStack(spacing: 16) {
            Text(viewModel.engine.matchWinner == viewModel.localPlayer ? "🏆 승리!" : "💀 패배")
                .font(.largeTitle.bold())
            Text(viewModel.banner)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            if let result = viewModel.showdown {
                HStack(spacing: 20) {
                    finalHand(title: "나", cards: result.hands[viewModel.localPlayer.rawValue],
                              rank: result.ranks[viewModel.localPlayer.rawValue])
                    finalHand(title: viewModel.opponentName,
                              cards: result.hands[viewModel.localPlayer.opponent.rawValue],
                              rank: result.ranks[viewModel.localPlayer.opponent.rawValue])
                }
            }
            Button("나가기") {
                // 게임 도중에는 광고를 절대 띄우지 않는다 — 노출 지점은 여기뿐
                ads.maybeShowInterstitialAfterExit()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.88)))
        .padding(32)
    }

    private func finalHand(title: String, cards: [Card], rank: HandRank) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    Text(card.emoji).font(.title3)
                }
            }
            Text(rank.label).font(.caption2).foregroundStyle(.yellow)
        }
    }
}

/// 카드 한 장 — 앞면은 이모지+이름, 뒷면은 하트 패턴.
struct CardView: View {
    let card: Card?
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(card != nil
                      ? AnyShapeStyle(Color(red: 0.95, green: 0.92, blue: 0.86))
                      : AnyShapeStyle(LinearGradient(
                          colors: [Color(red: 0.55, green: 0.15, blue: 0.30),
                                   Color(red: 0.30, green: 0.08, blue: 0.20)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.yellow : Color.white.opacity(0.3),
                                lineWidth: selected ? 3 : 1)
                )

            if let card {
                VStack(spacing: 4) {
                    Text(card.emoji).font(.system(size: 30))
                    Text(card.label)
                        .font(.caption2.bold())
                        .foregroundStyle(Color(red: 0.35, green: 0.15, blue: 0.12))
                }
            } else {
                Text("💘")
                    .font(.system(size: 22))
                    .opacity(0.5)
            }
        }
        .frame(width: 64, height: 90)
        .animation(.spring(duration: 0.3), value: card)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
