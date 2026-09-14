import Foundation

/// Internal generation selected from the resolved application appearance.
enum ContextMenuPresentationStyle: Equatable {
    case legacy
    case glassmorphic
}

struct ContextMenuGlassmorphicTiming: Equatable {
    let openDuration: TimeInterval
    let closeDuration: TimeInterval
}

enum ContextMenuSourceVisualMode {
    case persistentSource
    case leasedGlassSource
}
