import SwiftUI

/// Раздел «Настройки»: профиль, синхронизация, служебные экраны.
/// Всегда последняя вкладка, поэтому не входит в `FeatureRegistry.all`.
enum SettingsFeature {
    static let feature = Feature(
        id: "settings",
        title: "Настройки",
        systemImage: "gearshape"
    ) {
        SettingsView()
    }
}
