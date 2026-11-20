import SwiftUI

/// Два поля времени для сна: «лёг» и «проснулся», без выбора дня.
/// Считается, что проснулся(ась) сегодня, а лёг(ла) вчера (или сегодня после полуночи).
/// Карандаш рядом открывает полные даты, если нужно что-то исправить.
struct SleepTimeFields: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date
    @State private var showDates = false

    private var calendar: Calendar { .current }

    private func clock(_ date: Date) -> DateComponents {
        calendar.dateComponents([.hour, .minute], from: date)
    }

    /// Вход «лёг» относительно времени пробуждения: ближайшее время перед ним.
    private func bedtimeDate(clock: DateComponents, before wake: Date) -> Date {
        let day = calendar.startOfDay(for: wake)
        var candidate = calendar.date(bySettingHour: clock.hour ?? 23, minute: clock.minute ?? 0, second: 0, of: day) ?? day
        if candidate >= wake { candidate = calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate }
        return candidate
    }

    var body: some View {
        if showDates {
            DatePicker("Лёг(ла)", selection: $bedtime)
            DatePicker("Проснулся(ась)", selection: $wakeTime)
        } else {
            DatePicker("Лёг(ла)", selection: Binding(
                get: { bedtime },
                set: { bedtime = bedtimeDate(clock: clock($0), before: wakeTime) }
            ), displayedComponents: .hourAndMinute)
            DatePicker("Проснулся(ась)", selection: Binding(
                get: { wakeTime },
                set: { newValue in
                    let bedClock = clock(bedtime)
                    let parts = clock(newValue)
                    let today = calendar.startOfDay(for: wakeTime)
                    wakeTime = calendar.date(bySettingHour: parts.hour ?? 7, minute: parts.minute ?? 0, second: 0, of: today) ?? newValue
                    bedtime = bedtimeDate(clock: bedClock, before: wakeTime)
                }
            ), displayedComponents: .hourAndMinute)
        }
        Button {
            showDates.toggle()
        } label: {
            Label(showDates ? "Скрыть даты" : "Изменить дату", systemImage: "pencil")
                .font(.footnote)
        }
    }
}
