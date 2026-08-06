import Foundation

enum GodoxProtocolError: LocalizedError, Equatable {
    case invalidRadioCode
    case invalidRandomValue
    case invalidPower

    var errorDescription: String? {
        switch self {
        case .invalidRadioCode:
            return "El código del radio debe contener exactamente seis dígitos."
        case .invalidRandomValue:
            return "El nonce requiere un entero entre 1 y 98."
        case .invalidPower:
            return "La potencia decimal debe estar entre 0 y 100."
        }
    }
}

enum GodoxGroup: UInt8, CaseIterable {
    case zero = 0x00, one, two, three, four, five, six, seven, eight, nine
    case a = 0x0A, b, c, d, e, f

    var label: String {
        switch self {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .a: "A"
        case .b: "B"
        case .c: "C"
        case .d: "D"
        case .e: "E"
        case .f: "F"
        }
    }
}

/// Pure, clean-room representation of the small protocol surface needed by the PoC.
enum GodoxProtocol {
    static let controlService = "0000FEC0-0000-1000-8000-00805F9B34FB"
    static let controlWrite = "0000FEC7-0000-1000-8000-00805F9B34FB"
    static let controlNotify = "0000FEC8-0000-1000-8000-00805F9B34FB"
    static let authenticationService = "0000FFF0-0000-1000-8000-00805F9B34FB"
    static let authenticationWrite = "0000FFF1-0000-1000-8000-00805F9B34FB"
    static let authenticationNotify = "0000FFF4-0000-1000-8000-00805F9B34FB"

    static func authenticationRequest(
        radioCode: String,
        unixMilliseconds: Int64,
        randomValue: Int
    ) throws -> Data {
        guard radioCode.count == 6,
              radioCode.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw GodoxProtocolError.invalidRadioCode
        }
        guard (1...98).contains(randomValue) else {
            throw GodoxProtocolError.invalidRandomValue
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
        return abs(nowSuffix - Int64(10_000 - decodedTime)) <= toleranceSeconds
    }

    static func manualGroupFrame(group: GodoxGroup, decimalPower: Int) throws -> Data {
        guard (0...100).contains(decimalPower) else {
            throw GodoxProtocolError.invalidPower
        }

        var bytes: [UInt8] = [
            0xF0, 0xA1, 0x07,
            group.rawValue,
            0x01,
            UInt8(100 - decimalPower),
            0x00, 0x00, 0x00, 0x00,
        ]
        bytes.append(crc8(bytes))
        return Data(bytes)
    }

    static func globalFrame(
        beep: Bool = false,
        modelingLight: Bool = false,
        standby: Bool = false,
        strobeEnabled: Bool = false,
        strobeCount: UInt8 = 10,
        strobeHertz: UInt8 = 10,
        strobeDecimalPower: Int = 50
    ) throws -> Data {
        guard (0...100).contains(strobeDecimalPower) else {
            throw GodoxProtocolError.invalidPower
        }

        var bytes: [UInt8] = [
            0xF0, 0xA0, 0x0A, 0xFF,
            beep ? 1 : 0,
            modelingLight ? 1 : 0,
            0x00,
            strobeEnabled ? 1 : 0,
            strobeCount,
            strobeHertz,
            UInt8(100 - strobeDecimalPower),
            standby ? 1 : 0,
            0x00,
        ]
        bytes.append(crc8(bytes))
        return Data(bytes)
    }

    static func synchronizationPayload(now: Date, calendar: Calendar = .current) -> Data {
        let milliseconds = millisecondsSinceLocal2017(now: now, calendar: calendar)
        return Data("\(milliseconds),Sync".utf8)
    }

    /// Present for protocol documentation only. The PoC deliberately exposes no caller action for it.
    static func testPayload(now: Date, calendar: Calendar = .current) -> Data {
        let milliseconds = millisecondsSinceLocal2017(now: now, calendar: calendar)
        return Data("\(milliseconds),Test".utf8)
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

    static func safeFrameSummary(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func millisecondsSinceLocal2017(now: Date, calendar source: Calendar) -> Int64 {
        let calendar = source
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
        let tens = selector / 10
        let ones = selector % 10
        let offset = key[tens] + key[ones]
        var decoded = 0

        for index in payloadStart..<units.count {
            let digit = units[index] - offset - 48
            guard (0...9).contains(digit) else { return nil }
            decoded = (decoded * 10) + digit
        }
        return decoded
    }
}
