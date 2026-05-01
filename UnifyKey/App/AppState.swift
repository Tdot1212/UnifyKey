import SwiftUI

final class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool {
        didSet { SharedSettings.shared.hasCompletedOnboarding = hasCompletedOnboarding }
    }
    @Published var selectedLanguage: SupportedLanguage {
        didSet { SharedSettings.shared.selectedLanguage = selectedLanguage }
    }
    @Published var selectedProvider: AIProvider {
        didSet { SharedSettings.shared.selectedProvider = selectedProvider }
    }
    @Published var industryContext: String {
        didSet { SharedSettings.shared.industryContext = industryContext }
    }
    @Published var apiKey: String
    @Published var customIndustry: String

    @Published var connectionTestResult: ConnectionTestState = .idle

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    static let industryOptions = [
        "General",
        "Jewelry & Fashion",
        "Manufacturing & Trade",
        "Technology",
        "Real Estate",
        "Medical",
        "Legal",
        "Custom"
    ]

    init() {
        let settings = SharedSettings.shared
        self.hasCompletedOnboarding = settings.hasCompletedOnboarding
        self.selectedLanguage = settings.selectedLanguage
        self.selectedProvider = settings.selectedProvider
        self.industryContext = settings.industryContext
        self.apiKey = KeychainHelper.shared.loadAPIKey() ?? ""
        self.customIndustry = ""

        // If the industry context is not one of the predefined options, it's custom
        if !Self.industryOptions.dropLast().contains(settings.industryContext) && settings.industryContext != "General" {
            self.customIndustry = settings.industryContext
            self.industryContext = "Custom"
        }
    }

    var effectiveIndustryContext: String {
        if industryContext == "Custom" {
            return customIndustry.isEmpty ? "General" : customIndustry
        }
        return industryContext
    }

    func saveAPIKey() {
        if apiKey.isEmpty {
            KeychainHelper.shared.deleteAPIKey()
        } else {
            _ = KeychainHelper.shared.saveAPIKey(apiKey)
        }
        // If custom industry, save the custom text
        if industryContext == "Custom" && !customIndustry.isEmpty {
            SharedSettings.shared.industryContext = customIndustry
        }
    }

    func testConnection() async {
        guard !apiKey.isEmpty else {
            await MainActor.run {
                connectionTestResult = .failure("Please enter an API key first")
            }
            return
        }

        await MainActor.run {
            connectionTestResult = .testing
        }

        let service = AIServiceFactory.createService(provider: selectedProvider, apiKey: apiKey)

        do {
            let success = try await service.testConnection()
            await MainActor.run {
                connectionTestResult = success ? .success : .failure("Connection failed")
            }
        } catch {
            await MainActor.run {
                connectionTestResult = .failure(error.localizedDescription)
            }
        }
    }
}
