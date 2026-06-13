import SwiftUI
import ShopwareAdminAPI

/// Editable filter form presented as a sheet. Each `ListingFilter` renders the matching editor;
/// "Apply" commits all values in a single reload, "Reset" clears them.
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
                    Section(filter.label) {
                        editor(for: filter)
                    }
                }
            }
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
                }
            }
            .task {
                draft = state.activeValues
                await loadAllOptions()
            }
        }
    }

    @ViewBuilder
    private func editor(for filter: ListingFilter) -> some View {
        switch filter {
        case let .text(key, label, _, _):
            TextField(label, text: textBinding(key))

        case let .numberRange(key, _, _):
            RangeEditor(value: rangeBinding(key))

        case let .dateRange(key, _, _, withPresets):
            DateRangeEditor(value: dateBinding(key), withPresets: withPresets)

        case let .options(key, _, _, multi, staticOptions, _):
            OptionsEditor(
                options: staticOptions ?? loadedOptions[key] ?? [],
                multi: multi,
                selection: optionsBinding(key)
            )

        case let .bool(key, _, _, trueLabel, falseLabel):
            OptionsEditor(
                options: [FilterOption(id: "true", label: trueLabel), FilterOption(id: "false", label: falseLabel)],
                multi: false,
                selection: optionsBinding(key)
            )

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

    private func existenceBinding(_ key: String) -> Binding<Bool?> {
        Binding(
            get: { if case let .existence(has)? = draft[key] { return has }; return nil },
            set: { draft[key] = .existence($0) }
        )
    }
}

// MARK: - Editors

private struct RangeEditor: View {
    @Binding var value: (min: Double?, max: Double?)

    var body: some View {
        HStack {
            TextField("Min", value: $value.min, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Divider()
            TextField("Max", value: $value.max, format: .number)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    presetButton("7 days", days: 7)
                    presetButton("30 days", days: 30)
                    presetButton("90 days", days: 90)
                }
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
        HStack {
            Toggle(isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? Date()) : nil })) {
                Text(label)
            }
            if date != nil {
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { date = $0 }), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

private struct OptionsEditor: View {
    let options: [FilterOption]
    let multi: Bool
    @Binding var selection: Set<String>

    var body: some View {
        if options.isEmpty {
            Text("No options").foregroundStyle(.secondary)
        } else {
            ForEach(options) { option in
                Button {
                    if selection.contains(option.id) {
                        selection.remove(option.id)
                    } else {
                        if !multi { selection.removeAll() }
                        selection.insert(option.id)
                    }
                } label: {
                    HStack {
                        Text(option.label).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(option.id) {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }
}
