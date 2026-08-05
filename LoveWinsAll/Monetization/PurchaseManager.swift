import Foundation
import Observation
import StoreKit

/// "광고 제거" 비소모성 인앱 결제 관리 (StoreKit 2).
/// 구매 상태는 StoreKit 영수증(currentEntitlements)으로 검증하고,
/// 오프라인 실행을 위해 UserDefaults에 캐시한다.
@Observable
@MainActor
final class PurchaseManager {
    private static let cacheKey = "removeAdsPurchased"

    private(set) var removeAdsPurchased: Bool = UserDefaults.standard.bool(forKey: PurchaseManager.cacheKey)
    private(set) var removeAdsProduct: Product?
    private(set) var purchaseInProgress = false
    private(set) var lastErrorMessage: String?

    /// 구매 상태가 바뀔 때 광고 매니저 등에 알리는 훅
    var onEntitlementChange: ((Bool) -> Void)?

    private var updatesTask: Task<Void, Never>?

    func start() {
        // 앱 실행 중 도착하는 트랜잭션(승인 지연, 다른 기기 구매 등) 수신
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [MonetizationConfig.removeAdsProductID])
            removeAdsProduct = products.first
        } catch {
            lastErrorMessage = "상품 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 영수증 전체를 다시 확인해 구매 상태를 재계산
    func refreshEntitlements() async {
        var purchased = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == MonetizationConfig.removeAdsProductID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        setPurchased(purchased)
    }

    func purchaseRemoveAds() async {
        guard let product = removeAdsProduct, !purchaseInProgress else { return }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        lastErrorMessage = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    setPurchased(true)
                    await transaction.finish()
                } else {
                    lastErrorMessage = "구매 영수증을 검증하지 못했습니다."
                }
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "구매 승인 대기 중입니다. 승인되면 자동으로 적용됩니다."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = "구매 실패: \(error.localizedDescription)"
        }
    }

    /// 기기 변경/재설치 시 구입 복원 (앱스토어 심사 필수 요건)
    func restore() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !removeAdsPurchased {
                lastErrorMessage = "복원할 구매 내역이 없습니다."
            }
        } catch {
            lastErrorMessage = "복원 실패: \(error.localizedDescription)"
        }
    }

    private func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = update,
              transaction.productID == MonetizationConfig.removeAdsProductID else { return }
        setPurchased(transaction.revocationDate == nil)
        await transaction.finish()
    }

    private func setPurchased(_ value: Bool) {
        removeAdsPurchased = value
        UserDefaults.standard.set(value, forKey: PurchaseManager.cacheKey)
        onEntitlementChange?(value)
    }
}
