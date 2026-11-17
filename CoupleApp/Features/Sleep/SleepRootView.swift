import SwiftUI

/// Главный экран раздела «Сон». Пока заглушка.
struct SleepRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Сон",
            systemImage: "bed.double.fill",
            summary: "Когда легли, когда встали и как спалось.",
            plannedItems: [
                "Время сна и пробуждения",
                "Качество сна",
                "Статистика за неделю",
            ]
        )
    }
}

#Preview {
    SleepRootView()
}
