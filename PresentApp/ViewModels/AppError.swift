import Foundation

enum ErrorScene {
    case mainWindow
    case menuBar
    case settings
}

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let scene: ErrorScene
}
