//
//  OnboardingView.swift
//  EasyCrypto
//
//  Minimal credential-only onboarding for first-time users.
//  Advanced settings are hidden until after initial setup.

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @State var processor: SettingsProcessor

    @State private var apiKeyInput = ""
    @State private var secretInput = ""
    @State private var isSaving = false

    private var state: SettingsState { processor.state }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)

                    VStack(spacing: 8) {
                        Text("Welcome to EasyCrypto")
                            .font(.title.bold())
                        Text("Add your Binance API credentials to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)

                    credentialSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                await processor.handle(.loadCredentials)
            }
            .onReceive(NotificationCenter.default.publisher(for: .apiKeyChanged)) { _ in
                // ContentView re-checks the keychain and transitions to main tab view
            }
        }
    }

    // MARK: - Credential Section

    private var credentialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API Credentials", systemImage: "key.fill")
                .font(.headline)

            if state.hasApiKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                    Text("Credentials saved! Loading your portfolio…")
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    SecureField("API Key", text: $apiKeyInput)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Secret Key", text: $secretInput)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        saveCredentials()
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(apiKeyInput.isEmpty || secretInput.isEmpty || isSaving)

                    // Inline API key creation guidance
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to get your API key:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("1. Open binance.com and sign in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("2. Go to API Management → Create API")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("3. Enable Spot & Margin Trading permissions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("4. Copy the API Key and Secret below")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Link("View Binance API guide →", destination: URL(string: "https://www.binance.com/en/support/faq/how-to-create-api-keys-on-binance-360002502072")!)
                            .font(.caption2)
                            .tint(Theme.accent)
                    }
                    .padding(.top, 4)

                    // Keychain security indicator
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.profit)
                        Text("Stored securely in iOS Keychain")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.loss)
                    .padding(.top, 4)
            }
        }
        .glassCard()
    }

    // MARK: - Actions

    private func saveCredentials() {
        guard !apiKeyInput.isEmpty, !secretInput.isEmpty else { return }
        isSaving = true

        Task {
            await processor.handle(.saveApiKey(apiKey: apiKeyInput, secret: secretInput))

            // The processor posts .apiKeyChanged on success.
            // ContentView listens and re-checks the keychain to transition.
            // Clear inputs only after the processor has finished.
            await MainActor.run {
                if processor.state.hasApiKey {
                    apiKeyInput = ""
                    secretInput = ""
                }
                isSaving = false
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding — no key") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = SettingsProcessor(
        keychainService: KeychainService(
            save: { _, _ in },
            load: { nil },
            delete: { }
        ),
        apiClient: .noop,
        modelContainer: container
    )
    return NavigationStack {
        OnboardingView(processor: processor)
    }
    .preferredColorScheme(.dark)
}

#Preview("Onboarding — saved") {
    let container = try! ModelContainer(
        for: Trade.self, SyncMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let processor = SettingsProcessor(
        keychainService: KeychainService(
            save: { _, _ in },
            load: { KeychainCredentials(apiKey: "key", secret: "secret") },
            delete: { }
        ),
        apiClient: .noop,
        modelContainer: container
    )
    processor.state.hasApiKey = true
    return NavigationStack {
        OnboardingView(processor: processor)
    }
    .preferredColorScheme(.dark)
}
