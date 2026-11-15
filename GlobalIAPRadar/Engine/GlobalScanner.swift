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

/// Outcome of the iTunes lookup call for one storefront.
enum LookupOutcome: Equatable, Sendable {
    /// Lookup returned 200 with at least one result: the App is listed there.
    case listed
    /// Lookup returned 200 with resultCount == 0: Apple itself says not sold there.
    case notListed
    case rateLimited
    /// Transport / decoding / other HTTP failure. Never evidence of absence.
    case failed
}

/// Outcome of the apps.apple.com catalog call for one storefront.
enum CatalogOutcome: Equatable, Sendable {
    case products([IAPProduct])
    /// Catalog returned 200 but the IAP view is empty.
    case empty
    /// Catalog returned 404 (no catalog entry for this app in this storefront).
    case notFound
    case rateLimited
    /// Other HTTP error (4xx/5xx) or transport failure.
    case failed
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

    /// Composes the final status from two independent sources.
    ///
    /// Hard rule: a query *failure* is never reported as "not listed".
    /// `.notListed` may only be produced when Apple's own lookup API answered
    /// 200 with an empty result set (or when catalog 404 agrees with it).
    static func resolveStatus(lookup: LookupOutcome, catalog: CatalogOutcome) -> StorefrontQueryStatus {
        switch catalog {
        case .products(let products):
            if products.contains(where: { $0.productID.isEmpty }) {
                return .identityUnverified
            }
            return .success
        case .empty:
            switch lookup {
            case .notListed: return .notListed
            default: return .noIAPData
            }
        case .notFound:
            switch lookup {
            case .notListed: return .notListed        // both sources agree: absent
            default: return .catalogUnavailable        // listed, but catalog query failed
            }
        case .rateLimited:
            return .rateLimited
        case .failed:
            switch lookup {
            case .notListed: return .notListed
            case .rateLimited: return .rateLimited
            default: return .catalogUnavailable
            }
        }
    }

    /// Queries a single storefront. Both sources are always queried; the app's
    /// own price comes from iTunes, the IAP list from the public catalog page API.
    func fetch(app: AppInfo, storefront: Storefront) async -> StorefrontResult {
        let code = storefront.storefront
        await gate.waitIfPaused()
        if Task.isCancelled {
            return StorefrontResult(storefront: code, status: .notVerified, appPrice: nil,
                                    appCurrency: nil, appFormattedPrice: nil, products: [], capturedAt: Date())
        }

        // --- Source 1: iTunes lookup (availability + app price) ---
        var appPrice: Double?
        var appCurrency: String?
        var appFormatted: String?
        var lookupOutcome: LookupOutcome

        do {
            let infos = try await iTunes.lookup(appID: app.appID, storefront: code)
            if let info = infos.first {
                appPrice = info.price
                appCurrency = info.currency
                appFormatted = info.formattedPrice
                lookupOutcome = .listed
            } else {
                // Apple's own API answered 200 with zero results: not sold here.
                lookupOutcome = .notListed
            }
        } catch let error as HTTPError {
            lookupOutcome = Self.lookupOutcome(for: error)
        } catch {
            lookupOutcome = .failed
        }

        await gate.waitIfPaused()
        if Task.isCancelled {
            return StorefrontResult(storefront: code, status: .notVerified, appPrice: appPrice,
                                    appCurrency: appCurrency, appFormattedPrice: appFormatted,
                                    products: [], capturedAt: Date())
        }

        // --- Source 2: public catalog page API (IAP products) ---
        var products: [IAPProduct] = []
        var catalogOutcome: CatalogOutcome
        do {
            let snapshot = try await catalog.fetchProducts(appID: app.appID, storefront: code)
            products = snapshot.products
            if !snapshot.iapViewPresent {
                // 200 OK but no IAP view in the payload: we could not read the
                // data -- never report that as "the app has no IAPs".
                catalogOutcome = .failed
            } else {
                catalogOutcome = products.isEmpty ? .empty : .products(products)
            }
        } catch let error as HTTPError {
            catalogOutcome = Self.catalogOutcome(for: error)
        } catch {
            catalogOutcome = .failed
        }

        let status = Self.resolveStatus(lookup: lookupOutcome, catalog: catalogOutcome)
        return StorefrontResult(storefront: code,
                                status: status,
                                appPrice: appPrice,
                                appCurrency: appCurrency,
                                appFormattedPrice: appFormatted,
                                products: products,
                                capturedAt: Date())
    }

    static func lookupOutcome(for error: HTTPError) -> LookupOutcome {
        switch error {
        case .badStatus(429): return .rateLimited
        default: return .failed
        }
    }

    static func catalogOutcome(for error: HTTPError) -> CatalogOutcome {
        switch error {
        case .badStatus(404): return .notFound
        case .badStatus(429): return .rateLimited
        default: return .failed
        }
    }
}
