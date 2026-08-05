import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        NavigationStack {
            Form {
                // 광고 제거 IAP — 스토어에 상품이 등록되어 조회될 때만 노출
                // (상품 미등록 상태에서는 섹션 자체가 보이지 않는다)
                if purchases.removeAdsPurchased || purchases.removeAdsProduct != nil {
                    Section {
                        if purchases.removeAdsPurchased {
                            Label("광고 제거됨 — 이용해 주셔서 감사합니다!", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task { await purchases.purchaseRemoveAds() }
                            } label: {
                                HStack {
                                    Label("광고 제거", systemImage: "nosign")
                                    Spacer()
                                    if purchases.purchaseInProgress {
                                        ProgressView()
                                    } else {
                                        Text(purchases.removeAdsProduct?.displayPrice ?? "—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(purchases.purchaseInProgress)

                            Button("구입 복원") {
                                Task { await purchases.restore() }
                            }
                        }
                    } header: {
                        Text("광고")
                    } footer: {
                        Text("구매 시 게임 종료 후 표시되는 전면 광고가 영구히 제거됩니다. 기기를 바꾸거나 앱을 재설치한 경우 '구입 복원'을 눌러주세요.")
                    }

                    if let message = purchases.lastErrorMessage {
                        Section {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }
                }

                Section("정보") {
                    LabeledContent("버전",
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
