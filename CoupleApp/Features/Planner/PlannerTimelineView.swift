import SwiftUI
import UIKit

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
    /// Нажали на запись другого раздела (например, ремонт).
    var onExternalTap: (CalendarItem) -> Void = { _ in }
    /// Можно ли двигать запись другого раздела.
    var canMoveExternal: (CalendarItem) -> Bool = { _ in false }
    /// Запись другого раздела перетащили на новое начало.
    var onExternalMove: (CalendarItem, Date) -> Void = { _, _ in }
    /// Дни со сменой (красноватая полоса 9:00–23:00).
    var shiftDays: Set<Date> = []
    /// Часть смены по дням: 0 — вся, 1 — первая половина, 2 — вторая.
    var shiftParts: [Date: Int] = [:]
    /// Эмодзи типов дел (по названию типа в нижнем регистре).
    var errandEmojis: [String: String] = [:]
    /// Долгое нажатие на красный промежуток смены.
    var onShiftHold: (Date) -> Void = { _ in }
    /// Своё эмодзи статуса записи: `nil` — обычное, пустая строка — без эмодзи.
    var badgeEmoji: (PlannerEvent, Date) -> String? = { _, _ in nil }
    /// Скрывать ли запись визуально (режим «глазик»).
    var isHidden: (PlannerEvent, Date) -> Bool = { _, _ in false }
    /// Подтверждение корта в YClients: нет запроса, ждём (белая) или подтверждён (оранжевая).
    var courtState: (PlannerEvent, Date) -> PlannerCourtState = { _, _ in .none }
    /// Кнопка-глазик над субботой: `nil` — без неё. Второе значение: глазик перечёркнут (скрываем).
    var onEyeTap: (() -> Void)? = nil
    var eyeHides = false
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

    private var eyeRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 18)
            if isDayMode {
                Spacer()
                eyeButton
            } else {
                ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                    if index == min(5, days.count - 1) { eyeButton.frame(maxWidth: .infinity) }
                    else { Color.clear.frame(maxWidth: .infinity, maxHeight: 18) }
                }
            }
        }
    }

    private var eyeButton: some View {
        Button { onEyeTap?() } label: {
            Image(systemName: eyeHides ? "eye.slash" : "eye.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(eyeHides ? Color.secondary : Color.plannerToday)
                .frame(width: 32, height: 18)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(eyeHides ? "Показать отменённые и перенесённые" : "Скрыть отменённые и перенесённые")
    }

    private var header: some View {
        VStack(spacing: 0) {
            headerRow
        }
    }

    private var headerRow: some View {
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
        let shiftHours = PlannerShift.hours(part: shiftParts[dayStart] ?? 0)
        let bandStart = dayStart.addingTimeInterval(Double(shiftHours.start) * 3600)
        let bandTop = max(0, y(of: bandStart, from: rangeStart, slotHeight: slotHeight))
        let bandBottom = min(
            slotHeight * CGFloat(range.count),
            y(of: dayStart.addingTimeInterval(Double(shiftHours.end) * 3600), from: rangeStart, slotHeight: slotHeight)
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
                        .onLongPressGesture(minimumDuration: 0.6) {
                            let minutes = slot * Self.slotMinutes
                            if isShift, minutes >= shiftHours.start * 60, minutes < shiftHours.end * 60 {
                                onShiftHold(dayStart)
                            }
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

    /// Ширина текста на 1 пункт шрифта (жирный системный): считаем по-настоящему, а не на глаз.
    nonisolated(unsafe) private static var widthCache: [String: CGFloat] = [:]
    private static let measureFont = UIFont.systemFont(ofSize: 100, weight: .bold)

    private static func unitWidth(_ text: String) -> CGFloat {
        if let cached = widthCache[text] { return cached }
        let width = (text as NSString).size(withAttributes: [.font: measureFont]).width / 100
        if widthCache.count > 2000 { widthCache.removeAll() }
        widthCache[text] = width
        return width
    }

    /// Как написать название в блоке: строки и размер шрифта.
    /// Размер — самый крупный, при котором все строки целиком влезают в ширину
    /// (слова не рвутся) и в высоту. Слова делим на строки так, чтобы они были
    /// ближе по ширине. Слова никогда не отбрасываются.
    /// Значок записи другого раздела в левом верхнем углу (рисуется кодом).
    static func leadingView(for block: PlannerTimelineBlock) -> AnyView? {
        switch block.source {
        case .external(let item): return item.leadingView
        case .event(let event):
            return (event.isFromYClients || block.court == .confirmed) ? AnyView(ClientsYClientsBadge(size: 10.5)) : nil
        }
    }

    static func titleLayout(_ title: String, width: CGFloat, height: CGFloat, maxFont: CGFloat)
        -> (text: String, lines: Int, font: CGFloat) {
        // Очень короткое название («СШ») не раздуваем на весь блок.
        let maxFont = title.count <= 4 ? min(maxFont, 12) : maxFont
        func fit(_ lines: [String]) -> CGFloat {
            let widest = max(0.1, lines.map(unitWidth).max() ?? 1)
            return min(maxFont, height / (CGFloat(lines.count) * 1.18), width / widest)
        }
        let words = title.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 2 else { return (title, 1, max(4.5, fit([title]))) }

        // Все слова остаются в блоке: пробуем разбить на 1…5 строк (самое узкое разбиение
        // для каждого числа строк) и берём вариант с самым крупным шрифтом.
        var best: (lines: [String], font: CGFloat) = ([title], fit([title]))
        // Слишком много слов: делим только на 2–3 строки, чтобы не считать зря.
        for count in 2...min(words.count > 12 ? 3 : 5, words.count) {
            let lines = Self.balancedLines(words, count: count)
            let size = fit(lines)
            if size > best.font { best = (lines, size) }
        }
        return (best.lines.joined(separator: "\n"), best.lines.count, max(4.5, best.font))
    }

    /// Делит слова на `count` строк так, чтобы самая широкая строка была как можно уже.
    static func balancedLines(_ words: [String], count: Int) -> [String] {
        let n = words.count
        func line(_ i: Int, _ j: Int) -> String { words[i..<j].joined(separator: " ") }
        // dp[k][j] — наименьшая ширина самой широкой строки для первых j слов в k строках.
        var dp = Array(repeating: Array(repeating: CGFloat.greatestFiniteMagnitude, count: n + 1), count: count + 1)
        var cut = Array(repeating: Array(repeating: 0, count: n + 1), count: count + 1)
        for j in 1...n { dp[1][j] = unitWidth(line(0, j)) }
        if count >= 2 {
            for k in 2...count {
                for j in k...n {
                    for i in (k - 1)..<j {
                        let value = max(dp[k - 1][i], unitWidth(line(i, j)))
                        if value < dp[k][j] { dp[k][j] = value; cut[k][j] = i }
                    }
                }
            }
        }
        var result: [String] = []
        var j = n
        var k = count
        while k >= 1 {
            let i = k == 1 ? 0 : cut[k][j]
            result.insert(line(i, j), at: 0)
            j = i
            k -= 1
        }
        return result
    }

    // MARK: - Блок

    @ViewBuilder
    private func blockView(
        _ block: PlannerTimelineBlock, height: CGFloat, day: Date, index: Int,
        range: Range<Int>, slotHeight: CGFloat, columnWidth: CGFloat
    ) -> some View {
        // Значок статуса или оплаты стоит строкой сверху, название всегда ниже него.
        // В низких блоках (получас) значок уходит вправо, чтобы название осталось крупным.
        // Размер шрифта: самый крупный, при котором самое длинное слово целиком влезает
        // в ширину колонки (слова не рвутся посередине) и строки влезают в высоту.
        let narrow = block.columns > 1
        let isCancelled = [PlannerPayBadge.cancelled, .fineUnpaid, .finePaid].contains(block.badge)
        // У отменённого остаётся только большой знак запрета, маленький справа вверху не нужен.
        let badgeSymbol: String? = isCancelled ? nil : (block.badgeOverride.map { $0.isEmpty ? nil : $0 } ?? block.badge.symbol)
        let leadingView: AnyView? = Self.leadingView(for: block)
        let hasMark = badgeSymbol != nil || block.together || !block.emoji.isEmpty || !block.corner.isEmpty || leadingView != nil
        let topRow = hasMark && height >= 30
        let topInset: CGFloat = topRow ? 11 : 1
        let trailingInset: CGFloat = (hasMark && !topRow) ? 15 : 1
        let textWidth = max(10, columnWidth / CGFloat(max(block.columns, 1)) - 6 - (trailingInset - 1))
        let availHeight = max(6, height - topInset - 2)
        let maxFont: CGFloat = isDayMode ? 22 : 18
        let fit = Self.titleLayout(block.title, width: textWidth, height: availHeight, maxFont: maxFont)
        let lineCount = CGFloat(fit.lines)
        let fontSize = fit.font
        let showTime = !narrow && availHeight > fontSize * lineCount * 1.2 + 14
        let showCourtNote = block.court == .confirmed && !narrow && availHeight > fontSize * lineCount * 1.2 + 28
        let content = VStack(alignment: .leading, spacing: 0) {
            // Одним текстом, чтобы при нехватке места обе строки уменьшались вместе.
            Text(fit.text)
                .font(.system(size: fontSize, weight: isCancelled ? .black : .bold))
                .lineLimit(fit.lines)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .multilineTextAlignment(.leading)
            if showTime {
                Text("\(PlannerCalendar.time(block.start))–\(PlannerCalendar.time(block.end))")
                    .font(.system(size: isDayMode ? 12 : 10, weight: isCancelled ? .bold : .medium))
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if showCourtNote {
                Text("✓ Корт подтверждён, YClients")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, trailingInset)
        .padding(.top, topInset)
        .padding(.bottom, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topLeading) {
            // Эмодзи типа дела стоит в верхней строке, название записи ниже него.
            if topRow, let leadingView {
                leadingView.padding(1)
            } else if topRow, !block.emoji.isEmpty {
                Text(block.emoji).font(.system(size: 10)).padding(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if !block.corner.isEmpty { Text(block.corner).font(.system(size: 10)) }
                if block.together { Text("💞").font(.system(size: 10)) }
                if let symbol = badgeSymbol {
                    Text(symbol).font(.system(size: 11))
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
            let fromYClients = event.isFromYClients || block.court == .confirmed
            let base = content
                .opacity(cancelled ? 0.55 : 1)
                .foregroundStyle(fromYClients ? Color.primary : Color.black)
                .background(
                    Group {
                        if fromYClients {
                            // Записи YClients: прозрачный жёлтый фон с обводкой, как ремонты авто.
                            // Подтверждённый корт: то же, но цвета подтверждения (оранжевый).
                            let tint = block.court == .confirmed ? block.color : Color.yellow
                            RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.35))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint))
                        } else if block.court == .request {
                            // Ждём подтверждения корта: белая запись с тонкой обводкой.
                            RoundedRectangle(cornerRadius: 6).fill(block.color)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.5)))
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(block.color)
                        }
                    }
                )
                .overlay {
                    // Отменённое занятие или группа: бледный блок с большим знаком запрета.
                    if cancelled {
                        // Без GeometryReader: знак сам уменьшается до размера блока.
                        Text("🚫")
                            .font(.system(size: 60))
                            .minimumScaleFactor(0.1)
                            .lineLimit(1)
                            .opacity(0.75)
                            .padding(2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onEventTap(event, block.start) }
            if canMove(event) && !event.isAllDay {
                base.gesture(moveGesture(
                    block: block, index: index, range: range,
                    slotHeight: slotHeight, columnWidth: columnWidth,
                    commit: { onMove(event, block.start, $0) }
                ))
            } else {
                base
            }
        case .external(let item):
            let base = content
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(item.detail == nil ? Color.gray.opacity(0.25) : item.color.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(item.detail == nil ? Color.gray : item.color, style: StrokeStyle(lineWidth: 1, dash: item.detail == nil ? [3, 2] : [])))
                )
                .contentShape(Rectangle())
                .onTapGesture { if item.detail != nil { onExternalTap(item) } }
            if canMoveExternal(item) {
                base.gesture(moveGesture(
                    block: block, index: index, range: range,
                    slotHeight: slotHeight, columnWidth: columnWidth,
                    commit: { onExternalMove(item, $0) }
                ))
            } else {
                base
            }
        }
    }

    /// Зажать блок и перетащить: на другое время или в другой день.
    private func moveGesture(
        block: PlannerTimelineBlock, index: Int,
        range: Range<Int>, slotHeight: CGFloat, columnWidth: CGFloat,
        commit: @escaping (Date) -> Void
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
                    commit(newStart)
                }
            }
    }

    // MARK: - Раскладка пересекающихся блоков

    private func layout(_ day: Date) -> [PlannerTimelineBlock] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = PlannerCalendar.addDays(1, to: dayStart)
        let minimum: TimeInterval = 15 * 60

        var raw: [PlannerTimelineBlock] = []
        for occurrence in events.occurrences(on: day) where !occurrence.event.isAllDay && !isHidden(occurrence.event, day) {
            let start = max(occurrence.start, dayStart)
            let end = min(max(occurrence.end, start.addingTimeInterval(minimum)), dayEnd)
            raw.append(PlannerTimelineBlock(
                id: occurrence.id, source: .event(occurrence.event),
                title: occurrence.event.plainTitle,
                color: colorFor(occurrence.event, day), start: start, end: end,
                badge: badge(occurrence.event, day), owner: ownerLetter(occurrence.event),
                emoji: (occurrence.event.errandType.isEmpty || occurrence.event.scopeValue == .shared)
                    ? ""
                    : (errandEmojis[occurrence.event.errandType.lowercased()] ?? "💼"),
                together: occurrence.event.scopeValue == .shared,
                badgeOverride: badgeEmoji(occurrence.event, day),
                court: courtState(occurrence.event, day)
            ))
        }
        for item in externalItems(day) {
            let start = max(item.start, dayStart)
            let end = min(max(item.end, start.addingTimeInterval(minimum)), dayEnd)
            raw.append(PlannerTimelineBlock(
                id: item.id, source: .external(item), title: item.title,
                color: item.color, start: start, end: end, badge: .none, owner: nil,
                corner: item.emoji
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
        case external(CalendarItem)
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
    /// Эмодзи в правом верхнем углу (записи других разделов).
    var corner = ""
    var together = false
    /// Настроенное эмодзи статуса: `nil` — обычное, пустое — не показывать.
    var badgeOverride: String? = nil
    var court: PlannerCourtState = .none
    var columns = 1
}
