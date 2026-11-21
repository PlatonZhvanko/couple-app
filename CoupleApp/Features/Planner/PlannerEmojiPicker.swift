import SwiftUI

/// Выбор эмодзи тапом: вкладки по темам и сетка. Можно ещё вписать свой.
struct PlannerEmojiPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    private struct Group: Identifiable {
        let id: String
        let icon: String
        let items: [String]
    }

    private static let groups: [Group] = [
        Group(id: "Работа", icon: "💼", items: "💼 📁 📌 📎 📝 📅 🗓 ⏰ 📞 💻 🖥 📊 📈 📉 🧾 ✉️ 📦 🛒 🧹 🧺 🛠 🔧 🔨 🧰 🗂 📚 🎓 ✏️ 🖊 🔑 🏢 🏦".split(separator: " ").map(String.init)),
        Group(id: "Деньги", icon: "💰", items: "💰 💵 💶 💳 🪙 🧮 🏧 💸 🤑 📈 📉 🎁 🛍 🏷 🧾 🏦".split(separator: " ").map(String.init)),
        Group(id: "Дом", icon: "🏠", items: "🏠 🛋 🛏 🚿 🛁 🧼 🧽 🪣 🧴 🍳 🔌 💡 🪴 🌿 🧸 🪟 🚪 📺 🧯 🗑 🧻 🪑 🧊 ♻️".split(separator: " ").map(String.init)),
        Group(id: "Еда", icon: "🍽", items: "🍽 🍕 🍔 🍟 🌮 🍣 🍜 🍝 🥗 🥪 🍞 🥐 🧁 🍰 🍪 🍫 ☕️ 🍵 🥤 🍷 🍺 🍎 🍌 🥑 🥩 🥚 🧀 🍓".split(separator: " ").map(String.init)),
        Group(id: "Спорт", icon: "🏃", items: "🏃 🚴 🏊 🧘 🏋️ 🤸 ⚽️ 🏀 🎾 🏐 🏓 🥊 ⛸ 🎿 🏂 🚶 💪 🥇 🏆 🎯 🧗 🤾 🛹 🎳".split(separator: " ").map(String.init)),
        Group(id: "Люди", icon: "🙂", items: "🙂 😊 😍 🥰 😎 🤗 😴 🤒 😢 😡 🤔 👶 👧 👦 👩 👨 👨‍👩‍👧 👫 💑 💞 ❤️ 💋 🤝 🙏 👏 👍".split(separator: " ").map(String.init)),
        Group(id: "Авто", icon: "🚗", items: "🚗 🚙 🚕 🏎 🛞 ⛽️ 🔋 🅿️ 🚦 🛣 🧰 🪫 🚘 🚌 🚆 ✈️ 🚲 🛵 🗺 🧭".split(separator: " ").map(String.init)),
        Group(id: "Природа", icon: "🌳", items: "🌳 🌸 🌻 🌷 🌹 🍀 🌲 🌴 🏖 🏔 ☀️ 🌙 ⭐️ ❄️ 🌈 🔥 🐱 🐶 🐟 🐦 🐾 🦋 🌍 ⛺️".split(separator: " ").map(String.init)),
        Group(id: "Разное", icon: "✨", items: "✨ 🎉 🎂 🎈 🎶 🎬 🎮 📷 🎨 🧩 ✈️ 🧳 🏥 💊 💉 🩺 🦷 💇 💅 🧖 📖 🔔 ⭐️ 🚀".split(separator: " ").map(String.init)),
    ]

    @State private var groupID = "Работа"
    @State private var custom = ""

    private var items: [String] { Self.groups.first { $0.id == groupID }?.items ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.groups) { group in
                            Button { groupID = group.id } label: {
                                VStack(spacing: 2) {
                                    Text(group.icon).font(.title2)
                                    Text(group.id).font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(groupID == group.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(items, id: \.self) { emoji in
                            Button {
                                selection = emoji
                                dismiss()
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(selection == emoji ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                HStack {
                    TextField("Свой эмодзи с клавиатуры", text: $custom)
                    Button("Выбрать") {
                        let clean = custom.trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty { selection = String(clean.prefix(2)); dismiss() }
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Эмодзи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сбросить") { selection = ""; dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
