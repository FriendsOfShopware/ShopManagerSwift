import SwiftUI
import ShopwareAdminAPI

/// Maps a `PromoStatus` to its badge label and tone (mirrors the Android promo state coloring).
private func promoBadge(_ status: PromoStatus) -> (label: String, tone: BadgeTone) {
    switch status {
    case .active: ("Active", .done)
    case .scheduled: ("Scheduled", .inProgress)
    case .ended: ("Ended", .neutral)
    }
}

@MainActor
@Observable
final class PromosViewModel: ListingViewModel<ShopPromo> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<ShopPromo> {
        let filters: [ListingFilter] = [
            .bool(key: "active", label: "Active", field: "active", trueLabel: "Active", falseLabel: "Inactive"),
            // NOTE: promotions reference sales channels via the m:n path.
            salesChannelFilter(label: "Sales channel", field: "salesChannels.salesChannelId"),
        ]

        return ListingState(
            filters: filters,
            source: { try await api.repository("promotion").search($0) },
            baseCriteria: { promoCriteria() },
            mapper: { parsePromo($0, Date(), shop) }
        )
    }
}

/// Promotions listing. Rows expose an active toggle and, for individual-code promotions, a
/// generate-codes action. Ports the Android `PromosScreen`.
struct PromosView: View {
    let shop: ConnectedShop
    @Environment(AppViewModel.self) private var model
    @State private var vm: PromosViewModel?
    @State private var codesMessage: String?

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                ListingScaffold(
                    state: listing,
                    api: vm.api,
                    searchPrompt: "Search promotions",
                    quickChips: chips(for: listing)
                ) { promo in
                    PromoCard(
                        promo: promo,
                        onToggle: { newValue in
                            Task {
                                try? await model.repo.setPromotionActive(shop, promotionId: promo.id, active: newValue)
                                listing.mutateItem(where: { $0.id == promo.id }) { var p = $0; p.active = newValue; return p }
                            }
                        },
                        onGenerateCodes: {
                            Task {
                                try? await model.repo.addPromotionCodes(shop, promotionId: promo.id, amount: 10)
                                codesMessage = "Generated 10 codes for \(promo.name)."
                            }
                        }
                    )
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Promotions")
        .onAppear {
            if vm == nil { vm = PromosViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .alert("Codes generated", isPresented: Binding(
            get: { codesMessage != nil },
            set: { if !$0 { codesMessage = nil } }
        )) {
            Button("OK", role: .cancel) { codesMessage = nil }
        } message: {
            Text(codesMessage ?? "")
        }
    }

    private func chips(for listing: ListingState<ShopPromo>) -> [QuickChip] {
        let quick: [(LocalizedStringKey, FilterValue)] = [
            ("Active", .options(["true"])),
            ("Inactive", .options(["false"])),
        ]
        return quick.map { label, value in
            let isOn = listing.activeValues["active"] == value
            return QuickChip(label: label, isOn: isOn) {
                listing.setFilterValue("active", isOn ? nil : value)
            }
        }
    }
}

/// A single promotion row: name + status, a detail subtitle (discount · window · redemptions),
/// and a trailing active toggle. Code generation is a swipe action to keep the row clean.
private struct PromoCard: View {
    let promo: ShopPromo
    let onToggle: (Bool) -> Void
    let onGenerateCodes: () -> Void

    var body: some View {
        let badge = promoBadge(promo.status)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(promo.name).lineLimit(1)
                HStack(spacing: 5) {
                    StatusBadge(label: badge.label, tone: badge.tone)
                    Text("· \(promo.detail) · ^[\(promo.redemptions) redeemed](inflect: true)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Toggle("Active", isOn: Binding(get: { promo.active }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if promo.useIndividualCodes {
                Button("Codes", systemImage: "qrcode", action: onGenerateCodes)
                    .tint(Theme.accent)
            }
        }
    }
}
