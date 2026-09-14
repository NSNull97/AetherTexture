import Foundation

/// Compile-time policy for Apple private API usage.
///
/// `APPSTORE_SAFE` is intentionally the only switch:
/// - defined: private UIKit/CoreAnimation code is excluded and public
///   look-alike implementations are used;
/// - absent: the private implementations are available and active.
internal enum AetherPrivateRuntime {
    #if APPSTORE_SAFE
    static let isEnabled = false
    static let isAppStoreSafe = true
    #else
    static let isEnabled = true
    static let isAppStoreSafe = false
    #endif
}
