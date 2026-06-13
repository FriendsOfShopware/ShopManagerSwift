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
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
    }
}

private struct ConnectSteps: View {
    @Bindable var vm: ConnectViewModel
    let onFinished: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                switch vm.step {
                case 0: urlStep
                case 1: credentialsStep
                case 2: verifyStep
                default: personalizeStep
                }
            }
            #if os(iOS)
            .formStyle(.grouped)
            #else
            .formStyle(.columns)
            .padding()
            #endif

            actionBar
        }
        .animation(.default, value: vm.step)
    }

    /// A single prominent primary button per step, pinned to the bottom (native look on both
    /// platforms rather than a flat in-form button row).
    @ViewBuilder
    private var actionBar: some View {
        let action: (label: LocalizedStringKey, run: () -> Void, enabled: Bool)? = {
            switch vm.step {
            case 0:
                return ("Continue", { vm.submitUrl() },
                        !vm.url.trimmingCharacters(in: .whitespaces).isEmpty && !vm.busy)
            case 1:
                return ("Verify access", { vm.startVerify() }, vm.credsValid)
            case 2 where vm.verify.connected:
                return ("Continue", { vm.toPersonalize() }, vm.canLeaveVerify)
            case 2 where vm.verify.error != nil:
                return ("Back to login", { vm.retryFromCredentials() }, true)
            case 3:
                return ("Add shop", { vm.finish(onDone: onFinished) }, !vm.busy)
            default:
                return nil
            }
        }()

        if let action {
            VStack(spacing: 0) {
                Divider()
                Button(action: action.run) {
                    HStack {
                        Text(action.label).frame(maxWidth: .infinity)
                        if vm.busy { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!action.enabled)
                .padding()
            }
        }
    }

    // MARK: Step 0 — URL

    private var urlStep: some View {
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
    }

    // MARK: Step 1 — Credentials

    private var credentialsStep: some View {
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
    }

    // MARK: Step 2 — Verify

    @ViewBuilder
    private var verifyStep: some View {
        if vm.verify.running {
            Section {
                HStack { ProgressView().controlSize(.small); Text("Verifying…").foregroundStyle(.secondary) }
            }
        } else if let error = vm.verify.error {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
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

            Section {
                ForEach(vm.verify.scopes) { scope in
                    Label {
                        Text(scope.label)
                    } icon: {
                        Image(systemName: scope.ok ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(scope.ok ? Theme.accent : .secondary)
                    }
                }
            } header: {
                Text("Access check")
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
