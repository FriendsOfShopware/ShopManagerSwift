#if os(macOS) || os(iOS)
import SwiftUI
#if os(iOS)
import WebKit
#endif
import ShopwareAdminAPI

struct CustomerLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: CustomerDetailViewModel
    @State private var domains: [CustomerStorefrontDomain] = []
    @State private var selectedDomainID: String?
    @State private var loading = true
    @State private var loggingIn = false
    @State private var loginTask: Task<Void, Never>?
    @State private var error: String?
    #if os(iOS)
    @State private var showingStorefront = false
    @State private var page: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        return WebPage(configuration: configuration)
    }()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if showingStorefront {
                NavigationStack {
                    WebView(page)
                        .navigationTitle("Log in as \(vm.detail?.name ?? "customer")")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                            ToolbarItem(placement: .automatic) {
                                Text(page.url?.host() ?? "").foregroundStyle(.secondary)
                            }
                        }
                }
            } else {
                storefrontPicker
            }
            #else
            storefrontPicker
                .frame(width: 480)
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        #if os(macOS)
        .presentationSizing(.fitted)
        #else
        .presentationDetents(showingStorefront ? [.large] : [.medium, .large])
        #endif
        .task { await loadDomains() }
        .onDisappear { loginTask?.cancel() }
    }

    private var selectedDomain: CustomerStorefrontDomain? {
        domains.first { $0.id == selectedDomainID }
    }

    private var storefrontPicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Log in as \(vm.detail?.name ?? "customer")")
                    .font(.headline)
                #if os(macOS)
                Text("Choose the storefront to open in your default browser with this customer's account.")
                    .foregroundStyle(.secondary)
                #else
                Text("Choose the storefront to open with this customer's account.")
                    .foregroundStyle(.secondary)
                #endif
            }

            if loading {
                ProgressView("Loading storefronts…")
                    .controlSize(.small)
            } else if !domains.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Storefront", selection: $selectedDomainID) {
                        ForEach(domains) { domain in
                            Text(domains.count > 1 ? "\(domain.name) — \(domain.url.absoluteString)" : domain.name)
                                .tag(Optional(domain.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(loggingIn)
                    if let selectedDomain {
                        Text(selectedDomain.url.absoluteString)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if error == nil {
                Label("No active storefront is available for this customer's sales-channel binding.", systemImage: "storefront")
                    .foregroundStyle(.secondary)
            }

            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if domains.isEmpty {
                        Button("Retry") { Task { await loadDomains() } }
                    }
                }
            }

            HStack {
                if loggingIn {
                    ProgressView().controlSize(.small)
                    Text("Logging in…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Log in", action: login)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || loggingIn || selectedDomain == nil)
            }
        }
        .padding(24)
    }

    private func loadDomains() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            domains = try await vm.api.customerStorefrontDomains(boundSalesChannelId: vm.detail?.boundSalesChannelId)
            if selectedDomain == nil { selectedDomainID = domains.first?.id }
        }
        catch is CancellationError { }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }

    private func login() {
        guard !loading, !loggingIn, let domain = selectedDomain,
              vm.permissions.allows("api_proxy_imitate-customer"), let userId = vm.permissions.userId else { return }
        loggingIn = true
        error = nil
        loginTask = Task {
            defer { loggingIn = false }
            do {
                let token = try await vm.api.customers.imitateToken(customerId: vm.customerId, salesChannelId: domain.salesChannelId)
                try Task.checkCancellation()
                #if os(macOS)
                try await CustomerBrowserLogin.open(domain: domain.url, token: token, customerId: vm.customerId, userId: userId)
                dismiss()
                #else
                showingStorefront = true
                for try await _ in page.load(customerImitationRequest(domain: domain.url, token: token, customerId: vm.customerId, userId: userId)) {}
                #endif
            } catch is CancellationError {
            } catch {
                #if os(iOS)
                showingStorefront = false
                #endif
                self.error = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }
}
#endif
