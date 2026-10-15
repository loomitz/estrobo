import Foundation

enum SessionPhase: String {
    case booting
    case idle
    case bluetoothUnavailable
    case scanning
    case discovered
    case connecting
    case discovering
    case authenticating
    case ready
    case writing
    case error
    case disconnected
}

enum SessionCommand: String {
    case raiseGroupB = "B +1 paso"
    case restoreGroupB = "B restaurado"
}

enum SessionEvent {
    case bluetoothAvailable
    case bluetoothUnavailable(String)
    case radioCodeLoaded
    case scanStarted
    case deviceFound(name: String, count: Int)
    case connectStarted(name: String)
    case servicesDiscovering
    case transportReady
    case authenticationSucceeded
    case authenticationFailed(String)
    case writeStarted(SessionCommand)
    case writeSucceeded(SessionCommand)
    case writeFailed(String)
    case sessionFailed(String)
    case disconnected(String)
    case message(String)
    case reset
}

struct SessionTransitionError: LocalizedError, Equatable {
    let description: String
    var errorDescription: String? { description }
}

/// Pure state machine. It knows nothing about CoreBluetooth, stdin, rendering, or secrets.
struct SessionState {
    var phase: SessionPhase = .booting
    var radioCodeLoaded = false
    var deviceName: String?
    var discoveredCount = 0
    var authenticated = false
    var pendingCommand: SessionCommand?
    var lastConfirmedCommand: SessionCommand?
    var lastMessage = "Inicializando"
    var lastError: String?
    var confirmedWrites = 0

    func applying(_ event: SessionEvent) -> Result<SessionState, SessionTransitionError> {
        var next = self

        switch event {
        case .bluetoothAvailable:
            next.phase = .idle
            next.lastMessage = "Bluetooth disponible"
            next.lastError = nil

        case .bluetoothUnavailable(let reason):
            next.phase = .bluetoothUnavailable
            next.lastError = reason
            next.lastMessage = "Bluetooth no disponible"

        case .radioCodeLoaded:
            next.radioCodeLoaded = true
            next.lastMessage = "Código del radio cargado sólo en memoria"

        case .scanStarted:
            guard [.idle, .disconnected, .discovered, .error].contains(phase) else {
                return .failure(.init(description: "No se puede escanear desde \(phase.rawValue)."))
            }
            next.phase = .scanning
            next.discoveredCount = 0
            next.deviceName = nil
            next.lastMessage = "Buscando transmisores GD*/Ami-*"
            next.lastError = nil

        case .deviceFound(let name, let count):
            guard [.scanning, .discovered].contains(phase) else {
                return .failure(.init(description: "Se recibió un dispositivo fuera del escaneo."))
            }
            next.phase = .discovered
            next.deviceName = name
            next.discoveredCount = count
            next.lastMessage = "Transmisor compatible encontrado"

        case .connectStarted(let name):
            guard [.idle, .scanning, .discovered, .disconnected, .error].contains(phase) else {
                return .failure(.init(description: "No se puede conectar desde \(phase.rawValue)."))
            }
            next.phase = .connecting
            next.deviceName = name
            next.authenticated = false
            next.lastMessage = "Conectando"
            next.lastError = nil

        case .servicesDiscovering:
            guard [.connecting, .discovering].contains(phase) else {
                return .failure(.init(description: "Descubrimiento GATT inesperado desde \(phase.rawValue)."))
            }
            next.phase = .discovering
            next.lastMessage = "Descubriendo FEC0/FFF0"

        case .transportReady:
            guard [.connecting, .discovering].contains(phase) else {
                return .failure(.init(description: "Transporte listo inesperadamente desde \(phase.rawValue)."))
            }
            next.phase = .authenticating
            next.lastMessage = "Autenticando localmente"

        case .authenticationSucceeded:
            guard phase == .authenticating else {
                return .failure(.init(description: "Respuesta de autenticación inesperada desde \(phase.rawValue)."))
            }
            next.phase = .ready
            next.authenticated = true
            next.lastMessage = "Radio autenticado y listo"
            next.lastError = nil

        case .authenticationFailed(let reason):
            next.phase = .error
            next.authenticated = false
            next.lastError = reason
            next.lastMessage = "Falló el handshake local"

        case .writeStarted(let command):
            guard phase == .ready else {
                return .failure(.init(description: "No se puede escribir desde \(phase.rawValue)."))
            }
            next.phase = .writing
            next.pendingCommand = command
            next.lastMessage = "Esperando confirmación de \(command.rawValue)"

        case .writeSucceeded(let command):
            guard phase == .writing, pendingCommand == command else {
                return .failure(.init(description: "Confirmación de escritura inesperada."))
            }
            next.phase = .ready
            next.pendingCommand = nil
            next.lastConfirmedCommand = command
            next.confirmedWrites += 1
            next.lastMessage = "Confirmado: \(command.rawValue)"
            next.lastError = nil

        case .writeFailed(let reason):
            next.phase = .error
            next.pendingCommand = nil
            next.lastError = reason
            next.lastMessage = "La escritura no fue confirmada"

        case .sessionFailed(let reason):
            next.phase = .error
            next.authenticated = false
            next.pendingCommand = nil
            next.lastError = reason
            next.lastMessage = "Falló la sesión Bluetooth"

        case .disconnected(let reason):
            next.phase = .disconnected
            next.authenticated = false
            next.pendingCommand = nil
            next.lastMessage = reason

        case .message(let message):
            next.lastMessage = message

        case .reset:
            next = SessionState(phase: .idle, radioCodeLoaded: radioCodeLoaded)
            next.lastMessage = "Sesión reiniciada"
        }

        return .success(next)
    }

    var snapshot: [(String, String)] {
        [
            ("fase", phase.rawValue),
            ("código del radio en memoria", radioCodeLoaded ? "sí" : "no"),
            ("dispositivos", String(discoveredCount)),
            ("seleccionado", deviceName ?? "—"),
            ("autenticado", authenticated ? "sí" : "no"),
            ("orden pendiente", pendingCommand?.rawValue ?? "—"),
            ("última confirmación", lastConfirmedCommand?.rawValue ?? "—"),
            ("writes confirmados", String(confirmedWrites)),
            ("mensaje", lastMessage),
            ("error", lastError ?? "—"),
        ]
    }
}
