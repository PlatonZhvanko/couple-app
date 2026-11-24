import SwiftData
import SwiftUI

/// Планер «Олимпик»: колонки — корты, слева время. Копия журнала YClients, только для просмотра.
struct PlannerOlimpicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @Query(filter: #Predicate<PlannerOlimpicDay> { $0.deletedAt == nil })
    private var days: [PlannerOlimpicDay]
    /// Глазик: показывать ли «не пришёл» (по умолчанию показаны, как просил владелец: «не скрыто»).
    @AppStorage("planner.olimpic.hideNoShow") private var hideNoShow = false
    @State private var selectedDay = PlannerCalendar.calendar.startOfDay(for: .now)
    @State private var detail: PlannerOlimpicDay.Booking?
    @State private var showDatePicker = false
    /// Свежие данные, полученные сейчас из YClients (через функцию Supabase).
    @State private var live: [String: PlannerOlimpicDay.Payload] = [:]
    @State private var loading = false
    @State private var loadFailed = false

    private let timeWidth: CGFloat = 44
    private let firstSlot = 14   // 7:00
    private let lastSlot = 48    // 0:00
    private var cal: Calendar { PlannerCalendar.calendar }

    private var dayKey: String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDay)
    }

    private var record: PlannerOlimpicDay? { days.first { $0.day == dayKey } }

    /// Что показываем: свежий ответ, иначе сохранённое в памяти телефона, иначе копию с сервера синхронизации.
    private var shown: PlannerOlimpicDay.Payload? {
        live[dayKey] ?? PlannerOlimpicCache.load(dayKey) ?? record?.payload
    }

    private func refresh() async {
        let key = dayKey
        guard let client = account.client else { loadFailed = true; return }
        loading = true
        defer { loading = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["action": "olimpic", "day": key])
            let data = try await client.callFunction("yclients-sync", body: body)
            let payload = try JSONDecoder().decode(PlannerOlimpicDay.Payload.self, from: data)
            live[key] = payload
            PlannerOlimpicCache.save(payload, key: key)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Колонки кортов: берём с любого дня, чтобы набор не «прыгал» на пустых днях.
    private var courts: [PlannerOlimpicDay.Court] {
        if let own = shown?.courts, !own.isEmpty { return own }
        return days.max(by: { $0.day < $1.day })?.courts ?? []
    }

    private var bookings: [PlannerOlimpicDay.Booking] {
        (shown?.bookings ?? []).filter { !(hideNoShow && $0.status == "noshow") }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func start(_ b: PlannerOlimpicDay.Booking) -> Date? { Self.isoFormatter.date(from: b.start) }

    private func color(_ status: String) -> Color {
        switch status {
        case "arrived": return Color.blue.opacity(0.55)
        case "confirmed": return Color.green.opacity(0.6)
        case "noshow": return Color.red.opacity(0.4)
        default: return Color.yellow.opacity(0.65)
        }
    }

    private func statusName(_ status: String) -> String {
        switch status {
        case "arrived": return "Пришёл"
        case "confirmed": return "Подтверждён"
        case "noshow": return "Не пришёл"
        default: return "Ожидание"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            GeometryReader { geo in
                let columnWidth = max(48, (geo.size.width - timeWidth) / CGFloat(max(courts.count, 1)))
                let slots = lastSlot - firstSlot
                let headerHeight: CGFloat = 34
                let fit = (geo.size.height - headerHeight - 8) / CGFloat(slots)
                let slotHeight = max(fit, 15)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(width: timeWidth, height: headerHeight)
                            timeColumn(slotHeight: slotHeight)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(courts, id: \.id) { court in
                                        Text(court.name)
                                            .font(.system(size: 9, weight: .semibold))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.7)
                                            .frame(width: columnWidth, height: headerHeight)
                                    }
                                }
                                .background(Color(.secondarySystemBackground))
                                HStack(spacing: 0) {
                                    ForEach(courts, id: \.id) { court in
                                        courtColumn(court, width: columnWidth, slotHeight: slotHeight)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollDisabled(fit >= 15)
                .overlay {
                    if courts.isEmpty {
                        Group {
                            if loading { ProgressView("Загружаю журнал…") }
                            else { Text("Нет интернета: журнал посмотреть нельзя.\nКак только появится связь, он загрузится сам.") }
                        }
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: dayKey) { await refresh() }
        .task {
            // Пока экран открыт и связи не было, пробуем снова.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if loadFailed || shown == nil { await refresh() }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 70, abs(dx) > abs(value.translation.height) * 2 else { return }
                move(dx < 0 ? 1 : -1)
            }
        )
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("День", selection: Binding(
                    get: { selectedDay },
                    set: { selectedDay = cal.startOfDay(for: $0) }
                ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Какой день смотреть")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Сегодня") { selectedDay = cal.startOfDay(for: .now) }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $detail) { booking in
            detailView(booking)
                .presentationDetents([.height(260)])
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark") }
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            VStack(spacing: 0) {
                Text("Олимпик").font(.caption.weight(.semibold)).foregroundStyle(Color.plannerToday)
                Label(PlannerCalendar.dayTitle(selectedDay), systemImage: "calendar").font(.headline)
            }
            .frame(minWidth: 150)
            .contentShape(Rectangle())
            .onTapGesture { showDatePicker = true }
            Button { move(1) } label: { Image(systemName: "chevron.right") }
            Spacer()
            Button { withAnimation { hideNoShow.toggle() } } label: {
                Image(systemName: hideNoShow ? "eye.slash" : "eye.fill")
                    .foregroundStyle(hideNoShow ? Color.secondary : Color.plannerToday)
            }
            .accessibilityLabel(hideNoShow ? "Показать «не пришёл»" : "Скрыть «не пришёл»")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func move(_ step: Int) {
        withAnimation { selectedDay = PlannerCalendar.addDays(step, to: cal.startOfDay(for: selectedDay)) }
    }

    private func timeColumn(slotHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(firstSlot..<lastSlot, id: \.self) { slot in
                let isHour = slot % 2 == 0
                Text(String(format: "%d:%02d", slot / 2, isHour ? 0 : 30))
                    .font(.system(size: isHour ? 11 : 9, weight: isHour ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isHour ? Color.primary : Color.secondary)
                    .fixedSize()
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(slot - firstSlot) * slotHeight - 7)
            }
        }
        .frame(width: timeWidth, height: slotHeight * CGFloat(lastSlot - firstSlot), alignment: .topTrailing)
        .padding(.top, 6)
    }

    private func courtColumn(_ court: PlannerOlimpicDay.Court, width: CGFloat, slotHeight: CGFloat) -> some View {
        let dayStart = cal.startOfDay(for: selectedDay)
        let origin = dayStart.addingTimeInterval(Double(firstSlot * 30 * 60))
        let perSecond = slotHeight / (30 * 60)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(firstSlot..<lastSlot, id: \.self) { slot in
                    Rectangle().fill(Color.clear)
                        .frame(height: slotHeight)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.secondary.opacity(slot % 2 == 0 ? 0.3 : 0.12)).frame(height: 0.5)
                        }
                }
            }
            ForEach(bookings.filter { $0.court == court.id }) { b in
                if let begin = start(b) {
                    let top = begin.timeIntervalSince(origin) * perSecond
                    let height = max(Double(b.length) * perSecond - 1, 8)
                    if top + height > 0 {
                        block(b, begin: begin, width: width, height: height)
                            .offset(y: top)
                    }
                }
            }
        }
        .frame(width: width, height: slotHeight * CGFloat(lastSlot - firstSlot))
        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5) }
        .padding(.top, 6)
    }

    private func block(_ b: PlannerOlimpicDay.Booking, begin: Date, width: CGFloat, height: CGFloat) -> some View {
        let end = begin.addingTimeInterval(Double(b.length))
        return VStack(alignment: .leading, spacing: 0) {
            Text(b.client).font(.system(size: 9, weight: .semibold)).lineLimit(height > 36 ? 3 : 1)
            if height > 24 {
                Text("\(timeText(begin))–\(timeText(end))").font(.system(size: 8).monospacedDigit())
            }
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(width: width - 2, height: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4).fill(color(b.status)))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .onTapGesture { detail = b }
    }

    private func timeText(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Просмотр записи: только чтение.
    private func detailView(_ b: PlannerOlimpicDay.Booking) -> some View {
        let begin = start(b) ?? .now
        let end = begin.addingTimeInterval(Double(b.length))
        let court = courts.first { $0.id == b.court }?.name ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text(b.client).font(.title3.weight(.semibold))
            Label("\(timeText(begin))–\(timeText(end))", systemImage: "clock")
            if !court.isEmpty { Label(court, systemImage: "tennisball") }
            if let service = b.service, !service.isEmpty { Label(service, systemImage: "list.bullet") }
            Label(statusName(b.status), systemImage: "circle.fill").foregroundStyle(color(b.status))
            Text("Только просмотр: запись берётся из YClients.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
