import SwiftUI

/// Быстрый выбор эмодзи: тапнул на эмодзи, он сразу выбран. Ниже можно вписать свой.
/// Повторный тап по выбранному снимает выбор (остаётся значок по умолчанию).
struct PlannerEmojiStrip: View {
    @Binding var selection: String
    @State private var custom = ""

    private static let quick: [String] = [
        "💼", "📌", "🛒", "🧹", "🍳", "🏠", "🚗", "🛠",
        "📞", "💻", "📅", "🧾", "🎓", "🏃", "🧘", "💇",
        "💅", "🎁", "🏥", "✈️", "🐱", "🌿", "❤️", "⭐️",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Self.quick, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == emoji ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selection = selection == emoji ? "" : emoji }
                }
            }
            TextField("Свой эмодзи (по желанию)", text: $custom)
                .font(.footnote)
                .onChange(of: custom) { _, value in
                    // Берём последний введённый символ-эмодзи целиком.
                    if let last = value.trimmingCharacters(in: .whitespaces).last {
                        selection = String(last)
                    }
                }
        }
    }
}
