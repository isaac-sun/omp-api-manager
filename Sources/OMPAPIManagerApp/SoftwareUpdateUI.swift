import AppKit
import SwiftUI
import OMPAPIManagerCore

enum AppVersion {
    static var current: String {
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           SoftwareVersion(bundleVersion) != nil {
            return bundleVersion
        }
        if let resourceURL = Bundle.module.url(forResource: "AppVersion", withExtension: "txt"),
           let resourceVersion = try? String(contentsOf: resourceURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           SoftwareVersion(resourceVersion) != nil {
            return resourceVersion
        }
        return "0.0.0-dev"
    }
}

@MainActor
final class SoftwareUpdateViewModel: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate(SoftwareUpdateCheck)
        case updateAvailable(SoftwareUpdateCheck)
        case newerThanLatest(SoftwareUpdateCheck)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String
    private let checker: any SoftwareUpdateChecking
    private let minimumCheckInterval: TimeInterval
    private var lastRequestAt: Date?

    init(
        checker: any SoftwareUpdateChecking = GitHubSoftwareUpdateService(),
        currentVersion: String = AppVersion.current,
        minimumCheckInterval: TimeInterval = 60
    ) {
        self.checker = checker
        self.currentVersion = currentVersion
        self.minimumCheckInterval = minimumCheckInterval
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var currentVersionDisplay: String {
        SoftwareVersion(currentVersion)?.description ?? currentVersion
    }

    func checkForUpdates(presentResult: Bool = false) async {
        guard !isChecking else { return }
        let now = Date()
        if let lastRequestAt, now.timeIntervalSince(lastRequestAt) < minimumCheckInterval {
            if presentResult { presentCurrentResult() }
            return
        }

        lastRequestAt = now
        state = .checking
        do {
            let check = try await checker.check(currentVersion: currentVersion)
            if check.isUpdateAvailable {
                state = .updateAvailable(check)
            } else if check.currentVersion > check.latestRelease.version {
                state = .newerThanLatest(check)
            } else {
                state = .upToDate(check)
            }
            lastCheckedAt = Date()
        } catch is CancellationError {
            state = .idle
            return
        } catch {
            state = .failed(error.localizedDescription)
            lastCheckedAt = Date()
        }

        if presentResult { presentCurrentResult() }
    }

    func openOfficialReleasePage() {
        guard let check = completedCheck else { return }
        NSWorkspace.shared.open(check.latestRelease.officialReleaseURL)
    }

    private var completedCheck: SoftwareUpdateCheck? {
        switch state {
        case .upToDate(let check), .updateAvailable(let check), .newerThanLatest(let check): check
        case .idle, .checking, .failed: nil
        }
    }

    private func presentCurrentResult() {
        let alert = NSAlert()
        switch state {
        case .idle:
            return
        case .checking:
            alert.messageText = "Checking for Updates"
            alert.informativeText = "OMP API Manager is still contacting GitHub."
            alert.addButton(withTitle: "OK")
        case .upToDate(let check):
            alert.messageText = "OMP API Manager Is Up to Date"
            alert.informativeText = "Version \(check.currentVersion) is the latest published version."
            alert.addButton(withTitle: "OK")
        case .newerThanLatest(let check):
            alert.messageText = "Development Version"
            alert.informativeText = "This build is version \(check.currentVersion), newer than the latest published version \(check.latestRelease.version)."
            alert.addButton(withTitle: "OK")
        case .updateAvailable(let check):
            alert.messageText = "Update Available"
            alert.informativeText = "OMP API Manager \(check.latestRelease.version) is available. You have \(check.currentVersion). Updates are downloaded manually from the official GitHub Release page."
            alert.addButton(withTitle: "Open Official Release Page")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { openOfficialReleasePage() }
            return
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "Unable to Check for Updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
        }
        alert.runModal()
    }
}

struct SoftwareUpdateSettingsView: View {
    @ObservedObject var viewModel: SoftwareUpdateViewModel

    var body: some View {
        Form {
            Section("Software Update") {
                LabeledContent("Current version", value: viewModel.currentVersionDisplay)
                latestVersionRow
                if let lastCheckedAt = viewModel.lastCheckedAt {
                    LabeledContent("Last checked", value: lastCheckedAt.formatted(date: .abbreviated, time: .shortened))
                }

                HStack {
                    Button("Check for Updates…") {
                        Task { await viewModel.checkForUpdates() }
                    }
                    .disabled(viewModel.isChecking)

                    if viewModel.isChecking { ProgressView().controlSize(.small) }
                    Spacer()
                    if case .updateAvailable = viewModel.state {
                        Button("Open Official Release Page") { viewModel.openOfficialReleasePage() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Privacy and installation") {
                Text("Checks happen only when you request them. The app sends its version in a standard HTTPS request to GitHub; it does not send OMP configuration, providers, API keys, usage, or a device identifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("This version does not install updates automatically. Downloads open on the official GitHub Release page because current builds are ad-hoc signed and not notarized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560, height: 330)
    }

    @ViewBuilder
    private var latestVersionRow: some View {
        switch viewModel.state {
        case .idle:
            LabeledContent("Latest release", value: "Not checked")
        case .checking:
            LabeledContent("Latest release", value: "Checking…")
        case .upToDate(let check):
            LabeledContent("Latest release", value: "\(check.latestRelease.version) · Up to date")
        case .newerThanLatest(let check):
            LabeledContent("Latest release", value: "\(check.latestRelease.version) · Development build")
        case .updateAvailable(let check):
            LabeledContent("Latest release", value: "\(check.latestRelease.version) · Available")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Latest release").font(.caption).foregroundStyle(.secondary)
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}
