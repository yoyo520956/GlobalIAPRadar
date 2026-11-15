import Foundation
import Observation

enum ScanPhase: String, Sendable {
    case idle
    case searching
    case scanning
    case paused
    case finished
    case failed
    case cancelled
}

/// Observable state machine for one global sweep.
@MainActor
@Observable
final class ScanEngine {
    private(set) var phase: ScanPhase = .idle
    private(set) var app: AppInfo?
    private(set) var results: [StorefrontResult] = []
    private(set) var progress: [StorefrontProgress] = []
    private(set) var errorMessage: String?
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var scannedStorefronts: [Storefront] = []

    private var task: Task<Void, Never>?
    private var progressIndex: [String: Int] = [:]
    let scanner = GlobalScanner()
    private var activeScanner: GlobalScanner?

    // MARK: Derived statistics

    var totalCount: Int { progress.count }
    var completedCount: Int { progress.filter { $0.finishedAt != nil }.count }
    var successCount: Int { progress.filter { $0.status == .success }.count }
    var failedCount: Int { completedCount - successCount }
    var progressRatio: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }
    var distinctIAPCount: Int {
        Set(results.flatMap { $0.products.map(\.productID) }).count
    }
    var alignedSKUs: [AlignedSKU] { SKUAligner.align(results: results) }
    var isRunning: Bool { phase == .scanning || phase == .searching }
    var canPause: Bool { phase == .scanning }
    var canResume: Bool { phase == .paused }
    var remainingCount: Int { max(totalCount - completedCount, 0) }

    var statusBreakdown: [StorefrontQueryStatus: Int] {
        progress.reduce(into: [:]) { counts, entry in
            counts[entry.status, default: 0] += 1
        }
    }

    // MARK: Control

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        app = nil
        results = []
        progress = []
        progressIndex = [:]
        scannedStorefronts = []
        errorMessage = nil
        startedAt = nil
        finishedAt = nil
    }

    func searchApps(term: String) async throws -> [AppInfo] {
        phase = .searching
        errorMessage = nil
        defer { if phase == .searching { phase = .idle } }
        return try await scanner.iTunes.search(term: term, storefront: "us")
    }

    func startScan(app: AppInfo, storefronts: [Storefront], maxConcurrent: Int = 6) {
        task?.cancel()
        self.app = app
        self.scannedStorefronts = storefronts
        self.results = []
        self.progress = storefronts.map {
            StorefrontProgress(storefront: $0.storefront, status: .notVerified, iapCount: 0, finishedAt: nil)
        }
        self.progressIndex = Dictionary(uniqueKeysWithValues: storefronts.enumerated().map { ($0.element.storefront, $0.offset) })
        self.phase = .scanning
        self.startedAt = Date()
        self.finishedAt = nil
        self.errorMessage = nil

        let scanner = GlobalScanner(maxConcurrent: maxConcurrent)
        activeScanner = scanner
        task = Task { [weak self] in
            let results = await scanner.scan(app: app, storefronts: storefronts) { update in
                self?.apply(update)
            }
            guard let self else { return }
            self.results = results
            self.finishedAt = Date()
            self.phase = .finished
        }
    }

    func retryFailed() {
        guard let app else { return }
        let retryable: Set<StorefrontQueryStatus> = [.networkError, .rateLimited, .catalogUnavailable, .notVerified]
        let failedCodes = Set(progress.filter { retryable.contains($0.status) }.map(\.storefront))
        let subset = scannedStorefronts.filter { failedCodes.contains($0.storefront) }
        guard !subset.isEmpty else { return }

        phase = .scanning
        errorMessage = nil
        // A fresh scanner guarantees the gate is not left paused by a previous
        // run (pause -> cancel -> retry would otherwise deadlock here).
        let scanner = GlobalScanner(maxConcurrent: 6)
        activeScanner = scanner
        task = Task { [weak self] in
            let fresh = await scanner.scan(app: app, storefronts: subset) { update in
                self?.apply(update)
            }
            guard let self else { return }
            let replacement = Dictionary(uniqueKeysWithValues: fresh.map { ($0.storefront, $0) })
            self.results = self.results.map { replacement[$0.storefront] ?? $0 }
            self.finishedAt = Date()
            self.phase = .finished
        }
    }

    func pause() async {
        guard phase == .scanning else { return }
        await activeScanner?.gate.pause()
        phase = .paused
    }

    func resume() async {
        guard phase == .paused else { return }
        await activeScanner?.gate.resume()
        phase = .scanning
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .scanning || phase == .paused || phase == .searching {
            phase = .cancelled
        }
    }

    private func apply(_ update: StorefrontProgress) {
        guard let index = progressIndex[update.storefront] else { return }
        progress[index] = update
    }
}
