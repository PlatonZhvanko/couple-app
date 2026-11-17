import SwiftUI

/// Главный экран раздела «Питание». Пока заглушка.
struct NutritionRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Питание",
            systemImage: "fork.knife",
            summary: "Что съели за день, калории и вода.",
            plannedItems: [
                "Дневник питания",
                "Калории и БЖУ",
                "Учёт воды",
            ]
        )
    }
}

#Preview {
    NutritionRootView()
}
