import SwiftUI

/// Раздел «Сон».
///
/// Всё, что относится к разделу, лежит в папке `Features/Sleep/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum SleepFeature {
    static let feature = Feature(
        id: "sleep",
        title: "Сон",
        systemImage: "bed.double.fill",
        models: [
            // Сюда добавлять модели SwiftData раздела, например: SleepEntry.self
        ]
    ) {
        SleepRootView()
    }
}
