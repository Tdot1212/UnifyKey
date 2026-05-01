import SwiftUI

struct LanguagePickerView: View {
    @Binding var selectedLanguage: SupportedLanguage

    var body: some View {
        Picker("My Language", selection: $selectedLanguage) {
            ForEach(SupportedLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
    }
}
