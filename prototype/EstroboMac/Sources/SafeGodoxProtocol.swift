import Foundation

enum SafeGodoxProtocolError: LocalizedError, Equatable {
    case invalidRadioCode
    case invalidRandomValue
    case invalidPower
    case powerOutsideCapability(minimumDenominator: Int)
    case invalidModelingLight
    case invalidBeep
    case invalidGroupSnapshot
    case invalidGlobalSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidRadioCode:
            return "El código del radio debe contener exactamente seis dígitos."
        case .invalidRandomValue:
            return "No fue posible crear el reto local."
        case .invalidPower:
            return "La potencia solicitada no pertenece a la escala permitida."
        case .powerOutsideCapability(let denominator):
            return "La potencia solicitada excede el rango común del grupo (mínimo 1/\(denominator))."
        case .invalidModelingLight:
            return "La intensidad fija de la luz de modelado debe estar entre 10 y 100%."
        case .invalidBeep:
            return "El beep por grupo sólo admite 0 o 1."
        case .invalidGroupSnapshot:
            return "La instantánea A1 no contiene un estado completo y válido."
        case .invalidGlobalSnapshot:
            return "La instantánea A0 no contiene un estado global completo y válido."
        }
    }
}

enum GodoxGroup: UInt8, CaseIterable, Hashable, Identifiable {
    case zero = 0x00
    case one = 0x01
    case two = 0x02
    case three = 0x03
    case four = 0x04
    case five = 0x05
    case six = 0x06
    case seven = 0x07
    case eight = 0x08
    case nine = 0x09
    case a = 0x0A
    case b = 0x0B
    case c = 0x0C
    case d = 0x0D
    case e = 0x0E
    case f = 0x0F

    var id: UInt8 { rawValue }
    var label: String {
        if rawValue < 10 { return String(rawValue) }
        return String(UnicodeScalar(55 + Int(rawValue))!)
    }

    static let lettered: [GodoxGroup] = [.a, .b, .c, .d, .e, .f]
}

struct ManualPower: Hashable, Identifiable {
    let decimalValue: Int
    let label: String

    var id: Int { decimalValue }

    static let all: [ManualPower] = {
        var result: [ManualPower] = []
        for base in stride(from: 10, through: 90, by: 10) {
            result.append(ManualPower(decimalValue: base, label: label(for: base)))
            result.append(ManualPower(decimalValue: base + 3, label: label(for: base + 3)))
            result.append(ManualPower(decimalValue: base + 7, label: label(for: base + 7)))
        }
        result.append(ManualPower(decimalValue: 100, label: label(for: 100)))
        return result
    }()

    static func value(decimal: Int) -> ManualPower? {
        all.first { $0.decimalValue == decimal }
    }

    static func minimumDecimalValue(for denominator: Int) -> Int? {
        guard denominator >= 1, denominator <= 512,
              denominator.nonzeroBitCount == 1 else {
            return nil
        }
        return 100 - (denominator.trailingZeroBitCount * 10)
    }

    static func scale(minimumDenominator: Int) -> [ManualPower] {
        guard let minimum = minimumDecimalValue(for: minimumDenominator) else { return [] }
        return all.filter { $0.decimalValue >= minimum }
    }

    static func isSupported(_ power: ManualPower, minimumDenominator: Int) -> Bool {
        scale(minimumDenominator: minimumDenominator).contains(power)
    }

    static func value(atSliderIndex index: Int, minimumDenominator: Int) -> ManualPower? {
        let values = scale(minimumDenominator: minimumDenominator)
        guard values.indices.contains(index) else { return nil }
        return values[index]
    }

    func sliderIndex(minimumDenominator: Int) -> Int? {
        Self.scale(minimumDenominator: minimumDenominator).firstIndex(of: self)
    }

    var encodedByte: UInt8 { UInt8(100 - decimalValue) }

    private static func label(for value: Int) -> String {
        let fullStops = max(0, min(9, (value - 10) / 10))
        let denominator = 512 >> fullStops
        let remainder = (value - 10) % 10
        let suffix: String
        switch remainder {
        case 3:
            suffix = "+0.3"
        case 7:
            suffix = "+0.7"
        default:
            suffix = "+0.0"
        }
        return "1/\(denominator) \(suffix)"
    }
}

/// Ajustes globales de una ráfaga Multi que Estrobo puede editar con seguridad.
///
/// El A0 crudo sigue siendo tolerante para conservar compatibilidad con valores
/// observados fuera de la UI. Este tipo representa únicamente el subconjunto que
/// la aplicación permite crear, persistir y enviar desde sus controles.
struct MultiFlashSettings: Equatable, Hashable {
    static let countRange = 1...100
    // Godox Flash currently exposes 1...100 Hz across its portable Multi UI.
    // Some transmitters document higher wire values, but those remain outside
    // this editable subset until a matching flash/profile is verified.
    static let hertzRange = 1...100
    static let supportedPowers: [ManualPower] = stride(from: 10, through: 80, by: 10)
        .compactMap(ManualPower.value(decimal:))

    static let `default`: MultiFlashSettings = {
        guard let power = ManualPower.value(decimal: 50),
              let settings = MultiFlashSettings(power: power, count: 10, hertz: 10) else {
            preconditionFailure("Los defaults Multi deben pertenecer al dominio editable")
        }
        return settings
    }()

    let power: ManualPower
    let count: Int
    let hertz: Int

    init?(power: ManualPower, count: Int, hertz: Int) {
        guard Self.supportedPowers.contains(power),
              Self.countRange.contains(count),
              Self.hertzRange.contains(hertz) else {
            return nil
        }
        self.power = power
        self.count = count
        self.hertz = hertz
    }

    init?(countByte: UInt8, hertzByte: UInt8, powerByte: UInt8) {
        guard let power = ManualPower.value(decimal: 100 - Int(powerByte)) else {
            return nil
        }
        self.init(power: power, count: Int(countByte), hertz: Int(hertzByte))
    }

    var countByte: UInt8 { UInt8(count) }
    var hertzByte: UInt8 { UInt8(hertz) }
    var powerByte: UInt8 { power.encodedByte }
    var estimatedDurationSeconds: Double { Double(count) / Double(hertz) }
    /// Límite orientativo mostrado al usuario. Siempre redondea hacia arriba
    /// para no sugerir una obturación menor que `destellos / Hz`.
    var minimumExposureSeconds: Double {
        ceil(estimatedDurationSeconds * 1_000) / 1_000
    }
}

enum ModelingLight: Hashable, Identifiable {
    case off
    case proportional
    case fixed(percent: Int)

    var id: String {
        switch self {
        case .off:
            "off"
        case .proportional:
            "proportional"
        case .fixed(let percent):
            "fixed-\(percent)"
        }
    }

    var label: String {
        switch self {
        case .off:
            "Apagada"
        case .proportional:
            "Proporcional"
        case .fixed(let percent):
            "Fija · \(percent)%"
        }
    }

    static let allEditableValues: [ModelingLight] =
        [.off, .proportional] + (10...100).map { .fixed(percent: $0) }

    static let apkBackedHardwareValues: Set<ModelingLight> = [
        .off,
        .proportional,
        .fixed(percent: 25),
        .fixed(percent: 100),
    ]

    fileprivate var encodedValues: (intensity: UInt8, mode: UInt8)? {
        switch self {
        case .off:
            (0, 0)
        case .proportional:
            (0, 1)
        case .fixed(let percent) where (10...100).contains(percent):
            (UInt8(percent), 2)
        case .fixed:
            nil
        }
    }
}

enum GroupOperatingMode: UInt8, CaseIterable, Hashable {
    case autoTTL = 0x00
    case manual = 0x01
    case multi = 0x02
    case off = 0x03

    var label: String {
        switch self {
        case .autoTTL: "TTL"
        case .manual: "M"
        case .multi: "MULTI"
        case .off: "OFF"
        }
    }
}

enum ModelingMode: UInt8, Hashable {
    case off = 0x00
    case proportional = 0x01
    case fixed = 0x02
}

struct ModelingState: Equatable, Hashable {
    var intensityByte: UInt8
    var mode: ModelingMode

    init(_ value: ModelingLight) {
        switch value {
        case .off:
            intensityByte = 0
            mode = .off
        case .proportional:
            intensityByte = 0
            mode = .proportional
        case .fixed(let percent):
            intensityByte = UInt8(clamping: percent)
            mode = .fixed
        }
    }

    init?(intensityByte: UInt8, modeByte: UInt8) {
        guard let mode = ModelingMode(rawValue: modeByte) else { return nil }
        self.intensityByte = intensityByte
        self.mode = mode
    }

    var value: ModelingLight {
        switch mode {
        case .off: .off
        case .proportional: .proportional
        case .fixed: .fixed(percent: Int(intensityByte))
        }
    }

    var isValidForWrite: Bool {
        switch mode {
        case .off, .proportional:
            return intensityByte <= 100
        case .fixed:
            return (10...100).contains(Int(intensityByte))
        }
    }
}

/// Instantánea completa de los seis bytes mutables de una orden A1.
///
/// El nombre histórico se conserva para no confundirla con A0. A diferencia
/// del primer corte, no fuerza modo manual, beep ni compensación a cero.
struct ManualGroupSnapshot: Equatable {
    var operatingMode: GroupOperatingMode
    var power: ManualPower
    var modelingState: ModelingState
    var beepEnabled: Bool
    var compensationByte: UInt8

    init(
        power: ManualPower,
        modeling: ModelingLight,
        beepEnabled: Bool = false,
        operatingMode: GroupOperatingMode = .manual,
        compensationByte: UInt8 = 0
    ) {
        self.operatingMode = operatingMode
        self.power = power
        modelingState = ModelingState(modeling)
        self.beepEnabled = beepEnabled
        self.compensationByte = compensationByte
    }

    init?(
        modeByte: UInt8,
        powerByte: UInt8,
        modelingIntensityByte: UInt8,
        beepByte: UInt8,
        modelingModeByte: UInt8,
        compensationByte: UInt8
    ) {
        guard let operatingMode = GroupOperatingMode(rawValue: modeByte),
              powerByte <= 90,
              let power = ManualPower.value(decimal: 100 - Int(powerByte)),
              beepByte == 0 || beepByte == 1,
              let modelingState = ModelingState(
                  intensityByte: modelingIntensityByte,
                  modeByte: modelingModeByte
              ) else {
            return nil
        }
        self.operatingMode = operatingMode
        self.power = power
        self.modelingState = modelingState
        beepEnabled = beepByte == 1
        self.compensationByte = compensationByte
    }

    var modeling: ModelingLight {
        get { modelingState.value }
        set { modelingState = ModelingState(newValue) }
    }

    var beepByte: UInt8 { beepEnabled ? 1 : 0 }
    var isEnabledOnRadio: Bool { operatingMode != .off }
    var label: String { power.label }
}

/// Instantánea completa de los nueve bytes mutables de una orden global A0.
///
/// A0 comparte una sola trama para beep, modelado, ajuste relativo, Multi y
/// standby. Conservar todos los campos en un único valor evita que un cambio
/// aislado sobrescriba silenciosamente otro ajuste global del transmisor.
struct GlobalRadioSnapshot: Equatable {
    var beepEnabled: Bool
    var modelingLightEnabled: Bool
    var relativeAdjustmentByte: UInt8
    var multiEnabled: Bool
    var multiCount: UInt8
    var multiHertz: UInt8
    var multiPowerByte: UInt8
    var standbyEnabled: Bool
    var adjustmentCounter: UInt8

    init(
        beepEnabled: Bool,
        modelingLightEnabled: Bool,
        relativeAdjustmentByte: UInt8,
        multiEnabled: Bool,
        multiCount: UInt8,
        multiHertz: UInt8,
        multiPowerByte: UInt8,
        standbyEnabled: Bool,
        adjustmentCounter: UInt8
    ) {
        self.beepEnabled = beepEnabled
        self.modelingLightEnabled = modelingLightEnabled
        self.relativeAdjustmentByte = relativeAdjustmentByte
        self.multiEnabled = multiEnabled
        self.multiCount = multiCount
        self.multiHertz = multiHertz
        self.multiPowerByte = multiPowerByte
        self.standbyEnabled = standbyEnabled
        self.adjustmentCounter = adjustmentCounter
    }

    /// Valores iniciales observados en Godox Flash 1.3.3.
    ///
    /// Este inicializador lleva una etiqueta deliberadamente explícita: no debe
    /// confundirse con una lectura del estado actual ni usarse para reconstruir
    /// parcialmente una trama que ya tenga valores globales conocidos.
    init(
        apkDefaultsWithBeepEnabled beepEnabled: Bool,
        modelingLightEnabled: Bool,
        standbyEnabled: Bool
    ) {
        self.init(
            beepEnabled: beepEnabled,
            modelingLightEnabled: modelingLightEnabled,
            relativeAdjustmentByte: 0x00,
            multiEnabled: false,
            multiCount: 0x0A,
            multiHertz: 0x0A,
            multiPowerByte: 0x32,
            standbyEnabled: standbyEnabled,
            adjustmentCounter: 0x00
        )
    }

    fileprivate var beepByte: UInt8 { beepEnabled ? 1 : 0 }
    fileprivate var modelingLightByte: UInt8 { modelingLightEnabled ? 1 : 0 }
    fileprivate var multiEnabledByte: UInt8 { multiEnabled ? 1 : 0 }
    fileprivate var standbyByte: UInt8 { standbyEnabled ? 1 : 0 }
    fileprivate var isValidForWrite: Bool { multiPowerByte <= 100 }
}

/// Superficie clean-room deliberadamente limitada: autenticación, Sync,
/// heartbeat, disparo Test explícito e instantáneas A0/A1 completas.
/// No contiene cambio de código del radio ni firmware/OAD.
enum SafeGodoxProtocol {
    /// Clasifica una respuesta A0 cuando existe. Godox Flash 1.3.3 entrega sus
    /// órdenes A0 normales con el acuse GATT y no exige una notificación FEC8.
    static func isGlobalAcknowledgement(_ notification: Data) -> Bool {
        let bytes = [UInt8](notification)
        return bytes.count >= 2 && bytes[0] == 0xF0 && bytes[1] == 0xA0
    }

    static func isGroupAcknowledgement(_ notification: Data) -> Bool {
        let bytes = [UInt8](notification)
        return bytes.count >= 2 && bytes[0] == 0xF0 && bytes[1] == 0xA1
    }

    static func authenticationRequest(
        radioCode: String,
        unixMilliseconds: Int64,
        randomValue: Int
    ) throws -> Data {
        guard radioCode.count == 6,
              radioCode.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw SafeGodoxProtocolError.invalidRadioCode
        }
        guard (1...98).contains(randomValue) else {
            throw SafeGodoxProtocolError.invalidRandomValue
        }

        let secondsSuffix = (unixMilliseconds / 1_000) % 10_000
        let nonce = 1_000_000 - (Int64(randomValue * 10_000) + secondsSuffix)
        return Data("\(nonce),Psub,\(radioCode)".utf8)
    }

    static func isValidAuthenticationResponse(
        _ data: Data,
        unixMilliseconds: Int64,
        toleranceSeconds: Int64 = 20
    ) -> Bool {
        guard let response = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let comma = response.firstIndex(of: ","),
            response[..<comma] == "PWOK"
        else {
            return false
        }

        let token = String(response[response.index(after: comma)...])
        guard let decodedTime = decodeAuthenticationToken(token) else { return false }
        let nowSuffix = (unixMilliseconds / 1_000) % 10_000
        let expectedSuffix = Int64((10_000 - decodedTime) % 10_000)
        let directDistance = abs(nowSuffix - expectedSuffix)
        let circularDistance = min(directDistance, 10_000 - directDistance)
        return circularDistance <= toleranceSeconds
    }

    static func manualGroupFrame(
        group: GodoxGroup,
        snapshot: ManualGroupSnapshot,
        minimumManualDenominator: Int = 512,
        underlyingMultiMode: GroupOperatingMode? = nil
    ) throws -> Data {
        guard ManualPower.value(decimal: snapshot.power.decimalValue) != nil else {
            throw SafeGodoxProtocolError.invalidPower
        }
        guard !ManualPower.scale(minimumDenominator: minimumManualDenominator).isEmpty else {
            throw SafeGodoxProtocolError.invalidPower
        }
        guard ManualPower.isSupported(
            snapshot.power,
            minimumDenominator: minimumManualDenominator
        ) else {
            throw SafeGodoxProtocolError.powerOutsideCapability(
                minimumDenominator: minimumManualDenominator
            )
        }
        guard snapshot.modelingState.isValidForWrite,
              snapshot.modeling.encodedValues != nil else {
            throw SafeGodoxProtocolError.invalidModelingLight
        }

        // Godox Flash conserva la potencia M fuera de la trama al entrar a
        // Auto/TTL, pero A1 usa siempre 0x32 en el campo de potencia. MULTI
        // conserva ese origen incluso cuando el grupo queda temporalmente Off:
        // desde TTL usa 0x32; desde M conserva la potencia.
        let usesTTLSentinel = snapshot.operatingMode == .autoTTL
            || ((snapshot.operatingMode == .multi || snapshot.operatingMode == .off)
                && underlyingMultiMode == .autoTTL)
        let transmittedPowerByte: UInt8 = usesTTLSentinel
            ? 0x32
            : snapshot.power.encodedByte

        var bytes: [UInt8] = [
            0xF0, 0xA1, 0x07,
            group.rawValue,
            snapshot.operatingMode.rawValue,
            transmittedPowerByte,
            snapshot.modelingState.intensityByte,
            snapshot.beepByte,
            snapshot.modelingState.mode.rawValue,
            snapshot.compensationByte,
        ]
        bytes.append(crc8(bytes))
        return Data(bytes)
    }

    static func globalFrame(snapshot: GlobalRadioSnapshot) throws -> Data {
        guard snapshot.isValidForWrite else {
            throw SafeGodoxProtocolError.invalidGlobalSnapshot
        }

        var bytes: [UInt8] = [
            0xF0, 0xA0, 0x0A, 0xFF,
            snapshot.beepByte,
            snapshot.modelingLightByte,
            snapshot.relativeAdjustmentByte,
            snapshot.multiEnabledByte,
            snapshot.multiCount,
            snapshot.multiHertz,
            snapshot.multiPowerByte,
            snapshot.standbyByte,
            snapshot.adjustmentCounter,
        ]
        bytes.append(crc8(bytes))
        return Data(bytes)
    }

    static func globalSnapshot(from frame: Data) -> GlobalRadioSnapshot? {
        let bytes = [UInt8](frame)
        guard bytes.count == 14,
              bytes[0] == 0xF0,
              bytes[1] == 0xA0,
              bytes[2] == 0x0A,
              bytes[3] == 0xFF,
              bytes[4] <= 1,
              bytes[5] <= 1,
              bytes[7] <= 1,
              bytes[10] <= 100,
              bytes[11] <= 1,
              crc8(Array(bytes.dropLast())) == bytes[13] else {
            return nil
        }
        return GlobalRadioSnapshot(
            beepEnabled: bytes[4] == 1,
            modelingLightEnabled: bytes[5] == 1,
            relativeAdjustmentByte: bytes[6],
            multiEnabled: bytes[7] == 1,
            multiCount: bytes[8],
            multiHertz: bytes[9],
            multiPowerByte: bytes[10],
            standbyEnabled: bytes[11] == 1,
            adjustmentCounter: bytes[12]
        )
    }

    static func groupSnapshot(from frame: Data) -> (GodoxGroup, ManualGroupSnapshot)? {
        let bytes = [UInt8](frame)
        guard bytes.count == 11,
              bytes[0] == 0xF0,
              bytes[1] == 0xA1,
              bytes[2] == 0x07,
              crc8(Array(bytes.dropLast())) == bytes[10],
              let group = GodoxGroup(rawValue: bytes[3]),
              let snapshot = ManualGroupSnapshot(
                  modeByte: bytes[4],
                  powerByte: bytes[5],
                  modelingIntensityByte: bytes[6],
                  beepByte: bytes[7],
                  modelingModeByte: bytes[8],
                  compensationByte: bytes[9]
              ) else {
            return nil
        }
        return (group, snapshot)
    }

    static func synchronizationPayload(now: Date, calendar: Calendar = .current) -> Data {
        let milliseconds = millisecondsSinceLocal2017(now: now, calendar: calendar)
        return Data("\(milliseconds),Sync".utf8)
    }

    static func testPayload(now: Date, calendar: Calendar = .current) -> Data {
        let milliseconds = millisecondsSinceLocal2017(now: now, calendar: calendar)
        return Data("\(milliseconds),Test".utf8)
    }

    private static func millisecondsSinceLocal2017(now: Date, calendar: Calendar) -> Int64 {
        let timeZone = calendar.timeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: 2017,
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0
        )
        guard let epoch = calendar.date(from: components) else { return 0 }
        return Int64((now.timeIntervalSince(epoch) * 1_000).rounded(.towardZero))
    }

    static func heartbeatResponse(for notification: Data) -> Data? {
        let bytes = [UInt8](notification)
        guard bytes.count == 6, bytes[0] == 0xF0, bytes[1] == 0xE0 else { return nil }
        return Data([0xF0, 0xE0])
    }

    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x01) != 0 ? (crc >> 1) ^ 0x8C : crc >> 1
            }
        }
        return crc
    }

    private static func decodeAuthenticationToken(_ token: String) -> Int? {
        let units = Array(token.utf16).map(Int.init)
        guard units.count == 5 || units.count == 6 else { return nil }
        let key = [12, 31, 24, 6, 17, 5, 18, 29, 35, 3]

        let selector: Int
        let payloadStart: Int
        if units.count == 5 {
            selector = 99 - ((units[0] - 11) - 48)
            payloadStart = 1
        } else {
            selector = 99 - (((units[0] - 23 - 48) * 10) + (units[1] - 11 - 48))
            payloadStart = 2
        }

        guard (0...99).contains(selector) else { return nil }
        let offset = key[selector / 10] + key[selector % 10]
        var decoded = 0
        for index in payloadStart..<units.count {
            let digit = units[index] - offset - 48
            guard (0...9).contains(digit) else { return nil }
            decoded = (decoded * 10) + digit
        }
        return decoded
    }
}
