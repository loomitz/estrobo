import CoreBluetooth
import Darwin
import Dispatch
import Foundation

private let ansiClear = "\u{001B}[2J\u{001B}[H"
private let ansiBold = "\u{001B}[1m"
private let ansiDim = "\u{001B}[2m"
private let ansiReset = "\u{001B}[0m"

private func writeTerminal(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

private func readRadioCodeWithoutEcho() -> String? {
    while true {
        writeTerminal("Código local de seis dígitos del radio: ")

        var original = termios()
        let terminalAvailable = isatty(STDIN_FILENO) == 1
            && tcgetattr(STDIN_FILENO, &original) == 0
        if terminalAvailable {
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden)
        }

        let radioCode = readLine()
        if terminalAvailable {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
        writeTerminal("\n")

        guard let radioCode else { return nil }
        if radioCode.count == 6, radioCode.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
            return radioCode
        }
        writeTerminal("El código del radio debe contener exactamente seis dígitos.\n")
    }
}

@MainActor
private final class TerminalApp: BluetoothClientDelegate {
    private var radioCode: String
    private lazy var client = BluetoothClient(delegate: self)
    private var state = SessionState()
    private var devices: [BluetoothClient.Device] = []
    private var recentEvents: [String] = []
    private var inputSource: (any DispatchSourceRead)?
    private var inputBuffer = ""
    private var authenticationAttempt: UUID?
    private var pendingControl: SessionCommand?
    private var lastFrame = "—"
    private var needsRestore = false

    init(radioCode: String) {
        self.radioCode = radioCode
    }

    func start() {
        apply(.radioCodeLoaded)
        apply(.bluetoothAvailable)
        installInputSource()
        client.startScanning()
        render()
    }

    func bluetoothClient(didReceive event: BluetoothClient.Event) {
        switch event {
        case .stateChanged(let clientState):
            handle(clientState)

        case .discoveryReset:
            devices.removeAll()
            render()

        case .discovered(let device):
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
            devices.sort { $0.name < $1.name }
            apply(.deviceFound(name: device.name, count: devices.count))

        case .log(let level, let message):
            appendEvent("\(label(for: level)): \(message)")

        case .readyForAuthentication:
            beginAuthentication()

        case .notification(.authentication, let data):
            handleAuthenticationResponse(data)

        case .notification(.control, let data):
            if let heartbeat = GodoxProtocol.heartbeatResponse(for: data) {
                appendEvent("heartbeat F0 E0 recibido")
                client.sendControl(heartbeat)
            } else {
                appendEvent("notificación FEC8 recibida (\(data.count) bytes)")
            }

        case .commandSent(let kind):
            switch kind {
            case .authentication:
                appendEvent("reto local enviado; payload redactado")
            case .sync:
                appendEvent("reloj del radio sincronizado")
            case .test:
                appendEvent("disparo Test explícito enviado")
            case .control:
                break
            }

        case .controlWriteStarted:
            break

        case .controlWriteCompleted:
            if let command = pendingControl {
                pendingControl = nil
                apply(.writeSucceeded(command))
                if command == .raiseGroupB {
                    needsRestore = true
                } else if command == .restoreGroupB {
                    needsRestore = false
                }
            } else {
                appendEvent("write auxiliar confirmado")
            }

        case .commandFailed(let kind, let error):
            let message = error.localizedDescription
            if kind == .control, pendingControl != nil {
                pendingControl = nil
                apply(.writeFailed(message))
            } else if kind == .authentication {
                authenticationAttempt = nil
                apply(.authenticationFailed(message))
            } else {
                appendEvent("error de comando: \(message)")
            }

        case .failed(let error):
            authenticationAttempt = nil
            apply(.sessionFailed(error.localizedDescription))
        }
    }

    private func handle(_ clientState: BluetoothClient.State) {
        switch clientState {
        case .idle:
            if state.phase == .booting || state.phase == .bluetoothUnavailable {
                apply(.bluetoothAvailable)
            } else if ![.idle, .scanning, .discovered].contains(state.phase) {
                apply(.disconnected("Radio BLE desconectado"))
            }

        case .waitingForBluetooth:
            apply(.message("Esperando a que macOS habilite Bluetooth"))

        case .bluetoothUnavailable(let reason):
            apply(.bluetoothUnavailable(reason))

        case .scanning:
            if state.phase != .scanning {
                apply(.scanStarted)
            }

        case .connecting(let device):
            apply(.connectStarted(name: device.name))

        case .discovering:
            apply(.servicesDiscovering)

        case .subscribing:
            apply(.message("Activando FFF4 y FEC8"))

        case .ready:
            apply(.message("Transporte GATT listo; esperando handshake"))

        case .disconnecting:
            apply(.message("Desconectando"))

        case .failed(let message):
            apply(.sessionFailed(message))
        }
    }

    private func beginAuthentication() {
        apply(.transportReady)
        let now = unixMilliseconds()
        do {
            let request = try GodoxProtocol.authenticationRequest(
                radioCode: radioCode,
                unixMilliseconds: now,
                randomValue: Int.random(in: 1...98)
            )
            let attempt = UUID()
            authenticationAttempt = attempt
            client.sendAuthentication(request)

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self,
                      self.authenticationAttempt == attempt,
                      self.state.phase == .authenticating else {
                    return
                }
                self.authenticationAttempt = nil
                self.apply(.authenticationFailed("El radio no respondió en 10 segundos"))
            }
        } catch {
            apply(.authenticationFailed(error.localizedDescription))
        }
    }

    private func handleAuthenticationResponse(_ data: Data) {
        guard state.phase == .authenticating else {
            appendEvent("respuesta FFF4 ignorada fuera del handshake")
            return
        }
        guard GodoxProtocol.isValidAuthenticationResponse(
            data,
            unixMilliseconds: unixMilliseconds()
        ) else {
            authenticationAttempt = nil
            apply(.authenticationFailed("Respuesta PWOK inválida o fuera de tiempo"))
            return
        }

        authenticationAttempt = nil
        appendEvent("handshake PWOK validado localmente")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.state.phase == .authenticating else { return }
            self.client.sendSync(GodoxProtocol.synchronizationPayload(now: Date()))
            self.apply(.authenticationSucceeded)
        }
    }

    private func sendPowerCommand(_ command: SessionCommand) {
        guard state.phase == .ready else {
            apply(.message("El radio aún no está autenticado"))
            return
        }

        let decimalPower = command == .raiseGroupB ? 23 : 20
        do {
            let frame = try GodoxProtocol.manualGroupFrame(
                group: .b,
                decimalPower: decimalPower
            )
            pendingControl = command
            lastFrame = GodoxProtocol.safeFrameSummary(frame)
            apply(.writeStarted(command))
            client.sendControl(frame)
        } catch {
            apply(.writeFailed(error.localizedDescription))
        }
    }

    private func installInputSource() {
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler { [weak self] in
            self?.consumeAvailableInput()
        }
        source.setCancelHandler {}
        inputSource = source
        source.resume()
    }

    private func consumeAvailableInput() {
        let data = FileHandle.standardInput.availableData
        guard !data.isEmpty else {
            quitIfSafe()
            return
        }
        inputBuffer += String(decoding: data, as: UTF8.self)
        while let newline = inputBuffer.firstIndex(of: "\n") {
            let line = String(inputBuffer[..<newline])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            inputBuffer.removeSubrange(...newline)
            handleCommand(line)
        }
    }

    private func handleCommand(_ line: String) {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else {
            render()
            return
        }

        switch command {
        case "s":
            client.startScanning()

        case "x":
            client.stopScanning()
            apply(.message("Escaneo detenido"))

        case "c":
            guard parts.count == 2,
                  let number = Int(parts[1]),
                  devices.indices.contains(number - 1) else {
                apply(.message("Usa c <número>, por ejemplo: c 1"))
                return
            }
            client.connect(to: devices[number - 1])

        case "u":
            sendPowerCommand(.raiseGroupB)

        case "r":
            sendPowerCommand(.restoreGroupB)

        case "d":
            guard !needsRestore else {
                apply(.message("Restaura primero con r antes de desconectar"))
                return
            }
            client.disconnect()

        case "q":
            quitIfSafe()

        case "h", "?":
            apply(.message("Comandos mostrados al pie"))

        default:
            apply(.message("Comando desconocido: \(command)"))
        }
    }

    private func quitIfSafe() {
        guard !needsRestore else {
            apply(.message("La potencia fue elevada: usa r y espera confirmación antes de salir"))
            return
        }

        radioCode = ""
        inputSource?.cancel()
        inputSource = nil
        client.disconnect()
        writeTerminal("\nPoC finalizado sin una restauración pendiente.\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(EXIT_SUCCESS)
        }
    }

    private func apply(_ event: SessionEvent) {
        switch state.applying(event) {
        case .success(let next):
            state = next
        case .failure(let error):
            recentEvents.append("TRANSICIÓN: \(error.localizedDescription)")
            recentEvents = Array(recentEvents.suffix(5))
        }
        render()
    }

    private func appendEvent(_ message: String) {
        recentEvents.append(message)
        recentEvents = Array(recentEvents.suffix(5))
        render()
    }

    private func render() {
        var output = ansiClear
        output += "\(ansiBold)Godox BLE PoC — prototipo desechable\(ansiReset)\n"
        output += "\(ansiDim)Sin cuenta, red, firmware ni disparo\(ansiReset)\n\n"

        output += "\(ansiBold)Estado\(ansiReset)\n"
        for (key, value) in state.snapshot {
            let paddedKey = key.padding(toLength: 22, withPad: " ", startingAt: 0)
            output += "  \(paddedKey) \(value)\n"
        }
        output += "  requiere restauración  \(needsRestore ? "SÍ — usa r" : "no")\n"
        output += "  último frame A1         \(lastFrame)\n"

        output += "\n\(ansiBold)Dispositivos\(ansiReset)\n"
        if devices.isEmpty {
            output += "  — ninguno; Android debe liberar el radio —\n"
        } else {
            for (index, device) in devices.enumerated() {
                output += "  \(index + 1). \(device.name)  RSSI \(device.rssi)\n"
            }
        }

        output += "\n\(ansiBold)Eventos recientes\(ansiReset)\n"
        if recentEvents.isEmpty {
            output += "  —\n"
        } else {
            for event in recentEvents {
                output += "  \(ansiDim)\(event)\(ansiReset)\n"
            }
        }

        output += "\n\(ansiBold)Comandos\(ansiReset)\n"
        output += "  s escanear   x detener   c <n> conectar   d desconectar\n"
        output += "  u grupo B +1 paso   r restaurar B   q salir   h ayuda\n"
        output += "\n> "
        writeTerminal(output)
    }

    private func label(for level: BluetoothClient.LogLevel) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .warning: "aviso"
        case .error: "error"
        }
    }

    private func unixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }
}

@main
private enum GodoxBLEPoCMain {
    @MainActor
    static func main() {
        guard let radioCode = readRadioCodeWithoutEcho() else {
            writeTerminal("No se recibió el código del radio.\n")
            exit(EXIT_FAILURE)
        }

        let app = TerminalApp(radioCode: radioCode)
        app.start()
        dispatchMain()
    }
}
