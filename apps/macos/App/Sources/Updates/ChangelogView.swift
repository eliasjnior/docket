import DocketUpdate
import SwiftUI

struct ChangelogView: View {
    let entries: [ChangelogEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Version \(entry.version.description)", comment: "Changelog entry title").font(
                                .title3.bold())
                            Spacer()
                            if let date = entry.date {
                                Text(verbatim: date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(entry.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(section.title, systemImage: symbol(for: section.title)).font(.headline)
                                ForEach(section.items, id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(verbatim: "•").foregroundStyle(.secondary)
                                        Text(verbatim: item).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    if entry.id != entries.last?.id { Divider() }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbol(for section: String) -> String {
        switch section {
        case "New": "sparkles"
        case "Fixed": "wrench.and.screwdriver"
        case "Improved": "gauge.with.dots.needle.67percent"
        default: "list.bullet"
        }
    }
}

struct WhatsNewView: View {
    let entries: [ChangelogEntry]
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                AppIconView(size: 64)
                Text("What's New in Docket", comment: "What's New window title").font(.title2.bold())
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            if entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "No release notes", comment: "What's New empty"), systemImage: "doc.text")
            } else {
                ChangelogView(entries: entries)
            }
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Continue", comment: "What's New button"), action: close).keyboardShortcut(
                    .defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
    }
}
