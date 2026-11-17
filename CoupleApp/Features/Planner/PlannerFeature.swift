import SwiftUI

/// Раздел «Планер».
///
/// Всё, что относится к разделу, лежит в папке `Features/Planner/`:
/// модели данных, экраны, логика. Наружу отдаётся только `feature`.
enum PlannerFeature {
    static let feature = Feature(
        id: "planner",
        title: "Планер",
        systemImage: "calendar",
        models: [
            // Сюда добавлять модели SwiftData раздела, например: PlannerEntry.self
        ]
    ) {
        PlannerRootView()
    }
}
