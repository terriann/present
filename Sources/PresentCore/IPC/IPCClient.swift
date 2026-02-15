import Foundation

/// IPC client used by the CLI to notify the running app of mutations.
public struct IPCClient: Sendable {
    private let socketPath: String

    public init(socketPath: String = IPCServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Send a message to the app. Fails silently if the app isn't running.
    public func send(_ message: IPCMessage) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                for (i, byte) in pathBytes.enumerated() where i < 104 {
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

        let data = message.data
        data.withUnsafeBytes { buffer in
            _ = Foundation.write(fd, buffer.baseAddress!, buffer.count)
        }
    }
}
