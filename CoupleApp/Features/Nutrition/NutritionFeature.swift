import SwiftUI

/// Раздел «Питание».
///
/// Всё, что относится к разделу, лежит в папке `Features/Nutrition/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
/// Что умеет раздел: docs/nutrition.md в репозитории.
enum NutritionFeature {
    static let feature = Feature(
        id: "nutrition",
        title: "Питание",
        systemImage: "fork.knife",
        models: [
            NutritionEntry.self,
            NutritionWater.self,
            NutritionFavorite.self,
            NutritionGoal.self,
            NutritionFood.self,
            NutritionDish.self,
        ]
    ) {
        NutritionRootView()
    }
}
