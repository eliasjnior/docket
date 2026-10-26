import DocketStores
import DocketUpdate
import SwiftUI

/// The setup window (`docs/05-design.md` §7.4): the three things Docket needs, in order, each with the button
/// that does it. It re-checks by itself while open, so a step finished in Terminal or the browser ticks off.
struct SetupView: View {
    let setup: SetupStore
    let chooseGhLocation: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AppIconView(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Up Docket", comment: "Setup window title").font(.title3.bold())
                    Text(
                        "Docket reads your pull requests through the GitHub CLI. Three steps, once.",
                        comment: "Setup window subtitle"
                    )
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                ForEach(SetupStore.Step.allCases, id: \.self) { step in
                    SetupStepRow(step: step, state: setup.state(of: step)) { actions(for: step) }
                }
            }
            .padding(20)
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 480)
        .task { await setup.keepChecking() }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if setup.isComplete {
                Label(
                    String(localized: "All set. Docket is in your menu bar.", comment: "Setup window: every step done"),
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(Color.statusReady)
            } else if setup.account == .loading {
                ProgressView().controlSize(.small)
                Text("Checking…", comment: "Setup window: reading the account state").foregroundStyle(
                    Color.textSecondary)
            }
            Spacer()
            Button(
                setup.isComplete
                    ? String(localized: "Done", comment: "Setup window button")
                    : String(localized: "Close", comment: "Setup window button"),
                action: close
            )
            .keyboardShortcut(setup.isComplete ? .defaultAction : .cancelAction)
        }
    }

    @ViewBuilder
    private func actions(for step: SetupStore.Step) -> some View {
        switch step {
        case .install:
            if setup.activity == .installing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading from GitHub…", comment: "Setup window: installing gh")
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                if case .failed(let error) = setup.activity {
                    Label(Self.message(for: error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.statusAttention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(String(localized: "Install GitHub CLI", comment: "Setup window button")) {
                        Task { await setup.install() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(
                        String(localized: "Choose Location…", comment: "Setup window button"), action: chooseGhLocation)
                }
            }
        case .signIn:
            Button(String(localized: "Sign In in Terminal", comment: "Setup window button")) {
                Task { await setup.signIn() }
            }
            .buttonStyle(.borderedProminent)
        case .scopes:
            Button(String(localized: "Grant in Terminal", comment: "Setup window button")) {
                Task { await setup.grantScopes() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    static func message(for error: GhInstallError) -> String {
        switch error {
        case .unavailable:
            String(
                localized: "GitHub could not be reached. Check your connection and try again.",
                comment: "Setup window: gh download failed")
        case .missingAsset:
            String(
                localized: "GitHub's latest release of the CLI has no build for this Mac.",
                comment: "Setup window: gh download failed")
        case .checksumMismatch:
            String(
                localized: "The download did not match GitHub's checksum, so nothing was installed.",
                comment: "Setup window: gh download failed")
        case .badSignature:
            String(
                localized: "The download is not signed by GitHub, so nothing was installed.",
                comment: "Setup window: gh download failed")
        case .unpackFailed:
            String(localized: "The download could not be unpacked.", comment: "Setup window: gh download failed")
        }
    }
}

/// One step: its number or a tick, its title and explanation, and its actions while it is the current one.
private struct SetupStepRow<Actions: View>: View {
    let step: SetupStore.Step
    let state: SetupStore.StepState
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(.headline)
                    .foregroundStyle(state == .upcoming ? Color.textSecondary : Color.textPrimary)
                Text(verbatim: detail).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .current {
                    VStack(alignment: .leading, spacing: 8) { actions() }.padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(title), \(stateLabel)"))
    }

    @ViewBuilder
    private var marker: some View {
        if state == .done {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.statusReady)
                .frame(width: 22, height: 22)
        } else {
            Text(verbatim: "\(step.rawValue + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(state == .current ? Color.white : Color.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(state == .current ? Color.accent : Color.fillTag))
        }
    }

    private var title: String {
        switch step {
        case .install: String(localized: "Install the GitHub CLI", comment: "Setup step title")
        case .signIn: String(localized: "Sign in to GitHub", comment: "Setup step title")
        case .scopes: String(localized: "Allow reading your repositories and teams", comment: "Setup step title")
        }
    }

    private var detail: String {
        switch step {
        case .install:
            String(
                localized:
                    """
                    Docket downloads the official gh from GitHub, checks GitHub's signature, and keeps it in its own \
                    folder. No Homebrew or password needed.
                    """,
                comment: "Setup step detail")
        case .signIn:
            String(
                localized:
                    "Opens Terminal and then your browser. Follow the prompts there; Docket notices when you are done.",
                comment: "Setup step detail")
        case .scopes:
            String(
                localized:
                    """
                    Docket only reads: the token needs the repo and read:org scopes to see your pull requests and \
                    teams.
                    """,
                comment: "Setup step detail")
        }
    }

    private var stateLabel: String {
        switch state {
        case .done: String(localized: "done", comment: "VoiceOver: setup step state")
        case .current: String(localized: "to do now", comment: "VoiceOver: setup step state")
        case .upcoming: String(localized: "later", comment: "VoiceOver: setup step state")
        }
    }
}
