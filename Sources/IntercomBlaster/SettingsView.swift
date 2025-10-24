import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import IntercomBlasterCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Divider()

                webServerSection

                Divider()

                videoMatchingSection

                Divider()

                playbackWindowSection

                Divider()

                defaultStreamSection

                Divider()

                triggerSection

                if let lastRequest = appState.lastRequestDescription {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Request")
                            .font(.headline)
                        Text(lastRequest)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 32)
            .padding(.horizontal, 28)
        }
        .frame(width: 600, height: 620)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            headerImage
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Intercom Blaster")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Instant video the moment someone hits the bell.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var webServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Web Server")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Port")
                        .gridColumnAlignment(.trailing)
                    TextField("Port", text: $appState.portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                if let portError = appState.portError {
                    GridRow {
                        EmptyView()
                        Text(portError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                GridRow {
                    Text("Status")
                        .gridColumnAlignment(.trailing)
                    statusView
                }
            }
        }
    }

    private var videoMatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video URL Matching")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Regular Expression", text: $appState.regexPattern)
                    .textFieldStyle(.roundedBorder)

                if let regexError = appState.regexError {
                    Text(regexError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Text("Only URLs matching this expression will trigger playback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var playbackWindowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Window")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Width")
                        .gridColumnAlignment(.trailing)
                    TextField("Width", text: $appState.windowWidthString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Height")
                        .gridColumnAlignment(.trailing)
                    TextField("Height", text: $appState.windowHeightString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            if let error = appState.windowSizeError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text("Values are in points; defaults to 720×720.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultStreamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Stream")
                .font(.headline)

            TextField("rtsp://camera.local/live", text: $appState.defaultStreamString)
                .textFieldStyle(.roundedBorder)

            if let error = appState.defaultStreamError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text("Used when GET /defaultStream is requested.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Trigger URL")
                .font(.headline)

            Text(triggerURLText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            if let curlCommand {
                Text("Sample curl command to start playback of a custom URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GroupBox {
                    Text(curlCommand)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusView: some View {
        HStack(spacing: 6) {
            switch appState.serverStatus {
            case .stopped:
                Label("Stopped", systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
            case .running(let port):
                Label("Listening on port \(port)", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private var resolvedPort: UInt16? {
        switch appState.serverStatus {
        case .running(let runningPort):
            return runningPort
        default:
            if case .success(let parsedPort) = ServerConfigurationValidator.normalizePort(appState.portString) {
                return parsedPort
            }
            return nil
        }
    }

    private var triggerURLText: String {
        guard let port = resolvedPort else {
            return "Port not configured"
        }
        let host = appState.hostAddress
        return "http://\(host):\(port)/play"
    }

    private var curlCommand: String? {
        guard let port = resolvedPort else { return nil }
        let host = appState.hostAddress
        return """
        curl -X POST http://\(host):\(port)/play \\
             -H "Content-Type: text/plain" \\
             -d "rtsp://username:password@camera.local/live/ch00_0"
        """
    }

    private var headerImage: some View {
        Group {
#if canImport(AppKit)
            if let url = Bundle.module.url(forResource: "intercom-256", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                placeholderImage
            }
#else
            placeholderImage
#endif
        }
        .frame(width: 108, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private var placeholderImage: some View {
        Image(systemName: "video.badge.waveform")
            .resizable()
            .scaledToFit()
            .padding(20)
            .foregroundStyle(.secondary)
    }
}
