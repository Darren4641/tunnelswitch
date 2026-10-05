import Foundation

struct CommandResult {
    var code: Int32
    var out: String
    var err: String

    var message: String {
        let text = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }
}

/// 터널 엔진(engine/tunsw, 파이썬) 호출. 앱 번들 Resources 에 포함된 사본을 쓰고,
/// 번들 밖에서 실행(`swift run`)하면 ~/.local/bin/tunsw 를 쓴다.
enum Engine {
    static let path: String = {
        if let bundled = Bundle.main.path(forResource: "tunsw", ofType: nil) {
            return bundled
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/tunsw").path
    }()

    static func run(_ args: [String]) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", path] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return CommandResult(code: -1, out: "", err: "엔진 실행 실패: \(error.localizedDescription)")
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return CommandResult(code: p.terminationStatus,
                             out: String(decoding: o, as: UTF8.self),
                             err: String(decoding: e, as: UTF8.self))
    }
}
