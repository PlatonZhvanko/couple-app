import SwiftUI

/// Раздел «Настроение».
///
/// Всё, что относится к разделу, лежит в папке `Features/Mood/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum MoodFeature {
    static let feature = Feature(
        id: "mood",
        title: "Настроение",
        systemImage: "face.smiling",
        models: [
            // Сюда добавлять модели SwiftData раздела, например: MoodEntry.self
        ]
    ) {
        MoodRootView()
    }
}
