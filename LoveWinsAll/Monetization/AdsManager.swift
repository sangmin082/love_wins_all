import Foundation
import Observation
import UIKit
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// 전면 광고 관리.
/// 노출 지점은 "매치 종료 후 결과 화면에서 나갈 때" 하나뿐이며,
/// 게임(베팅·심리전) 도중에는 절대 광고를 띄우지 않는다.
@Observable
@MainActor
final class AdsManager: NSObject {
    /// 광고 제거 구매 여부 (PurchaseManager가 갱신)
    var adsRemoved = false {
        didSet { if adsRemoved { discardLoadedAd() } }
    }

    private var started = false
    private var gamesSinceLastAd = 0
    private var lastAdShownAt: Date?

    #if canImport(GoogleMobileAds)
    private var interstitial: InterstitialAd?
    #endif

    /// 앱 시작 후 1회 — ATT 권한을 요청하고 광고 SDK를 초기화한다.
    func startAfterTrackingPrompt() {
        guard !started, !adsRemoved else { return }
        #if canImport(AppTrackingTransparency)
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            // 허용/거부와 무관하게 SDK는 시작한다 (거부 시 비맞춤 광고)
            Task { @MainActor in self?.startSDK() }
        }
        #else
        startSDK()
        #endif
    }

    private func startSDK() {
        guard !started else { return }
        started = true
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        loadInterstitial()
        #endif
    }

    /// 한 판이 끝날 때마다 호출 (빈도 계산용)
    func gameDidEnd() {
        gamesSinceLastAd += 1
    }

    /// 결과 화면에서 나갈 때 호출 — 빈도 조건을 만족하면 잠시 뒤 전면 광고를 띄운다.
    /// (fullScreenCover가 닫힌 다음에 표시되도록 지연을 둔다)
    func maybeShowInterstitialAfterExit() {
        guard !adsRemoved, started else { return }
        guard gamesSinceLastAd >= MonetizationConfig.gamesPerInterstitial else { return }
        if let last = lastAdShownAt,
           Date().timeIntervalSince(last) < MonetizationConfig.minSecondsBetweenAds { return }

        #if canImport(GoogleMobileAds)
        guard interstitial != nil else {
            loadInterstitial()
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard let self, let ad = self.interstitial,
                  let viewController = Self.topViewController() else { return }
            self.gamesSinceLastAd = 0
            self.lastAdShownAt = Date()
            self.interstitial = nil
            ad.present(from: viewController)
        }
        #endif
    }

    private func discardLoadedAd() {
        #if canImport(GoogleMobileAds)
        interstitial = nil
        #endif
    }

    #if canImport(GoogleMobileAds)
    private var retryScheduled = false

    private func loadInterstitial() {
        guard !adsRemoved, interstitial == nil else { return }
        InterstitialAd.load(with: MonetizationConfig.interstitialAdUnitID,
                            request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                if let ad {
                    ad.fullScreenContentDelegate = self
                    self.interstitial = ad
                } else if error != nil {
                    self.interstitial = nil
                    self.scheduleRetry()
                }
            }
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self else { return }
            self.retryScheduled = false
            self.loadInterstitial()
        }
    }
    #endif

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

#if canImport(GoogleMobileAds)
extension AdsManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        loadInterstitial() // 다음 광고 미리 로드
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        loadInterstitial()
    }
}
#endif
