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
    @State private var generatingFor: ShopPromo?
    @State private var resultMessage: String?
    @State private var actionError: String?

    private var snapshot: ShopSnapshot? { model.snapshot(shop.id) }

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                ListingScaffold(
                    state: listing,
                    api: vm.api,
                    searchPrompt: "Search promotions",
                    quickChips: chips(for: listing),
                    header: { heroHeader }
                ) { promo in
                    PromoCard(
                        promo: promo,
                        onToggle: { newValue in toggle(promo, active: newValue, listing: listing) },
                        onGenerateCodes: { generatingFor = promo }
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
        .sheet(item: $generatingFor) { promo in
            GenerateCodesSheet(promo: promo) { amount in
                await generateCodes(promo, amount: amount)
            }
        }
        .alert("Codes generated", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("Couldn't update", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private var heroHeader: some View {
        if let snapshot, !snapshot.promos.isEmpty {
            let live = snapshot.promos.filter { $0.status == .active }.count
            let redemptions = snapshot.promos.reduce(0) { $0 + $1.redemptions }
            Section {
                MetricRow(symbol: "tag", label: "Live campaigns", value: "\(live)")
                MetricRow(symbol: "checkmark.seal", label: "Redemptions", value: "\(redemptions)")
            }
        }
    }

    private func toggle(_ promo: ShopPromo, active: Bool, listing: ListingState<ShopPromo>) {
        Task {
            do {
                try await model.repo.setPromotionActive(shop, promotionId: promo.id, active: active)
                // status/window derive from active — refetch instead of patching locally.
                listing.reload()
                model.refresh(shop.id)
            } catch {
                actionError = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }

    private func generateCodes(_ promo: ShopPromo, amount: Int) async {
        do {
            try await model.repo.addPromotionCodes(shop, promotionId: promo.id, amount: amount)
            resultMessage = String(localized: "Added ^[\(amount) code](inflect: true) to \(promo.name).")
        } catch {
            actionError = (error as? ApiError)?.message ?? error.localizedDescription
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
                    Text("· \(promo.detail) · \(promo.window) · ^[\(promo.redemptions) redeemed](inflect: true)")
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

/// Amount-input dialog for generating individual promotion codes (1…500).
private struct GenerateCodesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let promo: ShopPromo
    let onGenerate: (Int) async -> Void

    @State private var amountText = "10"
    @State private var busy = false

    private var amount: Int? {
        guard let n = Int(amountText.trimmingCharacters(in: .whitespaces)), (1...500).contains(n) else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } header: {
                    Text("Number of codes")
                } footer: {
                    Text("Generate between 1 and 500 individual codes for \(promo.name).")
                }
            }
            .groupedFormStyle()
            .navigationTitle("Generate codes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        guard let amount else { return }
                        Task {
                            busy = true
                            await onGenerate(amount)
                            busy = false
                            dismiss()
                        }
                    }
                    .disabled(amount == nil || busy)
                }
            }
        }
        .presentationDetents([.height(220)])
        .acceptsFirstMouse()
    }
}
