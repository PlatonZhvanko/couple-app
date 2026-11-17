import Charts
import SwiftData
import SwiftUI

/// История настроения: календарь месяца и график за неделю или месяц.
struct MoodHistoryView: View {
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<MoodEntry> { $0.deletedAt == nil }, sort: \MoodEntry.createdAt, order: .reverse)
    private var entries: [MoodEntry]

    /// Чью историю показывать.
    enum Who: String, CaseIterable, Identifiable {
        case me, partner, both
        var id: String { rawValue }
    }

    enum Period: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
        var title: String { self == .week ? "Неделя" : "Месяц" }
    }

    @State private var who: Who = .both
    @State private var period: Period = .week
    @State private var month: Date = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    private func title(for who: Who) -> String {
        switch who {
        case .me: account.myName
        case .partner: account.partnerName
        case .both: "Оба"
        }
    }

    private var members: [CoupleMember] {
        switch who {
        case .me: [account.current]
        case .partner: [account.current.other]
        case .both: [account.current, account.current.other]
        }
    }

    private var filtered: [MoodEntry] {
        let allowed = Set(members.map(\.rawValue))
        return entries.filter { allowed.contains($0.member) }
    }

    var body: some View {
        List {
            Section {
                Picker("Чья история", selection: $who) {
                    ForEach(Who.allCases) { Text(title(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                chart
                    .frame(height: 200)
                    .padding(.vertical, 8)
            } header: {
                Text("График")
            }

            Section {
                MoodMonthGrid(
                    month: $month,
                    byDay: MoodStats.byDay(filtered),
                    selectedDay: $selectedDay
                )
            } header: {
                Text("Календарь")
            }

            if let selectedDay {
                let dayEntries = filtered.filter { calendar.isDate($0.createdAt, inSameDayAs: selectedDay) }
                Section(selectedDay.formatted(date: .complete, time: .omitted)) {
                    if dayEntries.isEmpty {
                        Text("Нет отметок").foregroundStyle(.secondary)
                    }
                    ForEach(dayEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            if who == .both {
                                Text(account.name(of: entry.coupleMember))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            MoodEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - График

    private struct Point: Identifiable {
        let day: Date
        let member: String
        let value: Double
        var id: String { "\(member)-\(day.timeIntervalSince1970)" }
    }

    private var points: [Point] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: today) else { return [] }
        var result: [Point] = []
        for member in members {
            let mine = filtered.filter { $0.member == member.rawValue && $0.createdAt >= start }
            for (day, items) in MoodStats.byDay(mine) {
                if let average = MoodStats.average(items) {
                    result.append(Point(day: day, member: account.name(of: member), value: average))
                }
            }
        }
        return result.sorted { $0.day < $1.day }
    }

    @ViewBuilder
    private var chart: some View {
        let data = points
        if data.isEmpty {
            ContentUnavailableView("Нет данных", systemImage: "chart.xyaxis.line", description: Text("Отметки за этот период появятся здесь."))
        } else {
            Chart(data) { point in
                LineMark(
                    x: .value("День", point.day, unit: .day),
                    y: .value("Настроение", point.value)
                )
                .foregroundStyle(by: .value("Кто", point.member))
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("День", point.day, unit: .day),
                    y: .value("Настроение", point.value)
                )
                .foregroundStyle(by: .value("Кто", point.member))
            }
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self), let level = MoodLevel(rawValue: Int(raw.rounded())) {
                            Text(level.emoji)
                        }
                    }
                }
            }
            .chartLegend(who == .both ? .visible : .hidden)
        }
    }
}

// MARK: - Календарь месяца

/// Сетка месяца: каждый день окрашен по среднему настроению.
struct MoodMonthGrid: View {
    @Binding var month: Date
    let byDay: [Date: [MoodEntry]]
    @Binding var selectedDay: Date?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            result.append(calendar.date(byAdding: .day, value: day - 1, to: month))
        }
        return result
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func dayCell(_ day: Date) -> some View {
        let average = MoodStats.average(byDay[day] ?? [])
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption2)
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.secondary)
                Text(average.map { MoodLevel.nearest(to: $0).emoji } ?? " ")
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(average.map { MoodLevel.color(for: $0).opacity(0.35) } ?? Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) {
            month = calendar.startOfMonth(for: next)
            selectedDay = nil
        }
    }
}

fileprivate extension Calendar {
    /// Первое число месяца для даты.
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
