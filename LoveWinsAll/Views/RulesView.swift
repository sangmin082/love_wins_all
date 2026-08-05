import SwiftUI

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ruleSection("🎯 목표",
                        "가위바위보 카드 승부와 베팅으로 상대의 칩 25개를 전부 빼앗으면 승리합니다. " +
                        "각 플레이어는 칩 25개를 가지고 시작합니다. (연습 게임은 20개)")

                    ruleSection("🃏 카드",
                        "가위 12장 · 바위 7장 · 보 7장 · 러브 4장 — 총 30장을 사용하며, " +
                        "매 라운드 30장을 모두 섞어 각자 3장씩 받습니다.")

                    handRankSection

                    ruleSection("⚖️ 동순위 비교",
                        """
                        • 같은 족보끼리는 가위바위보 상성(가위>보, 보>바위, 바위>가위)으로 승부합니다.
                        • 상성이 무승부면 나머지 카드의 상성으로 다시 비교합니다.
                        • 투 러브끼리는 나머지 1장의 상성으로 승부합니다.
                        • 원 러브끼리는 무승부입니다.
                        • 무승부가 나오면 베팅된 칩은 다음 라운드로 넘어갑니다.
                        """)

                    ruleSection("💰 라운드 진행",
                        """
                        1. 기본 배팅으로 칩 1개를 걸고 카드 3장을 받습니다.
                        2. 1차 베팅 — 체크/베팅/콜/레이즈/폴드 (통상적인 포커와 동일)
                        3. 각자 카드 1장을 오픈하고 족보를 선언합니다. 족보는 거짓으로 선언할 수 있습니다!
                        4. 2차 베팅 후 모든 카드를 공개해 족보가 높은 쪽이 팟을 가져갑니다.
                        5. 폴드로 끝난 라운드는 카드를 공개하지 않습니다.
                        """)

                    ruleSection("👑 선(先)",
                        "1라운드의 선은 추첨으로 정하고, 2라운드부터는 직전 라운드 승자가 선이 됩니다. " +
                        "선이 베팅과 선언을 먼저 합니다.")

                    ruleSection("💡 팁",
                        "선언은 심리전의 핵심입니다. 약한 패로 강한 족보를 선언해 상대를 접게 만들거나, " +
                        "강한 패를 숨겨 베팅을 유도해 보세요. 오픈한 카드와 모순되는 선언은 할 수 없습니다.")
                }
                .padding()
            }
            .navigationTitle("게임 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var handRankSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🏆 족보 (높은 순)").font(.headline)
            VStack(spacing: 6) {
                ForEach(HandRank.allCases, id: \.rawValue) { rank in
                    HStack {
                        Text("\(rank.rawValue)위")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.yellow)
                            .frame(width: 34, alignment: .leading)
                        Text(rank.label)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(rank.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }

    private func ruleSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}
