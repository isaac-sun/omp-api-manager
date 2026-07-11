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
        if let iconURL = Bundle.module.url(forResource: "AppIcon-master", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
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

    func save(id: String, name: String, type: ProviderType, ompAPI: String, baseURL: String, apiKey: String, models: [ManagedModel], apply: Bool) async -> Bool {
        guard let service else { return false }
        guard let endpoint = URL(string: baseURL) else {
            errorMessage = "Enter a valid API base URL."
            return false
        }
        let provider = ProviderConfiguration(
            id: id,
            displayName: name,
            type: type,
            ompAPIOverride: ompAPI == type.ompAPI ? nil : ompAPI,
            baseURL: endpoint,
            keychainAccount: "provider.\(id)",
            models: models,
            defaultModelID: models.first?.id
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

    func importNewAPIChannelConnection(_ source: String, apply: Bool) async -> Bool {
        guard let service else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.importNewAPIChannelConnection(source, apply: apply)
            await refresh()
            return true
        } catch {
            // Applying can fail after the provider was safely imported as a draft.
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
                SwiftUI.Section("Workspace") {
                    Label("Overview", systemImage: "rectangle.3.group.fill").tag(Section.overview)
                    Label("Providers", systemImage: "point.3.connected.trianglepath.dotted").tag(Section.providers)
                    Label("Usage", systemImage: "chart.xyaxis.line").tag(Section.usage)
                }
                SwiftUI.Section("System") {
                    Label("Configuration", systemImage: "slider.horizontal.3").tag(Section.configuration)
                }
            }
            .listStyle(.sidebar)
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
        .tint(AppTheme.accent)
        .frame(minWidth: 960, minHeight: 640)
    }
}

private struct UsageView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Usage",
                    subtitle: "Private, local request metadata from your gateway. Prompts and API keys are never stored.",
                    icon: "chart.xyaxis.line"
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricCard(title: "Requests", value: "\(viewModel.summary.requestCount)", icon: "arrow.left.arrow.right", tint: AppTheme.accent)
                    MetricCard(title: "Tokens", value: "\(viewModel.summary.totalTokens)", icon: "number", tint: .purple)
                    MetricCard(title: "Errors", value: "\(viewModel.summary.errorCount)", icon: "exclamationmark.triangle", tint: viewModel.summary.errorCount == 0 ? .green : .orange)
                    MetricCard(title: "Average latency", value: "\(viewModel.summary.averageLatencyMilliseconds) ms", icon: "timer", tint: .blue)
                }

                AppCard {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recent activity").font(.headline)
                            Text("Most recent 100 gateway requests")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Today").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)

                    if viewModel.records.isEmpty {
                        ContentUnavailableView("No usage yet", systemImage: "chart.line.uptrend.xyaxis", description: Text("Start the local gateway and send a request to see sanitized usage data here."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(viewModel.records) { record in
                                UsageRow(record: record, tokens: tokenText(for: record), status: statusText(for: record))
                                if record.id != viewModel.records.last?.id { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
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
        Group {
            switch state {
            case .loading:
                ProgressView("Inspecting local OMP configuration…").controlSize(.large)
            case .failed(let message):
                ContentUnavailableView("OMP Not Available", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded(let snapshot):
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    PageHeader(
                        title: "Overview",
                        subtitle: "Your local OMP environment at a glance.",
                        icon: "rectangle.3.group.fill",
                        status: snapshot.isWriteSupported ? "Ready to manage" : "Read-only"
                    )

                    AppCard {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: snapshot.isWriteSupported ? "checkmark.shield.fill" : "eye.slash.fill")
                                .font(.title2).foregroundStyle(snapshot.isWriteSupported ? .green : .orange)
                                .frame(width: 38, height: 38)
                                .background((snapshot.isWriteSupported ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(snapshot.isWriteSupported ? "OMP 16.x is ready" : "Compatibility mode")
                                    .font(.headline)
                                Text(snapshot.isWriteSupported ? "Provider changes are safely applied with backups." : "You can inspect this installation, but edits remain disabled to protect your configuration.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        AppCard {
                            Text("Environment").font(.headline)
                            LabeledContent("OMP version", value: snapshot.installation.version)
                            LabeledContent("Default model", value: snapshot.defaultModel ?? "Not configured")
                            Divider().padding(.vertical, 3)
                            DetailLine(label: "Executable", value: snapshot.installation.executableURL.path)
                            DetailLine(label: "Configuration", value: snapshot.installation.agentDirectory.path)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        AppCard {
                            HStack {
                                Text("Local gateway").font(.headline)
                                Spacer()
                                StatusPill(text: gatewayViewModel.status == nil ? "Stopped" : "Running", tint: gatewayViewModel.status == nil ? .secondary : .green)
                            }
                            Text(gatewayViewModel.message)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            Text("Only localhost can reach the gateway. Usage records remain on this Mac.")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    if !snapshot.diagnostics.isEmpty {
                        AppCard {
                            Label("Diagnostics", systemImage: "exclamationmark.circle.fill").font(.headline)
                            DiagnosticsList(messages: snapshot.diagnostics).padding(.top, 5)
                        }
                    }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Overview")
    }
}

private struct ProvidersView: View {
    let state: OMPConfigurationViewModel.State
    @ObservedObject var viewModel: ProviderManagementViewModel
    @ObservedObject var gatewayViewModel: GatewayViewModel
    @State private var isPresentingEditor = false
    @State private var isPresentingNewAPIImporter = false
    @State private var providerToDuplicate: ProviderConfiguration?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Providers",
                    subtitle: "Credentials are stored only in your macOS Keychain.",
                    icon: "point.3.connected.trianglepath.dotted",
                    status: "\(viewModel.providers.count) saved"
                )
            if viewModel.providers.isEmpty {
                    AppCard {
                        ContentUnavailableView("No saved providers", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Add an OpenAI- or Anthropic-compatible provider. Its API key stays in your Keychain."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        Button("Add your first provider", systemImage: "plus") { isPresentingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
            } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.providers) { provider in
                            ProviderCard(provider: provider, gatewayViewModel: gatewayViewModel) {
                                Task { await viewModel.delete(provider) }
                            } duplicate: {
                                providerToDuplicate = provider
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItemGroup {
                Button("Import New API Connection", systemImage: "arrow.down.doc") { isPresentingNewAPIImporter = true }
                Button("Add Provider", systemImage: "plus") { isPresentingEditor = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $isPresentingEditor) { ProviderEditor(viewModel: viewModel) }
        .sheet(item: $providerToDuplicate) { ProviderEditor(viewModel: viewModel, template: $0) }
        .sheet(isPresented: $isPresentingNewAPIImporter) { NewAPIChannelConnectionImporterView(viewModel: viewModel) }
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
    @State private var ompAPI = ProviderType.openAICompatible.ompAPI
    @State private var baseURL = "https://"
    @State private var apiKey = ""
    @State private var isAPIKeyVisible = false
    @State private var modelDrafts: [ModelDraft] = [ModelDraft()]
    @State private var validationMessage: String?

    init(viewModel: ProviderManagementViewModel, template: ProviderConfiguration? = nil) {
        self.viewModel = viewModel
        _id = State(initialValue: template.map { "\($0.id)-copy-\(UUID().uuidString.prefix(4).lowercased())" } ?? "")
        _name = State(initialValue: template.map { "\($0.displayName) Copy" } ?? "")
        _type = State(initialValue: template?.type ?? .openAICompatible)
        _ompAPI = State(initialValue: template?.ompAPI ?? ProviderType.openAICompatible.ompAPI)
        _baseURL = State(initialValue: template?.baseURL.absoluteString ?? "https://")
        _modelDrafts = State(initialValue: template.map { $0.models.map(ModelDraft.init) } ?? [ModelDraft()])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Add provider",
                subtitle: "Connect an OpenAI- or Anthropic-compatible endpoint.",
                icon: "plus.circle.fill"
            )
            Form {
                Section("Identity") {
                    TextField("Provider ID", text: $id, prompt: Text("acme"))
                    TextField("Display Name", text: $name, prompt: Text("Acme AI"))
                    Picker("Protocol", selection: $type) {
                        ForEach(ProviderType.allCases, id: \.self) { option in
                            Text(protocolLabel(option)).tag(option)
                        }
                    }
                    Picker("OMP API mode", selection: $ompAPI) {
                        ForEach(ompAPIOptions(for: type), id: \.self) { option in Text(option).tag(option) }
                    }
                    .onChange(of: type) { _, newValue in
                        if !ompAPIOptions(for: newValue).contains(ompAPI) { ompAPI = newValue.ompAPI }
                    }
                }

                Section("Connection") {
                    TextField("API Base URL", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                    LabeledContent("API Key") {
                        HStack(spacing: 8) {
                            Group {
                                if isAPIKeyVisible { TextField("Enter API key", text: $apiKey) }
                                else { SecureField("Enter API key", text: $apiKey) }
                            }
                            Button { isAPIKeyVisible.toggle() } label: {
                                Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            }
                            .accessibilityLabel(isAPIKeyVisible ? "Hide API key" : "Show API key")
                        }
                    }
                    HStack {
                        Button("Fetch Models") { Task { await viewModel.fetchModels(type: type, baseURL: baseURL, apiKey: apiKey) } }
                        Button("Test Connection") { Task { await viewModel.testConnection(type: type, baseURL: baseURL, apiKey: apiKey, modelID: modelDrafts.first?.modelID ?? "") } }
                    }
                    .disabled(viewModel.isConnecting)
                    if viewModel.isConnecting { ProgressView().controlSize(.small) }
                    if !viewModel.connectionMessage.isEmpty {
                        Label(viewModel.connectionMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Models") {
                    Text("Define one or more models, including capabilities and per-million-token pricing.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($modelDrafts) { $draft in
                        ModelDraftFields(
                            draft: $draft,
                            fetchedModels: viewModel.fetchedModels,
                            canRemove: modelDrafts.count > 1,
                            remove: { modelDrafts.removeAll { $0.id == draft.id } }
                        )
                    }
                    Button("Add Another Model", systemImage: "plus") { modelDrafts.append(ModelDraft()) }
                }
            }
            .formStyle(.grouped)
            Label("The API key is saved only in your macOS Keychain and is cleared from this form after success.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
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
        .padding(28)
        .frame(width: 650)
        .onDisappear { apiKey = "" }
        .alert("Model Configuration", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
            Button("OK", role: .cancel) { validationMessage = nil }
        } message: { Text(validationMessage ?? "") }
    }

    private func save(apply: Bool) {
        let models: [ManagedModel]
        do {
            models = try modelDrafts.filter(\.hasContent).map { try $0.makeModel() }
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        Task {
            if await viewModel.save(id: id, name: name, type: type, ompAPI: ompAPI, baseURL: baseURL, apiKey: apiKey, models: models, apply: apply) {
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

    private func ompAPIOptions(for type: ProviderType) -> [String] {
        switch type {
        case .openAICompatible, .customOpenAILike:
            ["openai-completions", "openai-responses", "openai-codex-responses", "azure-openai-responses"]
        case .anthropicCompatible, .customAnthropicLike:
            ["anthropic-messages"]
        }
    }
}

private struct ModelDraft: Identifiable {
    let id = UUID()
    var modelID = ""
    var displayName = ""
    var contextWindow = ""
    var maxTokens = ""
    var inputPrice = ""
    var outputPrice = ""
    var cacheReadPrice = ""
    var cacheWritePrice = ""
    var acceptsText = true
    var acceptsImage = false
    var supportsReasoning = false

    init(model: ManagedModel? = nil) {
        guard let model else { return }
        modelID = model.id
        displayName = model.displayName == model.id ? "" : model.displayName
        contextWindow = model.contextWindow.map(String.init) ?? ""
        maxTokens = model.maxTokens.map(String.init) ?? ""
        inputPrice = model.inputPricePerMillion.map(decimalText) ?? ""
        outputPrice = model.outputPricePerMillion.map(decimalText) ?? ""
        cacheReadPrice = model.cacheReadPricePerMillion.map(decimalText) ?? ""
        cacheWritePrice = model.cacheWritePricePerMillion.map(decimalText) ?? ""
        acceptsText = model.inputModalities?.contains("text") ?? true
        acceptsImage = model.inputModalities?.contains("image") ?? false
        supportsReasoning = model.supportsReasoning ?? false
    }

    var hasContent: Bool {
        [modelID, displayName, contextWindow, maxTokens, inputPrice, outputPrice, cacheReadPrice, cacheWritePrice].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func makeModel() throws -> ManagedModel {
        let identifier = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { throw AppError.invalidProvider("Each configured model needs an ID.") }
        let context = try positiveInteger(contextWindow, label: "Context window")
        let maximum = try positiveInteger(maxTokens, label: "Max tokens")
        let input = try nonNegativeDecimal(inputPrice, label: "Input price")
        let output = try nonNegativeDecimal(outputPrice, label: "Output price")
        let cacheRead = try nonNegativeDecimal(cacheReadPrice, label: "Cache read price")
        let cacheWrite = try nonNegativeDecimal(cacheWritePrice, label: "Cache write price")
        var modalities: [String] = []
        if acceptsText { modalities.append("text") }
        if acceptsImage { modalities.append("image") }
        return ManagedModel(
            id: identifier,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            contextWindow: context,
            maxTokens: maximum,
            inputPricePerMillion: input,
            outputPricePerMillion: output,
            cacheReadPricePerMillion: cacheRead,
            cacheWritePricePerMillion: cacheWrite,
            inputModalities: modalities.isEmpty ? nil : modalities,
            supportsReasoning: supportsReasoning ? true : nil
        )
    }

    private func positiveInteger(_ value: String, label: String) throws -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let number = Int(text), number > 0 else { throw AppError.invalidProvider("\(label) must be a positive whole number.") }
        return number
    }

    private func nonNegativeDecimal(_ value: String, label: String) throws -> Decimal? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let number = Decimal(string: text) ?? Double(text).map { Decimal($0) }
        guard let number, number >= 0 else { throw AppError.invalidProvider("\(label) must be a non-negative number.") }
        return number
    }

    private func decimalText(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

private struct ModelDraftFields: View {
    @Binding var draft: ModelDraft
    let fetchedModels: [RemoteModel]
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.modelID.isEmpty ? "New model" : draft.modelID).font(.subheadline.weight(.semibold))
                Spacer()
                if canRemove {
                    Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove model")
                }
            }
            if !fetchedModels.isEmpty {
                Picker("Discovered model", selection: $draft.modelID) {
                    Text("Select a model").tag("")
                    ForEach(fetchedModels) { model in Text(model.displayName ?? model.id).tag(model.id) }
                }
            }
            TextField("Model ID", text: $draft.modelID, prompt: Text("gpt-4.1"))
            TextField("Display name", text: $draft.displayName, prompt: Text("Optional"))
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    TextField("Context window", text: $draft.contextWindow)
                    TextField("Max tokens", text: $draft.maxTokens)
                }
                GridRow {
                    TextField("Input / 1M", text: $draft.inputPrice)
                    TextField("Output / 1M", text: $draft.outputPrice)
                }
                GridRow {
                    TextField("Cache read / 1M", text: $draft.cacheReadPrice)
                    TextField("Cache write / 1M", text: $draft.cacheWritePrice)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick token presets").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Context").font(.caption).foregroundStyle(.secondary)
                    ForEach([32_000, 64_000, 128_000, 200_000, 500_000], id: \.self) { value in
                        Button(tokenLabel(value)) { draft.contextWindow = String(value) }.buttonStyle(.bordered)
                    }
                }
                HStack(spacing: 6) {
                    Text("Output").font(.caption).foregroundStyle(.secondary)
                    ForEach([8_000, 16_000, 32_000, 64_000, 128_000], id: \.self) { value in
                        Button(tokenLabel(value)) { draft.maxTokens = String(value) }.buttonStyle(.bordered)
                    }
                }
            }
            .controlSize(.small)
            Text("Advanced capabilities").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Toggle("Text", isOn: $draft.acceptsText)
                Toggle("Image", isOn: $draft.acceptsImage)
                Toggle("Reasoning", isOn: $draft.supportsReasoning)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tokenLabel(_ value: Int) -> String { "\(value / 1_000)K" }
}

private struct NewAPIChannelConnectionImporterView: View {
    @ObservedObject var viewModel: ProviderManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "Import New API connection",
                subtitle: "Paste a newapi_channel_conn JSON connection to create an OpenAI-compatible provider.",
                icon: "arrow.down.doc.fill"
            )
            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 210)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Label("The connection is parsed only in memory. Its API key is stored in macOS Keychain; the pasted JSON is never saved.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Import Draft") { `import`(apply: false) }
                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
                Button("Import and Apply") { `import`(apply: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
            }
        }
        .padding(28)
        .frame(width: 680)
        .onDisappear { source = "" }
    }

    private func `import`(apply: Bool) {
        Task {
            if await viewModel.importNewAPIChannelConnection(source, apply: apply) {
                source = ""
                dismiss()
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Configuration",
                    subtitle: "Inspect the local OMP files and manage advanced model definitions safely.",
                    icon: "slider.horizontal.3",
                    status: snapshot.isWriteSupported ? "Write enabled" : "Read-only"
                )

                HStack(alignment: .top, spacing: 16) {
                    AppCard {
                        Text("OMP installation").font(.headline)
                        LabeledContent("Version", value: snapshot.installation.version)
                        LabeledContent("Write mode", value: snapshot.isWriteSupported ? "OMP 16.x adapter" : "Read-only")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    AppCard {
                        Text("Configuration files").font(.headline)
                        LabeledContent("config.yml", value: description(for: snapshot.configStatus))
                        LabeledContent("models.yml", value: description(for: snapshot.modelsStatus))
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                AppCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(AppTheme.accent).font(.title3)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Advanced models.yml editor").font(.headline)
                            Text(isModelsFileEditable ? "Secrets are redacted in the editor. Existing secret references are preserved on save." : "models.yml must be valid and OMP 16.x must be detected before editing.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("Edit models.yml…") { isPresentingModelsEditor = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isModelsFileEditable)
                    }
                }

                if !snapshot.diagnostics.isEmpty {
                    AppCard {
                        Label("Diagnostics", systemImage: "exclamationmark.circle.fill").font(.headline)
                        DiagnosticsList(messages: snapshot.diagnostics).padding(.top, 5)
                    }
                }
            }
            .padding(28)
        }
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

private enum AppTheme {
    static let accent = Color(red: 0.43, green: 0.25, blue: 0.88)
    static let surfaceBorder = Color.primary.opacity(0.09)
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    var status: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [AppTheme.accent, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title.weight(.bold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let status { StatusPill(text: status, tint: AppTheme.accent) }
        }
    }
}

private struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.surfaceBorder, lineWidth: 1)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        AppCard {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
            }
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.caption).textSelection(.enabled).lineLimit(2)
        }
    }
}

private struct UsageRow: View {
    let record: GatewayUsageRecord
    let tokens: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.errorCategory == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(record.errorCategory == nil ? .green : .orange)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.modelID ?? record.providerID).font(.subheadline.weight(.medium))
                Text("\(record.providerID) · \(record.source?.rawValue ?? "usage unavailable")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(tokens) tokens").font(.subheadline.weight(.medium)).monospacedDigit()
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.errorCategory == nil ? Color.secondary : Color.orange)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct ProviderCard: View {
    let provider: ProviderConfiguration
    @ObservedObject var gatewayViewModel: GatewayViewModel
    let delete: () -> Void
    let duplicate: () -> Void

    var body: some View {
        AppCard {
            HStack(alignment: .top) {
                Image(systemName: provider.type == .anthropicCompatible || provider.type == .customAnthropicLike ? "bubble.left.and.bubble.right.fill" : "bolt.horizontal.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName).font(.headline)
                    Text(provider.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: provider.isEnabled ? "Enabled" : "Disabled", tint: provider.isEnabled ? .green : .secondary)
            }
            Divider()
            DetailLine(label: "Endpoint", value: provider.baseURL.absoluteString)
            DetailLine(label: "Protocol", value: "\(protocolLabel(provider.type)) · \(provider.ompAPI)")
            HStack {
                if gatewayViewModel.status == nil {
                    Button("Start gateway") { Task { await gatewayViewModel.start(for: provider) } }
                        .buttonStyle(.bordered)
                } else {
                    Button("Stop gateway") { Task { await gatewayViewModel.stop() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Duplicate", action: duplicate)
                    .buttonStyle(.bordered)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete \(provider.displayName)")
            }
        }
    }

    private func protocolLabel(_ type: ProviderType) -> String {
        switch type {
        case .openAICompatible: "OpenAI compatible"
        case .anthropicCompatible: "Anthropic compatible"
        case .customOpenAILike: "Custom OpenAI-like"
        case .customAnthropicLike: "Custom Anthropic-like"
        }
    }
}
