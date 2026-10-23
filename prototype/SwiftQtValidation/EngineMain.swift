import Foundation
import EstroboCore

@main
struct EngineMain {
    static func main() async {
        let runtime = await ExperimentRuntime()
        let lines = AsyncStream<String> { continuation in
            Task.detached {
                while let line = readLine() { continuation.yield(line) }
                continuation.finish()
            }
        }
        await runtime.hello()
        for await line in lines {
            if !(await runtime.handle(line)) { break }
        }
        await runtime.close()
    }
}
