import SwiftUI

/// Главный экран раздела «Настроение». Пока заглушка.
struct MoodRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Настроение",
            systemImage: "face.smiling",
            summary: "Настроение каждого из нас по дням.",
            plannedItems: [
                "Отметка настроения за день",
                "Заметки к дню",
                "История и графики",
            ]
        )
    }
}

#Preview {
    MoodRootView()
}
