import SwiftUI

extension StatusLevel {
    var color: Color {
        switch self {
        case .ok: return Theme.connected
        case .warning: return Theme.warning
        case .error: return Theme.error
        }
    }

    /// Shape + colour, so status is never colour-only.
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// Large placeholder for a scene. Inert and not a Button: Batch A sends no MIDI from scenes.
/// Dashed border + "NOT CONFIGURED" mark it as unavailable without dimming the text.
struct SceneButton: View {
    let slot: SceneSlotPresentation
    @ScaledMetric(relativeTo: .largeTitle) private var letterSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.sceneAccent.opacity(0.55)).frame(width: 6)
            VStack(spacing: 2) {
                Text(slot.letter)
                    .font(.system(size: letterSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.sceneAccent.opacity(0.8))
                    .minimumScaleFactor(0.5)
                Text(slot.statusText)
                    .font(.caption2.bold())
                    .tracking(0.5)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: Theme.minTouch)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .themedCard(dashed: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scene \(slot.letter), not configured, unavailable")
        .accessibilityIdentifier("scene-\(slot.letter)")
    }
}

struct StompPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct StompButton: View {
    let tile: StompTile
    let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var badge: CGFloat = 30

    private var identity: Color { StompAccent.color(for: tile.accentID) }

    var body: some View {
        if tile.isEnabled {
            Button(action: action) { face }
                .buttonStyle(StompPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.accessibilityLabel)
                .accessibilityValue(tile.accessibilityValue)
                .accessibilityHint(tile.accessibilityHint)
                .accessibilityIdentifier("stomp-\(tile.slot)")
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.accessibilityLabel)
                .accessibilityValue(tile.accessibilityValue + ", unavailable")
                .accessibilityHint(tile.accessibilityHint)
                .accessibilityIdentifier("stomp-\(tile.slot)")
        }
    }

    private var face: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(tile.slot)")
                    .font(.footnote.bold().monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: badge, height: badge)
                    .background(Circle().strokeBorder(identity.opacity(0.7), lineWidth: 2))
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(Theme.textSecondary, lineWidth: 2)
                    .frame(width: 16, height: 16)
            }
            Spacer(minLength: 4)
            Text(tile.label)
                .font(.title2.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(Theme.textPrimary)
            if tile.kind != .unassigned {
                Text(tile.summary)
                    .font(.caption.bold())
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            Text(tile.detail).font(.caption2.bold()).tracking(0.6)
                .foregroundStyle(tile.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Capsule().fill(tile.isEnabled ? identity.opacity(0.8) : Theme.border).frame(width: 56, height: 6)
        }
        .padding(Theme.Spacing.gutter - 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: Theme.minTouch)
        .themedCard(raised: tile.isEnabled, dashed: !tile.isEnabled)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Functional M1 direct-preset button.
struct PresetShortcutButton: View {
    let shortcut: PresetShortcut
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Preset \(shortcut.label)")
                .font(.title3.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary)
                .frame(minWidth: 140, maxHeight: .infinity)
                .frame(minHeight: Theme.minTouch)
                .padding(.horizontal, Theme.Spacing.gutter)
                .themedCard(raised: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("preset-\(shortcut.label)")
    }
}

/// Always-available entry to the connection settings sheet.
struct ConnectionSettingsButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Connection", systemImage: "gearshape")
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.gutter)
                .frame(minHeight: Theme.minTouch)
                .themedCard(raised: true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel("Connection settings")
        .accessibilityIdentifier("connection-settings")
    }
}

/// Entry to the separate editing area. A deliberate two-step (tap, then confirm) works the same for touch,
/// VoiceOver and Switch Control, unlike a long press.
struct EditControlsButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Edit", systemImage: "slider.horizontal.3")
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.gutter)
                .frame(minHeight: Theme.minTouch)
                .themedCard()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel("Edit controls")
        .accessibilityHint("Opens the stomp configuration area. Asks for confirmation first.")
        .accessibilityIdentifier("edit-controls")
    }
}
