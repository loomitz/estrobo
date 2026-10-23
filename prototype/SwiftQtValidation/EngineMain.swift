import Foundation
import EstroboCore

@main
struct EngineMain {
    static func main() async {
        let runtime = await ExperimentRuntime()
        let (lines, continuation) = AsyncStream<String>.makeStream()
        let reader = Task.detached {
            while let line = readLine() { continuation.yield(line) }
            continuation.finish()
        }
        await runtime.hello()
        for await line in lines {
            if !(await runtime.handle(line)) { break }
        }
        await runtime.close()
        await reader.value // Qt closes stdin after the shutdown result.
    }
}
