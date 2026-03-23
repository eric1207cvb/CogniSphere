import Combine
import Foundation

#if canImport(RevenueCat)
import RevenueCat
#endif

enum PremiumFeature: String {
    case smartScan
    case additionalOCR
    case referenceImageOCR
    case pdfSummary

    func localizedName(for region: SupportedRegionUI) -> String {
        switch (self, region) {
        case (.smartScan, .taiwan):
            return "智慧辨識"
        case (.smartScan, .unitedStates):
            return "Smart Scan"
        case (.smartScan, .japan):
            return "スマート認識"
        case (.additionalOCR, .taiwan):
            return "額外 OCR"
        case (.additionalOCR, .unitedStates):
            return "Additional OCR"
        case (.additionalOCR, .japan):
            return "追加OCR"
        case (.referenceImageOCR, .taiwan):
            return "圖片 OCR"
        case (.referenceImageOCR, .unitedStates):
            return "Image OCR"
        case (.referenceImageOCR, .japan):
            return "画像OCR"
        case (.pdfSummary, .taiwan):
            return "PDF 摘要"
        case (.pdfSummary, .unitedStates):
            return "PDF Summary"
        case (.pdfSummary, .japan):
            return "PDF要約"
        }
    }
}

struct SubscriptionPaywallPresentation: Identifiable {
    enum Reason {
        case manual
        case limitReached
    }

    let id = UUID()
    let feature: PremiumFeature
    let reason: Reason
}

struct RevenueCatOfferSnapshot {
    enum Kind {
        case monthly
        case annual
        case lifetime
        case unknown
    }

    let kind: Kind
    let priceText: String
}

@MainActor
final class SubscriptionAccessController: ObservableObject {
    private static let dailyFreeLimit = 3

    @Published private(set) var isSubscriber = false
    @Published private(set) var usedTodayCount = 0
    @Published private(set) var canPurchase = false
    @Published private(set) var primaryOffer: RevenueCatOfferSnapshot?
    @Published var presentedPaywall: SubscriptionPaywallPresentation?

    private var hasPrepared = false

    #if canImport(RevenueCat)
    private static var didConfigureRevenueCat = false
    private var primaryPackage: Package?
    #endif

    init() {
        resetDailyQuotaIfNeeded()
    }

    var remainingFreeUses: Int {
        max(0, Self.dailyFreeLimit - usedTodayCount)
    }

    var dailyFreeLimit: Int {
        Self.dailyFreeLimit
    }

    var hasRevenueCatConfiguration: Bool {
        #if canImport(RevenueCat)
        return configuredAPIKey != nil
        #else
        return false
        #endif
    }

    var appUserID: String {
        SubscriptionIdentityStore.shared.appUserID
    }

    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        resetDailyQuotaIfNeeded()
        Task {
            await refreshSubscriptionState()
        }
    }

    func refreshSubscriptionState() async {
        resetDailyQuotaIfNeeded()

        #if canImport(RevenueCat)
        guard configureRevenueCatIfPossible() else {
            clearSubscriptionState()
            return
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            applyCustomerInfo(customerInfo)
        } catch {
            clearSubscriptionState()
            return
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = preferredOffering(from: offerings)
            primaryPackage = preferredPackage(from: offering)
            if let package = primaryPackage {
                primaryOffer = RevenueCatOfferSnapshot(
                    kind: offerKind(for: package),
                    priceText: package.localizedPriceString
                )
                canPurchase = true
            } else {
                primaryOffer = nil
                canPurchase = false
            }
        } catch {
            canPurchase = false
            primaryOffer = nil
            primaryPackage = nil
        }
        #else
        clearSubscriptionState()
        #endif
    }

    func authorize(_ feature: PremiumFeature) -> Bool {
        resetDailyQuotaIfNeeded()

        if isSubscriber {
            return true
        }

        guard usedTodayCount < Self.dailyFreeLimit else {
            presentedPaywall = SubscriptionPaywallPresentation(feature: feature, reason: .limitReached)
            return false
        }

        usedTodayCount += 1
        persistDailyQuotaState()
        return true
    }

    func presentPaywall(for feature: PremiumFeature = .smartScan) {
        presentedPaywall = SubscriptionPaywallPresentation(feature: feature, reason: .manual)
    }

    func dismissPaywall() {
        presentedPaywall = nil
    }

    func markQuotaExhausted() {
        usedTodayCount = Self.dailyFreeLimit
        persistDailyQuotaState()
    }

    func purchasePrimaryOffer(for region: SupportedRegionUI) async -> String {
        #if canImport(RevenueCat)
        guard configureRevenueCatIfPossible() else {
            return localizedRevenueCatNotReady(for: region)
        }
        guard let primaryPackage else {
            return localizedRevenueCatNotReady(for: region)
        }

        do {
            let result = try await Purchases.shared.purchase(package: primaryPackage)
            applyCustomerInfo(result.customerInfo)
            presentedPaywall = nil
            return localizedPurchaseSuccess(for: region)
        } catch {
            return localizedPurchaseFailure(for: region, error: error)
        }
        #else
        return localizedRevenueCatNotReady(for: region)
        #endif
    }

    func restorePurchases(for region: SupportedRegionUI) async -> String {
        #if canImport(RevenueCat)
        guard configureRevenueCatIfPossible() else {
            return localizedRevenueCatNotReady(for: region)
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(customerInfo)
            if isSubscriber {
                presentedPaywall = nil
                return localizedRestoreSuccess(for: region)
            }
            return localizedRestoreEmpty(for: region)
        } catch {
            return localizedPurchaseFailure(for: region, error: error)
        }
        #else
        return localizedRevenueCatNotReady(for: region)
        #endif
    }

    func quotaStatusLabel(for region: SupportedRegionUI) -> String {
        if isSubscriber {
            switch region {
            case .taiwan:
                return "AI / OCR 無限制"
            case .unitedStates:
                return "Unlimited AI / OCR"
            case .japan:
                return "AI / OCR 無制限"
            }
        }

        switch region {
        case .taiwan:
            return "今日剩餘 \(remainingFreeUses) / \(Self.dailyFreeLimit)"
        case .unitedStates:
            return "\(remainingFreeUses) / \(Self.dailyFreeLimit) left today"
        case .japan:
            return "本日残り \(remainingFreeUses) / \(Self.dailyFreeLimit)"
        }
    }

    func paywallTitle(for region: SupportedRegionUI, reason: SubscriptionPaywallPresentation.Reason) -> String {
        switch (region, reason) {
        case (.taiwan, .manual):
            return "解鎖 AI / OCR"
        case (.taiwan, .limitReached):
            return "今日免費額度已用完"
        case (.unitedStates, .manual):
            return "Unlock AI / OCR"
        case (.unitedStates, .limitReached):
            return "Today's Free Limit Is Used Up"
        case (.japan, .manual):
            return "AI / OCR を解放"
        case (.japan, .limitReached):
            return "本日の無料枠を使い切りました"
        }
    }

    func paywallSubtitle(for region: SupportedRegionUI, feature: PremiumFeature, reason: SubscriptionPaywallPresentation.Reason) -> String {
        let featureName = feature.localizedName(for: region)
        switch (region, reason) {
        case (.taiwan, .manual):
            return "訂閱後可不限次數使用 \(featureName)、圖片 OCR、PDF 摘要與 AI 知識提取。未訂閱者每天可免費使用 3 次。"
        case (.taiwan, .limitReached):
            return "你今天的 3 次免費 AI / OCR 額度已用完。訂閱後可立即繼續使用 \(featureName) 與其他智慧功能。"
        case (.unitedStates, .manual):
            return "Subscribe for unlimited \(featureName), image OCR, PDF summaries, and AI knowledge extraction. Free users can use these features 3 times per day."
        case (.unitedStates, .limitReached):
            return "You used all 3 free AI / OCR sessions for today. Subscribe to continue using \(featureName) and the rest of the smart tools right now."
        case (.japan, .manual):
            return "購読すると \(featureName)、画像OCR、PDF要約、AI知識抽出を無制限で使えます。未購読では1日3回まで無料です。"
        case (.japan, .limitReached):
            return "本日の無料 AI / OCR 枠 3 回を使い切りました。購読すると \(featureName) と他のスマート機能をすぐ再開できます。"
        }
    }

    func paywallBullets(for region: SupportedRegionUI) -> [String] {
        switch region {
        case .taiwan:
            return [
                "不限次數使用 AI 知識提取、OCR 與 PDF 摘要",
                "iPhone、iPad、Mac 的知識條目可持續同步",
                "更適合高強度學習、研究與整理工作"
            ]
        case .unitedStates:
            return [
                "Unlimited AI extraction, OCR, and PDF summaries",
                "Keep your knowledge entries in sync across iPhone, iPad, and Mac",
                "Built for heavier study and research workflows"
            ]
        case .japan:
            return [
                "AI抽出、OCR、PDF要約を無制限で利用",
                "iPhone、iPad、Mac 間で知識項目を継続同期",
                "高頻度の学習や研究ワークフローに適した設計"
            ]
        }
    }

    func primaryCTA(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "開始訂閱"
        case .unitedStates:
            return "Subscribe"
        case .japan:
            return "購読する"
        }
    }

    func offerTitle(for region: SupportedRegionUI) -> String? {
        guard let offer = primaryOffer else { return nil }
        switch (offer.kind, region) {
        case (.monthly, .taiwan):
            return "專業版月訂閱"
        case (.monthly, .unitedStates):
            return "Pro Monthly"
        case (.monthly, .japan):
            return "プロ月額プラン"
        case (.annual, .taiwan):
            return "專業版年訂閱"
        case (.annual, .unitedStates):
            return "Pro Annual"
        case (.annual, .japan):
            return "プロ年額プラン"
        case (.lifetime, .taiwan):
            return "專業版終身方案"
        case (.lifetime, .unitedStates):
            return "Pro Lifetime"
        case (.lifetime, .japan):
            return "プロ買い切りプラン"
        case (.unknown, .taiwan):
            return "專業版方案"
        case (.unknown, .unitedStates):
            return "Pro Plan"
        case (.unknown, .japan):
            return "プロプラン"
        }
    }

    func offerSubtitle(for region: SupportedRegionUI) -> String? {
        guard primaryOffer != nil else { return nil }
        switch region {
        case .taiwan:
            return "解鎖進階 AI 與 OCR 功能"
        case .unitedStates:
            return "Unlock advanced AI and OCR features"
        case .japan:
            return "高度な AI / OCR 機能を解放"
        }
    }

    func billingCurrencyNotice(for region: SupportedRegionUI) -> String? {
        guard primaryOffer != nil else { return nil }
        switch region {
        case .taiwan:
            return "實際幣別與售價會跟隨 App Store 商店地區。"
        case .unitedStates:
            return "The final price and currency follow your App Store storefront."
        case .japan:
            return "実際の価格と通貨は App Store のストア地域に従います。"
        }
    }

    func restoreCTA(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "還原購買"
        case .unitedStates:
            return "Restore Purchases"
        case .japan:
            return "購入を復元"
        }
    }

    func closeCTA(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "稍後再說"
        case .unitedStates:
            return "Maybe Later"
        case .japan:
            return "あとで"
        }
    }

    func notReadyHint(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "要啟用真實訂閱，請在 Info.plist 填入 RevenueCatAPIKey / RevenueCatEntitlementID，並加入 RevenueCat SDK。"
        case .unitedStates:
            return "To activate real subscriptions, add RevenueCatAPIKey / RevenueCatEntitlementID to Info.plist and include the RevenueCat SDK."
        case .japan:
            return "実際の購読を有効化するには、Info.plist に RevenueCatAPIKey / RevenueCatEntitlementID を設定し、RevenueCat SDK を追加してください。"
        }
    }

    private func resetDailyQuotaIfNeeded(now: Date = .now) {
        let startOfDay = Calendar.autoupdatingCurrent.startOfDay(for: now).timeIntervalSince1970
        let storedState = SubscriptionQuotaStore.shared.loadState()
        let storedStartOfDay = storedState?.dayStart ?? 0
        if storedStartOfDay != startOfDay {
            SubscriptionQuotaStore.shared.saveState(dayStart: startOfDay, usedCount: 0)
            usedTodayCount = 0
            return
        }

        usedTodayCount = storedState?.usedCount ?? 0
    }

    private func persistDailyQuotaState() {
        let startOfDay = Calendar.autoupdatingCurrent.startOfDay(for: .now).timeIntervalSince1970
        SubscriptionQuotaStore.shared.saveState(dayStart: startOfDay, usedCount: usedTodayCount)
    }

    #if canImport(RevenueCat)
    private func configureRevenueCatIfPossible() -> Bool {
        guard let apiKey = configuredAPIKey else {
            return false
        }

        if !Self.didConfigureRevenueCat {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
            Self.didConfigureRevenueCat = true
        }

        return true
    }

    private var configuredAPIKey: String? {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyCustomerInfo(_ customerInfo: CustomerInfo) {
        let entitlementID = configuredEntitlementID
        let isActive: Bool
        if let entitlementID {
            isActive = customerInfo.entitlements[entitlementID]?.isActive == true
        } else {
            isActive = customerInfo.entitlements.active.isEmpty == false
        }

        isSubscriber = isActive
        Task {
            await ProtectedServiceAuthStore.shared.updateSubscriptionStatus(isSubscriber: isActive)
        }
    }

    private var configuredEntitlementID: String? {
        let entitlementID = Bundle.main.object(forInfoDictionaryKey: "RevenueCatEntitlementID") as? String
        let trimmed = entitlementID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func preferredOffering(from offerings: Offerings) -> Offering? {
        let configuredOfferingID = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatOfferingID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredOfferingID, !configuredOfferingID.isEmpty,
           let explicit = offerings.all[configuredOfferingID] {
            return explicit
        }
        return offerings.current
    }

    private func preferredPackage(from offering: Offering?) -> Package? {
        guard let offering else { return nil }
        return offering.annual ?? offering.monthly ?? offering.lifetime ?? offering.availablePackages.first
    }

    private func offerKind(for package: Package) -> RevenueCatOfferSnapshot.Kind {
        switch package.packageType {
        case .monthly:
            return .monthly
        case .annual:
            return .annual
        case .lifetime:
            return .lifetime
        default:
            return .unknown
        }
    }
    #endif

    private func clearSubscriptionState() {
        isSubscriber = false
        canPurchase = false
        primaryOffer = nil
        #if canImport(RevenueCat)
        primaryPackage = nil
        #endif
        Task {
            await ProtectedServiceAuthStore.shared.updateSubscriptionStatus(isSubscriber: false)
        }
    }

    private func localizedRevenueCatNotReady(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "RevenueCat 尚未設定完成，暫時無法開始訂閱。"
        case .unitedStates:
            return "RevenueCat is not configured yet, so subscriptions are not available right now."
        case .japan:
            return "RevenueCat の設定がまだ完了していないため、現在は購読を開始できません。"
        }
    }

    private func localizedPurchaseSuccess(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "訂閱已啟用，AI / OCR 功能現已解鎖。"
        case .unitedStates:
            return "Subscription activated. AI / OCR features are now unlocked."
        case .japan:
            return "購読が有効になりました。AI / OCR 機能が解放されました。"
        }
    }

    private func localizedRestoreSuccess(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "已成功還原訂閱。"
        case .unitedStates:
            return "Subscription restored successfully."
        case .japan:
            return "購読を正常に復元しました。"
        }
    }

    private func localizedRestoreEmpty(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "目前沒有可還原的有效訂閱。"
        case .unitedStates:
            return "No active subscription was found to restore."
        case .japan:
            return "復元できる有効な購読が見つかりませんでした。"
        }
    }

    private func localizedPurchaseFailure(for region: SupportedRegionUI, error: Error) -> String {
        let message = error.localizedDescription
        switch region {
        case .taiwan:
            return "訂閱處理失敗：\(message)"
        case .unitedStates:
            return "Subscription failed: \(message)"
        case .japan:
            return "購読処理に失敗しました: \(message)"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
