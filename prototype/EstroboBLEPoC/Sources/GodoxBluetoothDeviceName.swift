import Foundation

/// Canonicalizes Bluetooth names before they become identifiers or UI text.
///
/// Directional, zero-width, and other format/control scalars can make two names
/// compare differently while rendering alike, or can alter terminal/UI output.
/// Reject them at the boundary instead of trying to strip or display them.
enum GodoxBluetoothDeviceName {
    static func canonicalName(from rawName: String) -> String? {
        // Inspect the original scalars first: compatibility normalization can
        // erase some default-ignorable controls, which must remain rejectable.
        guard !rawName.unicodeScalars.contains(where: isUnsafeForDisplay) else {
            return nil
        }

        let canonicalName = rawName.precomposedStringWithCompatibilityMapping
        guard !canonicalName.unicodeScalars.contains(where: isUnsafeForDisplay) else {
            return nil
        }

        let trimmedName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    static func compatibleName(from rawName: String) -> String? {
        guard let canonicalName = canonicalName(from: rawName),
              canonicalName.contains("-"),
              canonicalName.hasPrefix("GD") || canonicalName.hasPrefix("Ami-") else {
            return nil
        }
        return canonicalName
    }

    private static func isUnsafeForDisplay(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isDefaultIgnorableCodePoint {
            return true
        }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }
}
