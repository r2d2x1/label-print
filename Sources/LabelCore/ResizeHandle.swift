import Foundation

public enum ResizeHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    public var horizontal: Double {
        switch self { case .topLeft, .left, .bottomLeft: return -1; case .topRight, .right, .bottomRight: return 1; default: return 0 }
    }
    public var vertical: Double {
        switch self { case .topLeft, .top, .topRight: return -1; case .bottomLeft, .bottom, .bottomRight: return 1; default: return 0 }
    }
}
