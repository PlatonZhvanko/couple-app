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
    @State private var catCenter = CatPeekCenter()
    @Environment(\.scenePhase) private var scenePhase
    /// Меняется при уходе в фон: весь интерфейс пересоздаётся с нуля.
    @State private var generation = UUID()
    @State private var showReload = false
    /// После закрытия сторожем зависшего приложения: короткая подсказка при следующем запуске.
    @State private var showRestartNote = false

    var body: some View {
        ZStack {
            if let me = account.me {
                RootTabView(me: me)
                    .id("\(me.rawValue)-\(generation.uuidString)") // при смене аккаунта и после фона экраны пересоздаются
            } else {
                LoginView()
            }
            if showReload {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Загрузка…").font(.headline).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            }
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        // Мироня здоровается не чаще раза в несколько часов.
                        let key = "cat.lastGreeting"
                        let now = Date.now.timeIntervalSince1970
                        if now - UserDefaults.standard.double(forKey: key) > CatSettings.greetingCooldown {
                            UserDefaults.standard.set(now, forKey: key)
                            showGreeting = true
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .catPeek(.miron, topic: .greeting, isPresented: $showGreeting)
        .overlay {
            ZStack {
                if let view = catCenter.current {
                    view.id(catCenter.token)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: catCenter.token)
            .ignoresSafeArea()
        }
        .environment(catCenter)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Watchdog.shared.setActive(false)
                // Сворачивание не трогает экран: вернувшись, человек видит то же окно, где остановился.
                // Сброс на главный экран делает только сторож при настоящем зависании (см. ниже).
            case .active:
                Watchdog.shared.setActive(true)
                if showReload {
                    Task {
                        try? await Task.sleep(for: .seconds(0.7))
                        withAnimation(.easeOut(duration: 0.3)) { showReload = false }
                    }
                }
            default:
                break
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            if showRestartNote {
                Text("Приложение зависало и перезапустилось. Данные целы.")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            // Сторож зависаний: после зависания сбрасываем интерфейс и возвращаем на главный экран.
            let defaults = UserDefaults.standard
            if defaults.double(forKey: Watchdog.killedKey) > 0 {
                defaults.removeObject(forKey: Watchdog.killedKey)
                defaults.set("planner", forKey: "root.selectedTab")
                withAnimation { showRestartNote = true }
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { showRestartNote = false }
                }
            }
            try? await Task.sleep(for: .seconds(5))
            Watchdog.shared.onRecovered = {
                UserDefaults.standard.set("planner", forKey: "root.selectedTab")
                showReload = true
                generation = UUID()
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    withAnimation(.easeOut(duration: 0.3)) { showReload = false }
                }
            }
            Watchdog.shared.setActive(true)
            Watchdog.shared.start()
        }
        .task {
            // Окно появляется не сразу, поэтому пробуем несколько раз.
            for _ in 0..<10 {
                KeyboardDismisser.shared.install()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }
}
