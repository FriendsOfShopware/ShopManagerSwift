import SwiftUI
import ShopwareAdminAPI

/// 4-step connect wizard: URL → admin login → ACL verify checklist → personalize.
struct ConnectView: View {
    @Environment(AppViewModel.self) private var model
    let onClose: () -> Void
    let onFinished: (String) -> Void

    @State private var vm: ConnectViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    ConnectSteps(vm: vm, onFinished: onFinished)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Connect a shop")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if let vm, vm.goBack() { return }
                        onClose()
                    }
                }
            }
        }
        .onAppear {
            if vm == nil { vm = ConnectViewModel(repo: model.repo) }
        }
    }
}

private struct ConnectSteps: View {
    @Bindable var vm: ConnectViewModel
    let onFinished: (String) -> Void

    var body: some View {
        Form {
            switch vm.step {
            case 0: urlStep
            case 1: credentialsStep
            case 2: verifyStep
            default: personalizeStep
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: vm.step)
    }

    // MARK: Step 0 — URL

    private var urlStep: some View {
        Group {
        Section {
            TextField("https://your-shop.com", text: $vm.url)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if let error = vm.urlError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text("Shop address")
        } footer: {
            Text("Enter the URL of your Shopware 6 store. We'll verify it hosts an Admin API.")
        }

        Section {
            Button {
                vm.submitUrl()
            } label: {
                HStack {
                    Text("Continue")
                    if vm.busy { Spacer(); ProgressView() }
                }
            }
            .disabled(vm.url.trimmingCharacters(in: .whitespaces).isEmpty || vm.busy)
        }
        }
    }

    // MARK: Step 1 — Credentials

    private var credentialsStep: some View {
        Group {
            Section {
                TextField("Username", text: $vm.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $vm.password)
            } header: {
                Text("Admin login")
            } footer: {
                Text("Your admin credentials. The password is used once to sign in — only a rotating refresh token is stored.")
            }

            Section {
                Button("Verify access") { vm.startVerify() }
                    .disabled(!vm.credsValid)
            }
        }
    }

    // MARK: Step 2 — Verify

    @ViewBuilder
    private var verifyStep: some View {
        if vm.verify.running {
            Section {
                HStack { ProgressView(); Text("Verifying…").foregroundStyle(.secondary) }
            }
        } else if let error = vm.verify.error {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Back to login") { vm.retryFromCredentials() }
            }
        } else {
            Section {
                if let version = vm.verify.version {
                    LabeledContent("Shopware", value: version)
                }
            } header: {
                Label("Connected", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
            }

            Section("Access check") {
                ForEach(vm.verify.scopes) { scope in
                    Label {
                        Text(scope.label)
                    } icon: {
                        Image(systemName: scope.ok ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(scope.ok ? Theme.accent : .secondary)
                    }
                }
            }

            Section {
                Button("Continue") { vm.toPersonalize() }
                    .disabled(!vm.canLeaveVerify)
            } footer: {
                if !vm.canLeaveVerify {
                    Text("This login can't read any supported area. Use an account with more privileges.")
                }
            }
        }
    }

    // MARK: Step 3 — Personalize

    private var personalizeStep: some View {
        Group {
            Section("Shop") {
                TextField("Shop name", text: $vm.shopName)
                LabeledContent("Currency", value: vm.currency)
                TextField("Daily revenue target (optional)", text: $vm.dailyTarget)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }

            Section("Color") {
                TintPicker(selection: $vm.tintIndex)
            }

            if !vm.languages.isEmpty {
                Section("Content language") {
                    Picker("Language", selection: Binding(
                        get: { vm.selectedLanguage?.id ?? "" },
                        set: { id in vm.selectedLanguage = vm.languages.first { $0.id == id } }
                    )) {
                        ForEach(vm.languages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                }
            }

            Section {
                Button {
                    vm.finish(onDone: onFinished)
                } label: {
                    HStack {
                        Text("Add shop")
                        if vm.busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(vm.busy)
            }
        }
    }
}

/// Horizontal swatches for the five per-shop tints.
struct TintPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(TintPalette.enumerated()), id: \.offset) { index, tint in
                Circle()
                    .fill(tint.lightBg)
                    .frame(width: 34, height: 34)
                    .overlay {
                        if index == selection {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(tint.lightFg)
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(
                            index == selection ? Theme.accent : .clear, lineWidth: 2
                        )
                    }
                    .onTapGesture { selection = index }
            }
        }
        .padding(.vertical, 4)
    }
}
