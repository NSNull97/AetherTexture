//
//  UIVisualEffectView+Helpers.swift
//  VisualEffectView
//
//  Created by Lasha Efremidze on 9/14/20.
//

import UIKit
import ObjectiveC

private var aetherBackdropGroupingIdentifierAssociationKey: UInt8 = 0

extension UIVisualEffectView {
    /// Mirrors LNPopupController's backdrop grouping without exposing the
    /// private key in App-Store-safe binaries. Unsupported UIKit revisions
    /// simply keep their ordinary independent public material renderers.
    func aetherApplyBackdropGroupingIdentifier(_ identifier: String?) {
        #if !APPSTORE_SAFE
        guard let identifier else { return }
        let getter = NSSelectorFromString(ObfuscatedSymbols.groupName)
        let setter = NSSelectorFromString(ObfuscatedSymbols.setGroupName)
        let privateSetter = NSSelectorFromString(
            ObfuscatedSymbols.privateSetGroupName
        )
        if responds(to: privateSetter) {
            perform(privateSetter, with: identifier)
            objc_setAssociatedObject(
                self,
                &aetherBackdropGroupingIdentifierAssociationKey,
                identifier,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
            return
        }
        guard responds(to: getter) || responds(to: setter) else { return }
        if responds(to: getter),
           value(forKey: ObfuscatedSymbols.groupName) as? String == identifier {
            return
        }
        if responds(to: setter) {
            perform(setter, with: identifier)
        } else {
            setValue(identifier, forKey: ObfuscatedSymbols.groupName)
        }
        objc_setAssociatedObject(
            self,
            &aetherBackdropGroupingIdentifierAssociationKey,
            identifier,
            .OBJC_ASSOCIATION_COPY_NONATOMIC
        )
        #endif
    }

    var aetherBackdropGroupingIdentifier: String? {
        #if APPSTORE_SAFE
        return nil
        #else
        if let applied = objc_getAssociatedObject(
            self,
            &aetherBackdropGroupingIdentifierAssociationKey
        ) as? String {
            return applied
        }
        let getter = NSSelectorFromString(ObfuscatedSymbols.groupName)
        guard responds(to: getter) else { return nil }
        return value(forKey: ObfuscatedSymbols.groupName) as? String
        #endif
    }
}

#if !APPSTORE_SAFE
extension UIVisualEffectView {
    var backdropView: UIView? {
        return subview(of: NSClassFromString(ObfuscatedSymbols.uiVisualEffectBackdropView))
    }
    var overlayView: UIView? {
        return subview(of: NSClassFromString(ObfuscatedSymbols.uiVisualEffectSubview))
    }
    var gaussianBlur: NSObject? {
        return backdropView?.value(forKey: ObfuscatedSymbols.filters, withFilterType: ObfuscatedSymbols.gaussianBlur)
    }
    var sourceOver: NSObject? {
        return overlayView?.value(forKey: ObfuscatedSymbols.viewEffects, withFilterType: ObfuscatedSymbols.sourceOver)
    }
    func prepareForChanges() {
        self.effect = UIBlurEffect(style: .light)
        gaussianBlur?.setValue(1.0, forKeyPath: ObfuscatedSymbols.requestedScaleHint)
    }
    func applyChanges() {
        backdropView?.perform(NSSelectorFromString(ObfuscatedSymbols.applyRequestedFilterEffects))
    }
}

extension NSObject {
    var requestedValues: [String: Any]? {
        get { return value(forKeyPath: ObfuscatedSymbols.requestedValues) as? [String: Any] }
        set { setValue(newValue, forKeyPath: ObfuscatedSymbols.requestedValues) }
    }
    func value(forKey key: String, withFilterType filterType: String) -> NSObject? {
        return (value(forKeyPath: key) as? [NSObject])?.first { $0.value(forKeyPath: ObfuscatedSymbols.filterType) as? String == filterType }
    }
}

private extension UIView {
    func subview(of classType: AnyClass?) -> UIView? {
        return subviews.first { type(of: $0) == classType }
    }
}
#endif
