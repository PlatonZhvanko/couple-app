import SwiftData
import SwiftUI

/// Главный экран «Питомцы»: сетка карточек.
struct PetsRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<PetsPet> { $0.deletedAt == nil }, sort: \PetsPet.createdAt)
    private var pets: [PetsPet]

    @State private var editing: PetsPet?
    @State private var adding = false

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
        .onAppear {
            PetsSeed.seedIfNeeded(context: context)
            sync.requestSync()
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
        var parts = [pet.species]
        if let b = pet.birthday {
            let years = Calendar.current.dateComponents([.year], from: b, to: .now).year ?? 0
            parts.append(years > 0 ? "\(years) г." : "малыш")
        }
        if pet.weightKg > 0 { parts.append(String(format: "%.1f кг", pet.weightKg)) }
        return parts.joined(separator: " · ")
    }
}

/// Карточка питомца.
struct PetsDetailView: View {
    let pet: PetsPet
    @State private var editing = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    PetsAvatar(pet: pet, size: 140)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("О питомце") {
                LabeledContent("Вид", value: pet.species)
                if let b = pet.birthday {
                    LabeledContent("День рождения", value: b.formatted(date: .long, time: .omitted))
                }
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
            ToolbarItem(placement: .topBarTrailing) { Button("Изменить") { editing = true } }
        }
        .sheet(isPresented: $editing) { PetsFormView(pet: pet) }
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
