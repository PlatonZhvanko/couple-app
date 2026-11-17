import SwiftUI

/// Главный экран раздела «Авто». Пока заглушка.
struct CarRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Авто",
            systemImage: "car.fill",
            summary: "Обслуживание, расходы и документы на машину.",
            plannedItems: [
                "Заправки и расходы",
                "ТО и ремонт",
                "Страховка и документы",
            ]
        )
    }
}

#Preview {
    CarRootView()
}
