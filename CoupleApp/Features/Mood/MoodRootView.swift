import SwiftData
import SwiftUI

/// Главный экран раздела «Настроение»: мы сегодня, быстрая отметка,
/// поддержка партнёра и записи за сегодня.
struct MoodRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<MoodEntry> { $0.deletedAt == nil }, sort: \MoodEntry.createdAt, order: .reverse)
    private var entries: [MoodEntry]
    @Query(filter: #Predicate<MoodReaction> { $0.deletedAt == nil }, sort: \MoodReaction.createdAt, order: .reverse)
    private var reactions: [MoodReaction]

    @Query(filter: #Predicate<MoodDayCheckIn> { $0.deletedAt == nil }, sort: \MoodDayCheckIn.createdAt, order: .reverse)
    private var checkIns: [MoodDayCheckIn]

    @AppStorage("mood.checkin.autoPromptDay") private var autoPromptDay = ""
    @State private var showCheckIn = false
    @State private var showAllSupport = false
    @State private var showSleep = false
    @State private var newWishEmoji = ""
    @State private var newWishText = ""
    @AppStorage("mood.support.custom") private var customSupportRaw = ""
    @State private var insight: (item: MoodInsight, text: String)?
    @State private var editor: EditorTarget?
    @State private var sentEmoji: String?
    @State private var supportComment = ""

    /// Что открыть в редакторе.
    enum EditorTarget: Identifiable {
        case new(MoodLevel)
        case edit(MoodEntry)

        var id: String {
            switch self {
            case .new(let level): "new-\(level.rawValue)"
            case .edit(let entry): entry.syncID.uuidString
            }
        }
    }

    private var me: CoupleMember { account.current }

    private func today(of member: CoupleMember) -> [MoodEntry] {
        entries.filter { $0.member == member.rawValue && Calendar.current.isDateInToday($0.createdAt) }
    }

    private func checkIn(of member: CoupleMember) -> MoodDayCheckIn? {
        let key = MoodDayKey.key(for: .now)
        return checkIns.first { $0.member == member.rawValue && $0.dayKey == key }
    }

    private var isEvening: Bool { Calendar.current.component(.hour, from: .now) >= 18 }

    /// Реакции партнёра мне, которые я ещё не видел.
    private var unseenReactions: [MoodReaction] {
        reactions.filter { $0.recipient == me.rawValue && $0.seenAt == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    mironCard
                }

                if !unseenReactions.isEmpty {
                    Section {
                        reactionsBanner
                    }
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        MoodTodayCard(name: account.myName, entries: today(of: me), checkIn: checkIn(of: me))
                        MoodTodayCard(name: account.partnerName, entries: today(of: me.other), checkIn: checkIn(of: me.other))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Мы сегодня")
                }

                Section {
                    supportRow
                } header: {
                    Text("Поддержать: \(account.partnerName)")
                } footer: {
                    if let sentEmoji {
                        Text("\(sentEmoji) отправлено. \(account.partnerName) увидит, когда откроет приложение.")
                    }
                }

                Section("Мои отметки за сегодня") {
                    let mine = today(of: me)
                    if mine.isEmpty {
                        Text("Пока нет отметок")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mine) { entry in
                            Button { editor = .edit(entry) } label: {
                                MoodEntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        MoodHistoryView()
                    } label: {
                        Label("История и графики", systemImage: "chart.xyaxis.line")
                    }
                    Button { showSleep = true } label: {
                        Label("Сон: записи и график", systemImage: "bed.double")
                    }
                    NavigationLink {
                        MoodInsightsView()
                    } label: {
                        Label("Мироня заметил", systemImage: "sparkles")
                    }
                    NavigationLink {
                        MoodReminderSettingsView()
                    } label: {
                        Label("Напоминание", systemImage: "bell")
                    }
                }
            }
            .navigationTitle("Настроение")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = .new(.okay) } label: { Label("Быстрая отметка", systemImage: "plus") }
                }
            }
            .catVisit(.miron, topic: Calendar.current.component(.hour, from: .now) >= 20 ? .goodNight : .mood)
            .refreshable { await sync.syncNow() }
            .onAppear(perform: onAppear)
            .sheet(isPresented: $showSleep) {
                SleepRootView()
            }
            .sheet(isPresented: $showCheckIn) {
                MoodCheckInView(existing: checkIn(of: me))
            }
            .sheet(item: $editor) { target in
                switch target {
                case .new(let level): MoodEntryEditor(initialLevel: level)
                case .edit(let entry): MoodEntryEditor(entry: entry)
                }
            }
        }
    }

    // MARK: - Мироня

    private func onAppear() {
        MoodReminder.refreshIfEnabled()
        MoodSleepReminder.refreshIfEnabled()
        let days = MoodInsights.collect(context: context, member: me)
        let list = MoodInsights.insights(from: days)
        let good = (days.last?.mood ?? 0) >= 4
        let shortSleep = (days.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil } ?? 8) < 6.5
        insight = MoodInsights.gentleInsight(list, goodMood: good, preferSleep: shortSleep)

        // Вечером при первом заходе за день Мироня сам спрашивает итог дня.
        let key = MoodDayKey.key(for: .now)
        if isEvening, checkIn(of: me) == nil, autoPromptDay != key {
            autoPromptDay = key
            showCheckIn = true
        }
    }

    private var mironCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MoodMironAvatar(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Мироня")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let done = checkIn(of: me) {
                        Text("\(MoodMiron.thanks(for: .now)) Итог дня: \(done.level.emoji) \(done.overall)/5")
                            .font(.headline)
                    } else {
                        Text(MoodMiron.question(for: .now))
                            .font(.headline)
                    }
                }
            }
            Button {
                showCheckIn = true
            } label: {
                Text(checkIn(of: me) == nil ? "Рассказать про день" : "Изменить итог дня")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let insight {
                Text("🐾 \(insight.text)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Поддержка

    private var reactionsBanner: some View {
        HStack(spacing: 12) {
            Text(unseenReactions.prefix(3).map(\.emoji).joined())
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(account.partnerName) думает о тебе")
                    .font(.headline)
                Text(unseenReactions.prefix(3).map { MoodSupport.title(for: $0.emoji) }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(unseenReactions.filter { !$0.comment.isEmpty }.prefix(2)) { reaction in
                    Text("«\(reaction.comment)»")
                        .font(.subheadline.italic())
                }
            }
            Spacer()
            Button("Спасибо", action: markReactionsSeen)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private static let quickEmojis = Array(MoodSupport.emojis.prefix(3))

    /// Свои пожелания: строки «эмодзи|текст», хранятся на этом телефоне.
    private var customWishes: [(emoji: String, text: String)] {
        customSupportRaw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    private func supportButton(_ emoji: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji).font(.title2)
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    private var supportRow: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        let shownEmojis = showAllSupport ? MoodSupport.emojis : Self.quickEmojis
        return VStack(spacing: 10) {
            TextField("Добавить от себя, по желанию", text: $supportComment, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(shownEmojis, id: \.self) { emoji in
                    supportButton(emoji, title: MoodSupport.title(for: emoji)) { send(emoji) }
                }
                if showAllSupport {
                    ForEach(Array(customWishes.enumerated()), id: \.offset) { _, wish in
                        supportButton(wish.emoji, title: wish.text) { send(wish.emoji, comment: wish.text) }
                    }
                }
            }
            if showAllSupport {
                VStack(spacing: 8) {
                    Text("Своё пожелание")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        TextField("😊", text: $newWishEmoji)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                        TextField("Например: приготовлю ужин", text: $newWishText)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Отправить и сохранить", action: sendCustom)
                        .buttonStyle(.bordered)
                        .disabled(newWishText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Button(showAllSupport ? "Свернуть" : "Показать все и добавить своё") {
                withAnimation { showAllSupport.toggle() }
            }
            .font(.footnote)
        }
        .sensoryFeedback(.success, trigger: sentEmoji)
    }

    private func sendCustom() {
        let text = newWishText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Берём первый символ-эмодзи; если не ввели, ставим сердечко.
        let emoji = newWishEmoji.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "💌"
        guard !text.isEmpty else { return }
        customSupportRaw += "\(emoji)|\(text.replacingOccurrences(of: "\n", with: " "))\n"
        send(emoji, comment: text)
        newWishText = ""
        newWishEmoji = ""
    }

    private func send(_ emoji: String, comment custom: String? = nil) {
        let typed = supportComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [custom, typed].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
        context.insert(MoodReaction(from: me, to: me.other, emoji: emoji, comment: text))
        supportComment = ""
        try? context.save()
        sync.requestSync()
        sentEmoji = emoji
    }

    private func markReactionsSeen() {
        for reaction in unseenReactions {
            reaction.seenAt = .now
            reaction.markChanged()
        }
        try? context.save()
        sync.requestSync()
    }
}

// MARK: - Элементы

/// Карточка «как человек сегодня»: среднее настроение и число отметок.
struct MoodTodayCard: View {
    let name: String
    let entries: [MoodEntry]
    var checkIn: MoodDayCheckIn? = nil

    var body: some View {
        let average = MoodStats.average(entries)
        VStack(spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let average {
                Text(MoodLevel.nearest(to: average).emoji)
                    .font(.system(size: 44))
                Text(MoodLevel.nearest(to: average).title)
                    .font(.caption)
                if let checkIn {
                    Text("итог дня: \(checkIn.level.emoji) \(checkIn.overall)/5")
                        .font(.caption2.weight(.semibold))
                } else if let last = entries.first {
                    Text("в \(last.createdAt.formatted(date: .omitted, time: .shortened)) · отметок: \(entries.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("ещё не отмечено")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill((average.map(MoodLevel.color(for:)) ?? Color.secondary).opacity(0.18))
        )
    }
}

/// Строка одной отметки.
struct MoodEntryRow: View {
    let entry: MoodEntry
    var showsPrivateNote: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.moodLevel.emoji)
                .font(.title)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.moodLevel.title).font(.headline)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !entry.tags.isEmpty {
                    Text(entry.tags.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !entry.note.isEmpty, showsPrivateNote || !entry.isNotePrivate {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if entry.isNotePrivate {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.note)
                            .font(.subheadline)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
