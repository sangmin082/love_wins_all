import SwiftUI

/// 전적 화면 — 난이도별/모드별 승패와 승률 (연습 게임은 기록되지 않는다)
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    private var stats: StatsStore { StatsStore.shared }

    var body: some View {
        NavigationStack {
            Form {
                Section("혼자 하기 (AI)") {
                    ForEach(AIPlayer.Difficulty.allCases) { difficulty in
                        row(difficulty.label, stats.solo[difficulty] ?? StatsStore.Record())
                    }
                }
                Section("둘이 하기") {
                    row("온라인 대전", stats.online)
                }
                Section("전체") {
                    row("총 전적", stats.total)
                }
                Section {
                    Button("전적 초기화", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
            .navigationTitle("전적")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .confirmationDialog("전적을 모두 삭제할까요?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("전부 삭제", role: .destructive) { StatsStore.shared.reset() }
                Button("취소", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ title: String, _ record: StatsStore.Record) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(record.wins)승 \(record.losses)패")
                .monospacedDigit()
            Text(record.games == 0 ? "—" : "\(record.winRatePercent)%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
