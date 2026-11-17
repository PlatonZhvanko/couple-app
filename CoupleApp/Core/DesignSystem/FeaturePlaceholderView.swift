import SwiftUI

/// Временный экран-заглушка для раздела, который ещё в разработке.
struct FeaturePlaceholderView: View {
    let title: String
    let systemImage: String
    let summary: String
    let plannedItems: [String]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                Section("Скоро здесь") {
                    ForEach(plannedItems, id: \.self) { item in
                        Label(item, systemImage: "circle.dashed")
                    }
                }
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    FeaturePlaceholderView(
        title: "Раздел",
        systemImage: "sparkles",
        summary: "Этот раздел в разработке.",
        plannedItems: ["Первая функция", "Вторая функция"]
    )
}
