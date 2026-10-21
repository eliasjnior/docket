import AppKit
import DocketStores
import SwiftUI

/// When no poll can run, one centred screen replaces the sections (`docs/05-design.md` §7.1).
enum FullScreen: Equatable {
    case ghNotFound
    case signedOut
    case missingScopes([String])
    case loading

    @MainActor
    static func `for`(watch: WatchStore) -> FullScreen? {
        switch watch.account {
        case .ghNotFound: .ghNotFound
        case .signedOut: .signedOut
        case .missingScopes(let scopes): .missingScopes(scopes)
        case .loading: watch.hasCache ? nil : .loading
        case .ready: nil
        }
    }
}

struct FullScreenView: View {
    let screen: FullScreen
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 10) {
            switch screen {
            case .loading:
                ProgressView().controlSize(.small)
                Text("Loading pull requests…", comment: "First poll of a launch with no cache").font(.headline)
            case .ghNotFound:
                content(
                    symbol: "terminal", title: String(localized: "GitHub CLI not found", comment: "Full screen title"),
                    body: String(
                        localized: "Docket reads your account through the GitHub CLI. Install it, then sign in.",
                        comment: "Full screen body"),
                    command: "brew install gh")
                HStack {
                    Button(
                        String(localized: "Choose Location…", comment: "Full screen button"),
                        action: actions.chooseGhLocation)
                    Button(String(localized: "Try Again", comment: "Full screen button"), action: actions.retry)
                }
            case .signedOut:
                content(
                    symbol: "person.crop.circle.badge.xmark",
                    title: String(localized: "Sign in to the GitHub CLI", comment: "Full screen title"),
                    body: String(
                        localized: "Run this in Terminal and follow the prompts.", comment: "Full screen body"),
                    command: "gh auth login")
                Button(String(localized: "Try Again", comment: "Full screen button"), action: actions.retry)
            case .missingScopes(let scopes):
                content(
                    symbol: "key",
                    title: String(
                        localized: "The GitHub CLI token is missing \(scopes.joined(separator: " and "))",
                        comment: "Full screen title"),
                    body: String(
                        localized:
                            "Docket needs \(scopes.joined(separator: ", ")) to read your pull requests and teams.",
                        comment: "Full screen body"),
                    command: "gh auth refresh -h github.com -s \(scopes.joined(separator: ","))")
                Button(String(localized: "Try Again", comment: "Full screen button"), action: actions.retry)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(symbol: String, title: String, body: String, command: String) -> some View {
        Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Color.textSecondary)
        Text(verbatim: title).font(.headline).multilineTextAlignment(.center)
        Text(verbatim: body).font(.body).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Text(verbatim: command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button(String(localized: "Copy", comment: "Copies the command")) { actions.row.copy(command) }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.fillTag))
    }
}
