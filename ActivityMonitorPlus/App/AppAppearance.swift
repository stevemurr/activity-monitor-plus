import AppKit
import SwiftUI

/// User's appearance preference. `.system` follows the OS light/dark setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "follow the system", which is SwiftUI's default behavior.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ActivityMonitorSettingsView: View {
    let mcpController: ActivityMonitorMCPController?
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue })
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearancePicker")
                Text("“System” follows your macOS Appearance setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local MCP") {
                Toggle(
                    "Allow approved local apps to read system activity",
                    isOn: Binding(
                        get: { mcpController?.isEnabled ?? false },
                        set: { mcpController?.setEnabled($0) }
                    )
                )
                .disabled(mcpController == nil)
                .accessibilityIdentifier("local-mcp-enabled")

                LabeledContent(
                    "Status",
                    value: mcpController?.status.label ?? "Unavailable"
                )
                .accessibilityIdentifier("local-mcp-status")

                Text("Discovery is not trust. Every consumer must be approved with a matching verification code. Access stays on this Mac and is read-only, but approved apps can see process names, network endpoints, and disk-capacity metadata.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("local-mcp-trust-copy")
            }

            Section("Authorized Local Apps") {
                if let grants = mcpController?.grants, !grants.isEmpty {
                    ForEach(grants) { grant in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(grant.consumerName)
                                        .fontWeight(.medium)
                                    Text(grant.consumerStableID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("Installation …\(grant.installationSuffix) · approved \(grant.issuedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if grant.revokedAt != nil {
                                    Text("Revoked")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Revoke") {
                                        mcpController?.revoke(grantID: grant.id)
                                    }
                                    .disabled(
                                        mcpController?.revokingGrantIDs.contains(grant.id) == true
                                    )
                                }
                            }
                            if grant.revokedAt != nil {
                                Text("The consumer must pair again before it can query activity.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } else {
                    Text("No apps have been approved. Pairing always requires an explicit Allow decision in Activity Monitor Plus.")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Access List") {
                    mcpController?.refreshGrants()
                }
                .disabled(mcpController == nil)
            }

            Section("Redacted Diagnostics") {
                Text(mcpController?.diagnostics ?? "Local MCP could not initialize.")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)

                Button("Copy Redacted Diagnostics") {
                    copyDiagnostics()
                }
                .disabled(mcpController == nil)
                .accessibilityIdentifier("local-mcp-copy-diagnostics")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 650)
    }

    private func copyDiagnostics() {
        guard let diagnostics = mcpController?.diagnostics else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics, forType: .string)
    }
}
