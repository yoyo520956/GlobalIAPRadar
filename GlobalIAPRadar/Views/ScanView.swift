import Foundation
import SwiftUI

struct ScanView: View {
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.settings.language }
    private var scan: ScanEngine { appState.scan }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let app = scan.app {
                        appCard(app)
                        progressCard
                        statsGrid
                        controls
                        statusList
                        comparisonLink
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.t("scan.title", language))
            .onChange(of: scan.phase) { _, newPhase in
                if newPhase == .finished, let app = scan.app {
                    Task { await appState.persistSnapshots(for: app) }
                }
            }
        }
    }

    // MARK: - Sections

    private func appCard(_ app: AppInfo) -> some View {
        HStack(spacing: 10) {
            AppIconView(url: app.artworkURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(app.seller).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(scan.phase == .finished ? L10n.t("scan.progress", language) : L10n.t("common.loading", language))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(scan.completedCount) / \(scan.totalCount)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Text(scan.progressRatio.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            CoverageBar(ratio: scan.progressRatio)
            if let started = scan.startedAt, let finished = scan.finishedAt {
                Text("\(L10n.t("scan.elapsed", language)): \(finished.timeIntervalSince(started), format: .number.precision(.fractionLength(0)))s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if scan.startedAt != nil {
                Text("\(L10n.t("scan.elapsed", language)): \(Date().timeIntervalSince(scan.startedAt!), format: .number.precision(.fractionLength(0)))s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsGrid: some View {
        let items: [(String, String, Color)] = [
            (L10n.t("scan.success", language), "\(scan.successCount)", .green),
            (L10n.t("scan.failed", language), "\(scan.failedCount)", .orange),
            (L10n.t("scan.discovered", language), "\(scan.distinctIAPCount)", .accentColor),
            (L10n.t("scan.remaining", language), "\(scan.remainingCount)", .secondary)
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.0) { item in
                StatTile(title: item.0, value: item.1, tint: item.2)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if scan.canPause {
                Button {
                    Task { await scan.pause() }
                } label: {
                    Label(L10n.t("scan.pause", language), systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if scan.canResume {
                Button {
                    Task { await scan.resume() }
                } label: {
                    Label(L10n.t("scan.resume", language), systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button(role: .destructive) {
                scan.cancel()
            } label: {
                Label(L10n.t("scan.cancel", language), systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!scan.isRunning && !scan.canResume)
        }
        .font(.footnote)
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("scan.storefrontStatus", language))
                .font(.subheadline.weight(.semibold))
            ForEach(scan.progress) { entry in
                HStack(spacing: 8) {
                    StorefrontBadge(code: entry.storefront)
                    Text(name(for: entry.storefront)).font(.caption).lineLimit(1)
                    Spacer()
                    if entry.finishedAt != nil {
                        StatusPill(status: entry.status, language: language)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var comparisonLink: some View {
        NavigationLink {
            ComparisonView()
        } label: {
            Label(L10n.t("scan.compare", language), systemImage: "tablecells")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(scan.results.isEmpty)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe.asia.australia")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(L10n.t("scan.idle", language))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func name(for code: String) -> String {
        appState.storefronts.first { $0.storefront == code }?.displayName ?? code.uppercased()
    }
}
