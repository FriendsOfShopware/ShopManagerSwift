import SwiftUI
import PhotosUI
import ShopwareAdminAPI

/// Quick-edit sheet: toggles a product's active flag, adjusts stock, edits the gross price (when
/// editable), and adds a cover photo — without leaving the listing. Loads its own `ProductQuickInfo`.
struct ProductActionSheet: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let productId: String

    @State private var info: ProductQuickInfo?
    @State private var active = false
    @State private var stock = 0
    @State private var priceModel: PriceEditModel?
    @State private var photoItem: PhotosPickerItem?
    #if os(iOS)
    @State private var showingCamera = false
    #endif
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    form(info)
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Quick edit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || info == nil)
                }
            }
            .task { await load() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
            #if os(iOS)
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in Task { await uploadData(data) } }
                    .ignoresSafeArea()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 520)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .acceptsFirstMouse()
    }

    private func form(_ info: ProductQuickInfo) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name).font(.headline)
                    Text(info.productNumber).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Active in shop", isOn: $active)
                Stepper("Stock: \(stock)", value: $stock, in: 0 ... 999_999)
            }

            Section("Price") {
                if let priceModel {
                    PriceEditor(shop: shop, editable: info.priceEditable, model: priceModel)
                }
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo")
                }
                #if os(iOS)
                Button { showingCamera = true } label: { Label("Take photo", systemImage: "camera") }
                #endif
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .groupedFormStyle()
    }

    private func load() async {
        error = nil
        do {
            let loaded = try await model.repo.productQuickInfo(shop, productId: productId)
            info = loaded
            if let loaded {
                active = loaded.active
                stock = loaded.stock
                priceModel = PriceEditModel(
                    gross: loaded.grossPrice, net: loaded.netPrice,
                    linked: loaded.priceLinked, taxRate: loaded.taxRate
                )
            }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    private func save() async {
        guard let info else { return }
        saving = true
        error = nil
        let price = priceModel?.edit(editable: info.priceEditable)
        do {
            try await model.repo.saveProductQuickEdit(shop, info: info, stock: stock, active: active, price: price)
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }

    private func upload(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await uploadData(data)
    }

    private func uploadData(_ data: Data) async {
        error = nil
        do {
            try await model.repo.uploadProductPhoto(shop, productId: productId, bytes: data)
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }
}
