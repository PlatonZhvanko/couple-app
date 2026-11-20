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
    /// Главный цвет приложения: нежный кофейно-розовый для кнопок и выделений.
    static let appAccent = Color(red: 0.93, green: 0.58, blue: 0.64)
    /// Кофейные и бежевые оттенки для карточек и деталей.
    static let appCocoa = Color(red: 0.36, green: 0.24, blue: 0.22)
    static let appCoffee = Color(red: 0.62, green: 0.45, blue: 0.38)
    static let appBeige = Color(red: 0.96, green: 0.9, blue: 0.82)
    static let appBlush = Color(red: 0.98, green: 0.84, blue: 0.82)
}
