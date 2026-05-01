import SwiftUI

struct ProviderPickerView: View {
    @Binding var selectedProvider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AIProvider.allCases) { provider in
                Button {
                    selectedProvider = provider
                } label: {
                    HStack {
                        Image(systemName: selectedProvider == provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedProvider == provider ? .blue : .secondary)

                        Text(provider.displayName)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
