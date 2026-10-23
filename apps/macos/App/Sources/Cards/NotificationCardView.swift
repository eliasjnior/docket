import SwiftUI

/// One card: the repository's square with the kind's symbol, the headline, the title, then actions.
struct NotificationCardView: View {
    let card: NotificationCard
    let actions: CardActions
    @State private var isHovered = false
    @State private var countdown: CardCountdown

    init(card: NotificationCard, actions: CardActions) {
        self.card = card
        self.actions = actions
        _countdown = State(initialValue: CardCountdown(lifetime: card.lifetime, startedAt: Date()))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                header
                Text(verbatim: card.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if let title = card.title {
                    Text(verbatim: title).font(.subheadline).foregroundStyle(Color.textPrimary.opacity(0.85))
                        .lineLimit(2)
                }
                if !card.detail.isEmpty {
                    Text(verbatim: card.detail).font(.caption).foregroundStyle(Color.textSecondary)
                        .lineLimit(card.title == nil ? 4 : 1)
                }
                buttons.padding(.top, 6)
            }
        }
        .padding(12)
        .frame(width: CardStackView.cardWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            // An approval is good news, and looks it.
            if card.kind == .approved {
                RoundedRectangle(cornerRadius: 14).fill(Color.statusReady.opacity(0.12))
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    card.isSticky || card.kind == .approved
                        ? card.kind.color.opacity(0.55) : Color(nsColor: .separatorColor))
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { actions.open(card) }
        .onHover { hovering in
            isHovered = hovering
            if hovering { countdown.freeze(at: Date()) } else { countdown.resume(at: Date()) }
        }
        .task(id: isHovered) {
            guard !card.isSticky, !isHovered else { return }
            do {
                try await Task.sleep(for: .seconds(countdown.remaining(at: Date())))
                actions.dismiss(card.id)
            } catch {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: [card.kind.label, card.headline, card.title ?? ""].joined(separator: ", ")))
    }

    private var badge: some View {
        let repository = card.repository ?? "Docket"
        let name = repository.split(separator: "/").last.map(String.init) ?? repository
        return Text(verbatim: String(name.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.identity(for: repository)))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: card.kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(card.kind.color))
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 5, y: 5)
            }
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(verbatim: card.kind.label).fontWeight(.semibold).foregroundStyle(card.kind.color)
            if let repository = card.repository {
                Text(verbatim: "·").foregroundStyle(Color.textTertiary)
                Text(verbatim: repository).foregroundStyle(Color.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button {
                actions.dismiss(card.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.fillTag))
                    .overlay { if !card.isSticky { countdownRing } }
            }
            .buttonStyle(.plain)
            .opacity(isHovered || !card.isSticky ? 1 : 0)
            .accessibilityLabel(Text("Dismiss", comment: "Card button"))
        }
        .font(.caption)
    }

    /// The time left, as a ring that empties clockwise around `✕`; it stops while the pointer is on the card.
    private var countdownRing: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isHovered)) { context in
            Circle()
                .trim(from: 0, to: countdown.fraction(at: context.date))
                .stroke(card.kind.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: -1)
        }
        .padding(1)
        .accessibilityHidden(true)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button(card.primaryAction) { actions.open(card) }
                .buttonStyle(.borderedProminent)
                .tint(card.kind.color)
            if card.kind.offersReview, card.pullRequestID != nil, actions.canReviewWithAI(card) {
                Button(String(localized: "Review with AI", comment: "Card button")) { actions.reviewWithAI(card) }
                    .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
            Button(
                card.isSticky
                    ? String(localized: "Later", comment: "Card button: dismiss a review request for now")
                    : String(localized: "Dismiss", comment: "Card button")
            ) {
                actions.dismiss(card.id)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
        }
        .controlSize(.small)
        .font(.caption.weight(.medium))
    }
}

extension NotificationCard.Kind {
    var label: String {
        switch self {
        case .reviewRequested: String(localized: "Review requested", comment: "Card kind")
        case .approved: String(localized: "Approved", comment: "Card kind")
        case .changesRequested: String(localized: "Changes requested", comment: "Card kind")
        case .reviewed: String(localized: "Reviewed", comment: "Card kind")
        case .comment: String(localized: "Comment", comment: "Card kind")
        case .reply: String(localized: "Reply", comment: "Card kind")
        case .checksFailed: String(localized: "Checks failed", comment: "Card kind")
        case .merged: String(localized: "Merged", comment: "Card kind")
        case .closed: String(localized: "Closed", comment: "Card kind")
        case .mention: String(localized: "Mention", comment: "Card kind")
        case .reminder: String(localized: "Still waiting", comment: "Card kind: a reminder")
        case .summary: String(localized: "Docket", comment: "Card kind: several updates")
        }
    }

    var symbol: String {
        switch self {
        case .reviewRequested: "eye.fill"
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "arrow.uturn.backward"
        case .reviewed, .comment: "text.bubble.fill"
        case .reply: "arrowshape.turn.up.left.fill"
        case .checksFailed: "xmark"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle.fill"
        case .mention: "at"
        case .reminder: "clock.fill"
        case .summary: "tray.full.fill"
        }
    }

    var color: Color {
        switch self {
        case .reviewRequested, .reminder: .statusWaiting
        case .approved: .statusReady
        case .changesRequested: .statusAttention
        case .checksFailed, .closed: .statusBlocking
        case .merged: Color(nsColor: .systemPurple)
        case .mention: Color(nsColor: .systemIndigo)
        case .reviewed, .comment, .reply: .statusNeutral
        case .summary: .accent
        }
    }

    var offersReview: Bool { self == .reviewRequested || self == .reminder }
}

extension NotificationCard {
    /// A card about several pull requests opens the popover, filtered to the repository.
    var primaryAction: String {
        if url == nil { return String(localized: "Open Docket", comment: "Card button") }
        return kind.offersReview
            ? String(localized: "Review", comment: "Card button: open the pull request")
            : String(localized: "Open", comment: "Card button")
    }
}
