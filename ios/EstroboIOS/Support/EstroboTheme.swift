import SwiftUI
import UIKit
import EstroboCore

enum EstroboTheme {
    static let amber = Color(estroboRGB: 0xFFAB17)
    // Burnished amber in light mode; brand amber in dark mode.
    static let interactiveAccent = Color("AccentColor")
    static let navy = Color(estroboRGB: 0x09223F)
    static let ivory = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.086, blue: 0.122, alpha: 1)
            : UIColor(red: 0.969, green: 0.957, blue: 0.933, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.082, green: 0.125, blue: 0.169, alpha: 1)
            : UIColor(red: 1, green: 0.996, blue: 0.976, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.949, green: 0.961, blue: 0.976, alpha: 1)
            : UIColor(red: 0.035, green: 0.133, blue: 0.247, alpha: 1)
    })
}

struct EstroboScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(EstroboTheme.ivory)
    }
}

extension View {
    func estroboScreenBackground() -> some View {
        modifier(EstroboScreenBackground())
    }
}

struct GroupBadge: View {
    let group: GodoxGroup
    let accessibilityName: String

    init(group: GodoxGroup, accessibilityName: String? = nil) {
        self.group = group
        self.accessibilityName = accessibilityName ?? group.label
    }

    var body: some View {
        Text(group.label)
            .font(.headline)
            .frame(width: 36, height: 36)
            .foregroundStyle(Color(estroboRGB: group.visualIdentity.foregroundRGB))
            .background(
                Color(estroboRGB: group.visualIdentity.fillRGB),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityLabel(accessibilityName)
    }
}
