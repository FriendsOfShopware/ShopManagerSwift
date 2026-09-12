import SwiftUI
import ShopwareAdminAPI
import QuickLook
import UniformTypeIdentifiers

struct OrderDocumentSheet: View {
    @Bindable var vm: OrderDetailViewModel
    @State private var type = "invoice"
    @State private var number = ""
    @State private var date = Date()
    @State private var deliveryDate = Date()
    @State private var comment = ""
    @State private var reference = ""
    @State private var upload = false
    @State private var importing = false
    @State private var file: Data?
    @State private var fileName = ""
    @State private var generated: GeneratedDocument?
    @State private var busy = false
    @State private var error: String?
    @State private var uncertain = false
    @State private var preview: URL?

    private var invoices: [OrderDocument] { (vm.detail?.documents ?? []).filter { $0.typeTechnical == "invoice" || $0.typeTechnical.hasPrefix("zugferd_") } }
    private var needsReference: Bool { type == "credit_note" || type == "storno" }
    private var valid: Bool {
        vm.canCreateDocuments && !uncertain && (!needsReference || invoices.contains { $0.id == reference }) &&
        (!upload || file != nil) && (type != "credit_note" || upload || vm.detail?.lineItems.contains { $0.type == "credit" } == true)
    }

    var body: some View {
        OrderFormSheet(title: "Create document", saveTitle: generated == nil ? "Create document" : "Retry upload",
                       canSave: valid, busy: busy, dirty: false, error: error, save: create,
                       cancel: { if generated != nil || uncertain { await vm.load() }; return true }) {
            Group {
                Section("Document") {
                    Picker("Document type", selection: $type) {
                        Text("Invoice").tag("invoice")
                        Text("Delivery note").tag("delivery_note")
                        Text("Credit note").tag("credit_note")
                        Text("Cancellation invoice").tag("storno")
                    }.accessibilityIdentifier("order.document.type")
                    DatePicker("Document date", selection: $date, displayedComponents: .date)
                    OrderLabeledField("Document number") {
                        TextField("Document number", text: $number, prompt: Text("Assigned automatically"))
                            .accessibilityIdentifier("order.document.number")
                    }
                    if type == "delivery_note" { DatePicker("Delivery date", selection: $deliveryDate, displayedComponents: .date) }
                    if needsReference {
                        Picker("Referenced invoice", selection: $reference) {
                            Text("Select an invoice").tag("")
                            ForEach(invoices) { Text($0.number).tag($0.id) }
                        }
                        if invoices.isEmpty { Text("Create an invoice before creating this document.").foregroundStyle(.secondary) }
                    }
                    OrderLabeledField("Document comment") {
                        TextField("Document comment", text: $comment, axis: .vertical).lineLimit(2...5)
                    }
                }
                Section {
                    Toggle("Upload an existing PDF", isOn: $upload).disabled(!vm.permissions.allows("document:update"))
                    if upload {
                        Button(fileName.isEmpty ? String(localized: "Choose PDF…") : fileName) { importing = true }
                        Text("PDF files up to 50 MB.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if type == "credit_note", vm.detail?.lineItems.contains(where: { $0.type == "credit" }) != true {
                            Text("Add a credit to the order before generating a credit note.").foregroundStyle(.secondary)
                        }
                        Button("Preview document", systemImage: "eye") { Task { await loadPreview() } }
                            .disabled(!valid).accessibilityIdentifier("order.document.preview")
                    }
                }
            }.disabled(generated != nil || uncertain)
            if generated != nil { Text("The document was created. Retry uploads the PDF to that same document.").foregroundStyle(.secondary) }
            if uncertain { Text("The response was lost. Close this sheet and check the document list before creating another document.").foregroundStyle(.secondary) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            do {
                let url = try result.get()
                let data = try readOrderPDF(url)
                file = data; fileName = url.lastPathComponent; error = nil
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
        .quickLookPreview($preview)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 600)
        #endif
    }

    private var config: JSONValue {
        var custom: [String: JSONValue] = [:]
        if let invoice = invoices.first(where: { $0.id == reference }) { custom["invoiceNumber"] = .string(invoice.number) }
        if type == "delivery_note" {
            custom["deliveryDate"] = .string(deliveryDate.ISO8601Format())
            custom["deliveryNoteDate"] = .string(date.ISO8601Format())
        }
        var config: [String: JSONValue] = ["documentDate": .string(date.ISO8601Format()), "documentComment": .string(comment)]
        if !number.trimmed.isEmpty {
            config["documentNumber"] = .string(number.trimmed)
            let key = ["invoice": "invoiceNumber", "delivery_note": "deliveryNoteNumber", "credit_note": "creditNoteNumber", "storno": "stornoNumber"][type] ?? "documentNumber"
            custom[key] = .string(number.trimmed)
        }
        config["custom"] = .object(custom)
        return .object(config)
    }

    private func create() async -> Bool {
        guard valid, !busy else { return false }
        busy = true; error = nil; defer { busy = false }
        do {
            if generated == nil {
                generated = try await vm.api.documents.generate(orderId: vm.orderId, type: type, config: config,
                                                               referencedDocumentId: needsReference ? reference : nil, staticDocument: upload)
            }
            if upload, let document = generated, let file {
                try await vm.api.documents.upload(documentId: document.id, data: file, fileName: String(fileName.dropLast(4)))
            }
            await vm.load()
            return true
        } catch {
            if generated == nil {
                switch error {
                case ApiError.network, ApiError.server: uncertain = true
                case ApiError.unexpected(let status, _): uncertain = status < 400 || status >= 500
                default: break
                }
            }
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
            return false
        }
    }

    private func loadPreview() async {
        guard let detail = vm.detail, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let data = try await vm.api.documents.preview(orderId: vm.orderId, deepLinkCode: detail.deepLinkCode, type: type, config: config,
                                                        referencedDocumentId: needsReference ? reference : nil)
            preview = try orderPDFPreview(data, name: "preview")
        } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
}
