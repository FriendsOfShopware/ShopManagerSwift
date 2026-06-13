import SwiftUI
import ShopwareAdminAPI

/// Per-shop settings: rename, tint, daily target, low-stock threshold, content language, sign-in-
/// again (reauthenticate), and remove.
struct ShopSettingsView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop

    @State private var name = ""
    @State private var tintIndex = 0
    @State private var targetText = ""
    @State private var thresholdText = ""
    @State private var languages: [LanguageOption] = []
    @State private var languageId: String?
    @State private var showingSignIn = false
    @State private var showingRemove = false

    var body: some View {
        Form {
            Section("Appearance") {
                TextField("Shop name", text: $name)
                TintPicker(selection: $tintIndex)
            }

            Section("Dashboard") {
                TextField("Daily revenue target (optional)", text: $targetText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("Low-stock threshold", text: $thresholdText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            if !languages.isEmpty {
                Section("Content language") {
                    Picker("Language", selection: Binding(
                        get: { languageId ?? "" },
                        set: { id in
                            languageId = id.isEmpty ? nil : id
                            model.setShopLanguage(shopId: shop.id, language: languages.first { $0.id == id })
                        }
                    )) {
                        ForEach(languages) { lang in Text(lang.name).tag(lang.id) }
                    }
                }
            }

            Section {
                Button("Sign in again") { showingSignIn = true }
            } footer: {
                Text("Re-authenticate if your session expired or privileges changed.")
            }

            Section {
                Button("Remove shop", role: .destructive) { showingRemove = true }
            }
        }
        .groupedFormStyle()
        .navigationTitle("Shop settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingSignIn) {
            SignInAgainSheet(shop: shop)
        }
        .alert("Remove \(shop.name)?", isPresented: $showingRemove) {
            Button("Remove", role: .destructive) {
                model.removeShop(shop.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects the shop and clears its cached data on this device.")
        }
    }

    private func load() async {
        name = shop.name
        tintIndex = shop.tintIndex
        targetText = shop.dailyTarget.map { String(Int($0)) } ?? ""
        thresholdText = "\(shop.lowStockThreshold)"
        languageId = shop.languageId
        languages = (try? await model.languagesFor(shop)) ?? []
    }

    private func save() {
        model.updateShopSettings(
            shopId: shop.id,
            name: name.trimmingCharacters(in: .whitespaces),
            tintIndex: tintIndex,
            dailyTarget: Double(targetText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil },
            lowStockThreshold: Int(thresholdText) ?? shop.lowStockThreshold
        )
    }
}

/// Sign-in-again form (reauthenticate with the admin password — only a refresh token is kept).
struct SignInAgainSheet: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop

    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .groupedFormStyle()
            .navigationTitle("Sign in again")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign in") {
                        Task {
                            busy = true
                            error = await model.reauthenticate(shop, username: username, password: password)
                            busy = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(busy || username.isEmpty || password.isEmpty)
                }
            }
        }
    }
}
