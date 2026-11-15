import SwiftUI

struct StatusPill: View {
    let status: StorefrontQueryStatus
    let language: AppLanguage

    var body: some View {
        Text(L10n.t(status.labelKey, language))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .fixedSize()
    }

    private var tint: Color {
        switch status {
        case .success: return .green
        case .notListed, .productNotFound, .noIAPData: return .orange
        case .rateLimited: return .yellow
        case .networkError, .catalogUnavailable, .identityUnverified, .notVerified: return .red
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct CoverageBar: View {
    let ratio: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(3, geometry.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(height: 7)
    }
}

/// Small, dependency-free formatting helpers.
enum PriceFormat {
    static func money(_ amount: Double?, currency: String?) -> String {
        guard let amount, let currency, !currency.isEmpty else { return "—" }
        return amount.formatted(.currency(code: currency))
    }

    static func percent(_ ratio: Double) -> String {
        ratio.formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StorefrontBadge: View {
    let code: String
    var tint: Color = .accentColor

    var body: some View {
        Text(code.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(tint)
    }
}

struct AppIconView: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
