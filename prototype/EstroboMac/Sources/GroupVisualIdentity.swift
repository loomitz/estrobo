/// Stable, theme-independent colors that mirror the group LEDs on Godox gear.
///
/// They live outside the general app palette because these colors identify a
/// physical group. Light/dark appearance must not change their meaning.
struct GroupVisualIdentity: Equatable {
    let fillRGB: UInt32
    let foregroundRGB: UInt32
}

extension GodoxGroup {
    var visualIdentity: GroupVisualIdentity {
        switch self {
        case .a: GroupVisualIdentity(fillRGB: 0xD92D20, foregroundRGB: 0xFFFDF7)
        case .b: GroupVisualIdentity(fillRGB: 0x32D74B, foregroundRGB: 0x081A2E)
        case .c: GroupVisualIdentity(fillRGB: 0x2F3AE0, foregroundRGB: 0xFFFDF7)
        case .d: GroupVisualIdentity(fillRGB: 0x21D4D8, foregroundRGB: 0x081A2E)
        case .e: GroupVisualIdentity(fillRGB: 0xC61BCC, foregroundRGB: 0xFFFDF7)
        case .f: GroupVisualIdentity(fillRGB: 0xE6E600, foregroundRGB: 0x081A2E)
        case .zero: GroupVisualIdentity(fillRGB: 0xE85D0F, foregroundRGB: 0x081A2E)
        case .one: GroupVisualIdentity(fillRGB: 0x19B977, foregroundRGB: 0x081A2E)
        case .two: GroupVisualIdentity(fillRGB: 0x7424D8, foregroundRGB: 0xFFFDF7)
        case .three: GroupVisualIdentity(fillRGB: 0xD81768, foregroundRGB: 0xFFFDF7)
        case .four: GroupVisualIdentity(fillRGB: 0xC9A8EA, foregroundRGB: 0x081A2E)
        case .five: GroupVisualIdentity(fillRGB: 0x24D6BC, foregroundRGB: 0x081A2E)
        case .six: GroupVisualIdentity(fillRGB: 0x168FDB, foregroundRGB: 0x081A2E)
        case .seven: GroupVisualIdentity(fillRGB: 0xB9EC98, foregroundRGB: 0x081A2E)
        case .eight: GroupVisualIdentity(fillRGB: 0xEE777B, foregroundRGB: 0x081A2E)
        case .nine: GroupVisualIdentity(fillRGB: 0xF3B373, foregroundRGB: 0x081A2E)
        }
    }
}
