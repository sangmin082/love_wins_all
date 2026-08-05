import Foundation

/// 수익화 설정 — 출시 전 교체가 필요한 값은 여기에 모아둔다.
enum MonetizationConfig {
    /// 전면 광고 단위 ID ("게임종료_전면").
    /// ⚠️ 현재는 Google 공식 테스트 ID다. 출시 전 AdMob 콘솔에서 이 앱의
    /// 광고 단위를 만들어 교체할 것. (Info.plist의 GADApplicationIdentifier도 함께)
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// 광고 제거 비소모성 인앱 결제 상품 ID (App Store Connect에 동일하게 등록)
    static let removeAdsProductID = "com.lovewinsall.game.removeads"

    /// 전면 광고 노출 빈도: N판 종료마다 1회
    static let gamesPerInterstitial = 2
    /// 전면 광고 최소 간격 (초)
    static let minSecondsBetweenAds: TimeInterval = 180
}
