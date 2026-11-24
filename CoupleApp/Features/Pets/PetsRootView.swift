import SwiftData
import SwiftUI

/// Главный экран «Питомцы»: сетка карточек.
struct PetsRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PetsPet> { $0.deletedAt == nil }, sort: \PetsPet.createdAt)
    private var pets: [PetsPet]

    @Query(filter: #Predicate<PetsTask> { $0.deletedAt == nil }, sort: \PetsTask.createdAt)
    private var tasks: [PetsTask]

    @State private var adding = false

    /// Меняется при любых правках питомцев и дел (в том числе со второго телефона): тогда уведомления пересоздаются.
    private var signature: String {
        (pets.map { "\($0.syncID)\($0.updatedAt.timeIntervalSince1970)" }
            + tasks.map { "\($0.syncID)\($0.updatedAt.timeIntervalSince1970)\($0.isDone)" }).joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(pets) { pet in
                        NavigationLink {
                            PetsDetailView(pet: pet)
                        } label: {
                            card(pet)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                if pets.isEmpty {
                    ContentUnavailableView("Пока никого", systemImage: "pawprint.fill",
                                           description: Text("Добавьте питомца кнопкой «+»."))
                }
            }
            .navigationTitle("Питомцы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $adding) {
                PetsFormView(pet: nil)
            }
            .refreshable { await sync.syncNow() }
        }
        .petsCatVisit()
        .onAppear {
            PetsSeed.seedIfNeeded(context: context)
            PetsSeed.applyBreedsIfNeeded(context: context)
            sync.requestSync()
        }
        .task(id: signature) {
            PetsNotifications.reschedule(pets: pets, tasks: tasks)
        }
    }

    private func card(_ pet: PetsPet) -> some View {
        VStack(spacing: 10) {
            PetsAvatar(pet: pet, size: 96)
            Text(pet.displayName).font(.headline)
            Text(subtitle(pet)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func subtitle(_ pet: PetsPet) -> String {
        var parts = [pet.breed.isEmpty ? pet.species : pet.breed]
        if let age = PetsAge.text(pet) { parts.append(age) }
        if pet.weightKg > 0 { parts.append(String(format: "%.1f кг", pet.weightKg)) }
        return parts.joined(separator: " · ")
    }
}

/// Карточка питомца: данные, внимание, быстрые кнопки, дела по здоровью и траты.
struct PetsDetailView: View {
    let pet: PetsPet
    private enum DetailSheet: String, Identifiable {
        case edit, entry, task
        var id: String { rawValue }
    }

    /// Одно окно за раз: две кнопки в одной строке списка не должны открывать окна одновременно.
    @State private var sheet: DetailSheet?

    @Query(filter: #Predicate<PetsTask> { $0.deletedAt == nil }) private var allTasks: [PetsTask]
    @Query(filter: #Predicate<PetsEntry> { $0.deletedAt == nil }) private var allEntries: [PetsEntry]

    var body: some View {
        let tasks = allTasks.filter { $0.petID == pet.syncID }
        let alerts = PetsAlerts.alerts(pet: pet, tasks: tasks)
        let spent = allEntries.filter { $0.petID == pet.syncID }.reduce(0) { $0 + $1.amount }
        List {
            Section {
                VStack(spacing: 6) {
                    PetsAvatar(pet: pet, size: 140)
                    ageBlock
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if !alerts.isEmpty {
                Section("Внимание") {
                    ForEach(alerts) { alert in
                        Label(alert.text, systemImage: alert.urgent ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(alert.urgent ? .red : .orange)
                    }
                }
            }
            Section {
                HStack(spacing: 12) {
                    quickButton("💸", "Трата") { sheet = .entry }
                    quickButton("🩺", "Что сделать") { sheet = .task }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                NavigationLink { PetsTasksView(pet: pet) } label: {
                    Label("Здоровье и дела", systemImage: "cross.case")
                }
                NavigationLink { PetsSpendingView(pet: pet) } label: {
                    HStack {
                        Label("Траты", systemImage: "rublesign.circle")
                        Spacer()
                        Text(CarFormat.money(spent)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("О питомце") {
                LabeledContent("Вид", value: pet.species)
                if !pet.breed.isEmpty { LabeledContent("Порода", value: pet.breed) }
                if let b = pet.birthday {
                    LabeledContent("День рождения", value: b.formatted(date: .long, time: .omitted))
                }
                if let age = PetsAge.text(pet) { LabeledContent("Возраст", value: age) }
                if pet.weightKg > 0 {
                    LabeledContent("Вес", value: String(format: "%.1f кг", pet.weightKg))
                }
                if !pet.note.isEmpty { Text(pet.note) }
            }
            Section("Прививки и врач") {
                Text(pet.vetNote.isEmpty ? "Пока пусто. Нажмите «Изменить», чтобы записать прививки и визиты." : pet.vetNote)
                    .foregroundStyle(pet.vetNote.isEmpty ? .secondary : .primary)
            }
        }
        .navigationTitle(pet.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Изменить") { sheet = .edit } }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .edit: PetsFormView(pet: pet)
            case .entry: PetsEntryFormView(pet: pet, entry: nil)
            case .task: PetsTaskFormView(pet: pet, task: nil)
            }
        }
    }

    /// Под аватаркой: дата рождения, крупно полные годы, мелко месяцы и дни.
    @ViewBuilder
    private var ageBlock: some View {
        if let birthday = pet.birthday {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: birthday, to: .now)
            let years = max(0, parts.year ?? 0)
            let months = max(0, parts.month ?? 0)
            let days = max(0, parts.day ?? 0)
            VStack(spacing: 2) {
                Text("🎂 \(birthday.formatted(date: .long, time: .omitted))")
                    .font(.footnote).foregroundStyle(.secondary)
                if years > 0 {
                    Text("\(years) \(yearWord(years))").font(.title2.weight(.bold))
                    Text("\(months) мес. \(days) дн.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(months) мес.").font(.title2.weight(.bold))
                    Text("\(days) дн.").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Указать день рождения") { sheet = .edit }
                .font(.footnote)
                .buttonStyle(.borderless)
        }
    }

    private func yearWord(_ n: Int) -> String {
        let last = n % 10, two = n % 100
        if two >= 11 && two <= 14 { return "лет" }
        if last == 1 { return "год" }
        if (2...4).contains(last) { return "года" }
        return "лет"
    }

    /// Аккуратная кнопка: маленький эмодзи и текст по центру.
    private func quickButton(_ emoji: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji).font(.subheadline)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.pink.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

/// Добавление и правка питомца.
struct PetsFormView: View {
    let pet: PetsPet?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync

    @State private var name: String
    @State private var species: String
    @State private var breed: String
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var weightText: String
    @State private var note: String
    @State private var vetNote: String
    @State private var confirmDelete = false

    init(pet: PetsPet?) {
        self.pet = pet
        _name = State(initialValue: pet?.name ?? "")
        _species = State(initialValue: pet?.species ?? "Кот")
        _breed = State(initialValue: pet?.breed ?? "")
        _hasBirthday = State(initialValue: pet?.birthday != nil)
        _birthday = State(initialValue: pet?.birthday ?? .now)
        _weightText = State(initialValue: (pet?.weightKg ?? 0) > 0 ? String(pet!.weightKg) : "")
        _note = State(initialValue: pet?.note ?? "")
        _vetNote = State(initialValue: pet?.vetNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Кличка", text: $name)
                    TextField("Вид", text: $species)
                    TextField("Порода", text: $breed)
                    Toggle("Знаю день рождения", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Дата", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                    LabeledContent("Вес, кг") {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Заметка") { TextField("Характер, любимое", text: $note, axis: .vertical) }
                Section("Прививки и врач") { TextField("Что и когда сделано", text: $vetNote, axis: .vertical) }
                if pet != nil {
                    Section {
                        Button("Удалить питомца", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(pet == nil ? "Новый питомец" : "Питомец")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Удалить питомца?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    pet?.markDeleted()
                    try? context.save()
                    sync.requestSync()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let target = pet ?? PetsPet(name: name)
        target.name = name
        target.species = species
        target.breed = breed
        target.birthday = hasBirthday ? birthday : nil
        target.weightKg = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        target.note = note
        target.vetNote = vetNote
        if pet == nil { context.insert(target) }
        target.markChanged()
        try? context.save()
        sync.requestSync()
        dismiss()
    }
}
