import Foundation

public protocol ProcessExecuting: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> String
}

public struct SystemProcessExecutor: ProcessExecuting {
    public init() {}
    public func run(executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else { throw AppError.ompNotInstalled }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

public struct OMPInstallationDetector: OMPInstallationDetecting {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let executor: any ProcessExecuting

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, executor: any ProcessExecuting = SystemProcessExecutor()) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.executor = executor
    }

    public func detectInstallation() async throws -> OMPInstallation {
        let executable = try locateExecutable()
        let output = try await executor.run(executable: executable, arguments: ["--version"])
        let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "omp/", with: "")
        let directories = resolveDirectories()
        return OMPInstallation(executableURL: executable, version: version, configurationRoot: directories.root, agentDirectory: directories.agent)
    }

    private func locateExecutable() throws -> URL {
        let pathCandidates = environment["PATH", default: ""].split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "omp")
        }
        let candidates = ["/opt/homebrew/bin/omp", "/usr/local/bin/omp", "/usr/bin/omp"].map(URL.init(fileURLWithPath:)) + pathCandidates
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw AppError.ompNotInstalled }
        return executable
    }

    private func resolveDirectories() -> (root: URL, agent: URL) {
        if let agentOverride = environment["PI_CODING_AGENT_DIR"], !agentOverride.isEmpty {
            let agent = URL(fileURLWithPath: agentOverride, isDirectory: true).standardizedFileURL
            return (agent.deletingLastPathComponent(), agent)
        }
        let root = environment["PI_CONFIG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            ?? homeDirectory.appending(path: ".omp", directoryHint: .isDirectory)
        return (root, root.appending(path: "agent", directoryHint: .isDirectory))
    }

}
