import SwiftUI

@main
struct UnifyKeyApp: App {
    @StateObject private var appState = AppState()

    init() {
        Self.migrateKeychainAccessibilityIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            if appState.hasCompletedOnboarding {
                SetupView()
                    .environmentObject(appState)
            } else {
                OnboardingView()
                    .environmentObject(appState)
            }
        }
    }

    /// One-time migration: re-save the stored API key so it picks up the tighter
    /// kSecAttrAccessibleWhenUnlockedThisDeviceOnly class. Old keychain items keep
    /// their original accessibility class until re-written; this forces the upgrade
    /// for the secret that matters (the BYOK API key).
    private static func migrateKeychainAccessibilityIfNeeded() {
        let settings = SharedSettings.shared
        guard !settings.keychainAccessibilityMigrationV1 else { return }

        if let existingKey = KeychainHelper.shared.loadAPIKey(), !existingKey.isEmpty {
            _ = KeychainHelper.shared.deleteAPIKey()
            _ = KeychainHelper.shared.saveAPIKey(existingKey)
        }

        settings.keychainAccessibilityMigrationV1 = true
    }
}
