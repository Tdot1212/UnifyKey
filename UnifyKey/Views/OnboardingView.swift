import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    private let cards: [(title: String, subtitle: String, symbol: String)] = [
        (
            "Translate in any app",
            "Copy a message in any app — the keyboard instantly translates it for you.",
            "globe"
        ),
        (
            "AI writes your replies",
            "Get smart, contextual reply suggestions in the sender's language.",
            "bubble.left.and.bubble.right"
        ),
        (
            "Your AI, your key, your privacy",
            "Use your own API key. No subscriptions, no data collection.",
            "key"
        )
    ]

    private static let blueGradient = LinearGradient(
        colors: [Color(red: 0, green: 0.478, blue: 1), Color(red: 0, green: 0.333, blue: 0.831)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(0..<cards.count, id: \.self) { index in
                    VStack(spacing: 28) {
                        Spacer()

                        Image(systemName: cards[index].symbol)
                            .font(.system(size: 80, weight: .light))
                            .foregroundStyle(.blue)
                            .frame(height: 100)

                        Text(cards[index].title)
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Text(cards[index].subtitle)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 40)

                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                appState.hasCompletedOnboarding = true
            } label: {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Self.blueGradient)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}
