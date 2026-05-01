import SwiftUI
import Translation

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var shakeCount: CGFloat = 0
    @State private var hapticEnabled: Bool = SharedSettings.shared.hapticFeedbackEnabled
    @State private var hasFullAccess: Bool = SharedSettings.shared.hasKeyboardFullAccess

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Language
                Section {
                    Label {
                        LanguagePickerView(selectedLanguage: $appState.selectedLanguage)
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Text("My Language")
                } footer: {
                    Text("This is your native language. Incoming messages in other languages will be translated to this.")
                }

                // MARK: - Instant Translation (Apple)
                if #available(iOS 18.0, *) {
                    TranslationLanguageSection()
                }

                // MARK: - AI Provider
                Section {
                    Label {
                        ProviderPickerView(selectedProvider: $appState.selectedProvider)
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundStyle(.purple)
                    }
                } header: {
                    Text("AI Provider")
                }

                // MARK: - API Key
                Section {
                    Label {
                        APIKeyInputView(apiKey: $appState.apiKey, provider: appState.selectedProvider)
                            .onChange(of: appState.apiKey) { _, _ in
                                appState.saveAPIKey()
                                appState.connectionTestResult = .idle
                            }
                    } icon: {
                        Image(systemName: "key")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("API Key")
                }

                // MARK: - Test Connection
                Section {
                    Button {
                        Task {
                            await appState.testConnection()
                            if case .failure = appState.connectionTestResult {
                                withAnimation(.default) {
                                    shakeCount += 3
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "bolt.horizontal")
                            Spacer()
                            connectionStatusView
                        }
                    }
                    .disabled(appState.apiKey.isEmpty || appState.connectionTestResult == .testing)
                }

                // MARK: - Industry Context
                Section {
                    Label {
                        Picker("Industry", selection: $appState.industryContext) {
                            ForEach(AppState.industryOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } icon: {
                        Image(systemName: "building.2")
                            .foregroundStyle(.teal)
                    }

                    if appState.industryContext == "Custom" {
                        TextField("Describe your industry...", text: $appState.customIndustry)
                            .onChange(of: appState.customIndustry) { _, _ in
                                appState.saveAPIKey()
                            }
                    }
                } header: {
                    Text("Industry Context (Optional)")
                } footer: {
                    Text("Helps the AI use relevant terminology in translations.")
                }

                // MARK: - Knowledge Base
                KnowledgeBaseView()

                // MARK: - Keyboard Feedback
                Section {
                    Toggle("Vibrate on key press", isOn: $hapticEnabled)
                        .onChange(of: hapticEnabled) { _, newValue in
                            SharedSettings.shared.hapticFeedbackEnabled = newValue
                        }

                    if hapticEnabled && !hasFullAccess {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\u{26A0}\u{FE0F} Full Access required for haptic feedback")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Go to Settings > General > Keyboard > Keyboards > UnifyKey > Allow Full Access")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Keyboard Feedback", systemImage: "hand.tap")
                }

                // MARK: - Enable Keyboard
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to enable UnifyKey keyboard:")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        enableStep(number: 1, text: "Open Settings > General > Keyboard > Keyboards")
                        enableStep(number: 2, text: "Tap \"Add New Keyboard...\"")
                        enableStep(number: 3, text: "Select \"UnifyKey\"")
                        enableStep(number: 4, text: "Tap UnifyKey and enable \"Allow Full Access\"")

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0, green: 0.478, blue: 1), Color(red: 0, green: 0.333, blue: 0.831)],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                            )
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Enable Keyboard", systemImage: "keyboard")
                }

                // MARK: - Usage & Cost
                UsageView().refreshStats()

                // MARK: - Full Access Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.green)
                            Text("Why Full Access?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        Text("Full Access is required so the keyboard can make API calls to your chosen AI provider for translation. No data is ever collected, stored on any server, or shared with anyone. All processing happens directly between your device and your AI provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("UnifyKey")
            .onAppear {
                hasFullAccess = SharedSettings.shared.hasKeyboardFullAccess
                hapticEnabled = SharedSettings.shared.hapticFeedbackEnabled
            }
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch appState.connectionTestResult {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .modifier(ShakeModifier(shakes: shakeCount))
        }
    }

    private func enableStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shake Animation Modifier

private struct ShakeModifier: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: -5 * sin(shakes * .pi * 2), y: 0)
        )
    }
}

// MARK: - Translation Language Downloads (iOS 18+)

@available(iOS 18.0, *)
struct TranslationLanguageSection: View {
    @State private var supportedLanguages: [AvailableLanguage] = []
    @State private var isLoading = true

    private let priorityLanguages = ["en", "zh", "es", "ja", "ko", "fr", "de", "ar", "pt", "ru", "it", "th", "vi", "id", "hi"]

    var body: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking available languages...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if supportedLanguages.isEmpty {
                Text("No downloadable languages found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(supportedLanguages) { lang in
                    HStack {
                        Text(lang.displayName)
                            .font(.subheadline)
                        Spacer()
                        if lang.isDownloaded {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text("Instant")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "cpu")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text("AI API")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("For free offline translation, download languages in Apple's Translate app (pre-installed on your iPhone).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Settings \u{203A} Apps \u{203A} Translate \u{203A} Downloaded Languages")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack(spacing: 6) {
                Text("Instant Translation")
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        } footer: {
            Text("Languages marked Instant are free, fast, and work offline. Others use your AI API (costs tokens).")
        }
        .task {
            await loadLanguages()
        }
    }

    private func loadLanguages() async {
        let avail = LanguageAvailability()
        var results: [AvailableLanguage] = []

        let userLang = SharedSettings.shared.selectedLanguage.rawValue
        let userLocale = Locale.Language(identifier: userLang)

        for code in priorityLanguages where code != userLang {
            let targetLocale = Locale.Language(identifier: code)
            let status = await avail.status(from: userLocale, to: targetLocale)
            let displayName = Locale.current.localizedString(forLanguageCode: code) ?? code
            let downloaded = (status == .installed)
            results.append(AvailableLanguage(
                id: "\(userLang)-\(code)",
                displayName: displayName,
                isDownloaded: downloaded
            ))
        }

        await MainActor.run {
            supportedLanguages = results
            isLoading = false
        }
    }
}

struct AvailableLanguage: Identifiable {
    let id: String
    let displayName: String
    let isDownloaded: Bool
}
