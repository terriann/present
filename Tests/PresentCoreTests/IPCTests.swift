import Testing
import Foundation
@testable import PresentCore

@Suite("IPC Tests")
struct IPCTests {

    // MARK: - Message Serialization

    @Test func messageRoundTrip() throws {
        let messages: [IPCMessage] = [
            .sessionStarted,
            .sessionPaused,
            .sessionResumed,
            .sessionStopped,
            .sessionCancelled,
            .activityUpdated,
            .dataChanged,
        ]

        for message in messages {
            let data = try #require(message.data)
            let decoded = IPCMessage.from(data: data)
            #expect(decoded != nil)
            #expect(String(describing: decoded!) == String(describing: message))
        }
    }

    @Test func invalidDataReturnsNil() {
        let garbage = Data([0x00, 0xFF, 0xDE, 0xAD])
        let decoded = IPCMessage.from(data: garbage)
        #expect(decoded == nil)
    }

    @Test func emptyDataReturnsNil() {
        let decoded = IPCMessage.from(data: Data())
        #expect(decoded == nil)
    }

    @Test func messageDataIsValidJSON() throws {
        let message = IPCMessage.sessionStarted
        let data = try #require(message.data)
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
    }

    @Test func allMessagesEncodeUniquely() throws {
        let messages: [IPCMessage] = [
            .sessionStarted, .sessionPaused, .sessionResumed,
            .sessionStopped, .sessionCancelled, .activityUpdated, .dataChanged,
        ]
        var seen = Set<String>()
        for message in messages {
            guard let data = message.data else { continue }
            let encoded = String(data: data, encoding: .utf8)!
            #expect(!seen.contains(encoded), "Duplicate encoding for \(message)")
            seen.insert(encoded)
        }
    }

    // MARK: - Client Fails Silently

    @Test func clientFailsSilentlyWhenNoServer() {
        let socketPath = "/tmp/p-none-\(UUID().uuidString).sock"
        let client = IPCClient(socketPath: socketPath)
        // Should not throw or crash
        client.send(.sessionStarted)
        client.send(.dataChanged)
    }

    // MARK: - Server/Client Round-Trip (non-async to allow semaphore)

    @Test func serverClientRoundTrip() throws {
        let socketPath = "/tmp/p-rt-\(UUID().uuidString).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        let received = ReceivedMessages()
        let semaphore = DispatchSemaphore(value: 0)

        let serverFD = startTestServer(socketPath: socketPath, received: received, semaphore: semaphore, acceptCount: 1)
        #expect(serverFD >= 0)
        defer { close(serverFD) }

        // Give server time to start (CI runners need more headroom)
        Thread.sleep(forTimeInterval: 0.15)

        let client = IPCClient(socketPath: socketPath)
        client.send(.sessionStarted)

        let result = semaphore.wait(timeout: .now() + 2)
        #expect(result == .success)
        #expect(received.messages.count == 1)
    }

    @Test func multipleMessagesDelivered() throws {
        let socketPath = "/tmp/p-multi-\(UUID().uuidString).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        let received = ReceivedMessages()
        let semaphore = DispatchSemaphore(value: 0)

        let serverFD = startTestServer(socketPath: socketPath, received: received, semaphore: semaphore, acceptCount: 3)
        #expect(serverFD >= 0)
        defer { close(serverFD) }

        // Give server time to start (CI runners need more headroom)
        Thread.sleep(forTimeInterval: 0.15)

        let client = IPCClient(socketPath: socketPath)
        client.send(.sessionStarted)
        client.send(.sessionPaused)
        client.send(.sessionStopped)

        for _ in 0..<3 {
            _ = semaphore.wait(timeout: .now() + 2)
        }

        #expect(received.messages.count == 3)
    }
}

// MARK: - Helpers

/// Thread-safe message collector using NSLock
private final class ReceivedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [IPCMessage] = []

    var messages: [IPCMessage] {
        lock.lock()
        defer { lock.unlock() }
        return _messages
    }

    func append(_ message: IPCMessage) {
        lock.lock()
        defer { lock.unlock() }
        _messages.append(message)
    }
}

/// Start a Unix domain socket test server that accepts `acceptCount` connections.
private func startTestServer(socketPath: String, received: ReceivedMessages, semaphore: DispatchSemaphore, acceptCount: Int) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
            for (i, byte) in pathBytes.enumerated() where i < 104 {
                dest[i] = byte
            }
        }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bindResult == 0 else { close(fd); return -1 }
    guard listen(fd, 5) == 0 else { close(fd); return -1 }

    DispatchQueue.global().async {
        for _ in 0..<acceptCount {
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFD, &buffer, buffer.count)
            close(clientFD)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                if let msg = IPCMessage.from(data: data) {
                    received.append(msg)
                    semaphore.signal()
                }
            }
        }
    }

    return fd
}
