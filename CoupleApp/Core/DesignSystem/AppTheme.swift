import SwiftUI

/// Тема оформления: тёмная по умолчанию, можно переключить в настройках.
enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Тёмная"
        case .light: "Светлая"
        case .system: "Как в iPhone"
        }
    }

    /// `nil` — следовать настройке iPhone.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    /// Ключ в `@AppStorage`.
    static let storageKey = "app.theme"
}

extension Color {
    /// Главный цвет приложения: яркий сиренево-синий для кнопок и выделений.
    static let appAccent = Color(red: 0.51, green: 0.43, blue: 1.0)
}
