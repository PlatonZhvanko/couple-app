import SwiftUI

/// Журнал: дни колонками, время слева с шагом 30 минут, записи блоками.
/// Неделя или один день. Нажатие на пустое время создаёт запись, на блок открывает её,
/// блок можно зажать и перетащить на другое время или день.
struct PlannerTimelineView: View {
    let days: [Date]
    let isDayMode: Bool
    let events: [PlannerEvent]
    /// Цвет записи (свой, по группе, делу, клиенту или по виду).
    let colorFor: (PlannerEvent, Date) -> Color
    let externalItems: (Date) -> [CalendarItem]
    /// Дни со сменой (красноватая полоса 9:00–23:00).
    var shiftDays: Set<Date> = []
    /// Смайлик настроения дня (для обоих), пустая строка — нет.
    var dayMark: (Date) -> String = { _ in "" }
    /// Значок оплаты записи за этот день.
    let badge: (PlannerEvent, Date) -> PlannerPayBadge
    /// Буква владельца записи (в общем журнале), `nil` — не показывать.
    let ownerLetter: (PlannerEvent) -> String?
    /// Можно ли переносить запись этому человеку.
    let canMove: (PlannerEvent) -> Bool
    /// Нажали на день в шапке.
    let onHeaderTap: (Date) -> Void
    /// Нажали на пустое время: начало получасового отрезка.
    let onSlotTap: (Date) -> Void
    /// Нажали на запись: событие и начало этого раза.
    let onEventTap: (PlannerEvent, Date) -> Void
    /// Запись перетащили: событие, начало этого раза, новое начало.
    let onMove: (PlannerEvent, Date, Date) -> Void
    /// Смахнули влево (1) или вправо (-1): листаем неделю или день.
    var onSwipe: (Int) -> Void = { _ in }

    static let slotMinutes = 30
    static let minSlotHeight: CGFloat = 15
    private let timeColumnWidth: CGFloat = 44
    private let topPadding: CGFloat = 6
    private let bottomPadding: CGFloat = 8
    /// Стандартный видимый промежуток: с 7:00 до 0:00 (в получасовых отрезках).
    private let defaultFirstSlot = 14
    private let defaultLastSlot = 48

    /// Показаны ли все 24 часа (с прокруткой) вместо экрана «всё сразу».
    @State private var showFullDay = false
    @State private var dragID: String?
    @State private var dragDay: Date?
    @State private var dragOffset: CGSize = .zero
    /// Блок двигали: такой жест не считаем листанием.
    @State private var blockWasDragged = false

    private var cal: Calendar { PlannerCalendar.calendar }

    /// Видимые отрезки. По умолчанию 9:00–0:00, расширяются, если у кого-то из дней
    /// есть записи раньше 9:00.
    private var slotRange: Range<Int> {
        if showFullDay { return 0..<48 }
        var first = defaultFirstSlot
        for day in days {
            let dayStart = cal.startOfDay(for: day)
            let starts = events.occurrences(on: day).filter { !$0.event.isAllDay }.map(\.start)
                + externalItems(day).map(\.start)
            for start in starts {
                let slot = Int(max(0, start.timeIntervalSince(dayStart)) / 60) / Self.slotMinutes
                first = min(first, slot)
            }
        }
        return max(0, first)..<defaultLastSlot
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayStrip
            Divider()
            GeometryReader { geo in
                let range = slotRange
                let columnWidth = (geo.size.width - timeColumnWidth) / CGFloat(max(days.count, 1))
                let fit = (geo.size.height - topPadding - bottomPadding) / CGFloat(range.count)
                // Весь день помещается на экран без прокрутки; не меньше 15 пт на получас: так блоки и подписи времени не слипаются.
                let slotHeight: CGFloat = showFullDay ? 34 : max(fit, Self.minSlotHeight)
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        timeColumn(range: range, slotHeight: slotHeight)
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            dayColumn(day, index: index, range: range, slotHeight: slotHeight, columnWidth: columnWidth)
                                .zIndex(dragDay == day ? 5 : 0)
                        }
                    }
                    .frame(height: slotHeight * CGFloat(range.count))
                    .coordinateSpace(.named("grid"))
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                }
                .scrollDisabled(!showFullDay && fit >= Self.minSlotHeight && dragID == nil)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    defer { blockWasDragged = false }
                    guard !blockWasDragged, dragID == nil else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 70, abs(dx) > abs(dy) * 2 else { return }
                    onSwipe(dx < 0 ? 1 : -1)
                }
        )
    }

    // MARK: - Шапка с днями

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showFullDay.toggle() }
            } label: {
                Image(systemName: showFullDay ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth, height: 30)
            }
            .accessibilityLabel(showFullDay ? "Свернуть до 7:00–0:00" : "Показать все 24 часа")
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
                    if !dayMark(day).isEmpty { Text(dayMark(day)) }
                    Image(systemName: "rectangle.split.3x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isToday ? Color.plannerToday : Color.primary)
            } else {
                VStack(spacing: 2) {
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isWeekend ? Color.red.opacity(0.8) : Color.secondary)
                    Text("\(cal.component(.day, from: day))")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                        .background {
                            if isToday { Circle().fill(Color.plannerToday) }
                        }
                        .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.red : Color.primary))
                    if !dayMark(day).isEmpty {
                        Text(dayMark(day)).font(.system(size: 11))
                    }
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
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 2) {
                        ForEach(perDay[index].prefix(isDayMode ? 4 : 2)) { occurrence in
                            Text(occurrence.event.displayTitle)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 3).fill(occurrence.event.categoryValue.color))
                                .onTapGesture { onEventTap(occurrence.event, day) }
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
        ZStack(alignment: .topTrailing) {
            ForEach(Array(range), id: \.self) { slot in
                let isHour = slot % 2 == 0
                Text(slot == 48 ? "0:00" : String(format: "%d:%02d", slot / 2, isHour ? 0 : 30))
                    // Фиксированный размер: подпись не зависит от крупности шрифта и не переносится.
                    .font(.system(size: isHour ? 11 : 9, weight: isHour ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isHour ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(slot - range.lowerBound) * slotHeight - 7)
            }
            if range.upperBound == 48 {
                Text("0:00")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(range.count) * slotHeight - 7)
            }
        }
        .frame(width: timeColumnWidth, height: slotHeight * CGFloat(range.count), alignment: .topTrailing)
    }

    // MARK: - Колонка дня

    private func dayColumn(_ day: Date, index: Int, range: Range<Int>, slotHeight: CGFloat, columnWidth: CGFloat) -> some View {
        let dayStart = cal.startOfDay(for: day)
        let isToday = cal.isDateInToday(day)
        let blocks = layout(day)
        let rangeStart = dayStart.addingTimeInterval(Double(range.lowerBound * Self.slotMinutes * 60))

        let isShift = shiftDays.contains(dayStart)
        let bandStart = dayStart.addingTimeInterval(Double(PlannerShift.startHour) * 3600)
        let bandTop = max(0, y(of: bandStart, from: rangeStart, slotHeight: slotHeight))
        let bandBottom = min(
            slotHeight * CGFloat(range.count),
            y(of: dayStart.addingTimeInterval(Double(PlannerShift.endHour) * 3600), from: rangeStart, slotHeight: slotHeight)
        )

        return ZStack(alignment: .topLeading) {
            if isShift, bandBottom > bandTop {
                // Смена: просто слегка красноватый промежуток 9:00–21:00, без линий.
                Rectangle()
                    .fill(Color.red.opacity(0.14))
                    .frame(maxWidth: .infinity)
                    .frame(height: bandBottom - bandTop)
                    .offset(y: bandTop)
                    .allowsHitTesting(false)
            }
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
                    let dragging = dragID == block.id
                    blockView(block, height: blockHeight, day: day, index: index, range: range,
                              slotHeight: slotHeight, columnWidth: columnWidth)
                        .frame(width: max(width - 2, 4), height: blockHeight)
                        .scaleEffect(dragging ? 1.05 : 1)
                        .shadow(color: .black.opacity(dragging ? 0.35 : 0), radius: 6)
                        .offset(
                            x: width * CGFloat(block.column) + 1 + (dragging ? dragOffset.width : 0),
                            y: y(of: block.start, from: rangeStart, slotHeight: slotHeight) + (dragging ? dragOffset.height : 0)
                        )
                        .zIndex(dragging ? 10 : 0)
                }
            }

            if isToday, y(of: .now, from: rangeStart, slotHeight: slotHeight) >= 0,
               y(of: .now, from: rangeStart, slotHeight: slotHeight) <= slotHeight * CGFloat(range.count) {
                nowLine(from: rangeStart, slotHeight: slotHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .background(isToday ? Color.plannerToday.opacity(0.09) : Color.clear)
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

    // MARK: - Блок

    @ViewBuilder
    private func blockView(
        _ block: PlannerTimelineBlock, height: CGFloat, day: Date, index: Int,
        range: Range<Int>, slotHeight: CGFloat, columnWidth: CGFloat
    ) -> some View {
        // Фамилия сверху, имя снизу, обе строки одного размера и всегда ниже значка оплаты.
        // Шрифт берём самый крупный из тех, что помещаются по высоте и ширине блока.
        let narrow = block.columns > 1
        let words = block.title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let topInset: CGFloat = height >= 34 ? 11 : 1
        let twoLines = words.count >= 2 && height - topInset >= 24
        let first = words.first ?? block.title
        let rest = words.dropFirst().joined(separator: " ")
        let lineCount: CGFloat = twoLines ? 2 : 1
        let textWidth = max(10, columnWidth / CGFloat(max(block.columns, 1)) - 6)
        let longest = CGFloat(max(1, twoLines ? max(first.count, rest.count) : block.title.count))
        let byHeight = (height - topInset - 3) / (lineCount * 1.2)
        let byWidth = textWidth / (longest * 0.64)
        let maxFont: CGFloat = isDayMode ? 22 : 17
        let fontSize = max(8, min(maxFont, byHeight, byWidth))
        let showTime = !narrow && height - topInset - 3 > fontSize * lineCount * 1.2 + 14
        let content = VStack(alignment: .leading, spacing: 0) {
            // Одним текстом, чтобы при нехватке места обе строки уменьшались вместе.
            Text(twoLines ? first + "\n" + rest : block.title)
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(Int(lineCount))
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.leading)
            if showTime {
                Text("\(PlannerCalendar.time(block.start))–\(PlannerCalendar.time(block.end))")
                    .font(.system(size: isDayMode ? 12 : 10, weight: .medium))
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 1)
        .padding(.top, topInset)
        .padding(.bottom, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if block.together { Text("💞").font(.system(size: 9)) }
                if let symbol = block.badge.symbol {
                    Text(symbol).font(.system(size: 10))
                }
            }
            .padding(1)
        }
        .overlay(alignment: .bottomTrailing) {
            if let owner = block.owner {
                Text(owner)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
                    .padding(1)
            }
        }

        switch block.source {
        case .event(let event):
            let cancelled = [.cancelled, .fineUnpaid, .finePaid].contains(block.badge)
            let base = content
                .opacity(cancelled ? 0.55 : 1)
                .foregroundStyle(Color.black)
                .background(RoundedRectangle(cornerRadius: 6).fill(block.color))
                .contentShape(Rectangle())
                .onTapGesture { onEventTap(event, block.start) }
            if canMove(event) && !event.isAllDay {
                base.gesture(moveGesture(
                    block: block, event: event, index: index, range: range,
                    slotHeight: slotHeight, columnWidth: columnWidth
                ))
            } else {
                base
            }
        case .external:
            content
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                )
        }
    }

    /// Зажать блок и перетащить: на другое время или в другой день.
    private func moveGesture(
        block: PlannerTimelineBlock, event: PlannerEvent, index: Int,
        range: Range<Int>, slotHeight: CGFloat, columnWidth: CGFloat
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    dragID = block.id
                    blockWasDragged = true
                    dragDay = days[index]
                    dragOffset = drag.translation
                }
            }
            .onEnded { value in
                defer {
                    dragID = nil
                    dragDay = nil
                    dragOffset = .zero
                }
                guard case .second(true, let drag?) = value, columnWidth > 0 else { return }

                let dayStart = cal.startOfDay(for: days[index])
                let origin = dayStart.addingTimeInterval(Double(range.lowerBound * Self.slotMinutes * 60))
                let blockTop = y(of: block.start, from: origin, slotHeight: slotHeight)
                let grab = drag.startLocation.y - blockTop
                let newTop = drag.location.y - grab
                let slot = Int((newTop / slotHeight).rounded())
                let absoluteSlot = min(max(range.lowerBound + slot, 0), 47)
                let column = Int(((drag.location.x - timeColumnWidth) / columnWidth).rounded(.down))
                let targetIndex = min(max(column, 0), days.count - 1)
                let newStart = cal.startOfDay(for: days[targetIndex])
                    .addingTimeInterval(Double(absoluteSlot * Self.slotMinutes * 60))
                if abs(newStart.timeIntervalSince(block.start)) >= 60 {
                    onMove(event, block.start, newStart)
                }
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
                title: occurrence.event.plainTitle,
                color: colorFor(occurrence.event, day), start: start, end: end,
                badge: badge(occurrence.event, day), owner: ownerLetter(occurrence.event),
                emoji: occurrence.event.categoryValue.emoji ?? "",
                together: occurrence.event.scopeValue == .shared
            ))
        }
        for item in externalItems(day) {
            let start = max(item.start, dayStart)
            let end = min(max(item.end, start.addingTimeInterval(minimum)), dayEnd)
            raw.append(PlannerTimelineBlock(
                id: item.id, source: .external, title: item.title,
                color: item.color, start: start, end: end, badge: .none, owner: nil
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
    let badge: PlannerPayBadge
    let owner: String?
    var column = 0
    var emoji = ""
    var together = false
    var columns = 1
}
