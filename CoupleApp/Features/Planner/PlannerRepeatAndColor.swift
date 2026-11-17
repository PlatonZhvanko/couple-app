import SwiftUI
import UIKit

// MARK: - Цвет в виде текста

extension Color {
    /// Цвет из строки `#RRGGBB`.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// Строки выбора цвета: по умолчанию цвет вида, но можно поставить свой.
struct PlannerColorField: View {
    let title: String
    @Binding var hex: String
    let defaultColor: Color

    var body: some View {
        Toggle("🎨 \(title)", isOn: Binding(
            get: { !hex.isEmpty },
            set: { hex = $0 ? defaultColor.hexString : "" }
        ))
        if !hex.isEmpty {
            ColorPicker("Цвет", selection: Binding(
                get: { Color(hex: hex) ?? defaultColor },
                set: { hex = $0.hexString }
            ), supportsOpacity: false)
        }
    }
}

// MARK: - Повтор

/// Повтор: как часто, по каким дням недели, до какого дня.
struct PlannerRepeatFields: View {
    @Binding var rule: PlannerRepeat
    @Binding var interval: Int
    @Binding var weekdays: [Int]
    @Binding var until: Date?
    let start: Date

    /// Номера дней недели в календаре (1 = воскресенье), начиная с понедельника.
    private let order = [2, 3, 4, 5, 6, 7, 1]
    private let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private var unit: String {
        switch rule {
        case .none: ""
        case .daily: "дн."
        case .weekly: "нед."
        case .monthly: "мес."
        case .yearly: "г."
        }
    }

    var body: some View {
        Picker("🔁 Повтор", selection: $rule) {
            ForEach(PlannerRepeat.allCases) { Text($0.title).tag($0) }
        }
        if rule != .none {
            Stepper(value: $interval, in: 1...30) {
                Text(interval == 1 ? "Каждый(ую) \(unit)" : "Каждые \(interval) \(unit)")
            }
        }
        if rule == .weekly {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let day = order[index]
                    let on = weekdays.contains(day)
                    Button {
                        if on { weekdays.removeAll { $0 == day } } else { weekdays.append(day) }
                    } label: {
                        Text(names[index])
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Circle().fill(on ? Color.appAccent.opacity(0.35) : Color.secondary.opacity(0.15)))
                            .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        if rule != .none {
            Toggle("Закончить повтор", isOn: Binding(
                get: { until != nil },
                set: { until = $0 ? (until ?? Calendar.current.date(byAdding: .month, value: 3, to: start)) : nil }
            ))
            if let current = until {
                DatePicker("До", selection: Binding(get: { current }, set: { until = $0 }), in: start..., displayedComponents: .date)
            }
        }
    }
}
