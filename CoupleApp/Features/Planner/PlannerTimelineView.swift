import SwiftUI

/// Планировщик: дни колонками, время слева с шагом 30 минут, события блоками.
/// Неделя или один день. Нажатие на пустое время создаёт блок, на блок открывает его.
struct PlannerTimelineView: View {
    let days: [Date]
    let isDayMode: Bool
    let events: [PlannerEvent]
    let externalItems: (Date) -> [CalendarItem]
    /// Нажали на день в шапке.
    let onHeaderTap: (Date) -> Void
    /// Нажали на пустое время: начало получасового отрезка.
    let onSlotTap: (Date) -> Void
    let onEventTap: (PlannerEvent) -> Void

    static let slotMinutes = 30
    private let timeColumnWidth: CGFloat = 46
    /// Стандартный видимый промежуток: с 9:00 до 22:00 (в получасовых отрезках).
    private let defaultFirstSlot = 18
    private let defaultLastSlot = 44

    /// Показан ли весь день (с прокруткой) вместо экрана «всё сразу».
    @State private var showFullDay = false

    private var cal: Calendar { PlannerCalendar.calendar }

    /// Видимые отрезки [первый, последний). По умолчанию 9:00–22:00,
    /// расширяются, если у кого-то из дней есть события за их пределами.
    private var slotRange: Range<Int> {
        if showFullDay { return 0..<48 }
        var first = defaultFirstSlot
        var last = defaultLastSlot
        for day in days {
            let dayStart = cal.startOfDay(for: day)
            let ends = events.occurrences(on: day).filter { !$0.event.isAllDay }.map { ($0.start, $0.end) }
                + externalItems(day).map { ($0.start, $0.end) }
            for (start, end) in ends {
                let startSlot = Int(max(0, start.timeIntervalSince(dayStart)) / 60) / Self.slotMinutes
                let endSlot = min(48, Int((max(0, end.timeIntervalSince(dayStart)) / 60).rounded(.up)) / Self.slotMinutes + 1)
                first = min(first, startSlot)
                last = max(last, endSlot)
            }
        }
        return max(0, first)..<min(48, max(last, first + 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayStrip
            Divider()
            GeometryReader { geo in
                let range = slotRange
                // Кнопка «показать весь день» занимает 28 пунктов под сеткой.
                let fit = (geo.size.height - 28) / CGFloat(range.count)
                let slotHeight = showFullDay ? 34 : max(fit, 16)
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            timeColumn(range: range, slotHeight: slotHeight)
                            ForEach(days, id: \.self) { day in
                                dayColumn(day, range: range, slotHeight: slotHeight)
                            }
                        }
                        .frame(height: slotHeight * CGFloat(range.count))
                        expandButton
                    }
                }
                .scrollDisabled(!showFullDay && fit >= 16)
            }
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(.snappy) { showFullDay.toggle() }
        } label: {
            Image(systemName: showFullDay ? "chevron.up" : "chevron.down")
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(showFullDay ? "Свернуть до рабочих часов" : "Показать весь день")
    }

    // MARK: - Шапка с днями

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 1)
            ForEach(days, id: \.self) { day in
                Button { onHeaderTap(day) } label: {
                    headerCell(day)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func headerCell(_ day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let isWeekend = cal.isDateInWeekend(day)
        let weekday = PlannerCalendar.weekdayShort(day)
        return Group {
            if isDayMode {
                HStack(spacing: 6) {
                    Text(PlannerCalendar.dayTitle(day))
                        .font(.headline)
                    Image(systemName: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isToday ? Color.red : Color.primary)
            } else {
                VStack(spacing: 2) {
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isWeekend ? Color.red.opacity(0.8) : Color.secondary)
                    Text("\(cal.component(.day, from: day))")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                        .background {
                            if isToday { Circle().fill(Color.red) }
                        }
                        .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.red : Color.primary))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - События на весь день

    @ViewBuilder
    private var allDayStrip: some View {
        let perDay = days.map { day in events.occurrences(on: day).filter(\.event.isAllDay) }
        if perDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("весь\nдень")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: timeColumnWidth - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                    VStack(spacing: 2) {
                        ForEach(perDay[index].prefix(isDayMode ? 4 : 2)) { occurrence in
                            Button { onEventTap(occurrence.event) } label: {
                                Text(occurrence.event.displayTitle)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(occurrence.event.categoryValue.color))
                            }
                            .buttonStyle(.plain)
                        }
                        let extra = perDay[index].count - (isDayMode ? 4 : 2)
                        if extra > 0 {
                            Text("+\(extra)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 1)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Шкала времени

    private func timeColumn(range: Range<Int>, slotHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(range), id: \.self) { slot in
                let isHour = slot % 2 == 0
                Text(String(format: "%d:%02d", slot / 2, isHour ? 0 : 30))
                    .font(isHour ? .caption.weight(.semibold) : .caption2)
                    .foregroundStyle(isHour ? Color.primary : Color.secondary)
                    .frame(width: timeColumnWidth - 6, height: slotHeight, alignment: .topTrailing)
                    .padding(.trailing, 6)
                    .offset(y: slot == range.lowerBound ? 0 : -7)
            }
        }
    }

    // MARK: - Колонка дня

    private func dayColumn(_ day: Date, range: Range<Int>, slotHeight: CGFloat) -> some View {
        let dayStart = cal.startOfDay(for: day)
        let isToday = cal.isDateInToday(day)
        let blocks = layout(day)
        let rangeStart = dayStart.addingTimeInterval(Double(range.lowerBound * Self.slotMinutes * 60))

        return ZStack(alignment: .topLeading) {
            // Сетка и пустые отрезки, на которые можно нажать.
            VStack(spacing: 0) {
                ForEach(Array(range), id: \.self) { slot in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: slotHeight)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.secondary.opacity(slot % 2 == 0 ? 0.3 : 0.12))
                                .frame(height: 0.5)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSlotTap(dayStart.addingTimeInterval(Double(slot * Self.slotMinutes * 60)))
                        }
                }
            }

            GeometryReader { geo in
                ForEach(blocks) { block in
                    let width = geo.size.width / CGFloat(block.columns)
                    let blockHeight = max(height(of: block, slotHeight: slotHeight), 14)
                    blockView(block, height: blockHeight)
                        .frame(width: max(width - 2, 4), height: blockHeight)
                        .offset(x: width * CGFloat(block.column) + 1, y: y(of: block.start, from: rangeStart, slotHeight: slotHeight))
                }
            }

            if isToday, y(of: .now, from: rangeStart, slotHeight: slotHeight) >= 0,
               y(of: .now, from: rangeStart, slotHeight: slotHeight) <= slotHeight * CGFloat(range.count) {
                nowLine(from: rangeStart, slotHeight: slotHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .background(isToday ? Color.secondary.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 0.5)
        }
    }

    private func y(of date: Date, from origin: Date, slotHeight: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(origin) / 60) / CGFloat(Self.slotMinutes) * slotHeight
    }

    private func height(of block: PlannerTimelineBlock, slotHeight: CGFloat) -> CGFloat {
        CGFloat(block.end.timeIntervalSince(block.start) / 60) / CGFloat(Self.slotMinutes) * slotHeight - 2
    }

    private func nowLine(from origin: Date, slotHeight: CGFloat) -> some View {
        let offset = y(of: .now, from: origin, slotHeight: slotHeight)
        return HStack(spacing: 0) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Rectangle().fill(Color.red).frame(height: 1.5)
        }
        .offset(x: -4, y: offset - 4)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func blockView(_ block: PlannerTimelineBlock, height: CGFloat) -> some View {
        let tall = height > 40
        let content = VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(isDayMode ? .callout.weight(.semibold) : .caption2.weight(.bold))
                .lineLimit(tall ? 4 : 1)
            if tall || isDayMode {
                Text("\(PlannerCalendar.time(block.start))–\(PlannerCalendar.time(block.end))")
                    .font(.system(size: 9))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        switch block.source {
        case .event(let event):
            Button { onEventTap(event) } label: {
                content
                    .foregroundStyle(Color.black)
                    .background(RoundedRectangle(cornerRadius: 4).fill(block.color))
            }
            .buttonStyle(.plain)
        case .external:
            content
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                )
        }
    }

    // MARK: - Раскладка пересекающихся блоков

    private func layout(_ day: Date) -> [PlannerTimelineBlock] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = PlannerCalendar.addDays(1, to: dayStart)
        let minimum: TimeInterval = 15 * 60

        var raw: [PlannerTimelineBlock] = []
        for occurrence in events.occurrences(on: day) where !occurrence.event.isAllDay {
            let start = max(occurrence.start, dayStart)
            let end = min(max(occurrence.end, start.addingTimeInterval(minimum)), dayEnd)
            raw.append(PlannerTimelineBlock(
                id: occurrence.id, source: .event(occurrence.event),
                title: occurrence.event.displayTitle,
                color: occurrence.event.categoryValue.color, start: start, end: end
            ))
        }
        for item in externalItems(day) {
            let start = max(item.start, dayStart)
            let end = min(max(item.end, start.addingTimeInterval(minimum)), dayEnd)
            raw.append(PlannerTimelineBlock(
                id: item.id, source: .external, title: item.title,
                color: item.color, start: start, end: end
            ))
        }
        raw.sort { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }

        // Группы пересекающихся блоков делят ширину колонки.
        var result: [PlannerTimelineBlock] = []
        var group: [PlannerTimelineBlock] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            result += group.map { var block = $0; block.columns = count; return block }
            group = []
            columnEnds = []
        }

        for var block in raw {
            if block.start >= groupEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= block.start }) {
                block.column = free
                columnEnds[free] = block.end
            } else {
                block.column = columnEnds.count
                columnEnds.append(block.end)
            }
            group.append(block)
            groupEnd = max(groupEnd, block.end)
        }
        flush()
        return result
    }
}

struct PlannerTimelineBlock: Identifiable {
    enum Source {
        case event(PlannerEvent)
        case external
    }

    let id: String
    let source: Source
    let title: String
    let color: Color
    let start: Date
    let end: Date
    var column = 0
    var columns = 1
}
