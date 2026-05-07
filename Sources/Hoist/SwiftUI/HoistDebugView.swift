import SwiftUI

/// A debug overlay that lists every known flag and lets you override each one
/// at runtime. Overrides persist across launches.
///
/// Present it however you like — a debug menu, a shake gesture, or `#if DEBUG`:
///
/// ```swift
/// .sheet(isPresented: $showFlags) {
///     HoistDebugView()
/// }
/// ```
public struct HoistDebugView: View {
    @State private var search: String = ""

    public init() {}

    public var body: some View {
        // Establish observation dependency so the list refreshes when
        // configure(), update(context:), or any override mutates state.
        let _ = HoistObservable.shared.version

        NavigationStack {
            List {
                Section {
                    if filteredKeys.isEmpty {
                        Text(Hoist.allFlagKeys.isEmpty ? "No flags configured." : "No matches.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredKeys, id: \.self) { key in
                            FlagDebugRow(key: key)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(Hoist.allFlagKeys.count) flags")
                        if !Hoist.overrides.isEmpty {
                            Spacer()
                            Text("\(Hoist.overrides.count) overridden")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !Hoist.overrides.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            Hoist.clearAllOverrides()
                        } label: {
                            Label("Clear all overrides", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Hoist Flags")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(watchOS)
            .searchable(text: $search, prompt: "Search flags")
            #endif
        }
    }

    private var filteredKeys: [String] {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Hoist.allFlagKeys }
        return Hoist.allFlagKeys.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

// MARK: - Per-row dispatch

private struct FlagDebugRow: View {
    let key: String

    var body: some View {
        if let flag = Hoist.flag(for: key) {
            switch flag.type {
            case .bool:   BoolFlagRow(key: key)
            case .int:    IntFlagRow(key: key)
            case .double: DoubleFlagRow(key: key)
            case .string: StringFlagRow(key: key)
            }
        }
    }
}

// MARK: - Editors

private struct BoolFlagRow: View {
    let key: String

    var body: some View {
        let value = Hoist.bool(key)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: Binding(
                    get: { value },
                    set: { Hoist.override(key, with: .bool($0)) }
                )) {
                    FlagLabel(key: key, type: "bool")
                }
            }
            OverrideFooter(key: key)
        }
    }
}

private struct IntFlagRow: View {
    let key: String
    @State private var draft: Int = 0
    @State private var loaded = false

    var body: some View {
        let value = Hoist.int(key)
        VStack(alignment: .leading, spacing: 6) {
            FlagLabel(key: key, type: "int", currentValue: "\(value)")
            HStack {
                TextField("value", value: $draft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onAppear { if !loaded { draft = value; loaded = true } }
                    .onSubmit { Hoist.override(key, with: .int(draft)) }
                Button("Set") { Hoist.override(key, with: .int(draft)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            OverrideFooter(key: key)
        }
    }
}

private struct DoubleFlagRow: View {
    let key: String
    @State private var draft: Double = 0
    @State private var loaded = false

    var body: some View {
        let value = Hoist.double(key)
        VStack(alignment: .leading, spacing: 6) {
            FlagLabel(key: key, type: "double", currentValue: String(format: "%g", value))
            HStack {
                TextField("value", value: $draft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onAppear { if !loaded { draft = value; loaded = true } }
                    .onSubmit { Hoist.override(key, with: .double(draft)) }
                Button("Set") { Hoist.override(key, with: .double(draft)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            OverrideFooter(key: key)
        }
    }
}

private struct StringFlagRow: View {
    let key: String
    @State private var draft: String = ""
    @State private var loaded = false

    var body: some View {
        let value = Hoist.string(key)
        VStack(alignment: .leading, spacing: 6) {
            FlagLabel(key: key, type: "string", currentValue: "\"\(value)\"")
            HStack {
                TextField("value", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { if !loaded { draft = value; loaded = true } }
                    .onSubmit { Hoist.override(key, with: .string(draft)) }
                Button("Set") { Hoist.override(key, with: .string(draft)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            OverrideFooter(key: key)
        }
    }
}

// MARK: - Bits

private struct FlagLabel: View {
    let key: String
    let type: String
    var currentValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.body.monospaced())
            HStack(spacing: 6) {
                Text(type)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                if let value = currentValue {
                    Text(value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OverrideFooter: View {
    let key: String

    var body: some View {
        if Hoist.isOverridden(key) {
            HStack(spacing: 8) {
                Label("OVERRIDDEN", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Button("Reset to rule") {
                    Hoist.clearOverride(key)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.top, 2)
        }
    }
}
