import SwiftUI

/// Одна строка отчёта: по нажатию открывается отдельное окно со списком, из чего сложилась сумма.
struct StatisticsLine<Details: View>: View {
    let title: String
    let value: String
    var bold = false
    @ViewBuilder let details: () -> Details

    var body: some View {
        NavigationLink {
            List {
                Section {
                    details()
                } footer: {
                    Text("Итого: \(value)")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
            .font(bold ? .headline : .body)
        }
    }
}

/// Строка внутри раскрытого списка: слева подпись и пояснение, справа сумма.
struct StatisticsDetailRow: View {
    let title: String
    var caption: String?
    var value: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

enum StatisticsFormat {
    static func day(_ date: Date) -> String {
        PlannerCalendar.format(date, "d MMM")
    }
}
