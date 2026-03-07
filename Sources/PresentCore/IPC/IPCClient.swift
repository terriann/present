import Foundation

/// IPC client used by the CLI to notify the running app of mutations.
public struct IPCClient: Sendable {
    private let socketPath: String

    public init(socketPath: String = IPCServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Send a message to the app. Fails silently if the app isn't running.
    public func send(_ message: IPCMessage) {
        let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard socketPath.utf8CString.count <= sunPathCapacity else { return }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

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

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return }

        guard let data = message.data, !data.isEmpty else { return }
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = Foundation.write(fd, baseAddress, buffer.count)
        }
    }
}
