import SwiftUI

/// Заставка при каждом запуске приложения.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.99, green: 0.9, blue: 0.86), Color(red: 0.93, green: 0.74, blue: 0.7)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                AppLogoView(size: 260)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                Text("Вдвоём")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.36, green: 0.24, blue: 0.22))
                    .opacity(appeared ? 1 : 0)
                Text("уютно, как дома, с котами")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color(red: 0.5, green: 0.36, blue: 0.33))
                    .opacity(appeared ? 1 : 0)
            }
        }
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appeared = true }
            try? await Task.sleep(for: .seconds(1.9))
            onFinish()
        }
    }
}
