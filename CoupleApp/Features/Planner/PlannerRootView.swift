import SwiftUI

/// Главный экран раздела «Планер». Пока заглушка.
struct PlannerRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Планер",
            systemImage: "calendar",
            summary: "Общий календарь, дела и планы на двоих.",
            plannedItems: [
                "Общий календарь",
                "Задачи и списки дел",
                "Напоминания",
            ]
        )
    }
}

#Preview {
    PlannerRootView()
}
