// Sources/Data/SafeHTTPClient.swift
// Size-capped HTTP client that refuses redirects to restricted hosts (logo SSRF).
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SafeHTTPError: Error, Equatable, Sendable {
    case blockedURL
    case tooLarge
    case noResponse
}

/// URLSession wrapper: redirect allow-list + hard body cap. Cancels before the full body is kept.
public final class SafeHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let shared = SafeHTTPClient()

    private var session: URLSession!
    private let lock = NSLock()
    private var inflight: [Int: LoadState] = [:]

    private struct LoadState {
        let maxBytes: Int
        let kind: RemoteResourceKind
        var buffer: Data
        var response: URLResponse?
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        var finished: Bool
    }

    public init(configuration: URLSessionConfiguration = .default) {
        super.init()
        let config = (configuration.copy() as? URLSessionConfiguration) ?? URLSessionConfiguration.default
        if config.urlCache == nil {
            config.urlCache = URLCache.shared
        }
        if config.timeoutIntervalForRequest <= 0 {
            config.timeoutIntervalForRequest = 15
        }
        if config.timeoutIntervalForResource <= 0 {
            config.timeoutIntervalForResource = 20
        }
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func data(
        for url: URL,
        maxBytes: Int,
        kind: RemoteResourceKind = .remoteAsset
    ) async throws -> (Data, URLResponse) {
        guard RemoteURLPolicy.validatedURL(from: url.absoluteString, kind: kind) != nil else {
            throw SafeHTTPError.blockedURL
        }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request)
            lock.lock()
            inflight[task.taskIdentifier] = LoadState(
                maxBytes: maxBytes,
                kind: kind,
                buffer: Data(),
                response: nil,
                continuation: continuation,
                finished: false
            )
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let kind = lockedKind(for: task.taskIdentifier)
        guard let next = newRequest.url,
              RemoteURLPolicy.shouldFollowRedirect(to: next, kind: kind) else {
            completionHandler(nil)
            finish(taskIdentifier: task.taskIdentifier, result: .failure(SafeHTTPError.blockedURL))
            task.cancel()
            return
        }
        completionHandler(newRequest)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let (kind, maxBytes) = lockedMeta(for: dataTask.taskIdentifier)
        if let final = response.url, !RemoteURLPolicy.shouldFollowRedirect(to: final, kind: kind) {
            completionHandler(.cancel)
            finish(taskIdentifier: dataTask.taskIdentifier, result: .failure(SafeHTTPError.blockedURL))
            return
        }
        if response.expectedContentLength > 0, response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            finish(taskIdentifier: dataTask.taskIdentifier, result: .failure(SafeHTTPError.tooLarge))
            return
        }
        lock.lock()
        inflight[dataTask.taskIdentifier]?.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        inflight[dataTask.taskIdentifier]?.buffer.append(data)
        let oversize: Bool
        if let state = inflight[dataTask.taskIdentifier] {
            oversize = state.buffer.count > state.maxBytes
        } else {
            oversize = false
        }
        lock.unlock()
        if oversize {
            dataTask.cancel()
            finish(taskIdentifier: dataTask.taskIdentifier, result: .failure(SafeHTTPError.tooLarge))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        if let error {
            if (error as? URLError)?.code == .cancelled {
                // Size/redirect path already finished with a typed error.
                lock.lock()
                let already = inflight[id]?.finished ?? true
                lock.unlock()
                if already { return }
            }
            finish(taskIdentifier: id, result: .failure(error))
            return
        }
        lock.lock()
        let state = inflight[id]
        lock.unlock()
        guard let state, let response = state.response else {
            finish(taskIdentifier: id, result: .failure(SafeHTTPError.noResponse))
            return
        }
        if state.buffer.count > state.maxBytes {
            finish(taskIdentifier: id, result: .failure(SafeHTTPError.tooLarge))
            return
        }
        finish(taskIdentifier: id, result: .success((state.buffer, response)))
    }

    // MARK: - Helpers

    private func lockedKind(for id: Int) -> RemoteResourceKind {
        lock.lock()
        defer { lock.unlock() }
        return inflight[id]?.kind ?? .remoteAsset
    }

    private func lockedMeta(for id: Int) -> (RemoteResourceKind, Int) {
        lock.lock()
        defer { lock.unlock() }
        let state = inflight[id]
        return (state?.kind ?? .remoteAsset, state?.maxBytes ?? RemoteURLPolicy.maxLogoBytes)
    }

    private func finish(taskIdentifier: Int, result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        guard var state = inflight[taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        state.finished = true
        inflight[taskIdentifier] = state
        let continuation = state.continuation
        inflight.removeValue(forKey: taskIdentifier)
        lock.unlock()
        continuation.resume(with: result)
    }
}
