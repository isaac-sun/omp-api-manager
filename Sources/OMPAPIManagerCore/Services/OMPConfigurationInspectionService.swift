import Foundation

/// Read-only inspection path shared by all OMP releases. Version-specific adapters own writes.
public struct OMPConfigurationInspectionService: OMPConfigurationInspecting {
    private let detector: any OMPInstallationDetecting
    private let store: YAMLConfigurationStore

    public init(detector: any OMPInstallationDetecting = OMPInstallationDetector(), store: YAMLConfigurationStore = YAMLConfigurationStore()) {
        self.detector = detector
        self.store = store
    }

    public func inspectCurrentInstallation() async throws -> OMPConfigurationSnapshot {
        let installation = try await detector.detectInstallation()
        let configResult = await readFile(at: installation.configURL)
        let modelsResult = await readFile(at: installation.modelsURL)
        let configDocument = configResult.document
        let modelsDocument = modelsResult.document
        let providerIDs = providerIDs(in: modelsDocument)
        let defaultModel = defaultModel(in: configDocument)
        let writeSupported = installation.version.split(separator: ".").first == "16"
        var diagnostics = configResult.diagnostics + modelsResult.diagnostics
        if !writeSupported {
            diagnostics.append("OMP \(installation.version) is shown read-only. No matching configuration write adapter is installed.")
        }
        return OMPConfigurationSnapshot(
            installation: installation,
            isWriteSupported: writeSupported,
            configStatus: configResult.status,
            modelsStatus: modelsResult.status,
            providerIDs: providerIDs,
            defaultModel: defaultModel,
            diagnostics: diagnostics
        )
    }

    private func readFile(at url: URL) async -> (document: YAMLDocument?, status: ConfigurationFileStatus, diagnostics: [String]) {
        do {
            let result = try await store.readDocument(at: url)
            return (result.document, .valid(result.fingerprint), [])
        } catch AppError.configurationNotFound {
            return (nil, .missing, ["\(url.lastPathComponent) is not present."])
        } catch AppError.configurationParseFailed(let description) {
            return (nil, .invalid(description), ["\(url.lastPathComponent) could not be parsed: \(description)"])
        } catch {
            return (nil, .invalid(error.localizedDescription), ["\(url.lastPathComponent) could not be inspected: \(error.localizedDescription)"])
        }
    }

    private func providerIDs(in document: YAMLDocument?) -> [String] {
        guard case .object(let root) = document?.root,
              case .object(let providers) = root["providers"] else { return [] }
        return providers.keys.sorted()
    }

    private func defaultModel(in document: YAMLDocument?) -> String? {
        guard case .object(let root) = document?.root,
              case .object(let roles) = root["modelRoles"],
              case .string(let model) = roles["default"] else { return nil }
        return model
    }
}
