import Foundation

enum CapabilityEvidence: String, Hashable {
    case apkCatalog = "Catálogo APK"
    case protocolGeneric = "Campo A1 genérico"
    case observedLocalData = "Datos locales observados"
    case manufacturerSpecification = "Especificación oficial Godox"
}

enum ModelingCapability: Hashable {
    case unavailable
    case proportionalAndFixed(range: ClosedRange<Int>, step: Int, evidence: CapabilityEvidence)
    case unknown

    var permitsModeling: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var editableValues: [ModelingLight] {
        switch self {
        case .unavailable:
            return [.off]
        case .unknown:
            return ModelingLight.allEditableValues
        case .proportionalAndFixed(let range, let step, _):
            let lower = max(10, range.lowerBound)
            let upper = min(100, range.upperBound)
            guard lower <= upper, step > 0 else { return [.off, .proportional] }
            return [.off, .proportional] + stride(
                from: lower,
                through: upper,
                by: step
            ).map { .fixed(percent: $0) }
        }
    }
}

enum FeatureSupport: String, Hashable {
    case unsupported
    case protocolGeneric
    case unknown

    var permitsDraft: Bool { self != .unsupported }
}

/// A manufacturer-published power × frequency table. Profiles stay explicit:
/// Godox models do not all share the same stroboscopic ceiling, so an unknown
/// model must remain visibly unverified instead of inheriting another flash's
/// limit by accident.
enum MultiFlashLimitProfile: String, Hashable {
    case ad400ProII

    func maximumFlashCount(power: ManualPower, hertz: Int) -> Int? {
        switch self {
        case .ad400ProII:
            return Self.ad400ProIIMaximumFlashCount(power: power, hertz: hertz)
        }
    }

    /// Distinguishes cells printed by Godox from a deliberately conservative
    /// fallback. The AD400Pro II table jumps from 20–50 Hz to 60–100 Hz; the
    /// app applies the safer following row at 51–59 Hz, but must not label that
    /// manufacturer-unpublished gap as verified.
    func hasManufacturerPublishedLimit(power: ManualPower, hertz: Int) -> Bool {
        guard maximumFlashCount(power: power, hertz: hertz) != nil else { return false }
        switch self {
        case .ad400ProII:
            return (1...50).contains(hertz) || (60...100).contains(hertz)
        }
    }

    private static func ad400ProIIMaximumFlashCount(
        power: ManualPower,
        hertz: Int
    ) -> Int? {
        let powerIndex: Int
        switch power.decimalValue {
        case 80: powerIndex = 0 // 1/4
        case 70: powerIndex = 1 // 1/8
        case 60: powerIndex = 2 // 1/16
        case 50: powerIndex = 3 // 1/32
        case 40: powerIndex = 4 // 1/64
        case 30: powerIndex = 5 // 1/128
        case 20: powerIndex = 6 // 1/256
        case 10: powerIndex = 7 // 1/512
        default: return nil
        }

        // Godox AD400Pro II manual, “Maximum Stroboscopic Flashes”. The
        // manual skips 51–59 Hz; use the following 60–100 row there as the
        // conservative ceiling instead of interpolating a larger value.
        let limits: [Int]
        switch hertz {
        case 1: limits = [7, 14, 30, 60, 90, 100, 100, 100]
        case 2: limits = [6, 14, 30, 60, 90, 100, 100, 100]
        case 3: limits = [5, 12, 30, 60, 90, 100, 100, 100]
        case 4: limits = [4, 10, 20, 50, 80, 100, 100, 100]
        case 5: limits = [3, 8, 20, 50, 80, 100, 100, 100]
        case 6...7: limits = [3, 6, 20, 40, 70, 90, 90, 90]
        case 8...9: limits = [3, 5, 10, 30, 60, 80, 80, 80]
        case 10: limits = [2, 4, 8, 20, 50, 70, 70, 70]
        case 11: limits = [2, 4, 8, 20, 40, 70, 70, 70]
        case 12...14: limits = [2, 4, 8, 20, 40, 60, 60, 60]
        case 15...19: limits = [2, 4, 8, 18, 35, 50, 50, 50]
        case 20...50: limits = [2, 4, 8, 16, 30, 40, 40, 40]
        case 51...100: limits = [2, 4, 8, 12, 20, 40, 40, 40]
        default: return nil
        }
        return limits[powerIndex]
    }
}

struct FlashCapability: Hashable, Identifiable {
    let id: String
    let name: String
    let minimumManualDenominator: Int
    let modeling: ModelingCapability
    let beep: FeatureSupport
    let evidence: CapabilityEvidence
    let multiLimitProfile: MultiFlashLimitProfile?
}

struct TransmitterProfile: Hashable, Identifiable {
    let id: String
    let name: String
    let supportedGroups: [GodoxGroup]
    /// Godox documents wireless Multi selection for groups A-E on the X3Pro.
    /// Keep this explicit instead of inferring it from the wider M/TTL group set.
    let supportedMultiGroups: [GodoxGroup]
    let flashCatalog: [FlashCapability]
    let supportsGroupBeep: Bool

    private static func flash(
        id: String,
        name: String,
        denominator: Int,
        evidence: CapabilityEvidence = .apkCatalog,
        multiLimitProfile: MultiFlashLimitProfile? = nil
    ) -> FlashCapability {
        FlashCapability(
            id: id,
            name: name,
            minimumManualDenominator: denominator,
            modeling: .unknown,
            beep: .unknown,
            evidence: evidence,
            multiLimitProfile: multiLimitProfile
        )
    }

    static let recoveredFlashCatalog: [FlashCapability] = [
        flash(id: "p2400", name: "P2400", denominator: 512),
        flash(
            id: "ad400pro-ii",
            name: "AD400Pro II",
            denominator: 512,
            evidence: .manufacturerSpecification,
            multiLimitProfile: .ad400ProII
        ),
        flash(
            id: "ad600pro-ii",
            name: "AD600Pro II",
            denominator: 512,
            evidence: .observedLocalData
        ),

        flash(id: "ad100pro", name: "AD100Pro", denominator: 256),
        flash(id: "ad200pro", name: "AD200Pro", denominator: 256),
        flash(id: "ad300pro", name: "AD300Pro", denominator: 256),
        flash(id: "ad400pro", name: "AD400Pro", denominator: 256),
        flash(id: "ad600pro", name: "AD600Pro", denominator: 256),
        flash(id: "ad1200pro", name: "AD1200Pro", denominator: 256),
        flash(id: "ad600", name: "AD600", denominator: 256),
        flash(id: "ad600m", name: "AD600M", denominator: 256),
        flash(id: "ad600b", name: "AD600B", denominator: 256),
        flash(id: "ad600bm", name: "AD600BM", denominator: 256),
        flash(id: "ad600e", name: "AD600E", denominator: 256),
        flash(id: "v1-c", name: "V1 C", denominator: 256),
        flash(id: "v1-n", name: "V1 N", denominator: 256),
        flash(id: "v1-s", name: "V1 S", denominator: 256),
        flash(id: "v1-f", name: "V1 F", denominator: 256),
        flash(id: "v1-o", name: "V1 O", denominator: 256),
        flash(id: "v1-p", name: "V1 P", denominator: 256),
        flash(id: "v1pro-c", name: "V1Pro C", denominator: 256),
        flash(id: "v1pro-n", name: "V1Pro N", denominator: 256),
        flash(id: "v1pro-s", name: "V1Pro S", denominator: 256),
        flash(id: "v1pro-f", name: "V1Pro F", denominator: 256),
        flash(id: "v1pro-o", name: "V1Pro O", denominator: 256),
        flash(id: "v860ii", name: "V860II", denominator: 256),
        flash(id: "v860iii-c", name: "V860III C", denominator: 256),
        flash(id: "v860iii-n", name: "V860III N", denominator: 256),
        flash(id: "v860iii-s", name: "V860III S", denominator: 256),
        flash(id: "v860iii-f", name: "V860III F", denominator: 256),
        flash(id: "v860iii-o", name: "V860III O", denominator: 256),
        flash(id: "v860iii-p", name: "V860III P", denominator: 256),
        flash(id: "tt685ii-c", name: "TT685II C", denominator: 256),
        flash(id: "tt685ii-n", name: "TT685II N", denominator: 256),
        flash(id: "tt685ii-s", name: "TT685II S", denominator: 256),
        flash(id: "tt685ii-f", name: "TT685II F", denominator: 256),
        flash(id: "tt685ii-o", name: "TT685II O", denominator: 256),

        flash(id: "quicker400iim", name: "Quicker400IIM", denominator: 128),
        flash(id: "quicker600iim", name: "Quicker600IIM", denominator: 128),
        flash(id: "qt1200iim", name: "QT1200IIM", denominator: 128),
        flash(id: "qhii", name: "QHII", denominator: 128),
        flash(id: "ad200", name: "AD200", denominator: 128),
        flash(id: "ad360ii-c", name: "AD360II-C", denominator: 128),
        flash(id: "ad360ii-n", name: "AD360II-N", denominator: 128),
        flash(id: "v350-c", name: "V350 C", denominator: 128),
        flash(id: "v350-s", name: "V350 S", denominator: 128),
        flash(id: "v350-o", name: "V350 O", denominator: 128),
        flash(id: "v350-n", name: "V350 N", denominator: 128),
        flash(id: "v350-f", name: "V350 F", denominator: 128),
        flash(id: "tt685-c", name: "TT685 C", denominator: 128),
        flash(id: "tt685-n", name: "TT685 N", denominator: 128),
        flash(id: "tt685-s", name: "TT685 S", denominator: 128),
        flash(id: "tt685-f", name: "TT685 F", denominator: 128),
        flash(id: "tt685-o", name: "TT685 O", denominator: 128),
        flash(id: "tt350-c", name: "TT350 C", denominator: 128),
        flash(id: "tt350-n", name: "TT350 N", denominator: 128),
        flash(id: "tt350-s", name: "TT350 S", denominator: 128),
        flash(id: "tt350-f", name: "TT350 F", denominator: 128),
        flash(id: "tt350-o", name: "TT350 O", denominator: 128),
        flash(id: "tt350-p", name: "TT350 P", denominator: 128),

        flash(id: "dpiii", name: "DPIII", denominator: 64),

        flash(id: "qsii", name: "QSII", denominator: 32),
        flash(id: "deii", name: "DEII", denominator: 32),
        flash(id: "dsii", name: "DSII", denominator: 32),
        flash(id: "ms300-series", name: "MS300 Series", denominator: 32),
        flash(id: "gsii-series", name: "GSII Series", denominator: 32),

        flash(id: "dpii", name: "DPII", denominator: 16),
        flash(id: "skii", name: "SKII", denominator: 16),
        flash(id: "seii", name: "SEII", denominator: 16),

        flash(
            id: "generic-128",
            name: "Otro · mínimo 1/128",
            denominator: 128,
            evidence: .observedLocalData
        ),
        flash(
            id: "generic-256",
            name: "Otro · mínimo 1/256",
            denominator: 256,
            evidence: .observedLocalData
        ),
        flash(
            id: "generic-512",
            name: "Otro · mínimo 1/512",
            denominator: 512,
            evidence: .observedLocalData
        ),
    ]

    static let observedGDBH = TransmitterProfile(
        id: "gdbh-observed-0-f",
        name: "GDBH · grupos 0–F",
        supportedGroups: GodoxGroup.allCases,
        supportedMultiGroups: [.a, .b, .c, .d, .e],
        flashCatalog: recoveredFlashCatalog,
        supportsGroupBeep: true
    )

    static let classicLetters = TransmitterProfile(
        id: "godox-letters-a-f",
        name: "Godox · grupos A–F",
        supportedGroups: GodoxGroup.lettered,
        supportedMultiGroups: [.a, .b, .c, .d, .e],
        flashCatalog: recoveredFlashCatalog,
        supportsGroupBeep: true
    )

    static let available: [TransmitterProfile] = [.observedGDBH, .classicLetters]
}

struct GroupConfiguration: Equatable {
    var assignedFlashModelIDs: Set<String>
    var isVisibleLocally: Bool
    var isEnabledOnRadio: Bool
    var hasCompleteBaseline: Bool
}

struct ResolvedGroupCapability: Equatable {
    let flashModels: [FlashCapability]
    let minimumManualDenominator: Int?
    let extendedManualDenominator: Int?
    let modeling: ModelingCapability
    let supportsBeepDraft: Bool
    let multiLimitProfiles: [MultiFlashLimitProfile]
    let hasUnverifiedMultiLimits: Bool

    var hasMixedPowerCapabilities: Bool {
        Set(flashModels.map(\.minimumManualDenominator)).count > 1
    }

    var powerScale: [ManualPower] {
        guard let minimumManualDenominator else { return [] }
        return ManualPower.scale(minimumDenominator: minimumManualDenominator)
    }

    /// Multi uses whole-stop output values and tops out at 1/4 on the X3Pro.
    /// The lower bound still comes from the safest common range of the flashes
    /// assigned to the group.
    var multiPowerScale: [ManualPower] {
        powerScale.filter {
            $0.decimalValue <= 80 && $0.decimalValue.isMultiple(of: 10)
        }
    }

    var safeRangeLabel: String {
        guard let first = powerScale.first, let last = powerScale.last else { return "Sin modelo" }
        return "\(first.label) – \(last.label)"
    }

    static func resolve(
        configuration: GroupConfiguration,
        profile: TransmitterProfile
    ) -> ResolvedGroupCapability {
        let models = profile.flashCatalog.filter {
            configuration.assignedFlashModelIDs.contains($0.id)
        }
        let safeDenominator = models.map(\.minimumManualDenominator).min()
        let extendedDenominator = models.map(\.minimumManualDenominator).max()

        let modeling: ModelingCapability
        if models.isEmpty {
            modeling = .unknown
        } else if models.contains(where: {
            if case .unavailable = $0.modeling { return true }
            return false
        }) {
            modeling = .unavailable
        } else {
            let fixedRanges = models.compactMap { model -> ClosedRange<Int>? in
                if case .proportionalAndFixed(let range, _, _) = model.modeling {
                    return range
                }
                return nil
            }
            if fixedRanges.count == models.count,
               let lower = fixedRanges.map(\.lowerBound).max(),
               let upper = fixedRanges.map(\.upperBound).min(),
               lower <= upper {
                modeling = .proportionalAndFixed(
                    range: lower...upper,
                    step: 1,
                    evidence: .protocolGeneric
                )
            } else {
                modeling = .unknown
            }
        }

        let beep = !models.isEmpty && models.allSatisfy { $0.beep.permitsDraft }
        let multiProfiles = Array(Set(models.compactMap(\.multiLimitProfile))).sorted {
            $0.rawValue < $1.rawValue
        }
        return ResolvedGroupCapability(
            flashModels: models,
            minimumManualDenominator: safeDenominator,
            extendedManualDenominator: extendedDenominator,
            modeling: modeling,
            supportsBeepDraft: profile.supportsGroupBeep && beep,
            multiLimitProfiles: multiProfiles,
            hasUnverifiedMultiLimits: models.contains { $0.multiLimitProfile == nil }
        )
    }
}
