import SwiftUI
import Observation

/// Linked gross/net price editing state (mirrors the admin's sw-price-field). Editing gross
/// recomputes net from the tax rate when linked, and vice versa; the lock toggle re-snaps net to
/// gross. `edit(editable:)` returns a validated `PriceEdit` only when something actually changed.
@MainActor
@Observable
final class PriceEditModel {
    var gross: String
    var net: String
    var linked: Bool
    let taxRate: Double?

    private let origGross: Double?
    private let origNet: Double?
    private let origLinked: Bool

    init(gross: Double?, net: Double?, linked: Bool, taxRate: Double?) {
        self.gross = gross.map { Self.fmt($0) } ?? ""
        self.net = net.map { Self.fmt($0) } ?? ""
        self.linked = linked
        self.taxRate = taxRate
        self.origGross = gross
        self.origNet = net
        self.origLinked = linked
    }

    private static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    var grossBinding: Binding<String> {
        Binding(get: { self.gross }, set: { self.onGrossChange($0) })
    }
    var netBinding: Binding<String> {
        Binding(get: { self.net }, set: { self.onNetChange($0) })
    }

    private func onGrossChange(_ s: String) {
        gross = s
        if linked, let g = Self.parse(s), let r = taxRate {
            net = Self.fmt(g / (1 + r / 100))
        }
    }

    private func onNetChange(_ s: String) {
        net = s
        if linked, let n = Self.parse(s), let r = taxRate {
            gross = Self.fmt(n * (1 + r / 100))
        }
    }

    func toggleLinked() {
        linked.toggle()
        if linked, let g = Self.parse(gross), let r = taxRate {
            net = Self.fmt(g / (1 + r / 100))
        }
    }

    /// A validated change, or nil when not editable / unchanged.
    func edit(editable: Bool) -> PriceEdit? {
        guard editable, let g = Self.parse(gross), let n = Self.parse(net) else { return nil }
        if g == origGross, n == origNet, linked == origLinked { return nil }
        return PriceEdit(gross: g, net: n, linked: linked)
    }
}

/// The gross + lock + net field row (shows a hint when not editable or no tax rate).
struct PriceEditor: View {
    let shop: ConnectedShop
    let editable: Bool
    @Bindable var model: PriceEditModel

    var body: some View {
        if !editable {
            Text("Price not editable (variant or advanced prices)")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            LabeledContent("Gross") {
                TextField("0.00", text: model.grossBinding)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            LabeledContent("Net") {
                HStack(spacing: 8) {
                    Button {
                        model.toggleLinked()
                    } label: {
                        Image(systemName: model.linked ? "link" : "link.badge.plus")
                            .foregroundStyle(model.linked ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.borderless)
                    TextField("0.00", text: model.netBinding)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            }
            if model.taxRate == nil, model.linked {
                Text("No tax rate — gross and net won't stay in sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
