import SwiftUI
import SwiftData

/// Точка входа приложения.
@main
struct CoupleApp: App {
    private let environment: AppEnvironment
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .dark

    init() {
        environment = AppEnvironment.live()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.account)
                .environment(environment.sync)
                .tint(.appAccent)
                .preferredColorScheme(theme.colorScheme)
        }
        .modelContainer(environment.modelContainer)
    }
}

/// Показывает заставку при запуске, затем экран входа или вкладки.
struct RootView: View {
    @Environment(AccountStore.self) private var account
    @State private var showSplash = true
    @State private var showGreeting = false

    var body: some View {
        ZStack {
            if let me = account.me {
                RootTabView(me: me)
                    .id(me) // при смене аккаунта экраны пересоздаются
            } else {
                LoginView()
            }
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        showGreeting = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .catPeek(.miron, topic: .greeting, isPresented: $showGreeting)
    }
}
