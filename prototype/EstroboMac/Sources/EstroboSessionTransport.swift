import Foundation

@MainActor
protocol EstroboSessionTransport: AnyObject {
    var delegate: (any BluetoothClientDelegate)? { get set }
    var isSimulation: Bool { get }

    func startScanning()
    func stopScanning()
    func connect(to device: BluetoothClient.Device)
    func disconnect()
    func forceResetConnection()
    func sendAuthentication(_ payload: Data)
    func sendSync(_ payload: Data)
    func sendTest(_ payload: Data)
    func sendControl(_ payload: Data)
}

extension EstroboSessionTransport {
    var isSimulation: Bool { false }
}

extension BluetoothClient: EstroboSessionTransport {}
