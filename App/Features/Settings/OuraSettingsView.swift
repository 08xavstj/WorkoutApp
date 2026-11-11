import SwiftUI
import UIKit
import AuthenticationServices
import AppCore

/// Settings › Data sources › Oura Ring: the direct link to an Oura account
/// (`OuraLink`) and which device's sleep comes first (`SleepSourceSetting`).
struct OuraSettingsView: View {
    @State private var link = OuraLink.shared
    @AppStorage(SleepSourceSetting.key) private var sleepSource: SleepSourcePreference = .standard
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var redirectURI = ""
    @State private var editingApp = false
    @State private var signingIn = false

    var body: some View {
        Form {
            statusSection
            if link.status == .needsSetup || editingApp {
                developerAppSection
            }
            sleepSection
        }
        .navigationTitle("Oura Ring")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clientID = link.clientID
            redirectURI = link.redirectURI
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            LabeledContent("Status", value: statusText)
            if let syncedAt = link.syncedAt, link.status == .connected {
                LabeledContent("Last sync", value: syncedAt.formatted(.relative(presentation: .named)))
            }
            if let error = link.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
            switch link.status {
            case .connected:
                Button(link.isSyncing ? "Syncing…" : "Sync now") {
                    Task { await link.sync(force: true) }
                }
                .disabled(link.isSyncing)
                Button("Disconnect", role: .destructive) { link.disconnect() }
            case .disconnected:
                Button(signingIn ? "Opening Oura…" : "Connect to Oura") { connect() }
                    .disabled(signingIn)
                Button("Change developer app details") { editingApp = true }
            case .needsSetup:
                EmptyView()
            }
        } footer: {
            Text("Tensile downloads your Oura sleep, sleep score, readiness, overnight HRV and temperature change for the last 90 days, then keeps the last week up to date. It's kept on this iPhone; nothing is sent to Oura except the sign-in. Oura needs an active membership to share data with other apps.")
        }
    }

    private var statusText: String {
        switch link.status {
        case .connected: "Connected"
        case .disconnected: "Not connected"
        case .needsSetup: "Set up below"
        }
    }

    // MARK: Developer app

    private var developerAppSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                step(1, "On a computer, sign in at developer.ouraring.com and create an application (it's free).")
                step(2, "Set its redirect URI to the address below.")
                step(3, "Copy its Client ID and Client Secret here, tap Save, then Connect.")
            }
            .padding(.vertical, 4)
            if let portal = URL(string: "https://developer.ouraring.com") {
                Link("Open Oura's developer site", destination: portal)
            }
            LabeledContent("Redirect URI") {
                Text(redirectURI.isEmpty ? Oura.defaultRedirectURI : redirectURI)
                    .textSelection(.enabled)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Copy redirect URI") {
                UIPasteboard.general.string = redirectURI.isEmpty ? Oura.defaultRedirectURI : redirectURI
            }
            TextField("Client ID", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(link.hasCredentials ? "Client Secret (saved)" : "Client Secret", text: $clientSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                link.saveCredentials(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI)
                clientSecret = ""
                editingApp = false
            }
            .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || (!link.hasCredentials && clientSecret.isEmpty))
        } header: {
            Text("Your Oura developer app")
        } footer: {
            Text("Oura only lets apps read your data through a developer app you create. The Client ID and Secret are kept in this iPhone's Keychain.")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sleep

    private var sleepSection: some View {
        Section {
            Picker("Sleep from", selection: $sleepSource) {
                ForEach(SleepSourcePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("Sleep")
        } footer: {
            // Robbins et al., Sensors 2024 (see `SleepSourcePreference`).
            Text("\(sleepSource.detail) One device's whole night is used, so the stages come from one tracker. In a lab study the ring staged sleep a little more consistently than Apple Watch, though both got total sleep about right. With the ring first, its overnight HRV is used for recovery on the nights it has.")
        }
    }

    // MARK: Sign-in

    private func connect() {
        guard let url = link.authorizationURL() else { return }
        signingIn = true
        Task {
            defer { signingIn = false }
            do {
                let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: Oura.callbackScheme)
                await link.finishSignIn(callbackURL: callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Closed the sign-in page: nothing to report.
            } catch {
                link.signInFailed(error)
            }
        }
    }
}
