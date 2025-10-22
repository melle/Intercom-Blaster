import SwiftUI
import DingDongBlasterCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Web Server") {
                TextField("Port", text: $appState.portString)
                    .textFieldStyle(.roundedBorder)
                if let portError = appState.portError {
                    Text(portError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                statusRow
            }

            Section("Video URL Matching") {
                TextField("Regular Expression", text: $appState.regexPattern)
                    .textFieldStyle(.roundedBorder)
                if let regexError = appState.regexError {
                    Text(regexError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let lastRequest = appState.lastRequestDescription {
                Section("Last Request") {
                    Text(lastRequest)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            Section("Trigger URL") {
                Text(triggerURLText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var statusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            switch appState.serverStatus {
            case .stopped:
                Label("Stopped", systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
            case .running(let port):
                Label("Listening on \(port)", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private var triggerURLText: String {
        let port: UInt16?
        switch appState.serverStatus {
        case .running(let runningPort):
            port = runningPort
        default:
            if case .success(let parsedPort) = ServerConfigurationValidator.normalizePort(appState.portString) {
                port = parsedPort
            } else {
                port = nil
            }
        }

        if let port {
            return "http://localhost:\(port)/play"
        } else {
            return "Port not configured"
        }
    }
}
