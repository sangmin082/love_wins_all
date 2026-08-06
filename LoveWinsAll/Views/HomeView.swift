import SwiftUI

struct HomeView: View {
    @State private var showDifficultyDialog = false
    @State private var pendingPractice = false
    @State private var soloGame: GameViewModel?
    @State private var showRules = false
    @State private var showOnlineLobby = false
    @State private var showSettings = false
    @State private var showStats = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.12),
                                        Color(red: 0.22, green: 0.07, blue: 0.13)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 36) {
                    Spacer()

                    VStack(spacing: 10) {
                        Text("💘")
                            .font(.system(size: 72))
                        Text("러브 윈즈 올")
                            .font(.system(size: 40, weight: .black, design: .serif))
                            .foregroundStyle(.white)
                        Text("DEATH GAME — LOVE WINS ALL")
                            .font(.caption.weight(.semibold))
                            .kerning(2)
                            .foregroundStyle(.pink.opacity(0.8))
                    }

                    VStack(spacing: 14) {
                        menuButton("혼자 하기", subtitle: "AI와 베팅 심리전 (칩 25개)", icon: "person.fill") {
                            pendingPractice = false
                            showDifficultyDialog = true
                        }
                        menuButton("연습 게임", subtitle: "칩 20개로 규칙 익히기 (전적 미기록)", icon: "graduationcap.fill") {
                            pendingPractice = true
                            showDifficultyDialog = true
                        }
                        menuButton("둘이 하기", subtitle: "방을 만들고 코드로 초대", icon: "person.2.fill") {
                            showOnlineLobby = true
                        }
                        menuButton("전적", subtitle: "승패 기록 보기", icon: "chart.bar.fill") {
                            showStats = true
                        }
                        menuButton("게임 방법", subtitle: "규칙과 족보 읽기", icon: "book.fill") {
                            showRules = true
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Text("상대의 칩을 모두 빼앗으면 승리!")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 8)
                }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(10)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .confirmationDialog(pendingPractice ? "연습 게임 — AI 난이도" : "AI 난이도",
                                isPresented: $showDifficultyDialog, titleVisibility: .visible) {
                ForEach(AIPlayer.Difficulty.allCases) { difficulty in
                    Button(difficulty.label) {
                        soloGame = GameViewModel(mode: .solo(difficulty), practice: pendingPractice)
                    }
                }
            }
            .fullScreenCover(item: $soloGame) { game in
                GameView(viewModel: game)
            }
            .sheet(isPresented: $showRules) {
                RulesView()
            }
            .sheet(isPresented: $showOnlineLobby) {
                OnlineLobbyView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showStats) {
                StatsView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func menuButton(_ title: String, subtitle: String, icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(0.6)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).opacity(0.5)
            }
            .foregroundStyle(.white)
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        }
    }
}

extension GameViewModel: Identifiable {}

#Preview {
    HomeView()
}
