import SwiftUI
import SwiftData
import UIKit

/// Точка входа версии для Mac (Mac Catalyst). Данные, вход и синхронизация те же, что на iPhone;
/// отличаются только окно, боковая панель и горячие клавиши.
@main
struct CoupleAppMacApp: App {
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
                .onAppear { MacWindowSetup.apply() }
        }
        .modelContainer(environment.modelContainer)
        .commands { MacCommands(sync: environment.sync, account: environment.account) }
    }
}

/// Размер окна: не меньше удобного для компьютера, при первом запуске крупное.
@MainActor
enum MacWindowSetup {
    static func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1000, height: 680)
            windowScene.title = "Вдвоём"
        }
    }
}

/// Меню и горячие клавиши.
struct MacCommands: Commands {
    let sync: SyncCoordinator
    let account: AccountStore

    private var features: [Feature] {
        guard let me = account.me else { return [] }
        return FeatureRegistry.all.filter { $0.isAvailable(for: me) }
    }

    var body: some Commands {
        CommandMenu("Разделы") {
            ForEach(Array(features.prefix(9).enumerated()), id: \.element.id) { index, feature in
                Button(feature.title) {
                    UserDefaults.standard.set(feature.id, forKey: "root.selectedTab")
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button(SettingsFeature.feature.title) {
                UserDefaults.standard.set(SettingsFeature.feature.id, forKey: "root.selectedTab")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button("Синхронизировать сейчас") { sync.requestSync() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
