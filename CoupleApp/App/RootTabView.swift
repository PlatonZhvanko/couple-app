import SwiftUI

/// Нижняя панель вкладок. Вкладки берутся из `FeatureRegistry`.
/// На iPhone видно 4 вкладки, остальные автоматически попадают в «Ещё».
struct RootTabView: View {
    /// Кто вошёл. Набор вкладок может зависеть от аккаунта.
    let me: CoupleMember

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("root.selectedTab") private var selection: String = FeatureRegistry.all.first?.id ?? SettingsFeature.feature.id

    private var features: [Feature] {
        FeatureRegistry.all.filter { $0.isAvailable(for: me) }
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(features) { feature in
                Tab(feature.title, systemImage: feature.systemImage, value: feature.id) {
                    feature.makeRootView()
                }
            }
            Tab(SettingsFeature.feature.title, systemImage: SettingsFeature.feature.systemImage, value: SettingsFeature.feature.id) {
                SettingsFeature.feature.makeRootView()
            }
        }
        .moodSupportPopup()
        .onAppear {
            // Напоминания обновляются при каждом открытии приложения.
            MoodReminder.refreshIfEnabled()
            MoodSleepReminder.refreshIfEnabled()
            ReminderScheduler.refresh()
            if !features.contains(where: { $0.id == selection }) && selection != SettingsFeature.feature.id {
                selection = features.first?.id ?? SettingsFeature.feature.id
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.requestSync()
                Task { await account.refreshFromServer() }
            }
        }
        .task {
            // Сразу после входа и дальше каждые 4 секунды, пока приложение открыто:
            // изменения партнёра появляются сами (запрос лёгкий, берутся только новые записи).
            sync.requestSync()
            await account.refreshFromServer()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                sync.requestSync()
            }
        }
    }
}
