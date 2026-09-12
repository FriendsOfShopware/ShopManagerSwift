import SwiftUI
import ShopwareAdminAPI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReviewDetailView: View {
    let shop: ConnectedShop
    let reviewID: String
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ReviewDetailViewModel?
    @State private var editing = false
    @State private var deleting = false

    var body: some View {
        Group {
            if let vm {
                if let review = vm.review { detail(review, vm: vm) }
                else if let error = vm.error {
                    ContentUnavailableView {
                        Label("Couldn't load review", systemImage: "exclamationmark.bubble")
                    } description: { Text(error) } actions: { Button("Retry") { Task { await vm.load() } } }
                } else { ProgressView("Loading review…") }
            } else { ProgressView("Loading review…") }
        }
        .navigationTitle("Review")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(shop.id)|\(shop.languageId ?? "")|\(reviewID)") {
            let value = ReviewDetailViewModel(api: model.repo.apiFor(shop), shop: shop, reviewID: reviewID)
            vm = value
            await value.load()
        }
    }
    private func detail(_ review: ReviewItem, vm: ReviewDetailViewModel) -> some View {
        Form {
            if let error = vm.error { Section { ReviewErrorBanner(message: error) { Task { await vm.load() } } } }
            if let error = vm.actions.permissionsError { Section { ReviewErrorBanner(message: error) { Task { await vm.actions.loadPermissions() } } } }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ReviewSummaryLine(review: review)
                    Text(review.title).font(.title2.bold()).accessibilityElement(children: .ignore).accessibilityLabel(review.title).accessibilityIdentifier("review.title")
                    Text(review.content).textSelection(.enabled).accessibilityElement(children: .ignore).accessibilityLabel(review.content).accessibilityIdentifier("review.content")
                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
            }
            Section("Review details") {
                LabeledContent("Product") {
                    if let id = review.productId, vm.actions.permissions.allows("product:read") {
                        NavigationLink { ProductDetailView(shop: shop, productId: id) } label: { Text(review.productName) }
                    } else { Text(review.productName) }
                }
                LabeledContent("Customer") {
                    if let id = review.customerId, vm.actions.permissions.allows("customer:read") {
                        NavigationLink { CustomerDetailView(shop: shop, customerId: id) } label: { Text(review.reviewer) }
                    } else { Text(review.reviewer) }
                }
                if let email = review.email, !email.isEmpty { LabeledContent("Email address", value: email).textSelection(.enabled) }
                LabeledContent("Sales channel", value: review.salesChannel)
                LabeledContent("Created at") {
                    if let date = review.createdAt { Text(date, format: .dateTime.day().month().year().hour().minute()) }
                    else { Text("—") }
                }
                LabeledContent("Language", value: review.languageName).accessibilityIdentifier("review.language")
            }
            Section {
                if review.hasReply { Text(review.comment).textSelection(.enabled).accessibilityIdentifier("review.reply") }
                else {
                    Text("No reply yet").foregroundStyle(.secondary)
                    if vm.actions.canEdit && vm.fieldsError == nil { Button("Write a reply…") { editing = true }.accessibilityIdentifier("review.writeReply") }
                }
            } header: { Text("Public reply") } footer: { Text("Your reply appears with the approved review in the storefront.") }
            if let error = vm.fieldsError { Section { ReviewErrorBanner(message: error) { Task { await vm.loadFields() } } } }
            ForEach(vm.fields) { set in
                Section(set.label) {
                    ForEach(set.fields) { field in
                        CustomerCustomFieldSummaryRow(field: field, value: review.customFields[field.name], api: vm.actions.api)
                    }
                }
            }
        }
        .groupedFormStyle()
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .overlay { if vm.actions.busy || vm.loading { ProgressView("Working…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit review", systemImage: "pencil") { editing = true }
                    .disabled(!vm.actions.canEdit || vm.loading || vm.fieldsError != nil).accessibilityIdentifier("review.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if vm.actions.permissions.allows("product_review:update") {
                        Button(review.approved ? "Hide review" : "Approve", systemImage: review.approved ? "eye.slash" : "checkmark") {
                            Task {
                                if await vm.actions.approve(id: review.id, approved: !review.approved) {
                                    model.refresh(shop.id); await vm.load()
                                }
                            }
                        }.accessibilityIdentifier("review.approve")
                    }
                    Button("Refresh review", systemImage: "arrow.clockwise") { Task { await vm.load() } }
                    if vm.actions.permissions.allows("product_review:delete") {
                        Button("Delete review…", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("review.delete")
                    }
                } label: { Label("Review actions", systemImage: "ellipsis.circle") }
                .disabled(vm.actions.busy || vm.loading).accessibilityIdentifier("review.actions")
            }
        }
        .sheet(isPresented: $editing) {
            ReviewEditorSheet(review: review, fields: vm.fields, actions: vm.actions) {
                model.refresh(shop.id)
                Task { await vm.load() }
            }
        }
        .confirmationDialog("Delete review?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete review", role: .destructive) {
                Task {
                    if await vm.actions.delete(ids: [review.id]).contains(review.id) { model.refresh(shop.id); dismiss() }
                }
            }
        } message: { Text("The review and its public reply will be permanently deleted.") }
        .alert("Couldn't update review", isPresented: Binding(get: { vm.actions.error != nil && !editing }, set: { if !$0 { vm.actions.error = nil } })) {
            Button("OK", role: .cancel) { vm.actions.error = nil }
        } message: { Text(vm.actions.error ?? "") }
        .accessibilityIdentifier("review.detail")
    }
}
