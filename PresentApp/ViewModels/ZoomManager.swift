import SwiftUI
import PresentCore

@MainActor @Observable
final class ZoomManager {
    // MARK: - State

    var zoomScale: CGFloat = 1.0

    static let defaultZoomIndex = 3
    static let zoomScales: [CGFloat] = [0.85, 0.9, 0.95, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75]

    // MARK: - Dependencies

    private let service: PresentService

    // MARK: - Computed Properties

    private var zoomIndex: Int {
        Self.zoomScales.firstIndex(of: zoomScale) ?? Self.defaultZoomIndex
    }

    var canZoomIn: Bool { zoomIndex < Self.zoomScales.count - 1 }
    var canZoomOut: Bool { zoomIndex > 0 }
    var isDefaultZoom: Bool { zoomScale == 1.0 }

    // MARK: - Initialization

    init(service: PresentService) {
        self.service = service
    }

    // MARK: - Actions

    func zoomIn() {
        guard canZoomIn else { return }
        zoomScale = Self.zoomScales[zoomIndex + 1]
        saveZoomLevel()
    }

    func zoomOut() {
        guard canZoomOut else { return }
        zoomScale = Self.zoomScales[zoomIndex - 1]
        saveZoomLevel()
    }

    func resetZoom() {
        zoomScale = 1.0
        saveZoomLevel()
    }

    func loadFromPreferences() async {
        if let zoomStr = try? await service.getPreference(key: PreferenceKey.zoomLevel),
           let index = Int(zoomStr),
           index >= 0, index < Self.zoomScales.count {
            zoomScale = Self.zoomScales[index]
        }
    }

    // MARK: - Persistence

    private func saveZoomLevel() {
        Task {
            try? await service.setPreference(key: PreferenceKey.zoomLevel, value: String(zoomIndex))
        }
    }
}
