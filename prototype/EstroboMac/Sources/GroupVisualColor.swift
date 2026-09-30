import SwiftUI

extension Color {
    /// Builds the physical group identity in the same sRGB space used by the
    /// hexadecimal tokens and their contrast checks.
    init(estroboRGB value: UInt32) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
