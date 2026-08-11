import Foundation

/// 수익화 설정 — 출시 전 교체가 필요한 값은 여기에 모아둔다.
enum MonetizationConfig {
    /// 전면 광고 단위 ID ("게임종료_전면").
    /// 개발 중 테스트가 필요하면 Google 테스트 ID(ca-app-pub-3940256099942544/4411468910)로
    /// 잠시 바꾸거나, AdMob 콘솔에서 본인 기기를 테스트 기기로 등록할 것.
    static let interstitialAdUnitID = "ca-app-pub-1063542820867439/1140643079"

    /// 광고 제거 비소모성 인앱 결제 상품 ID (App Store Connect에 동일하게 등록)
    static let removeAdsProductID = "com.lovewinsall.game.removeads"

    /// 전면 광고 노출 빈도: N판 종료마다 1회
    static let gamesPerInterstitial = 2
    /// 전면 광고 최소 간격 (초)
    static let minSecondsBetweenAds: TimeInterval = 180
}
