import SwiftUI

extension StatusLevel {
    var color: Color {
        switch self {
        case .ok: return Theme.connected
        case .warning: return Theme.warning
        case .error: return Theme.error
        }
    }
}

/// Large placeholder control for a scene. Disabled and inert in Batch A.
struct SceneButton: View {
    let slot: SceneSlotPresentation
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Text(slot.letter)
                    .font(.system(size: 72, weight: .heavy))
                    .minimumScaleFactor(0.5)
                Text(slot.statusText).font(.caption.bold())
            }
            .foregroundStyle(Theme.sceneAccent.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: Theme.minTouch)
            .themedCard(dashed: true)
        }
        .buttonStyle(.plain)
        .disabled(!slot.isEnabled)
        .accessibilityLabel("Scene \(slot.letter), not configured, unavailable")
        .accessibilityIdentifier("scene-\(slot.letter)")
    }
}

/// Placeholder control for a programmable stomp. Disabled and inert in Batch A.
struct StompButton: View {
    let stomp: StompPresentation
    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                Text(stomp.customLabel ?? stomp.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(stomp.statusText).font(.caption.bold())
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: Theme.minTouch)
            .themedCard(dashed: true)
        }
        .buttonStyle(.plain)
        .disabled(!stomp.isEnabled)
        .accessibilityLabel("\(stomp.title), unassigned, unavailable")
        .accessibilityIdentifier("stomp-\(stomp.index)")
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
                .font(.system(size: 24, weight: .bold))
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

/// Header navigation affordance. `action == nil` renders a disabled "later" placeholder.
struct NavChip: View {
    let title: String
    let systemImage: String
    var action: (() -> Void)? = nil
    var body: some View {
        Button(action: action ?? {}) {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                if action == nil { Text("LATER").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(action == nil ? Theme.textSecondary.opacity(0.6) : Theme.textPrimary)
            .frame(minWidth: Theme.minTouch + 12, minHeight: Theme.minTouch)
            .themedCard(raised: action != nil, dashed: action == nil)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(action == nil ? "\(title), coming later, unavailable" : title)
    }
}
