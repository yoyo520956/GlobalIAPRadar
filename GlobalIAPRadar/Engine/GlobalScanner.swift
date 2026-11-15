import Foundation

/// Pauses and resumes an in-flight scan without cancelling the running task.
actor ScanGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isPaused: Bool { paused }

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitIfPaused() async {
        guard paused else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// Runs the 175-storefront sweep. Pure infrastructure: no UI, fully testable.
struct GlobalScanner: Sendable {
    let iTunes: ITunesClient
    let catalog: IAPCatalogClient
    let gate: ScanGate
    private let semaphore: AsyncSemaphore

    init(maxConcurrent: Int = 6) {
        self.iTunes = ITunesClient()
        self.catalog = IAPCatalogClient()
        self.gate = ScanGate()
        self.semaphore = AsyncSemaphore(permits: maxConcurrent)
    }

    func scan(app: AppInfo,
              storefronts: [Storefront],
              onUpdate: @escaping @MainActor @Sendable (StorefrontProgress) -> Void) async -> [StorefrontResult] {
        await withTaskGroup(of: StorefrontResult.self) { group in
            for storefront in storefronts {
                group.addTask { [self] in
                    await self.semaphore.acquire()
                    let result = await self.fetch(app: app, storefront: storefront)
                    await self.semaphore.release()
                    return result
                }
            }
            var collected: [StorefrontResult] = []
            for await result in group {
                collected.append(result)
                await onUpdate(StorefrontProgress(storefront: result.storefront,
                                                 status: result.status,
                                                 iapCount: result.products.count,
                                                 finishedAt: result.capturedAt))
            }
            return collected
        }
    }

    /// Queries a single storefront: availability + app price via iTunes, IAP via the catalog.
    func fetch(app: AppInfo, storefront: Storefront) async -> StorefrontResult {
        let code = storefront.storefront
        await gate.waitIfPaused()
        if Task.isCancelled {
            return StorefrontResult(storefront: code, status: .notVerified, appPrice: nil,
                                    appCurrency: nil, appFormattedPrice: nil, products: [], capturedAt: Date())
        }

        var appPrice: Double?
        var appCurrency: String?
        var appFormatted: String?

        do {
            let infos = try await iTunes.lookup(appID: app.appID, storefront: code)
            guard let info = infos.first else {
                return StorefrontResult(storefront: code, status: .notListed, appPrice: nil,
                                        appCurrency: nil, appFormattedPrice: nil, products: [], capturedAt: Date())
            }
            appPrice = info.price
            appCurrency = info.currency
            appFormatted = info.formattedPrice
        } catch let error as HTTPError {
            return StorefrontResult(storefront: code, status: Self.status(for: error),
                                    appPrice: nil, appCurrency: nil, appFormattedPrice: nil,
                                    products: [], capturedAt: Date())
        } catch {
            return StorefrontResult(storefront: code, status: .networkError, appPrice: nil,
                                    appCurrency: nil, appFormattedPrice: nil, products: [], capturedAt: Date())
        }

        await gate.waitIfPaused()
        if Task.isCancelled {
            return StorefrontResult(storefront: code, status: .notVerified, appPrice: appPrice,
                                    appCurrency: appCurrency, appFormattedPrice: appFormatted,
                                    products: [], capturedAt: Date())
        }

        var products: [IAPProduct] = []
        var status: StorefrontQueryStatus
        do {
            let snapshot = try await catalog.fetchProducts(appID: app.appID, storefront: code)
            products = snapshot.products
            if products.isEmpty {
                status = .noIAPData
            } else if products.contains(where: { $0.productID.isEmpty }) {
                status = .identityUnverified
            } else {
                status = .success
            }
        } catch let error as HTTPError {
            status = Self.status(for: error)
        } catch {
            status = .networkError
        }

        return StorefrontResult(storefront: code,
                                status: status,
                                appPrice: appPrice,
                                appCurrency: appCurrency,
                                appFormattedPrice: appFormatted,
                                products: products,
                                capturedAt: Date())
    }

    static func status(for error: HTTPError) -> StorefrontQueryStatus {
        switch error {
        case .badStatus(404): return .notListed
        case .badStatus(429): return .rateLimited
        default: return .networkError
        }
    }
}
