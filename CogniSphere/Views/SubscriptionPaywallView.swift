import SwiftUI

private struct PaywallLegalRoute: Identifiable {
    let id = UUID()
    let document: LegalDocumentKind
}

struct SubscriptionPaywallView: View {
    let presentation: SubscriptionPaywallPresentation

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore
    @EnvironmentObject private var subscriptionAccess: SubscriptionAccessController
    @State private var paywallMessage: String?
    @State private var isSubmitting = false
    @State private var legalRoute: PaywallLegalRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(subscriptionAccess.paywallBullets(for: regionUI.region), id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(regionUI.theme.accent)
                                Text(bullet)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(regionUI.theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(regionUI.theme.outline.opacity(0.7), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        Button {
                            submitPurchase()
                        } label: {
                            VStack(spacing: 4) {
                                Text(subscriptionAccess.primaryCTA(for: regionUI.region))
                                    .font(.headline)

                                if let offer = subscriptionAccess.primaryOffer {
                                    Text("\(subscriptionAccess.offerTitle(for: regionUI.region) ?? "") · \(offer.priceText)")
                                        .font(.caption)
                                        .opacity(0.9)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)

                        Button(subscriptionAccess.restoreCTA(for: regionUI.region)) {
                            restorePurchases()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSubmitting)

                        Button(subscriptionAccess.closeCTA(for: regionUI.region)) {
                            closePaywall()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    if !subscriptionAccess.canPurchase && !subscriptionAccess.hasRevenueCatConfiguration {
                        Text(subscriptionAccess.notReadyHint(for: regionUI.region))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    legalLinksSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(regionUI.theme.canvas.ignoresSafeArea())
            .navigationTitle(subscriptionAccess.paywallTitle(for: regionUI.region, reason: presentation.reason))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.close) {
                        closePaywall()
                    }
                }
            }
        }
        .alert(localizedPaywallAlertTitle, isPresented: Binding(
            get: { paywallMessage != nil },
            set: { if !$0 { paywallMessage = nil } }
        )) {
            Button(regionUI.copy.ok, role: .cancel) {}
        } message: {
            Text(paywallMessage ?? "")
        }
        .sheet(item: $legalRoute) { route in
            LegalCenterView(initialDocument: route.document)
                .environmentObject(regionUI)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: subscriptionAccess.isSubscriber ? "checkmark.seal.fill" : "sparkles")
                    .font(.title2)
                    .foregroundStyle(regionUI.theme.accent)

                Text(subscriptionAccess.quotaStatusLabel(for: regionUI.region))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(subscriptionAccess.paywallSubtitle(
                for: regionUI.region,
                feature: presentation.feature,
                reason: presentation.reason
            ))
            .font(.body)
            .foregroundStyle(.secondary)

            if let offer = subscriptionAccess.primaryOffer {
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.priceText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(regionUI.theme.accent)

                    if let subtitle = subscriptionAccess.offerSubtitle(for: regionUI.region) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let currencyNotice = subscriptionAccess.billingCurrencyNotice(for: regionUI.region) {
                        Text(currencyNotice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(regionUI.theme.cardSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(regionUI.theme.outline.opacity(0.75), lineWidth: 1)
        )
    }

    private var localizedPaywallAlertTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "訂閱結果"
        case .unitedStates:
            return "Subscription Result"
        case .japan:
            return "購読結果"
        }
    }

    private var legalLinksSection: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(localizedLegalNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button(localizedPrivacyCTA) {
                    legalRoute = PaywallLegalRoute(document: .privacy)
                }
                .buttonStyle(.bordered)

                Button("EULA") {
                    legalRoute = PaywallLegalRoute(document: .eula)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var localizedLegalNotice: String {
        switch regionUI.region {
        case .taiwan:
            return "訂閱前可先查看隱私權政策與授權條款。"
        case .unitedStates:
            return "Review the Privacy Policy and EULA before purchasing."
        case .japan:
            return "購読前にプライバシーポリシーと EULA を確認できます。"
        }
    }

    private var localizedPrivacyCTA: String {
        switch regionUI.region {
        case .taiwan:
            return "隱私權政策"
        case .unitedStates:
            return "Privacy Policy"
        case .japan:
            return "プライバシー"
        }
    }

    private func submitPurchase() {
        isSubmitting = true
        Task {
            let message = await subscriptionAccess.purchasePrimaryOffer(for: regionUI.region)
            await MainActor.run {
                isSubmitting = false
                if subscriptionAccess.presentedPaywall == nil {
                    paywallMessage = nil
                    dismiss()
                } else {
                    paywallMessage = message
                }
            }
        }
    }

    private func restorePurchases() {
        isSubmitting = true
        Task {
            let message = await subscriptionAccess.restorePurchases(for: regionUI.region)
            await MainActor.run {
                isSubmitting = false
                if subscriptionAccess.presentedPaywall == nil {
                    paywallMessage = nil
                    dismiss()
                } else {
                    paywallMessage = message
                }
            }
        }
    }

    private func closePaywall() {
        paywallMessage = nil
        legalRoute = nil
        subscriptionAccess.dismissPaywall()
        dismiss()
    }
}
