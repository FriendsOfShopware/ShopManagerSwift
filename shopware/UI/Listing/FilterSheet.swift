import SwiftUI
import ShopwareAdminAPI

/// Editable filter form presented as a sheet, in the Settings style: option/bool filters push a
/// selection sub-screen (with native checkmark rows) and show the current choice as a trailing
/// value; text/range/date/existence filters edit inline. "Apply" commits all values in one reload.
struct FilterSheet<T: Identifiable>: View {
    let state: ListingState<T>
    let api: ShopApi?
    @Environment(\.dismiss) private var dismiss

    @State private var draft = FilterDraft()

    var body: some View {
        NavigationStack {
            Form {
                ForEach(state.filters) { filter in
                    Section {
                        editor(for: filter)
                    } header: {
                        Text(filter.label)
                    }
                }
            }
            .groupedFormStyle()
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset", action: reset)
                        .disabled(draft.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .fontWeight(.semibold)
                }
            }
            .task {
                draft.seed(state.activeValues)
                await draft.loadOptions(for: state.filters, api: api)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .acceptsFirstMouse()
    }

    private func reset() {
        draft.clear()
        state.applyFilterValues([:])
        dismiss()
    }

    private func apply() {
        state.applyFilterValues(draft.values)
        dismiss()
    }

    @ViewBuilder
    private func editor(for filter: ListingFilter) -> some View {
        switch filter {
        case let .text(_, label, _, _):
            TextField(LocalizedStringKey(label), text: draft.textBinding(filter.key))
                .accessibilityIdentifier("filter.\(filter.key)")

        case .numberRange:
            RangeEditor(value: draft.rangeBinding(filter.key))

        case let .dateRange(_, _, _, withPresets):
            DateRangeEditor(value: draft.dateBinding(filter.key), withPresets: withPresets)

        case let .options(key, label, _, multi, _, _):
            OptionSelectionLink(
                label: label,
                options: draft.options(for: filter),
                multi: multi,
                selection: draft.optionsBinding(key)
            )

        case let .bool(key, label, _, trueLabel, falseLabel):
            // Two-way bool reads naturally as a segmented control inline.
            Picker(LocalizedStringKey(label), selection: draft.boolBinding(key)) {
                Text("Any").tag(String?.none)
                Text(trueLabel).tag(String?.some("true"))
                Text(falseLabel).tag(String?.some("false"))
            }
            .pickerStyle(.segmented)

        case let .existence(key, _, _, hasLabel, hasNotLabel):
            Picker("", selection: draft.existenceBinding(key)) {
                Text("Any").tag(Bool?.none)
                Text(hasLabel).tag(Bool?.some(true))
                Text(hasNotLabel).tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - Editors

/// A row that shows the current selection and pushes a checkmark list to change it.
private struct OptionSelectionLink: View {
    let label: String
    let options: [FilterOption]
    let multi: Bool
    @Binding var selection: Set<String>

    private var summary: String {
        if selection.isEmpty { return String(localized: "Any") }
        let names = options.filter { selection.contains($0.id) }.map(\.label)
        if names.count == 1 { return names[0] }
        if !names.isEmpty { return String(localized: "\(names.count) selected") }
        return String(localized: "\(selection.count) selected")
    }

    var body: some View {
        if options.isEmpty {
            HStack {
                Text(LocalizedStringKey(label))
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else {
            NavigationLink {
                OptionSelectionList(title: label, options: options, multi: multi, selection: $selection)
            } label: {
                LabeledContent(LocalizedStringKey(label), value: summary)
            }
        }
    }
}

/// The pushed checkmark list for an options filter.
private struct OptionSelectionList: View {
    let title: String
    let options: [FilterOption]
    let multi: Bool
    @Binding var selection: Set<String>

    var body: some View {
        Form {
            if !selection.isEmpty {
                Section {
                    Button("Clear selection", role: .destructive) { selection.removeAll() }
                }
            }
            Section {
                ForEach(options) { option in
                    Button {
                        toggle(option.id)
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(option.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .groupedFormStyle()
        .navigationTitle(LocalizedStringKey(title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            if !multi { selection.removeAll() }
            selection.insert(id)
        }
    }
}

struct DateRangeEditor: View {
    @Binding var value: DateRangeValue
    let withPresets: Bool

    var body: some View {
        OptionalDatePicker(label: "From", date: $value.from)
        OptionalDatePicker(label: "To", date: $value.to)
        if withPresets {
            HStack {
                presetButton("7 days", days: 7)
                presetButton("30 days", days: 30)
                presetButton("90 days", days: 90)
            }
        }
    }

    private func presetButton(_ label: LocalizedStringKey, days: Int) -> some View {
        Button(label) {
            let cal = Calendar.current
            value = DateRangeValue(from: cal.date(byAdding: .day, value: -days, to: .now), to: .now)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct OptionalDatePicker: View {
    let label: LocalizedStringKey
    @Binding var date: Date?

    var body: some View {
        Toggle(label, isOn: enabledBinding)
        if date != nil {
            DatePicker(label, selection: unwrappedBinding, displayedComponents: .date)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { date != nil }, set: { date = $0 ? (date ?? .now) : nil })
    }

    private var unwrappedBinding: Binding<Date> {
        Binding(get: { date ?? .now }, set: { date = $0 })
    }
}
