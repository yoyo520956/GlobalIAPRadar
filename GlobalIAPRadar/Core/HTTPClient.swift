import Foundation

enum HTTPError: LocalizedError, Sendable {
    case badStatus(Int)
    case emptyResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "HTTP \(code)"
        case .emptyResponse:
            return "空响应"
        case .decoding(let message):
            return "解析失败：\(message)"
        }
    }
}

/// Small, dependency-free HTTP layer with bounded retries and exponential backoff.
/// `URLSession` is not `Sendable`, so the class opts out explicitly; the session is
/// immutable and safe to use from multiple tasks.
final class HTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let maxRetries: Int
    private let baseDelay: TimeInterval

    init(maxRetries: Int = 3, baseDelay: TimeInterval = 0.8, timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        self.session = URLSession(configuration: configuration)
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    func data(for request: URLRequest) async throws -> Data {
        var lastError: Error = HTTPError.emptyResponse
        for attempt in 0...maxRetries {
            if Task.isCancelled { throw CancellationError() }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HTTPError.emptyResponse }
                if (200..<300).contains(http.statusCode) { return data }
                if http.statusCode == 429 || http.statusCode >= 500 {
                    lastError = HTTPError.badStatus(http.statusCode)
                    try await backoff(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                    continue
                }
                throw HTTPError.badStatus(http.statusCode)
            } catch is CancellationError {
                throw CancellationError()
            } catch let httpError as HTTPError {
                // Non-retryable HTTP errors (404 etc.) propagate immediately.
                throw httpError
            } catch {
                lastError = error
                try await backoff(attempt: attempt, retryAfter: nil)
            }
        }
        throw lastError
    }

    private func backoff(attempt: Int, retryAfter: String?) async throws {
        let seconds: TimeInterval
        if let retryAfter, let value = Double(retryAfter) {
            seconds = min(value, 20)
        } else {
            seconds = min(pow(1.8, Double(attempt)) * baseDelay, 12)
        }
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Caps the number of in-flight requests without blocking a thread.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.permits = max(1, permits)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Spaces out outgoing requests so the scan stays polite and avoids 429s.
actor RateLimiter {
    private let minInterval: TimeInterval
    private var lastRequest = Date.distantPast

    init(minInterval: TimeInterval = 0.15) {
        self.minInterval = minInterval
    }

    func wait() async throws {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            try await Task.sleep(for: .seconds(minInterval - elapsed))
        }
        lastRequest = Date()
    }
}
