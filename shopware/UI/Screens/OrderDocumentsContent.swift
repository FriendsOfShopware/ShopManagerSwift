import SwiftUI
import ShopwareAdminAPI
import QuickLook
import UniformTypeIdentifiers

struct OrderDocumentsContent: View {
    @Bindable var vm: OrderDetailViewModel
    let detail: OrderDetail
    let create: () -> Void
    @State private var preview: URL?
    @State private var export: OrderPDFFile?
    @State private var exporting = false
    @State private var filename = "document"
    @State private var uploadTarget: OrderDocument?
    @State private var importing = false

    var body: some View {
        Group {
            if !vm.permissions.allows("document:read") {
                ContentUnavailableView("Document access unavailable", systemImage: "lock")
            } else if detail.documents.isEmpty {
                ContentUnavailableView {
                    Label("No documents yet", systemImage: "doc")
                } description: { Text("Create invoices, delivery notes, and credit notes for this order.") }
                actions: { Button("Generate document…", action: create).disabled(!vm.canCreateDocuments) }
            } else {
                List(detail.documents) { document in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(document.typeName, systemImage: "doc.text").font(.headline)
                            Spacer()
                            Text(document.number).monospacedDigit()
                        }
                        if let date = document.createdAt { Text(date, format: .dateTime.day().month().year()).foregroundStyle(.secondary) }
                        if document.staticDocument { Label("Uploaded PDF", systemImage: "arrow.up.doc").font(.caption).foregroundStyle(.secondary) }
                        if document.sent { Label("Sent to customer", systemImage: "envelope").font(.caption).foregroundStyle(.secondary) }
                        if let reference = document.referencedDocumentId, let invoice = detail.documents.first(where: { $0.id == reference }) {
                            Text("Invoice: \(invoice.number)").font(.callout).foregroundStyle(.secondary)
                        }
                        if document.hasFile {
                            HStack {
                                Button("Preview", systemImage: "eye") { Task { await prepare(document, download: false) } }
                                    .accessibilityIdentifier("order.document.preview.\(document.id)")
                                Button("Save PDF…", systemImage: "square.and.arrow.down") { Task { await prepare(document, download: true) } }
                            }.buttonStyle(.bordered).disabled(vm.busy)
                        } else {
                            Text("No PDF uploaded").foregroundStyle(.secondary)
                            Button("Upload PDF…", systemImage: "arrow.up.doc") { uploadTarget = document; importing = true }
                                .disabled(!vm.permissions.allows("document:update") || vm.busy)
                        }
                    }.padding(.vertical, 8)
                }.refreshable { await vm.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !detail.documents.isEmpty {
                HStack { Spacer(); Button("Generate document…", systemImage: "doc.badge.plus", action: create).disabled(!vm.canCreateDocuments) }
                    .padding().fixedSize(horizontal: false, vertical: true)
            }
        }
        .quickLookPreview($preview)
        .fileExporter(isPresented: $exporting, document: export, contentType: .pdf, defaultFilename: filename) { result in
            if case .failure(let error) = result { vm.actionError = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            guard let target = uploadTarget else { return }
            do {
                let url = try result.get()
                let data = try readOrderPDF(url)
                Task { await vm.uploadDocument(target, data: data, fileName: url.deletingPathExtension().lastPathComponent) }
            } catch { vm.actionError = (error as? ApiError)?.message ?? error.localizedDescription }
        }
        .accessibilityIdentifier("order.documents")
    }

    private func prepare(_ document: OrderDocument, download: Bool) async {
        guard let data = await vm.downloadDocument(document) else { return }
        filename = safeOrderDocumentName(document.number.isEmpty ? document.id : document.number)
        if download { export = OrderPDFFile(data: data); exporting = true }
        else {
            do { preview = try orderPDFPreview(data, name: filename) }
            catch { vm.actionError = error.localizedDescription }
        }
    }
}

func readOrderPDF(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 52_428_800 else {
        throw ApiError.unexpected(status: 400, message: String(localized: "Choose a PDF smaller than 50 MB."))
    }
    let data = try Data(contentsOf: url)
    guard data.starts(with: Data("%PDF-".utf8)) else {
        throw ApiError.unexpected(status: 400, message: String(localized: "Choose a valid PDF file."))
    }
    return data
}

struct OrderPDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

func safeOrderDocumentName(_ name: String) -> String {
    let result = String(name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_" }.joined().prefix(100))
    return result.isEmpty ? "document" : result
}

func orderPDFPreview(_ data: Data, name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("order-document-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(safeOrderDocumentName(name)).appendingPathExtension("pdf")
    try data.write(to: url, options: .atomic)
    return url
}
