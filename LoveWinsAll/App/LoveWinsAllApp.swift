import SwiftUI

@main
struct LoveWinsAllApp: App {
    @State private var purchases = PurchaseManager()
    @State private var ads = AdsManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 족보·베팅·시나리오 전수 테스트로 엔진 규칙을 검증 (DEBUG 전용)
        EngineSelfTest.run()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(purchases)
                .environment(ads)
                .task {
                    purchases.onEntitlementChange = { removed in
                        ads.adsRemoved = removed
                    }
                    ads.adsRemoved = purchases.removeAdsPurchased
                    purchases.start()
                    // 홈 화면이 자리 잡은 뒤 ATT 권한 요청 → 광고 SDK 시작
                    try? await Task.sleep(for: .seconds(1))
                    ads.startAfterTrackingPrompt()
                }
                // ATT 팝업은 앱이 active일 때만 뜬다 — 권한이 미결정으로 남아 있으면
                // active 전환 때마다 다시 요청해서 반드시 팝업이 표시되게 한다
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        ads.startAfterTrackingPrompt()
                    }
                }
        }
    }
}
