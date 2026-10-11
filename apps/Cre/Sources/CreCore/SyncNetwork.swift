import Foundation
import Network

// MARK: - Transport: one request, one response over TCP; each message is a 4-byte length then JSON.

public enum SyncWire {
    public static let serviceType = "_tide._tcp"

    static func frame<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func receive<T: Decodable>(_ type: T.Type, on c: NWConnection, done: @escaping (Result<T, Error>) -> Void) {
        c.receive(minimumIncompleteLength: 4, maximumLength: 4) { head, _, _, error in
            guard let head, head.count == 4, error == nil else { return done(.failure(error ?? SyncError.closed)) }
            let length = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
            guard length > 0, length < 200_000_000 else { return done(.failure(SyncError.badMessage)) }
            readBody(length, on: c, into: Data()) { result in
                done(result.flatMap { data in Result { try JSONDecoder().decode(T.self, from: data) } })
            }
        }
    }

    private static func readBody(_ remaining: Int, on c: NWConnection, into buffer: Data, done: @escaping (Result<Data, Error>) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: remaining) { chunk, _, _, error in
            guard let chunk, error == nil else { return done(.failure(error ?? SyncError.closed)) }
            let all = buffer + chunk
            if chunk.count >= remaining { return done(.success(all)) }
            readBody(remaining - chunk.count, on: c, into: all, done: done)
        }
    }
}

public enum SyncError: Error { case closed, badMessage, timeout }

/// The Mac side: listens on the local network (advertised over Bonjour when `serviceName` is set).
public final class SyncServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: (SyncRequest) async -> SyncResponse
    private let queue = DispatchQueue(label: "tide.sync.server")

    public init(serviceName: String?, handler: @escaping (SyncRequest) async -> SyncResponse) throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: .any)
        if let serviceName { listener.service = NWListener.Service(name: serviceName, type: SyncWire.serviceType) }
        self.handler = handler
    }

    /// Starts listening; returns the port.
    public func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] c in self?.serve(c) }
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: once.run { cont.resume(returning: self?.listener.port?.rawValue ?? 0) }
                case .failed(let e): once.run { cont.resume(throwing: e) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() { listener.cancel() }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        SyncWire.receive(SyncRequest.self, on: c) { [handler] result in
            guard case .success(let request) = result else { c.cancel(); return }
            Task {
                let response = await handler(request)
                guard let data = try? SyncWire.frame(response) else { c.cancel(); return }
                c.send(content: data, completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }
}

/// The phone side: one request to the Mac.
public enum SyncClient {
    public static func send(_ request: SyncRequest, to endpoint: NWEndpoint, timeout: TimeInterval = 15) async throws -> SyncResponse {
        let c = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "tide.sync.client")
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            let finish: (Result<SyncResponse, Error>) -> Void = { r in once.run { c.cancel(); cont.resume(with: r) } }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(SyncError.timeout)) }
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = try? SyncWire.frame(request) else { return finish(.failure(SyncError.badMessage)) }
                    c.send(content: data, completion: .contentProcessed { error in
                        if let error { return finish(.failure(error)) }
                        SyncWire.receive(SyncResponse.self, on: c, done: finish)
                    })
                case .failed(let e): finish(.failure(e))
                case .cancelled: finish(.failure(SyncError.closed))
                default: break
                }
            }
            c.start(queue: queue)
        }
    }

    /// The Mac by its Bonjour name.
    public static func endpoint(serviceName: String) -> NWEndpoint {
        .service(name: serviceName, type: SyncWire.serviceType, domain: "local.", interface: nil)
    }

    /// Macs running 朝夕 on this network (names), looked for during `seconds`.
    public static func discover(seconds: Double = 3) async -> [String] {
        let browser = NWBrowser(for: .bonjour(type: SyncWire.serviceType, domain: nil), using: .tcp)
        let queue = DispatchQueue(label: "tide.sync.browse")
        return await withCheckedContinuation { cont in
            let once = Once()
            queue.asyncAfter(deadline: .now() + seconds) {
                let names = browser.browseResults.compactMap { r -> String? in
                    if case .service(let name, _, _, _) = r.endpoint { return name }
                    return nil
                }
                browser.cancel()
                once.run { cont.resume(returning: Array(Set(names)).sorted()) }
            }
            browser.start(queue: queue)
        }
    }
}

/// Runs its block at most once (callbacks that may fire twice).
final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}
