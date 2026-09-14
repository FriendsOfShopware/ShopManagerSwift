import SwiftUI
import ShopwareAdminAPI

struct ConnectView: View {
    @Environment(AppViewModel.self) private var model
    var isFirstShop = false
    var onClose: () -> Void = {}
    let onFinished: (String) -> Void
    @State private var vm: ConnectViewModel?

    init(isFirstShop: Bool = false, onClose: @escaping () -> Void = {},
         onFinished: @escaping (String) -> Void, viewModel: ConnectViewModel? = nil) {
        self.isFirstShop = isFirstShop
        self.onClose = onClose
        self.onFinished = onFinished
        _vm = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let vm {
                if isFirstShop {
                    ConnectFlow(vm: vm, isFirstShop: true, onFinished: onFinished)
                } else {
                    NavigationStack {
                        ConnectFlow(vm: vm, isFirstShop: false, onFinished: onFinished)
                            .navigationTitle("Connect a shop")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { vm.cancel(); onClose() }
                                        .disabled(vm.saving)
                                        .accessibilityIdentifier("setup.cancel")
                                }
                            }
                    }
                    .interactiveDismissDisabled(vm.saving)
                    #if os(macOS)
                    .frame(width: 560, height: vm.step == .shop ? 420 : vm.step == .signIn ? 540 : 680)
                    .presentationSizing(.fitted)
                    #endif
                }
            } else {
                ProgressView()
            }
        }
        .onAppear { if vm == nil { vm = ConnectViewModel(repo: model.repo) } }
        .onDisappear { vm?.cancel() }
        .acceptsFirstMouse()
    }
}

/// All steps and interactions are shared; only the surrounding presentation adapts.
struct ConnectFlow: View {
    @Bindable var vm: ConnectViewModel
    let isFirstShop: Bool
    let onFinished: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var showsPassword = false
    @State private var showsAccess = false

    private enum Field: Hashable { case address, username, password, visiblePassword, name }
    private let surface = Theme.setupSurface
    private let backdrop = Theme.setupBackdrop

    var body: some View {
        GeometryReader { geometry in
            let wide = isFirstShop && geometry.size.width >= 860 && !typeSize.isAccessibilitySize
            let card = isFirstShop && geometry.size.width >= 600
            HStack(spacing: 44) {
                if wide {
                    SetupWelcomeArtwork()
                        .frame(width: 300)
                }
                panel(compactWelcome: !wide && isFirstShop, card: card)
                    .frame(maxWidth: 520, maxHeight: card ? max(0, min(panelHeight, geometry.size.height - 48)) : .infinity)
            }
            .padding(.horizontal, card ? 32 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(isFirstShop ? backdrop : surface)
        .onChange(of: vm.step) { _, step in
            showsPassword = false
            showsAccess = false
            focusedField = step == .signIn ? .username : nil
        }
        .onChange(of: showsPassword) { _, visible in
            focusedField = visible ? .visiblePassword : .password
        }
        .onDisappear { vm.cancel() }
    }

    private var panelHeight: CGFloat {
        if typeSize.isAccessibilitySize { return 760 }
        switch vm.step {
        case .shop: return 380
        case .signIn: return 520
        case .personalize: return 680
        }
    }

    private func panel(compactWelcome: Bool, card: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if compactWelcome && vm.step == .shop {
                        SetupWelcomeArtwork(compact: true)
                    }
                    SetupProgress(step: vm.step)
                    stepHeading
                    if vm.step == .signIn { shopIdentity }
                    Group {
                        switch vm.step {
                        case .shop: addressFields
                        case .signIn: signInFields
                        case .personalize: personalFields
                        }
                    }
                    .disabled(vm.busy)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: vm.step)
                    if vm.busy {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(vm.status).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("setup.status")
                    }
                    if let issue = vm.issue {
                        Label { Text(issue).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(light: 0xAD3229, dark: 0xFF9E94))
                        .accessibilityIdentifier("setup.error")
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("setup.content")
            footer
        }
        .background(surface, in: .rect(cornerRadius: card ? 28 : 0))
        .overlay {
            if card { RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.accent.opacity(0.08)) }
        }
    }

    private var stepHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.title.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("setup.heading")
            Text(subheading).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heading: LocalizedStringResource {
        switch vm.step {
        case .shop: "Connect your shop"
        case .signIn: "Sign in to your shop"
        case .personalize: "Make it yours"
        }
    }
    private var subheading: LocalizedStringResource {
        switch vm.step {
        case .shop: "Start with the address of your Shopware 6 shop."
        case .signIn: "Use the same account you use in your Shopware administration."
        case .personalize: "Your shop is connected. Choose how it appears in the app."
        }
    }

    private var shopIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "storefront")
                .foregroundStyle(Theme.accent)
            Text(verbatim: vm.normalizedUrl.replacingOccurrences(of: "https://", with: ""))
                .font(.subheadline).lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 12))
    }

    private var addressFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Shop address")
            TextField("Shop address", text: $vm.url, prompt: Text(verbatim: "https://your-shop.com"))
                .labelsHidden()
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focusedField, equals: .address)
                .submitLabel(.continue)
                .onSubmit(advance)
                .accessibilityIdentifier("setup.address")
            Text("You can paste your storefront or administration address.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var signInFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Username")
                TextField("Username", text: $vm.username)
                    .labelsHidden().textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = showsPassword ? .visiblePassword : .password }
                    .accessibilityIdentifier("setup.username")
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Password")
                HStack(spacing: 8) {
                    Group {
                        if showsPassword {
                            TextField("Password", text: $vm.password)
                                .focused($focusedField, equals: .visiblePassword)
                        } else {
                            SecureField("Password", text: $vm.password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .labelsHidden().textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.go)
                    .onSubmit(advance)
                    .accessibilityIdentifier("setup.password")
                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .frame(minWidth: 32, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsPassword ? Text("Hide password") : Text("Show password"))
                    .help(showsPassword ? Text("Hide password") : Text("Show password"))
                    .accessibilityIdentifier("setup.passwordVisibility")
                }
            }
            Label {
                Text("Your sign-in details are encrypted on this device, so the app can reconnect when needed.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "lock.shield") }
            .font(.caption).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
    }

    private var personalFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupShopPreview(name: vm.shopName, address: vm.normalizedUrl, tintIndex: vm.tintIndex)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: vm.tintIndex)
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Shop name")
                TextField("Shop name", text: $vm.shopName).labelsHidden()
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done).onSubmit { focusedField = nil }
                    .accessibilityIdentifier("setup.name")
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Shop color")
                TintPicker(selection: $vm.tintIndex)
            }
            if !vm.languages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Content language")
                    Picker("Content language", selection: Binding(
                        get: { vm.selectedLanguage?.id ?? "" },
                        set: { id in vm.selectedLanguage = vm.languages.first { $0.id == id } }
                    )) {
                        ForEach(vm.languages) { language in
                            Text(verbatim: language.name).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("setup.language")
                }
            }
            DisclosureGroup(isExpanded: $showsAccess) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.verify.scopes) { scope in
                        HStack {
                            Label { Text(scope.label) } icon: {
                                Image(systemName: scope.ok ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(scope.ok ? Theme.accent : .secondary)
                            }
                            Spacer()
                            Text(scope.ok ? "Available" : "Unavailable").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if let version = vm.verify.version {
                        LabeledContent("Shopware", value: version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(vm.verify.scopes.allSatisfy(\.ok) ? "Shop access" : "Some areas are unavailable")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("setup.access")
            Text("You can change these preferences and set a revenue target in shop settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fieldLabel(_ title: LocalizedStringResource) -> some View {
        Text(title).font(.subheadline.weight(.medium))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            footerButtons
            .padding(24)
        }
    }

    private var footerButtons: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            if vm.step != .shop {
                Button("Back") { focusedField = nil; vm.goBack() }
                    .disabled(vm.saving)
                    .accessibilityIdentifier("setup.back")
            } else if vm.busy {
                Button("Cancel check") { vm.cancel() }
                    .accessibilityIdentifier("setup.cancelCheck")
            }
            Button(action: advance) {
                Text(vm.step == .personalize ? "Open shop" : vm.step == .signIn ? "Sign in" : "Continue")
                    .foregroundStyle(vm.canContinue ? Theme.onAccent : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!vm.canContinue)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("setup.continue")
        }
    }

    private func advance() {
        guard vm.canContinue else { return }
        focusedField = nil
        switch vm.step {
        case .shop: vm.submitUrl()
        case .signIn: vm.signIn()
        case .personalize: vm.finish(onDone: onFinished)
        }
    }
}

struct TintPicker: View {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<TintPalette.count, id: \.self) { index in
                let tint = TintPalette[index]
                Button { selection = index } label: {
                    Circle().fill(tint.bg(colorScheme == .dark))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selection == index {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint.fg(colorScheme == .dark))
                            }
                        }
                        .padding(6)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(index + 1)")
                .accessibilityAddTraits(selection == index ? [.isSelected] : [])
                .accessibilityIdentifier("setup.tint.\(index)")
            }
        }
    }
}
