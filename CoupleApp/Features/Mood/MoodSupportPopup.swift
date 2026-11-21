import SwiftData
import SwiftUI

/// Всплывающее окно при открытии приложения: «Платоня желает тебе…».
/// Подключается один раз на корневом экране и ловит новые реакции поддержки от партнёра,
/// в том числе те, что пришли, пока приложение было открыто.
private struct MoodSupportPopupModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account

    @Query(filter: #Predicate<MoodReaction> { $0.deletedAt == nil && $0.seenAt == nil }, sort: \MoodReaction.createdAt)
    private var unseen: [MoodReaction]

    @State private var shownIDs: [UUID] = []

    private var mine: [MoodReaction] {
        unseen.filter { $0.recipient == account.current.rawValue }
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { !mine.isEmpty },
            set: { if !$0 { markSeen() } }
        )) {
            MoodSupportPopupView(reactions: mine, partnerName: account.partnerName, onThanks: markSeen)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(false)
        }
    }

    private func markSeen() {
        for reaction in mine {
            reaction.seenAt = .now
            reaction.markChanged()
        }
        try? context.save()
        sync.requestSync()
    }
}

extension View {
    /// Показывает окно с поддержкой от партнёра, если она ещё не прочитана.
    func moodSupportPopup() -> some View { modifier(MoodSupportPopupModifier()) }
}

struct MoodSupportPopupView: View {
    let reactions: [MoodReaction]
    let partnerName: String
    let onThanks: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            MoodMironSpeech(text: "\(partnerName) о тебе думает. Передаю лично в лапы.") { EmptyView() }
                .padding(.top, 20)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(reactions.suffix(6)) { reaction in
                        HStack(spacing: 14) {
                            Text(reaction.emoji).font(.system(size: 40))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(partnerName) желает тебе")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(reaction.comment.isEmpty ? MoodSupport.title(for: reaction.emoji) : reaction.comment)
                                    .font(.headline)
                                if !reaction.comment.isEmpty, MoodSupport.title(for: reaction.emoji) != reaction.emoji {
                                    Text(MoodSupport.title(for: reaction.emoji))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.appBlush.opacity(0.25)))
                    }
                }
                .padding(.horizontal)
            }

            Button(action: onThanks) {
                Text("Спасибо ❤️").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding([.horizontal, .bottom])
        }
    }
}
