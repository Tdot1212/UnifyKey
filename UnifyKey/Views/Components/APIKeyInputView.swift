import SwiftUI

struct APIKeyInputView: View {
    @Binding var apiKey: String
    let provider: AIProvider
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isRevealed {
                    TextField("Paste your API key", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("Paste your API key", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }

            if let url = URL(string: provider.apiKeyURL) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("How to get an API key")
                    }
                    .font(.caption)
                }
            }
        }
    }
}
