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

struct FlashCapability: Hashable, Identifiable {
    let id: String
    let name: String
    let minimumManualDenominator: Int
    let modeling: ModelingCapability
    let beep: FeatureSupport
    let evidence: CapabilityEvidence
}

struct TransmitterProfile: Hashable, Identifiable {
    let id: String
    let name: String
    let supportedGroups: [GodoxGroup]
    let flashCatalog: [FlashCapability]
    let supportsGroupBeep: Bool

    private static func flash(
        id: String,
        name: String,
        denominator: Int,
        evidence: CapabilityEvidence = .apkCatalog
    ) -> FlashCapability {
        FlashCapability(
            id: id,
            name: name,
            minimumManualDenominator: denominator,
            modeling: .unknown,
            beep: .unknown,
            evidence: evidence
        )
    }

    static let recoveredFlashCatalog: [FlashCapability] = [
        flash(id: "p2400", name: "P2400", denominator: 512),
        flash(
            id: "ad400pro-ii",
            name: "AD400Pro II",
            denominator: 512,
            evidence: .manufacturerSpecification
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
        flashCatalog: recoveredFlashCatalog,
        supportsGroupBeep: true
    )

    static let classicLetters = TransmitterProfile(
        id: "godox-letters-a-f",
        name: "Godox · grupos A–F",
        supportedGroups: GodoxGroup.lettered,
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

    var hasMixedPowerCapabilities: Bool {
        Set(flashModels.map(\.minimumManualDenominator)).count > 1
    }

    var powerScale: [ManualPower] {
        guard let minimumManualDenominator else { return [] }
        return ManualPower.scale(minimumDenominator: minimumManualDenominator)
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
        return ResolvedGroupCapability(
            flashModels: models,
            minimumManualDenominator: safeDenominator,
            extendedManualDenominator: extendedDenominator,
            modeling: modeling,
            supportsBeepDraft: profile.supportsGroupBeep && beep
        )
    }
}
