import SwiftUI

/// M1 connection controls (destination, channel, rescan, diagnostics), presented as a sheet.
struct ConnectionSettingsView: View {
    @ObservedObject var vm: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Connection").font(.title.bold())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 14, height: 14)
                Text(vm.statusText).font(.headline)
            }
            destinationPicker
            channelPicker
            Button("Rescan destinations") { vm.rescan() }
                .buttonStyle(.bordered).controlSize(.large)
            diagnostics
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        switch vm.state {
        case .connected: return Theme.connected
        case .disconnected, .transportUnavailable: return Theme.error
        default: return Theme.warning
        }
    }

    private var destinationPicker: some View {
        HStack {
            Text("Destination").frame(width: 130, alignment: .leading)
            Picker("Destination", selection: Binding(
                get: { vm.selectedDestinationID },
                set: { vm.selectDestination($0) })) {
                Text("None").tag(Int32?.none)
                ForEach(vm.destinations) { d in Text(d.name).tag(Int32?.some(d.id)) }
            }
            .pickerStyle(.menu)
        }
    }

    private var channelPicker: some View {
        HStack {
            Text("MIDI channel").frame(width: 130, alignment: .leading)
            Picker("MIDI channel", selection: Binding(
                get: { vm.channel }, set: { vm.setChannel($0) })) {
                ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last transmitted").font(.caption).foregroundStyle(Theme.textSecondary)
            if let t = vm.lastTransmission {
                Text(t.summary).font(.system(.body, design: .monospaced))
                Text("Handed to CoreMIDI. Not confirmed by hardware.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Nothing sent yet").foregroundStyle(Theme.textSecondary)
            }
            if let e = vm.lastError {
                Text("Error: \(e)").foregroundStyle(Theme.error)
            }
        }
    }
}
