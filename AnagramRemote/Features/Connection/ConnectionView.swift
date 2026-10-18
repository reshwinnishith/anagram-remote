import SwiftUI

struct ConnectionView: View {
    @StateObject private var vm = ConnectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Anagram Remote").font(.largeTitle.bold())

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    statusRow
                    destinationPicker
                    channelPicker
                    Button("Rescan destinations") { vm.rescan() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                .frame(maxWidth: 420, alignment: .leading)

                HStack(spacing: 20) {
                    presetButton("Preset 01A", program: 1)
                    presetButton("Preset 01B", program: 2)
                }
            }

            diagnostics
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 14, height: 14)
            Text(vm.statusText).font(.headline)
        }
    }

    private var statusColor: Color {
        switch vm.state {
        case .connected: return .green
        case .disconnected: return .red
        default: return .orange
        }
    }

    private var destinationPicker: some View {
        HStack {
            Text("Destination").frame(width: 110, alignment: .leading)
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
            Text("MIDI channel").frame(width: 110, alignment: .leading)
            Picker("MIDI channel", selection: Binding(
                get: { vm.channel }, set: { vm.setChannel($0) })) {
                ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func presetButton(_ title: String, program: Int) -> some View {
        Button { vm.sendPreset(program) } label: {
            Text(title).font(.system(size: 34, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(!vm.canSend)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last transmitted").font(.caption).foregroundStyle(.secondary)
            if let t = vm.lastTransmission {
                Text(t.summary).font(.system(.body, design: .monospaced))
                Text("Handed to CoreMIDI. Not confirmed by hardware.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Nothing sent yet").foregroundStyle(.secondary)
            }
            if let e = vm.lastError {
                Text("Error: \(e)").foregroundStyle(.red)
            }
        }
    }
}
