import AppKit
import Foundation
import SwiftUI

@main
enum SafeGodoxProtocolFrameCheck {
    static func main() throws {
        try checkPowerScales()
        checkGroupVisualIdentities()
        try checkExactFrames()
        try checkExactGlobalFrames()
        try checkExactAuthenticationRequest()
        checkExactTestPayload()
        try checkCapabilityValidation()
        checkOperationRecoveryState()
        checkPendingRestorationStore()
        checkSavedRadioStore()
        checkDraftDiscard()
        checkVisibleGroupPersistence()
        checkWorkspaceViewPersistence()
        checkTransmitterProfilePreferences()
        print("Perfiles, colores de grupo, borradores, preferencias, tramas A0/A1 y CRC verificados")
    }

    private static func checkExactTestPayload() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let epoch = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2017,
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0
        )) else {
            preconditionFailure("No se pudo construir la época local de Godox")
        }
        let now = epoch.addingTimeInterval(42)

        expect(
            SafeGodoxProtocol.testPayload(now: now, calendar: calendar) ==
                Data("42000,Test".utf8)
        )
        expect(
            SafeGodoxProtocol.synchronizationPayload(now: now, calendar: calendar) ==
                Data("42000,Sync".utf8)
        )
    }

    private static func checkExactAuthenticationRequest() throws {
        let syntheticCode = "246810"
        let request = try SafeGodoxProtocol.authenticationRequest(
            radioCode: syntheticCode,
            unixMilliseconds: 1_704_067_242_000,
            randomValue: 42
        )
        expect(request == Data("572758,Psub,246810".utf8))

        for invalidCode in ["", "12345", "1234567", "12345A", "１２３４５６"] {
            do {
                _ = try SafeGodoxProtocol.authenticationRequest(
                    radioCode: invalidCode,
                    unixMilliseconds: 1_704_067_242_000,
                    randomValue: 42
                )
                preconditionFailure("Un código sintético inválido produjo Psub")
            } catch let error as SafeGodoxProtocolError {
                expect(error == .invalidRadioCode)
            }
        }
    }

    private static func checkPowerScales() throws {
        let scale512 = ManualPower.scale(minimumDenominator: 512)
        let scale256 = ManualPower.scale(minimumDenominator: 256)
        let scale128 = ManualPower.scale(minimumDenominator: 128)

        expect(scale512.count == 28)
        expect(scale256.count == 25)
        expect(scale128.count == 22)
        expect(scale512.first?.decimalValue == 10)
        expect(scale256.first?.decimalValue == 20)
        expect(scale128.first?.decimalValue == 30)
        expect(scale512.last?.decimalValue == 100)
        expect(scale512[0].label == "1/512 +0.0")
        expect(scale512[1].label == "1/512 +0.3")
        expect(scale512[2].label == "1/512 +0.7")
        expect(scale256[0].label == "1/256 +0.0")
        expect(scale256[2].decimalValue == 27)
        expect(scale128[0].encodedByte == 0x46)
        expect(scale512[27].label == "1/1 +0.0")
        expect(!scale256.contains(power(10)))
        expect(scale512.contains(power(10)))
        expect(power(10).sliderIndex(minimumDenominator: 512) == 0)
        expect(power(20).sliderIndex(minimumDenominator: 256) == 0)
        expect(power(30).sliderIndex(minimumDenominator: 128) == 0)
        expect(power(100).sliderIndex(minimumDenominator: 512) == 27)
        expect(power(10).sliderIndex(minimumDenominator: 256) == nil)
        expect(ManualPower.value(atSliderIndex: 0, minimumDenominator: 256) == power(20))
        expect(ManualPower.value(atSliderIndex: 24, minimumDenominator: 256) == power(100))
        expect(ManualPower.value(atSliderIndex: -1, minimumDenominator: 256) == nil)
        expect(ManualPower.value(atSliderIndex: 25, minimumDenominator: 256) == nil)
    }

    private static func checkGroupVisualIdentities() {
        let expected: [GodoxGroup: GroupVisualIdentity] = [
            .a: GroupVisualIdentity(fillRGB: 0xD92D20, foregroundRGB: 0xFFFDF7),
            .b: GroupVisualIdentity(fillRGB: 0x32D74B, foregroundRGB: 0x081A2E),
            .c: GroupVisualIdentity(fillRGB: 0x2F3AE0, foregroundRGB: 0xFFFDF7),
            .d: GroupVisualIdentity(fillRGB: 0x21D4D8, foregroundRGB: 0x081A2E),
            .e: GroupVisualIdentity(fillRGB: 0xC61BCC, foregroundRGB: 0xFFFDF7),
            .f: GroupVisualIdentity(fillRGB: 0xE6E600, foregroundRGB: 0x081A2E),
            .zero: GroupVisualIdentity(fillRGB: 0xE85D0F, foregroundRGB: 0x081A2E),
            .one: GroupVisualIdentity(fillRGB: 0x19B977, foregroundRGB: 0x081A2E),
            .two: GroupVisualIdentity(fillRGB: 0x7424D8, foregroundRGB: 0xFFFDF7),
            .three: GroupVisualIdentity(fillRGB: 0xD81768, foregroundRGB: 0xFFFDF7),
            .four: GroupVisualIdentity(fillRGB: 0xC9A8EA, foregroundRGB: 0x081A2E),
            .five: GroupVisualIdentity(fillRGB: 0x24D6BC, foregroundRGB: 0x081A2E),
            .six: GroupVisualIdentity(fillRGB: 0x168FDB, foregroundRGB: 0x081A2E),
            .seven: GroupVisualIdentity(fillRGB: 0xB9EC98, foregroundRGB: 0x081A2E),
            .eight: GroupVisualIdentity(fillRGB: 0xEE777B, foregroundRGB: 0x081A2E),
            .nine: GroupVisualIdentity(fillRGB: 0xF3B373, foregroundRGB: 0x081A2E),
        ]

        expect(expected.count == GodoxGroup.allCases.count)
        expect(Set(expected.values.map(\.fillRGB)).count == GodoxGroup.allCases.count)

        for group in GodoxGroup.allCases {
            guard let expectedIdentity = expected[group] else {
                preconditionFailure("Falta el color del grupo \(group.label)")
            }
            expect(group.visualIdentity == expectedIdentity)
            let renderedFill = renderedSRGB(Color(estroboRGB: expectedIdentity.fillRGB))
            let renderedForeground = renderedSRGB(Color(estroboRGB: expectedIdentity.foregroundRGB))
            expect(renderedFill == expectedIdentity.fillRGB)
            expect(renderedForeground == expectedIdentity.foregroundRGB)
            expect(
                contrastRatio(
                    foreground: renderedForeground,
                    background: renderedFill
                ) >= 4.5
            )
        }
    }

    private static func renderedSRGB(_ color: Color) -> UInt32 {
        guard let rendered = NSColor(color).usingColorSpace(.sRGB) else {
            preconditionFailure("No se pudo convertir el color renderizado a sRGB")
        }

        let red = UInt32((rendered.redComponent * 255).rounded())
        let green = UInt32((rendered.greenComponent * 255).rounded())
        let blue = UInt32((rendered.blueComponent * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }

    private static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let component = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
    }

    private static func checkExactFrames() throws {
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .off),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x00, 0x00, 0x00, 0x00, 0xB2]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .proportional),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x00, 0x00, 0x01, 0x00, 0x76]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .fixed(percent: 10)),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x0A, 0x00, 0x02, 0x00, 0x38]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .fixed(percent: 25)),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x19, 0x00, 0x02, 0x00, 0x88]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .fixed(percent: 50)),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x32, 0x00, 0x02, 0x00, 0x6C]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .fixed(percent: 75)),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x4B, 0x00, 0x02, 0x00, 0x57]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .fixed(percent: 100)),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x64, 0x00, 0x02, 0x00, 0xBD]
        )
        try assertFrame(
            group: .b,
            snapshot: snapshot(power: 10, modeling: .off, beep: true),
            expected: [0xF0, 0xA1, 0x07, 0x0B, 0x01, 0x5A, 0x00, 0x01, 0x00, 0x00, 0x19]
        )
        try assertFrame(
            group: .a,
            snapshot: snapshot(power: 10, modeling: .off),
            expected: [0xF0, 0xA1, 0x07, 0x0A, 0x01, 0x5A, 0x00, 0x00, 0x00, 0x00, 0x8F]
        )
        try assertFrame(
            group: .zero,
            snapshot: snapshot(power: 10, modeling: .off),
            expected: [0xF0, 0xA1, 0x07, 0x00, 0x01, 0x5A, 0x00, 0x00, 0x00, 0x00, 0x04]
        )

        let cBaseline = snapshot(power: 27, modeling: .proportional)
        let cFrame: [UInt8] = [0xF0, 0xA1, 0x07, 0x0C, 0x01, 0x49, 0x00, 0x00, 0x01, 0x00, 0xF7]
        try assertFrame(group: .c, snapshot: cBaseline, expected: cFrame)
        try assertFrame(
            group: .c,
            snapshot: snapshot(power: 23, modeling: .proportional),
            expected: [0xF0, 0xA1, 0x07, 0x0C, 0x01, 0x4D, 0x00, 0x00, 0x01, 0x00, 0xE8]
        )
        let decoded = SafeGodoxProtocol.groupSnapshot(from: Data(cFrame))
        expect(decoded?.0 == .c)
        expect(decoded?.1 == cBaseline)

        let cTTL = snapshot(
            power: 27,
            modeling: .proportional,
            mode: .autoTTL
        )
        let cTTLFrame: [UInt8] = [
            0xF0, 0xA1, 0x07, 0x0C, 0x00, 0x32, 0x00, 0x00, 0x01, 0x00, 0xDD,
        ]
        try assertFrame(group: .c, snapshot: cTTL, expected: cTTLFrame)
        let decodedTTL = SafeGodoxProtocol.groupSnapshot(from: Data(cTTLFrame))
        expect(decodedTTL?.0 == .c)
        expect(decodedTTL?.1.operatingMode == .autoTTL)
        expect(decodedTTL?.1.power == ManualPower.value(decimal: 50))
        expect(decodedTTL?.1.modeling == cTTL.modeling)
        expect(decodedTTL?.1.compensationByte == 0)
        expect(cTTL.power == ManualPower.value(decimal: 27))

        expect(SafeGodoxProtocol.isGroupAcknowledgement(Data([0xF0, 0xA1])))
        expect(SafeGodoxProtocol.isGroupAcknowledgement(Data(cFrame)))
        expect(!SafeGodoxProtocol.isGroupAcknowledgement(Data([0xF0, 0xA0])))
        expect(!SafeGodoxProtocol.isGroupAcknowledgement(Data([0xF0])))

        let offSnapshot = snapshot(
            power: 10,
            modeling: .off,
            mode: .off,
            compensation: 0
        )
        try assertFrame(
            group: .a,
            snapshot: offSnapshot,
            expected: [0xF0, 0xA1, 0x07, 0x0A, 0x03, 0x5A, 0x00, 0x00, 0x00, 0x00, 0xE1]
        )
    }

    private static func checkExactGlobalFrames() throws {
        let apkDefaults = GlobalRadioSnapshot(
            apkDefaultsWithBeepEnabled: false,
            modelingLightEnabled: false,
            standbyEnabled: false
        )
        expect(!apkDefaults.beepEnabled)
        expect(!apkDefaults.modelingLightEnabled)
        expect(apkDefaults.relativeAdjustmentByte == 0x00)
        expect(!apkDefaults.multiEnabled)
        expect(apkDefaults.multiCount == 0x0A)
        expect(apkDefaults.multiHertz == 0x0A)
        expect(apkDefaults.multiPowerByte == 0x32)
        expect(!apkDefaults.standbyEnabled)
        expect(apkDefaults.adjustmentCounter == 0x00)
        try assertGlobalFrame(
            snapshot: apkDefaults,
            expected: [
                0xF0, 0xA0, 0x0A, 0xFF,
                0x00, 0x00, 0x00, 0x00,
                0x0A, 0x0A, 0x32, 0x00,
                0x00, 0x51,
            ]
        )

        let apkBeepEnabled = GlobalRadioSnapshot(
            apkDefaultsWithBeepEnabled: true,
            modelingLightEnabled: false,
            standbyEnabled: false
        )
        try assertGlobalFrame(
            snapshot: apkBeepEnabled,
            expected: [
                0xF0, 0xA0, 0x0A, 0xFF,
                0x01, 0x00, 0x00, 0x00,
                0x0A, 0x0A, 0x32, 0x00,
                0x00, 0xF5,
            ]
        )

        let apkBeepAndStandbyEnabled = GlobalRadioSnapshot(
            apkDefaultsWithBeepEnabled: true,
            modelingLightEnabled: false,
            standbyEnabled: true
        )
        try assertGlobalFrame(
            snapshot: apkBeepAndStandbyEnabled,
            expected: [
                0xF0, 0xA0, 0x0A, 0xFF,
                0x01, 0x00, 0x00, 0x00,
                0x0A, 0x0A, 0x32, 0x01,
                0x00, 0x31,
            ]
        )

        let completeSnapshot = GlobalRadioSnapshot(
            beepEnabled: true,
            modelingLightEnabled: true,
            relativeAdjustmentByte: 0x83,
            multiEnabled: true,
            multiCount: 0x03,
            multiHertz: 0x14,
            multiPowerByte: 0x4D,
            standbyEnabled: true,
            adjustmentCounter: 0x7F
        )
        let completeFrame: [UInt8] = [
            0xF0, 0xA0, 0x0A, 0xFF,
            0x01, 0x01, 0x83, 0x01,
            0x03, 0x14, 0x4D, 0x01,
            0x7F, 0x42,
        ]
        try assertGlobalFrame(snapshot: completeSnapshot, expected: completeFrame)
        expect(
            SafeGodoxProtocol.globalSnapshot(from: Data(completeFrame)) == completeSnapshot
        )
        expect(SafeGodoxProtocol.isGlobalAcknowledgement(Data([0xF0, 0xA0])))
        expect(SafeGodoxProtocol.isGlobalAcknowledgement(Data(completeFrame)))
        expect(!SafeGodoxProtocol.isGlobalAcknowledgement(Data([0xF0, 0xA1])))
        expect(!SafeGodoxProtocol.isGlobalAcknowledgement(Data([0xF0])))

        var badCRC = completeFrame
        badCRC[13] ^= 0x01
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badCRC)) == nil)

        var badFixedByte = completeFrame
        badFixedByte[3] = 0x01
        badFixedByte[13] = SafeGodoxProtocol.crc8(Array(badFixedByte.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badFixedByte)) == nil)

        var badBeep = completeFrame
        badBeep[4] = 0x02
        badBeep[13] = SafeGodoxProtocol.crc8(Array(badBeep.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badBeep)) == nil)

        var badModelingGate = completeFrame
        badModelingGate[5] = 0x02
        badModelingGate[13] = SafeGodoxProtocol.crc8(Array(badModelingGate.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badModelingGate)) == nil)

        var badMultiGate = completeFrame
        badMultiGate[7] = 0x02
        badMultiGate[13] = SafeGodoxProtocol.crc8(Array(badMultiGate.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badMultiGate)) == nil)

        var badStandby = completeFrame
        badStandby[11] = 0x02
        badStandby[13] = SafeGodoxProtocol.crc8(Array(badStandby.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badStandby)) == nil)

        var badMultiPower = completeFrame
        badMultiPower[10] = 101
        badMultiPower[13] = SafeGodoxProtocol.crc8(Array(badMultiPower.dropLast()))
        expect(SafeGodoxProtocol.globalSnapshot(from: Data(badMultiPower)) == nil)

        let invalidMultiPower = GlobalRadioSnapshot(
            beepEnabled: false,
            modelingLightEnabled: false,
            relativeAdjustmentByte: 0,
            multiEnabled: false,
            multiCount: 10,
            multiHertz: 10,
            multiPowerByte: 101,
            standbyEnabled: false,
            adjustmentCounter: 0
        )
        do {
            _ = try SafeGodoxProtocol.globalFrame(snapshot: invalidMultiPower)
            preconditionFailure("A0 no debe codificar una potencia Multi fuera de 0...100")
        } catch SafeGodoxProtocolError.invalidGlobalSnapshot {
            // Comportamiento esperado.
        }
    }

    private static func checkCapabilityValidation() throws {
        let catalog = TransmitterProfile.recoveredFlashCatalog
        expect(catalog.count == 72)
        expect(Set(catalog.map(\.id)).count == catalog.count)
        expect(catalog.first(where: { $0.id == "ad600" })?.minimumManualDenominator == 256)
        expect(catalog.first(where: { $0.id == "ad600pro-ii" })?.minimumManualDenominator == 512)
        let ad400ProII = catalog.first(where: { $0.id == "ad400pro-ii" })
        expect(ad400ProII?.name == "AD400Pro II")
        expect(ad400ProII?.minimumManualDenominator == 512)
        expect(ad400ProII?.evidence == .manufacturerSpecification)

        let ad400ProIICapability = ResolvedGroupCapability.resolve(
            configuration: GroupConfiguration(
                assignedFlashModelIDs: ["ad400pro-ii"],
                isVisibleLocally: true,
                isEnabledOnRadio: true,
                hasCompleteBaseline: true
            ),
            profile: .observedGDBH
        )
        expect(ad400ProIICapability.minimumManualDenominator == 512)
        expect(ad400ProIICapability.extendedManualDenominator == 512)
        expect(!ad400ProIICapability.hasMixedPowerCapabilities)
        expect(ad400ProIICapability.powerScale == ManualPower.scale(minimumDenominator: 512))
        expect(ad400ProIICapability.powerScale.first?.label == "1/512 +0.0")
        expect(ad400ProIICapability.powerScale.last?.label == "1/1 +0.0")

        let configuration = GroupConfiguration(
            assignedFlashModelIDs: ["ad600", "ad600pro-ii"],
            isVisibleLocally: true,
            isEnabledOnRadio: true,
            hasCompleteBaseline: true
        )
        let capability = ResolvedGroupCapability.resolve(
            configuration: configuration,
            profile: .observedGDBH
        )
        expect(capability.minimumManualDenominator == 256)
        expect(capability.extendedManualDenominator == 512)
        expect(capability.hasMixedPowerCapabilities)
        expect(capability.powerScale.first?.decimalValue == 20)
        expect(capability.powerScale == ManualPower.scale(minimumDenominator: 256))
        expect(!capability.powerScale.contains(power(10)))
        expect(!capability.powerScale.contains(power(13)))
        expect(!capability.powerScale.contains(power(17)))

        do {
            _ = try SafeGodoxProtocol.manualGroupFrame(
                group: .b,
                snapshot: snapshot(power: 10, modeling: .off),
                minimumManualDenominator: 256
            )
            preconditionFailure("1/512 nunca debe transmitirse con un perfil 1/256")
        } catch SafeGodoxProtocolError.powerOutsideCapability(let minimum) {
            expect(minimum == 256)
        }

        _ = try SafeGodoxProtocol.manualGroupFrame(
            group: .b,
            snapshot: snapshot(power: 20, modeling: .off),
            minimumManualDenominator: 256
        )

        do {
            _ = try SafeGodoxProtocol.manualGroupFrame(
                group: .b,
                snapshot: snapshot(power: 20, modeling: .fixed(percent: 0)),
                minimumManualDenominator: 256
            )
            preconditionFailure("Una intensidad fija fuera de rango no debe codificarse")
        } catch SafeGodoxProtocolError.invalidModelingLight {
            // Comportamiento esperado.
        }

        let invalidBeepSnapshot = ManualGroupSnapshot(
            modeByte: 1,
            powerByte: 0x50,
            modelingIntensityByte: 0,
            beepByte: 2,
            modelingModeByte: 0,
            compensationByte: 0
        )
        expect(invalidBeepSnapshot == nil)
    }

    private static func checkOperationRecoveryState() {
        let originalDevice = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let otherDevice = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let baseline = snapshot(power: 20, modeling: .off)
        let changed = snapshot(power: 23, modeling: .off)
        var safety = PhysicalOperationSafetyState()

        expect(safety.allowsNewEdits)
        expect(safety.permitsConnection(to: originalDevice))
        expect(safety.begin(group: .b, deviceID: originalDevice, baseline: baseline))
        expect(!safety.allowsNewEdits)
        expect(!safety.permitsConnection(to: otherDevice))
        expect(!safety.begin(group: .c, deviceID: originalDevice, baseline: baseline))
        expect(!safety.permitsOnlyExactRestoration(
            group: .b,
            deviceID: originalDevice,
            snapshot: changed
        ))
        expect(safety.restorationPoints[.b]?.snapshot == baseline)
        expect(safety.prepareRestoration(for: .b) == baseline)
        expect(safety.preparedRestorations == [.b])
        expect(!safety.completeRestoration(
            group: .b,
            deviceID: otherDevice,
            snapshot: baseline
        ))
        expect(safety.completeRestoration(
            group: .b,
            deviceID: originalDevice,
            snapshot: baseline
        ))
        expect(safety.allowsNewEdits)
        expect(safety.restorationPoints.isEmpty)
        expect(safety.preparedRestorations.isEmpty)

        var unsent = PhysicalOperationSafetyState()
        expect(unsent.begin(group: .c, deviceID: originalDevice, baseline: baseline))
        expect(unsent.cancelUnsentOperation(
            group: .c,
            deviceID: originalDevice,
            baseline: baseline
        ))
        expect(unsent.allowsNewEdits)

        var confirmedWrite = PhysicalOperationSafetyState()
        expect(confirmedWrite.begin(group: .b, deviceID: originalDevice, baseline: baseline))
        expect(!confirmedWrite.completeSuccessfulOperation(
            group: .b,
            deviceID: otherDevice
        ))
        expect(confirmedWrite.completeSuccessfulOperation(
            group: .b,
            deviceID: originalDevice
        ))
        expect(confirmedWrite.allowsNewEdits)
    }

    private static func checkPendingRestorationStore() {
        final class MemoryStore {
            var objects: [String: Any] = [:]
            var acceptsWrites = true
            var acceptsRemoval = true
        }
        let memory = MemoryStore()
        let store = PendingRestorationStore(
            storageKey: "restoration-test",
            readObject: { memory.objects[$0] },
            writeData: { data, key in
                guard memory.acceptsWrites else { return false }
                memory.objects[key] = data
                return true
            },
            removeValue: { key in
                guard memory.acceptsRemoval else { return false }
                memory.objects[key] = nil
                return true
            }
        )
        let deviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let point = GroupRestorationPoint(
            deviceID: deviceID,
            snapshot: snapshot(
                power: 23,
                modeling: .fixed(percent: 25),
                beep: true,
                mode: .manual,
                compensation: 0x81
            )
        )

        expect(store.load() == .none)
        expect(store.save(group: .c, point: point))
        expect(store.load() == .record(group: .c, point: point))

        let ttlPoint = GroupRestorationPoint(
            deviceID: deviceID,
            snapshot: snapshot(
                power: 27,
                modeling: .proportional,
                mode: .autoTTL,
                compensation: 0
            )
        )
        expect(store.save(group: .c, point: ttlPoint))
        expect(store.load() == .record(group: .c, point: ttlPoint))

        memory.acceptsRemoval = false
        expect(!store.clear())
        expect(store.load() == .record(group: .c, point: ttlPoint))
        memory.acceptsRemoval = true
        expect(store.clear())
        expect(store.load() == .none)

        memory.objects["restoration-test"] = Data([0x00, 0x01])
        expect(store.load() == .invalid)
        memory.objects.removeAll()
        memory.acceptsWrites = false
        expect(!store.save(group: .c, point: point))
        expect(store.load() == .none)
    }

    private static func checkSavedRadioStore() {
        final class MemoryStore {
            var objects: [String: Any] = [:]
            var acceptsWrites = true
            var acceptsRemoval = true
        }
        let memory = MemoryStore()
        let store = SavedRadioStore(
            storageKey: "saved-radio-test",
            readObject: { memory.objects[$0] },
            writeData: { data, key in
                guard memory.acceptsWrites else { return false }
                memory.objects[key] = data
                return true
            },
            removeValue: { key in
                guard memory.acceptsRemoval else { return false }
                memory.objects[key] = nil
                return true
            }
        )
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let replacementID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        expect(SavedRadio(deviceID: firstID, name: "", radioCode: "123456") == nil)
        expect(SavedRadio(deviceID: firstID, name: "GDBH-TEST", radioCode: "12345") == nil)
        expect(SavedRadio(deviceID: firstID, name: "GDBH-TEST", radioCode: "12345A") == nil)
        guard let first = SavedRadio(
            deviceID: firstID,
            name: "  GDBH-TEST  ",
            radioCode: "123456"
        ), let replacement = SavedRadio(
            deviceID: replacementID,
            name: "Ami-TEST",
            radioCode: "654321"
        ) else {
            preconditionFailure("No se pudieron construir los radios sintéticos")
        }
        expect(first.name == "GDBH-TEST")

        expect(store.load() == .none)
        expect(store.save(first))
        expect(store.load() == .record(first))

        expect(store.save(replacement))
        expect(store.load() == .record(replacement))

        memory.objects["saved-radio-test"] = Data([0x00, 0x01])
        expect(store.load() == .invalid)
        memory.objects["saved-radio-test"] = Data(
            #"{"version":1,"deviceID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"Ami-TEST","password":"12345A"}"#.utf8
        )
        expect(store.load() == .invalid)
        memory.objects["saved-radio-test"] = Data(
            #"{"version":2,"deviceID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"Ami-TEST","password":"654321"}"#.utf8
        )
        expect(store.load() == .invalid)

        expect(store.save(replacement))
        memory.acceptsRemoval = false
        expect(!store.clear())
        expect(store.load() == .record(replacement))
        memory.acceptsRemoval = true
        expect(store.clear())
        expect(store.load() == .none)

        memory.acceptsWrites = false
        expect(!store.save(first))
        expect(store.load() == .none)
    }

    private static func checkDraftDiscard() {
        let baseline = snapshot(power: 20, modeling: .off)
        var draftSnapshot = baseline
        draftSnapshot.power = power(23)
        draftSnapshot.modeling = .fixed(percent: 50)
        draftSnapshot.beepEnabled = true
        draftSnapshot.operatingMode = .off
        var state = GroupDraft(baseline: baseline, draft: draftSnapshot)
        expect(state.pendingFields == Set(PendingGroupField.allCases))
        state.discard()
        expect(state.draft == baseline)
        expect(state.pendingFields.isEmpty)
    }

    private static func checkVisibleGroupPersistence() {
        final class MemoryStore {
            var arrays: [String: [Any]] = [:]
        }
        let store = MemoryStore()
        let preferences = LocalGroupPreferences(
            storageKey: "visible-test",
            readArray: { store.arrays[$0] },
            writeIntegers: { values, key in store.arrays[key] = values }
        )

        expect(
            preferences.loadVisibleGroups(
                supportedGroups: GodoxGroup.lettered,
                defaultVisibleGroups: [.b, .c]
            ) == [.b, .c]
        )
        preferences.saveVisibleGroups([.c, .b, .c], supportedGroups: GodoxGroup.lettered)
        expect(preferences.loadVisibleGroups(supportedGroups: GodoxGroup.lettered) == [.b, .c])

        let hideB = LocalGroupPreferences.visibilityAfterToggling(
            .b,
            isVisible: false,
            currentVisibleGroups: [.b, .c],
            supportedGroups: GodoxGroup.lettered
        )
        expect(hideB == .accepted([.c]))
        expect(LocalGroupPreferences.validSelection(current: .b, visibleGroups: [.c]) == .c)

        let hideLast = LocalGroupPreferences.visibilityAfterToggling(
            .c,
            isVisible: false,
            currentVisibleGroups: [.c],
            supportedGroups: GodoxGroup.lettered
        )
        expect(hideLast == .rejectedWouldHideLast([.c]))
    }

    private static func checkWorkspaceViewPersistence() {
        final class MemoryStore {
            var strings: [String: String] = [:]
        }
        let memory = MemoryStore()
        let preferences = WorkspaceViewPreferences(
            storageKey: "workspace-view-test",
            readString: { memory.strings[$0] },
            writeString: { value, key in memory.strings[key] = value }
        )

        expect(preferences.load() == .channels)
        preferences.save(.matrix)
        expect(memory.strings["workspace-view-test"] == "matrix")
        expect(preferences.load() == .matrix)
        expect(preferences.launchVariant(arguments: ["estrobo"]) == .matrix)
        expect(preferences.launchVariant(arguments: ["estrobo", "--variant", "B"]) == .inspector)
        expect(preferences.launchVariant(arguments: ["estrobo", "--variant=channels"]) == .channels)

        memory.strings["workspace-view-test"] = "valor-invalido"
        expect(preferences.load() == .channels)
    }

    private static func checkTransmitterProfilePreferences() {
        final class MemoryStore {
            var object: Any?
            var acceptsWrites = true
        }
        let memory = MemoryStore()
        let preferences = TransmitterProfilePreferences(
            storageKey: "transmitter-profile-preferences-test",
            readObject: { _ in memory.object },
            writeData: { data, _ in
                guard memory.acceptsWrites else { return false }
                memory.object = data
                return true
            }
        )
        let builtInIDs = TransmitterProfile.available.map(\.id)
        let fallbackID = TransmitterProfile.observedGDBH.id

        expect(preferences.load(
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ) == TransmitterProfilePreferences.State(
            availableProfileIDs: builtInIDs,
            defaultProfileID: fallbackID
        ))

        memory.object = Data(#"{"version":1,"availableProfileIDs":["unknown","godox-letters-a-f","godox-letters-a-f"],"defaultProfileID":"unknown"}"#.utf8)
        expect(preferences.load(
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ) == TransmitterProfilePreferences.State(
            availableProfileIDs: [TransmitterProfile.classicLetters.id],
            defaultProfileID: TransmitterProfile.classicLetters.id
        ))

        memory.object = Data(#"{"version":1,"availableProfileIDs":[],"defaultProfileID":"unknown"}"#.utf8)
        expect(preferences.load(
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ).availableProfileIDs == builtInIDs)

        expect(preferences.save(
            TransmitterProfilePreferences.State(
                availableProfileIDs: [TransmitterProfile.classicLetters.id],
                defaultProfileID: fallbackID
            ),
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ))
        expect(preferences.load(
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ) == TransmitterProfilePreferences.State(
            availableProfileIDs: [TransmitterProfile.classicLetters.id],
            defaultProfileID: TransmitterProfile.classicLetters.id
        ))

        memory.acceptsWrites = false
        expect(!preferences.save(
            TransmitterProfilePreferences.State(
                availableProfileIDs: builtInIDs,
                defaultProfileID: fallbackID
            ),
            builtInProfileIDs: builtInIDs,
            fallbackDefaultProfileID: fallbackID
        ))
    }

    private static func snapshot(
        power decimal: Int,
        modeling: ModelingLight,
        beep: Bool = false,
        mode: GroupOperatingMode = .manual,
        compensation: UInt8 = 0
    ) -> ManualGroupSnapshot {
        ManualGroupSnapshot(
            power: power(decimal),
            modeling: modeling,
            beepEnabled: beep,
            operatingMode: mode,
            compensationByte: compensation
        )
    }

    private static func power(_ decimal: Int) -> ManualPower {
        guard let value = ManualPower.value(decimal: decimal) else {
            preconditionFailure("Potencia de prueba inválida: \(decimal)")
        }
        return value
    }

    private static func assertFrame(
        group: GodoxGroup,
        snapshot: ManualGroupSnapshot,
        expected: [UInt8]
    ) throws {
        let frame = try SafeGodoxProtocol.manualGroupFrame(group: group, snapshot: snapshot)
        expect([UInt8](frame) == expected)
        expect(SafeGodoxProtocol.crc8(Array(expected.dropLast())) == expected.last)
    }

    private static func assertGlobalFrame(
        snapshot: GlobalRadioSnapshot,
        expected: [UInt8]
    ) throws {
        let frame = try SafeGodoxProtocol.globalFrame(snapshot: snapshot)
        expect([UInt8](frame) == expected)
        expect(SafeGodoxProtocol.crc8(Array(expected.dropLast())) == expected.last)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        precondition(condition(), "Verificación fallida", file: file, line: line)
    }
}
