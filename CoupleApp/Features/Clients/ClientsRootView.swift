import SwiftUI

/// Главный экран раздела «Клиенты». Пока заглушка.
struct ClientsRootView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Клиенты",
            systemImage: "person.2.fill",
            summary: "Кто и когда записан, услуги и оплата.",
            plannedItems: [
                "Записи клиентов",
                "Карточки клиентов",
                "Оплаты и история",
            ]
        )
    }
}

#Preview {
    ClientsRootView()
}
