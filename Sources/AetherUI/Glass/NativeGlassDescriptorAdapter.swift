import UIKit
import ObjectiveC.runtime

/// Internal options for the measured UIKit descriptor path. Public appearances
/// still choose the renderer; these options belong to individual render hosts.
struct NativeGlassDescriptorOptions: Equatable {
    var contentLensing = false
    var excludesShadow = false
}

@available(iOS 26.0, *)
enum NativeGlassDescriptorAdapter {
    static func applying(_ options: NativeGlassDescriptorOptions, to effect: UIGlassEffect) -> UIGlassEffect? {
        #if APPSTORE_SAFE
        return nil
        #else
        guard options != .init() else { return effect }
        let getter = NSSelectorFromString("glass")
        let factory = NSSelectorFromString("effectWithGlass:")
        guard let getMethod = class_getInstanceMethod(UIGlassEffect.self, getter),
              let makeMethod = class_getClassMethod(UIGlassEffect.self, factory),
              hasSignature(getMethod, result: "@", arguments: []),
              hasSignature(makeMethod, result: "@", arguments: ["@"])
        else { return nil }
        typealias Get = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        typealias Make = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
        let get = unsafeBitCast(method_getImplementation(getMethod), to: Get.self)
        guard let descriptor = get(effect, getter)?.takeUnretainedValue(),
              let descriptorClass = object_getClass(descriptor) else { return nil }
        // Validate the complete operation before mutating a descriptor.
        let values = [("setContentLensing:", options.contentLensing), ("setExcludingShadow:", options.excludesShadow)]
        var setters: [(Selector, Method, Bool)] = []
        for (name, value) in values {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(descriptorClass, selector),
                  hasSignature(method, result: "v", arguments: ["B"]) else { return nil }
            setters.append((selector, method, value))
        }
        for (selector, method, value) in setters {
            unsafeBitCast(method_getImplementation(method), to: Set.self)(descriptor, selector, value)
        }
        let make = unsafeBitCast(method_getImplementation(makeMethod), to: Make.self)
        guard let configured = make(UIGlassEffect.self, factory, descriptor)?.takeUnretainedValue() as? UIGlassEffect else { return nil }
        configured.tintColor = effect.tintColor
        configured.isInteractive = effect.isInteractive
        return configured
        #endif
    }

    #if !APPSTORE_SAFE
    private static func hasSignature(_ method: Method, result: String, arguments: [String]) -> Bool {
        guard method_getNumberOfArguments(method) == arguments.count + 2 else { return false }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == result else { return false }
        for (index, expected) in arguments.enumerated() {
            guard let type = method_copyArgumentType(method, UInt32(index + 2)) else { return false }
            let actual = String(cString: type)
            free(type)
            guard actual == expected else { return false }
        }
        return true
    }
    #endif
}
