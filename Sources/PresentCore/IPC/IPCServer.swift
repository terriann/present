import Foundation

/// IPC server that listens on a Unix domain socket for messages from the CLI.
/// Runs in the app process to receive notifications about CLI mutations.
public final class IPCServer: @unchecked Sendable {
    private let socketPath: String
    private let handler: @Sendable (IPCMessage) -> Void
    private var serverFD: Int32 = -1

    public init(socketPath: String? = nil, handler: @escaping @Sendable (IPCMessage) -> Void) throws {
        self.socketPath = try socketPath ?? IPCServer.defaultSocketPath()
        self.handler = handler
    }

    public static func defaultSocketPath() throws -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw IPCError.socketCreationFailed
        }
        let presentDir = appSupport.appendingPathComponent("Present", isDirectory: true)
        try FileManager.default.createDirectory(at: presentDir, withIntermediateDirectories: true)
        return presentDir.appendingPathComponent("present.sock").path
    }

    public func start() throws {
        let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard socketPath.utf8CString.count <= sunPathCapacity else {
            throw IPCError.pathTooLong
        }

        // Atomically remove any existing socket — avoids TOCTOU race
        // between fileExists() and removeItem(). Ignores ENOENT if absent.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.socketCreationFailed
        }
        self.serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dest in
                for (i, byte) in pathBytes.enumerated() where i < sunPathCapacity {
                    dest[i] = byte
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw IPCError.bindFailed
        }

        // Restrict socket to owner-only access
        chmod(socketPath, 0o600)

        guard listen(fd, 5) == 0 else {
            close(fd)
            throw IPCError.listenFailed
        }

        // Accept connections in background
        let handler = self.handler
        let myUID = getuid()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let clientFD = accept(fd, nil, nil)
                guard clientFD >= 0 else { break }

                // Verify the connecting process runs as the same user
                var peerUID: uid_t = 0
                var peerGID: gid_t = 0
                if getpeereid(clientFD, &peerUID, &peerGID) != 0 || peerUID != myUID {
                    close(clientFD)
                    continue
                }

                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(clientFD, &buffer, buffer.count)
                close(clientFD)

                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    if let message = IPCMessage.from(data: data) {
                        handler(message)
                    }
                }
            }
        }
    }

    public func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }
}

public enum IPCError: Error, Sendable {
    case socketCreationFailed
    case bindFailed
    case listenFailed
    case connectionFailed
    case sendFailed
    case pathTooLong
}

extension IPCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed: "IPC socket creation failed"
        case .bindFailed: "IPC socket bind failed"
        case .listenFailed: "IPC socket listen failed"
        case .connectionFailed: "IPC socket connection failed"
        case .sendFailed: "IPC socket send failed"
        case .pathTooLong: "IPC socket path exceeds maximum length"
        }
    }
}
