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

/// Показывает экран входа, пока никто не вошёл, и вкладки после входа.
struct RootView: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        if let me = account.me {
            RootTabView(me: me)
                .id(me) // при смене аккаунта экраны пересоздаются
        } else {
            LoginView()
        }
    }
}
