import SwiftUI

/// Нижняя панель вкладок. Вкладки берутся из `FeatureRegistry`.
/// На iPhone видно 4 вкладки, остальные автоматически попадают в «Ещё».
struct RootTabView: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("root.selectedTab") private var selection: String = FeatureRegistry.all.first?.id ?? SettingsFeature.feature.id

    var body: some View {
        TabView(selection: $selection) {
            ForEach(FeatureRegistry.all) { feature in
                Tab(feature.title, systemImage: feature.systemImage, value: feature.id) {
                    feature.makeRootView()
                }
            }
            Tab(SettingsFeature.feature.title, systemImage: SettingsFeature.feature.systemImage, value: SettingsFeature.feature.id) {
                SettingsFeature.feature.makeRootView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.requestSync() }
        }
        .task {
            // Пока приложение открыто, синхронизируемся раз в минуту.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                sync.requestSync()
            }
        }
    }
}
