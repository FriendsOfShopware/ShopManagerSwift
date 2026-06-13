import SwiftUI
import ShopwareAdminAPI

/// Editable filter form presented as a sheet, in the Settings style: option/bool filters push a
/// selection sub-screen (with native checkmark rows) and show the current choice as a trailing
/// value; text/range/date/existence filters edit inline. "Apply" commits all values in one reload.
struct FilterSheet<T: Identifiable>: View {
    let state: ListingState<T>
    let api: ShopApi?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [String: FilterValue] = [:]
    /// Async-loaded options per filter key (sales channel, manufacturer, …).
    @State private var loadedOptions: [String: [FilterOption]] = [:]

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
                    Button("Reset") {
                        draft = [:]
                        state.applyFilterValues([:])
                        dismiss()
                    }
                    .disabled(draft.allSatisfy { $0.value.isEmpty })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        state.applyFilterValues(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                draft = state.activeValues
                await loadAllOptions()
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    @ViewBuilder
    private func editor(for filter: ListingFilter) -> some View {
        switch filter {
        case let .text(_, label, _, _):
            TextField(LocalizedStringKey(label), text: textBinding(filter.key))

        case .numberRange:
            RangeEditor(value: rangeBinding(filter.key))

        case let .dateRange(_, _, _, withPresets):
            DateRangeEditor(value: dateBinding(filter.key), withPresets: withPresets)

        case let .options(key, label, _, multi, staticOptions, _):
            OptionSelectionLink(
                label: label,
                options: staticOptions ?? loadedOptions[key] ?? [],
                multi: multi,
                selection: optionsBinding(key)
            )

        case let .bool(key, label, _, trueLabel, falseLabel):
            // Two-way bool reads naturally as a segmented control inline.
            Picker(LocalizedStringKey(label), selection: boolBinding(key)) {
                Text("Any").tag(String?.none)
                Text(trueLabel).tag(String?.some("true"))
                Text(falseLabel).tag(String?.some("false"))
            }
            .pickerStyle(.segmented)

        case let .existence(key, _, _, hasLabel, hasNotLabel):
            Picker("", selection: existenceBinding(key)) {
                Text("Any").tag(Bool?.none)
                Text(hasLabel).tag(Bool?.some(true))
                Text(hasNotLabel).tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func loadAllOptions() async {
        guard let api else { return }
        for filter in state.filters {
            if case let .options(key, _, _, _, staticOptions, loadOptions) = filter,
               staticOptions == nil, let loadOptions, loadedOptions[key] == nil {
                if let result = try? await loadOptions(api) {
                    loadedOptions[key] = result
                }
            }
        }
    }

    // MARK: - Bindings into the draft

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { if case let .text(t)? = draft[key] { return t }; return "" },
            set: { draft[key] = .text($0) }
        )
    }

    private func rangeBinding(_ key: String) -> Binding<(min: Double?, max: Double?)> {
        Binding(
            get: { if case let .range(lo, hi)? = draft[key] { return (lo, hi) }; return (nil, nil) },
            set: { draft[key] = .range(min: $0.min, max: $0.max) }
        )
    }

    private func dateBinding(_ key: String) -> Binding<(from: Date?, to: Date?)> {
        Binding(
            get: { if case let .dateRange(f, t)? = draft[key] { return (f, t) }; return (nil, nil) },
            set: { draft[key] = .dateRange(from: $0.from, to: $0.to) }
        )
    }

    private func optionsBinding(_ key: String) -> Binding<Set<String>> {
        Binding(
            get: { if case let .options(ids)? = draft[key] { return ids }; return [] },
            set: { draft[key] = .options($0) }
        )
    }

    /// Bool filters store a single "true"/"false" id in an options set; surface it as an optional.
    private func boolBinding(_ key: String) -> Binding<String?> {
        Binding(
            get: { if case let .options(ids)? = draft[key] { return ids.first }; return nil },
            set: { value in
                if let value { draft[key] = .options([value]) } else { draft[key] = .options([]) }
            }
        )
    }

    private func existenceBinding(_ key: String) -> Binding<Bool?> {
        Binding(
            get: { if case let .existence(has)? = draft[key] { return has }; return nil },
            set: { draft[key] = .existence($0) }
        )
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

private struct RangeEditor: View {
    @Binding var value: (min: Double?, max: Double?)

    var body: some View {
        LabeledContent("Minimum") {
            TextField("Any", value: $value.min, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        LabeledContent("Maximum") {
            TextField("Any", value: $value.max, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}

private struct DateRangeEditor: View {
    @Binding var value: (from: Date?, to: Date?)
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
            value = (cal.date(byAdding: .day, value: -days, to: Date()), Date())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct OptionalDatePicker: View {
    let label: LocalizedStringKey
    @Binding var date: Date?

    var body: some View {
        Toggle(isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? Date()) : nil })) {
            Text(label)
        }
        if date != nil {
            DatePicker(
                label,
                selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                displayedComponents: .date
            )
        }
    }
}
