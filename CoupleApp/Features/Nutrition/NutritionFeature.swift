import SwiftUI

/// Раздел «Питание».
///
/// Всё, что относится к разделу, лежит в папке `Features/Nutrition/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum NutritionFeature {
    static let feature = Feature(
        id: "nutrition",
        title: "Питание",
        systemImage: "fork.knife",
        models: [
            // Сюда добавлять модели SwiftData раздела, например: NutritionEntry.self
        ]
    ) {
        NutritionRootView()
    }
}
