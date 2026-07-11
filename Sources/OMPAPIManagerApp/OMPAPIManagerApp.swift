import AppKit
import SwiftUI
import OMPAPIManagerCore

@main
struct OMPAPIManagerApp: App {
    @NSApplicationDelegateAdaptor(OMPApplicationDelegate.self) private var applicationDelegate
    @StateObject private var configurationViewModel = OMPConfigurationViewModel()
    @StateObject private var providerViewModel = ProviderManagementViewModel()
    @StateObject private var gatewayViewModel = GatewayViewModel()
    @StateObject private var usageViewModel = UsageDashboardViewModel()

    var body: some Scene {
        WindowGroup("OMP API Manager") {
            ContentView(viewModel: configurationViewModel, providerViewModel: providerViewModel, gatewayViewModel: gatewayViewModel, usageViewModel: usageViewModel)
        }
    }
}

private final class OMPApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class UsageDashboardViewModel: ObservableObject {
    @Published private(set) var summary = UsageSummary(requestCount: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0, errorCount: 0, averageLatencyMilliseconds: 0)
    @Published private(set) var records: [GatewayUsageRecord] = []
    @Published private(set) var errorMessage: String?
    private let repository: SQLiteUsageRepository?
    private let exporter = UsageExporter()

    init() {
        do { repository = try SQLiteUsageRepository.applicationSupportDefault() }
        catch { repository = nil; errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard let repository else { return }
        do {
            let startOfToday = Calendar.current.startOfDay(for: .now)
            summary = try await repository.summary(since: startOfToday)
            records = try await repository.recentUsage(limit: 100)
        } catch { errorMessage = error.localizedDescription }
    }

    func export(_ format: UsageExportFormat) async -> Data? {
        do { return try exporter.data(records: records, format: format) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func dismissError() { errorMessage = nil }
    func reportError(_ error: Error) { errorMessage = error.localizedDescription }
}

@MainActor
private final class GatewayViewModel: ObservableObject {
    @Published private(set) var status: GatewayStatus?
    @Published private(set) var message = "Gateway stopped"
    @Published private(set) var errorMessage: String?
    private let manager: GatewayManager?

    init() {
        do {
            manager = GatewayManager(usageRepository: try SQLiteUsageRepository.applicationSupportDefault())
        } catch {
            manager = nil
            errorMessage = error.localizedDescription
        }
    }

    func start(for provider: ProviderConfiguration) async {
        guard let manager else { return }
        do {
            status = try await manager.start(for: provider)
            if let status { message = "Gateway running at \(status.loopbackURL.absoluteString) for \(provider.displayName)" }
        } catch { errorMessage = error.localizedDescription }
    }

    func stop() async {
        guard let manager else { return }
        await manager.stop()
        status = nil
        message = "Gateway stopped"
    }

    func dismissError() { errorMessage = nil }
}

@MainActor
private final class ProviderManagementViewModel: ObservableObject {
    @Published private(set) var providers: [ProviderConfiguration] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var isConnecting = false
    @Published private(set) var fetchedModels: [RemoteModel] = []
    @Published private(set) var connectionMessage = ""
    private let service: ProviderManagementService?
    private let connectionService = ProviderConnectionService()

    init() {
        do {
            service = ProviderManagementService(repository: try JSONProviderRepository.applicationSupportDefault())
        } catch {
            service = nil
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let service else { return }
        do { providers = try await service.listProviders() }
        catch { errorMessage = error.localizedDescription }
    }

    func save(id: String, name: String, type: ProviderType, baseURL: String, apiKey: String, modelID: String, apply: Bool) async -> Bool {
        guard let service else { return false }
        guard let endpoint = URL(string: baseURL) else {
            errorMessage = "Enter a valid API base URL."
            return false
        }
        let provider = ProviderConfiguration(
            id: id,
            displayName: name,
            type: type,
            baseURL: endpoint,
            keychainAccount: "provider.\(id)",
            models: modelID.isEmpty ? [] : [ManagedModel(id: modelID)],
            defaultModelID: modelID.isEmpty ? nil : modelID
        )
        isSaving = true
        defer { isSaving = false }
        do {
            if apply { _ = try await service.saveAndApply(provider, apiKey: apiKey) }
            else { try await service.saveDraft(provider, apiKey: apiKey) }
            await refresh()
            return true
        } catch {
            // Applying can fail after the validated provider was safely saved as a draft.
            await refresh()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ provider: ProviderConfiguration) async {
        guard let service else { return }
        do {
            try await service.deleteDraft(provider)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func fetchModels(type: ProviderType, baseURL: String, apiKey: String) async {
        guard let endpoint = URL(string: baseURL) else { return setConnectionError("Enter a valid API base URL.") }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return setConnectionError("Enter an API key before fetching models.") }
        isConnecting = true
        defer { isConnecting = false }
        do {
            fetchedModels = try await connectionService.fetchModels(type: type, baseURL: endpoint, apiKey: apiKey)
                .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
            connectionMessage = "Fetched \(fetchedModels.count) models. You can also enter a model ID manually."
        } catch { setConnectionError(error.localizedDescription) }
    }

    func testConnection(type: ProviderType, baseURL: String, apiKey: String, modelID: String) async {
        guard let endpoint = URL(string: baseURL) else { return setConnectionError("Enter a valid API base URL.") }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return setConnectionError("Enter an API key before testing.") }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let result = try await connectionService.testConnection(type: type, baseURL: endpoint, apiKey: apiKey, model: modelID.isEmpty ? nil : modelID)
            connectionMessage = "Connection successful · HTTP \(result.statusCode.map(String.init) ?? "—") · \(result.detail)"
        } catch { setConnectionError(error.localizedDescription) }
    }

    func dismissError() { errorMessage = nil }

    private func setConnectionError(_ message: String) {
        connectionMessage = ""
        errorMessage = message
    }
}

@MainActor
private final class OMPConfigurationViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(OMPConfigurationSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private let inspector: any OMPConfigurationInspecting

    init(inspector: any OMPConfigurationInspecting = OMPConfigurationInspectionService()) {
        self.inspector = inspector
    }

    func refresh() async {
        state = .loading
        do { state = .loaded(try await inspector.inspectCurrentInstallation()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

private struct ContentView: View {
    private enum Section: Hashable { case overview, providers, usage, configuration }

    @ObservedObject var viewModel: OMPConfigurationViewModel
    @ObservedObject var providerViewModel: ProviderManagementViewModel
    @ObservedObject var gatewayViewModel: GatewayViewModel
    @ObservedObject var usageViewModel: UsageDashboardViewModel
    @State private var selection: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Overview", systemImage: "gauge.with.dots.needle.50percent").tag(Section.overview)
                Label("Providers", systemImage: "server.rack").tag(Section.providers)
                Label("Usage", systemImage: "chart.bar.xaxis").tag(Section.usage)
                Label("Configuration", systemImage: "doc.text").tag(Section.configuration)
            }
            .navigationTitle("OMP API Manager")
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(state: viewModel.state, gatewayViewModel: gatewayViewModel)
                case .providers: ProvidersView(state: viewModel.state, viewModel: providerViewModel, gatewayViewModel: gatewayViewModel)
                case .usage: UsageView(viewModel: usageViewModel)
                case .configuration: ConfigurationView(state: viewModel.state, providerViewModel: providerViewModel)
                }
            }
            .toolbar {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }
                    .accessibilityLabel("Refresh OMP configuration")
            }
            .task { await viewModel.refresh() }
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

private struct UsageView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Usage Today").font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                metric("Requests", value: "\(viewModel.summary.requestCount)")
                metric("Tokens", value: "\(viewModel.summary.totalTokens)")
                metric("Errors", value: "\(viewModel.summary.errorCount)")
                metric("Avg latency", value: "\(viewModel.summary.averageLatencyMilliseconds) ms")
            }
            List(viewModel.records) { record in
                HStack {
                    VStack(alignment: .leading) {
                        Text(record.modelID ?? record.providerID)
                        Text("\(record.providerID) · \(record.source?.rawValue ?? "usage unavailable")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tokenText(for: record)).monospacedDigit()
                    Text(statusText(for: record))
                        .foregroundStyle(record.errorCategory == nil ? Color.secondary : Color.red)
                }
            }
        }
        .padding(24)
        .navigationTitle("Usage")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }
            Menu("Export") {
                Button("CSV…") { export(.csv) }
                Button("JSON…") { export(.json) }
            }
        }
        .task { await viewModel.refresh() }
        .alert("Usage Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func tokenText(for record: GatewayUsageRecord) -> String {
        record.totalTokens.map { String($0) } ?? "—"
    }

    private func statusText(for record: GatewayUsageRecord) -> String {
        record.statusCode.map { String($0) } ?? "Network error"
    }

    private func export(_ format: UsageExportFormat) {
        Task {
            guard let data = await viewModel.export(format) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "omp-usage.\(format.rawValue)"
            if panel.runModal() == .OK, let url = panel.url {
                do { try data.write(to: url, options: .atomic) }
                catch { viewModel.reportError(error) }
            }
        }
    }
}

private struct OverviewView: View {
    let state: OMPConfigurationViewModel.State
    @ObservedObject var gatewayViewModel: GatewayViewModel

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Inspecting local OMP configuration…")
        case .failed(let message):
            ContentUnavailableView("OMP Not Available", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded(let snapshot):
            VStack(alignment: .leading, spacing: 20) {
                Label(snapshot.isWriteSupported ? "OMP 16.x configuration is supported" : "Read-only compatibility mode", systemImage: snapshot.isWriteSupported ? "checkmark.shield" : "eye.slash")
                    .font(.title2.weight(.semibold))
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow { Text("OMP version").foregroundStyle(.secondary); Text(snapshot.installation.version) }
                    GridRow { Text("Executable").foregroundStyle(.secondary); Text(snapshot.installation.executableURL.path).textSelection(.enabled) }
                    GridRow { Text("Configuration").foregroundStyle(.secondary); Text(snapshot.installation.agentDirectory.path).textSelection(.enabled) }
                    GridRow { Text("Default model").foregroundStyle(.secondary); Text(snapshot.defaultModel ?? "Not configured") }
                    GridRow { Text("Gateway").foregroundStyle(.secondary); Text(gatewayViewModel.message) }
                }
                if !snapshot.diagnostics.isEmpty { DiagnosticsList(messages: snapshot.diagnostics) }
                Spacer()
            }
            .padding(28)
        }
    }
}

private struct ProvidersView: View {
    let state: OMPConfigurationViewModel.State
    @ObservedObject var viewModel: ProviderManagementViewModel
    @ObservedObject var gatewayViewModel: GatewayViewModel
    @State private var isPresentingEditor = false

    var body: some View {
        Group {
            if viewModel.providers.isEmpty {
                ContentUnavailableView("No Saved Providers", systemImage: "server.rack", description: Text("Add an OpenAI- or Anthropic-compatible provider without exposing its API key."))
            } else {
                List {
                    ForEach(viewModel.providers) { provider in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                Text("\(provider.id) · \(provider.type.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !provider.isEnabled { Text("Disabled").foregroundStyle(.secondary) }
                            if gatewayViewModel.status == nil {
                                Button("Start Gateway") { Task { await gatewayViewModel.start(for: provider) } }
                            }
                            Button(role: .destructive) { Task { await viewModel.delete(provider) } } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(provider.displayName)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Providers")
        .toolbar { Button("Add Provider", systemImage: "plus") { isPresentingEditor = true } }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $isPresentingEditor) { ProviderEditor(viewModel: viewModel) }
        .alert("Provider Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: { Text(viewModel.errorMessage ?? "") }
        .alert("Gateway Error", isPresented: Binding(get: { gatewayViewModel.errorMessage != nil }, set: { if !$0 { gatewayViewModel.dismissError() } })) {
            Button("OK", role: .cancel) { gatewayViewModel.dismissError() }
        } message: { Text(gatewayViewModel.errorMessage ?? "") }
    }
}

private struct ProviderEditor: View {
    @ObservedObject var viewModel: ProviderManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var name = ""
    @State private var type: ProviderType = .openAICompatible
    @State private var baseURL = "https://"
    @State private var apiKey = ""
    @State private var modelID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Provider").font(.title2.weight(.semibold))
            Form {
                TextField("Provider ID", text: $id, prompt: Text("acme"))
                TextField("Display Name", text: $name, prompt: Text("Acme AI"))
                Picker("Protocol", selection: $type) {
                    ForEach(ProviderType.allCases, id: \.self) { option in
                        Text(protocolLabel(option)).tag(option)
                    }
                }
                TextField("API Base URL", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                SecureField("API Key", text: $apiKey)
                HStack {
                    Button("Fetch Models") { Task { await viewModel.fetchModels(type: type, baseURL: baseURL, apiKey: apiKey) } }
                    Button("Test Connection") { Task { await viewModel.testConnection(type: type, baseURL: baseURL, apiKey: apiKey, modelID: modelID) } }
                }
                .disabled(viewModel.isConnecting)
                if !viewModel.fetchedModels.isEmpty {
                    Picker("Fetched Model", selection: $modelID) {
                        Text("Select a model").tag("")
                        ForEach(viewModel.fetchedModels) { model in
                            Text(model.displayName ?? model.id).tag(model.id)
                        }
                    }
                }
                TextField("Model ID", text: $modelID, prompt: Text("Enter manually if needed"))
                if !viewModel.connectionMessage.isEmpty {
                    Label(viewModel.connectionMessage, systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("The API key is saved only in your macOS Keychain and is cleared from this form after success.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Draft") { save(apply: false) }
                    .disabled(viewModel.isSaving)
                Button("Save and Apply") { save(apply: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func save(apply: Bool) {
        Task {
            if await viewModel.save(id: id, name: name, type: type, baseURL: baseURL, apiKey: apiKey, modelID: modelID, apply: apply) {
                apiKey = ""
                dismiss()
            }
        }
    }

    private func protocolLabel(_ value: ProviderType) -> String {
        switch value {
        case .openAICompatible: "OpenAI Compatible"
        case .anthropicCompatible: "Anthropic Compatible"
        case .customOpenAILike: "Custom OpenAI-like"
        case .customAnthropicLike: "Custom Anthropic-like"
        }
    }
}

private struct ConfigurationView: View {
    let state: OMPConfigurationViewModel.State
    @ObservedObject var providerViewModel: ProviderManagementViewModel

    var body: some View {
        switch state {
        case .loaded(let snapshot):
            ConfigurationDetail(snapshot: snapshot, providerViewModel: providerViewModel)
        case .loading:
            ProgressView("Reading configuration…")
        case .failed(let message):
            ContentUnavailableView("Configuration Unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

}

private struct ConfigurationDetail: View {
    let snapshot: OMPConfigurationSnapshot
    @ObservedObject var providerViewModel: ProviderManagementViewModel
    @State private var isPresentingModelsEditor = false

    var body: some View {
        Form {
            Section("OMP") {
                LabeledContent("Version", value: snapshot.installation.version)
                LabeledContent("Write mode", value: snapshot.isWriteSupported ? "OMP 16.x adapter" : "Read-only")
            }
            Section("Files") {
                LabeledContent("config.yml", value: description(for: snapshot.configStatus))
                LabeledContent("models.yml", value: description(for: snapshot.modelsStatus))
            }
            Section("Advanced") {
                Button("Edit models.yml…") { isPresentingModelsEditor = true }
                    .disabled(!isModelsFileEditable)
                Text(isModelsFileEditable ? "Secrets are redacted in the editor. Existing secret references are preserved on save." : "models.yml must be valid and OMP 16.x must be detected before editing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !snapshot.diagnostics.isEmpty { Section("Diagnostics") { DiagnosticsList(messages: snapshot.diagnostics) } }
        }
        .formStyle(.grouped)
        .navigationTitle("Configuration")
        .sheet(isPresented: $isPresentingModelsEditor) {
            ModelsYAMLEditor(modelsURL: snapshot.installation.modelsURL, canWrite: snapshot.isWriteSupported, providerViewModel: providerViewModel)
        }
    }

    private var isModelsFileEditable: Bool {
        if case .valid = snapshot.modelsStatus { return snapshot.isWriteSupported }
        return false
    }

    private func description(for status: ConfigurationFileStatus) -> String {
        switch status {
        case .valid: "Valid YAML"
        case .missing: "Not found"
        case .invalid: "Invalid YAML"
        }
    }
}

@MainActor
private final class ModelsYAMLEditorViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = ""
    private let modelsURL: URL
    private let service = ModelsYAMLEditingService()
    private var fingerprint: FileFingerprint?

    init(modelsURL: URL) { self.modelsURL = modelsURL }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let document = try await service.load(at: modelsURL)
            text = document.text
            fingerprint = document.fingerprint
            statusMessage = "Loaded sanitized models.yml"
        } catch { errorMessage = error.localizedDescription }
    }

    func save() async {
        guard let fingerprint else { return await load() }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.save(editedYAML: text, to: modelsURL, expected: fingerprint)
            statusMessage = "Saved safely. Backup: \(result.backupURL.lastPathComponent)"
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func copy(_ provider: ProviderConfiguration) async {
        guard let fingerprint else { return await load() }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.copyProvider(provider, to: modelsURL, expected: fingerprint)
            statusMessage = "Copied \(provider.displayName). Backup: \(result.backupURL.lastPathComponent)"
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func dismissError() { errorMessage = nil }
}

private struct ModelsYAMLEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var providerViewModel: ProviderManagementViewModel
    @StateObject private var viewModel: ModelsYAMLEditorViewModel
    @State private var selectedProviderID = ""
    let canWrite: Bool

    init(modelsURL: URL, canWrite: Bool, providerViewModel: ProviderManagementViewModel) {
        self.canWrite = canWrite
        self.providerViewModel = providerViewModel
        _viewModel = StateObject(wrappedValue: ModelsYAMLEditorViewModel(modelsURL: modelsURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Advanced models.yml Editor").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Secret values are redacted. Leave the redaction marker unchanged to retain the existing Keychain reference. Plaintext secrets are rejected.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $viewModel.text)
                .font(.system(.body, design: .monospaced))
                .border(.quaternary)
                .disabled(!canWrite || viewModel.isLoading)
            HStack {
                Picker("Copy saved provider", selection: $selectedProviderID) {
                    Text("Select provider").tag("")
                    ForEach(providerViewModel.providers) { provider in Text(provider.displayName).tag(provider.id) }
                }
                Button("Copy into models.yml") {
                    if let provider = providerViewModel.providers.first(where: { $0.id == selectedProviderID }) {
                        Task { await viewModel.copy(provider) }
                    }
                }
                .disabled(!canWrite || selectedProviderID.isEmpty || viewModel.isLoading)
                Spacer()
                Button("Reload") { Task { await viewModel.load() } }
                Button("Validate and Save") { Task { await viewModel.save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canWrite || viewModel.isLoading)
            }
            if !viewModel.statusMessage.isEmpty { Text(viewModel.statusMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 580)
        .task {
            await providerViewModel.refresh()
            await viewModel.load()
        }
        .alert("models.yml Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: { Text(viewModel.errorMessage ?? "") }
    }
}

private struct DiagnosticsList: View {
    let messages: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
