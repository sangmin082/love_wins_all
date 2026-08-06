import Foundation

/// 온라인 대전 서버 설정
enum OnlineConfig {
    /// 기본 서버 주소 — 사용자에게는 노출되지 않는다.
    /// (server/ 디렉터리를 Render에 배포한 주소. 서비스 이름을 바꾸면 여기도 함께 수정)
    static let defaultServerURLString = "wss://love-wins-all.onrender.com"

    static func resolvedServerURL() -> URL? {
        URL(string: defaultServerURLString)
    }
}
