import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The tag editor of `docs/05-design.md` §6.6: every change is saved at once.
struct TagEditorView: View {
    let item: WatchedPullRequest
    let tags: TagStore
    let close: () -> Void
    @State private var input = ""
    @State private var feedback: Feedback?
    @FocusState private var focused: Bool

    private enum Feedback: Equatable {
        case savedAs(String)
        case rejected(Tags.Rejection)
    }

    private var current: [String] { tags.tags(of: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(current, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text(verbatim: tag)
                        Button {
                            tags.remove(tag, from: item.id, ref: item.pullRequest.ref)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove \(tag)", comment: "Tag editor: remove a tag"))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.fillTag))
                }
                TextField(String(localized: "Add tag", comment: "Tag editor field"), text: $input)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                    .onChange(of: input) { _, value in
                        if value.hasSuffix(",") {
                            input = String(value.dropLast())
                            add()
                        } else {
                            preview()
                        }
                    }
                    .onKeyPress(.delete) {
                        guard input.isEmpty, let last = current.last else { return .ignored }
                        tags.remove(last, from: item.id, ref: item.pullRequest.ref)
                        return .handled
                    }
                    .onExitCommand(perform: close)
            }
            if let feedback {
                feedbackLine(feedback)
            }
            Divider()
            Text("Suggestions", comment: "Tag editor section").font(.subheadline).foregroundStyle(Color.textSecondary)
            HStack(spacing: 6) {
                ForEach(Tags.suggestions(inUse: tags.inUse, prefix: input, excluding: current), id: \.self) { tag in
                    Button(tag) {
                        input = tag
                        add()
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            }
            HStack {
                Spacer()
                Text("\(current.count) of \(Tags.maximumPerPullRequest)", comment: "Tag editor counter")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Color.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { focused = true }
    }

    private func add() {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch tags.add(input, to: item.id, ref: item.pullRequest.ref) {
        case .success(let tag):
            feedback = tag == input ? nil : .savedAs(tag)
            input = ""
        case .failure(let rejection):
            feedback = .rejected(rejection)
        }
    }

    private func preview() {
        guard !input.isEmpty else {
            feedback = nil
            return
        }
        switch Tags.validate(input, existing: current) {
        case .success(let tag): feedback = tag == input ? nil : .savedAs(tag)
        case .failure(let rejection): feedback = .rejected(rejection)
        }
    }

    @ViewBuilder
    private func feedbackLine(_ feedback: Feedback) -> some View {
        switch feedback {
        case .savedAs(let tag):
            Text("Saved as \(tag)", comment: "Tag editor: normalization feedback")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
        case .rejected(let rejection):
            Label(Self.message(rejection), systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
        }
    }

    static func message(_ rejection: Tags.Rejection) -> String {
        switch rejection {
        case .invalidCharacters: String(localized: "Tags use letters, digits and hyphens", comment: "Tag rejected")
        case .tooLong: String(localized: "Tags are up to 24 characters", comment: "Tag rejected")
        case .alreadyAdded: String(localized: "Already added", comment: "Tag rejected")
        case .tooMany: String(localized: "Up to 5 tags per pull request", comment: "Tag rejected")
        case .empty: String(localized: "Type a tag", comment: "Tag rejected: empty")
        }
    }
}
