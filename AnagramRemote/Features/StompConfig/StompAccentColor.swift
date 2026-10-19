import SwiftUI

extension StompAccent {
    static func color(for id: String) -> Color {
        let i = ids.firstIndex(of: id) ?? 7
        return Theme.stompAccents[i]
    }
    static func displayName(for id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }
}
