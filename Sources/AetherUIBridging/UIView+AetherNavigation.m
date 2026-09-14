#import "UIView+AetherNavigation.h"
#import <objc/runtime.h>
#import <stdint.h>

static const void *kDisablesInteractiveTransitionGestureRecognizerKey = &kDisablesInteractiveTransitionGestureRecognizerKey;
static const void *kDisablesInteractiveKeyboardGestureRecognizerKey = &kDisablesInteractiveKeyboardGestureRecognizerKey;
static const void *kDisablesInteractiveTransitionGestureRecognizerNowKey = &kDisablesInteractiveTransitionGestureRecognizerNowKey;
static const void *kInteractiveTransitionGestureRecognizerTestKey = &kInteractiveTransitionGestureRecognizerTestKey;
static const void *kInputAccessoryHeightProviderKey = &kInputAccessoryHeightProviderKey;

static NSString *AetherDecodeSymbol(const uint8_t *bytes, NSUInteger length) {
    uint8_t decoded[length];
    for (NSUInteger i = 0; i < length; i++) {
        decoded[i] = bytes[i] ^ 0x5A;
    }
    return [[NSString alloc] initWithBytes:decoded length:length encoding:NSUTF8StringEncoding];
}

static NSString *AetherKeyboardWindowClassName(void) {
    static const uint8_t bytes[] = {
        0x0f, 0x13, 0x08, 0x3f, 0x37, 0x35, 0x2e, 0x3f, 0x11, 0x3f, 0x23,
        0x38, 0x35, 0x3b, 0x28, 0x3e, 0x0d, 0x33, 0x34, 0x3e, 0x35, 0x2d
    };
    return AetherDecodeSymbol(bytes, sizeof(bytes));
}

static NSString *AetherKeyboardWindowSelectorName(void) {
    static const uint8_t bytes[] = {
        0x28, 0x3f, 0x37, 0x35, 0x2e, 0x3f, 0x11, 0x3f, 0x23, 0x38, 0x35,
        0x3b, 0x28, 0x3e, 0x0d, 0x33, 0x34, 0x3e, 0x35, 0x2d, 0x1c, 0x35,
        0x28, 0x09, 0x39, 0x28, 0x3f, 0x3f, 0x34, 0x60, 0x39, 0x28, 0x3f,
        0x3b, 0x2e, 0x3f, 0x60
    };
    return AetherDecodeSymbol(bytes, sizeof(bytes));
}


@implementation UIView (AetherNavigation)

- (BOOL)disablesInteractiveTransitionGestureRecognizer {
    return [objc_getAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerKey) boolValue];
}

- (void)setDisablesInteractiveTransitionGestureRecognizer:(BOOL)value {
    objc_setAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)disablesInteractiveKeyboardGestureRecognizer {
    return [objc_getAssociatedObject(self, kDisablesInteractiveKeyboardGestureRecognizerKey) boolValue];
}

- (void)setDisablesInteractiveKeyboardGestureRecognizer:(BOOL)value {
    objc_setAssociatedObject(self, kDisablesInteractiveKeyboardGestureRecognizerKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL (^)(void))disablesInteractiveTransitionGestureRecognizerNow {
    return objc_getAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerNowKey);
}

- (void)setDisablesInteractiveTransitionGestureRecognizerNow:(BOOL (^)(void))block {
    objc_setAssociatedObject(self, kDisablesInteractiveTransitionGestureRecognizerNowKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL (^)(CGPoint))interactiveTransitionGestureRecognizerTest {
    return objc_getAssociatedObject(self, kInteractiveTransitionGestureRecognizerTestKey);
}

- (void)setInteractiveTransitionGestureRecognizerTest:(BOOL (^)(CGPoint))block {
    objc_setAssociatedObject(self, kInteractiveTransitionGestureRecognizerTestKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)input_setInputAccessoryHeightProvider:(CGFloat (^)(void))block {
    objc_setAssociatedObject(self, kInputAccessoryHeightProviderKey, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)input_getInputAccessoryHeight {
    CGFloat (^block)(void) = objc_getAssociatedObject(self, kInputAccessoryHeightProviderKey);
    if (block != nil) {
        return block();
    }
    return 0.0;
}

@end

BOOL AetherViewTreeDisablesInteractiveTransitionGesture(UIView *view, CGPoint point, BOOL hasPoint) {
    UIView *current = view;
    CGPoint currentPoint = point;
    while (current != nil) {
        if (current.disablesInteractiveTransitionGestureRecognizer) {
            return YES;
        }
        BOOL (^now)(void) = current.disablesInteractiveTransitionGestureRecognizerNow;
        if (now != nil && now()) {
            return YES;
        }
        if (hasPoint) {
            BOOL (^test)(CGPoint) = current.interactiveTransitionGestureRecognizerTest;
            if (test != nil && test(currentPoint)) {
                return YES;
            }
        }
        UIView *superview = current.superview;
        if (superview != nil && hasPoint) {
            currentPoint = [current convertPoint:currentPoint toView:superview];
        }
        current = superview;
    }
    return NO;
}

BOOL AetherViewTreeDisablesInteractiveKeyboardGesture(UIView *view) {
    UIView *current = view;
    while (current != nil) {
        if (current.disablesInteractiveKeyboardGestureRecognizer) {
            return YES;
        }
        current = current.superview;
    }
    return NO;
}

BOOL AetherKeyboardRuntimeIsLinked(void) {
    return YES;
}

static id _Nullable AetherKeyboardGetObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }

    IMP implementation = [object methodForSelector:selector];
    if (implementation == NULL) {
        return nil;
    }

    typedef id _Nullable (*Getter)(id, SEL);
    return ((Getter)implementation)(object, selector);
}

UIWindow * _Nullable AetherLegacyKeyboardWindow(void) {
#if !APPSTORE_SAFE
    if (@available(iOS 27.0, *)) {
        Class delegateClass = NSClassFromString(@"UIKeyboardSceneDelegate");

        id delegate = AetherKeyboardGetObject(
            delegateClass,
            @"activeKeyboardSceneDelegate"
        );

        id window = AetherKeyboardGetObject(delegate, @"keyboardWindow");

        return [window isKindOfClass:[UIWindow class]] ? window : nil;
    }

    // Прежний путь для iOS ниже 27.
    Class windowClass = NSClassFromString(AetherKeyboardWindowClassName());
    SEL selector = NSSelectorFromString(AetherKeyboardWindowSelectorName());

    if (windowClass == Nil || ![windowClass respondsToSelector:selector]) {
        return nil;
    }

    IMP implementation = [windowClass methodForSelector:selector];
    if (implementation == NULL) {
        return nil;
    }

    typedef UIWindow * _Nullable (*AetherKeyboardWindowFunction)(
        id, SEL, UIScreen * _Nullable, BOOL
    );

    return ((AetherKeyboardWindowFunction)implementation)(
        windowClass, selector, [UIScreen mainScreen], NO
    );
#else
    return nil;
#endif
}

@implementation UIApplication (AetherKeyboardRuntime)

- (UIWindow * _Nullable)aether_internalGetKeyboardWindow {
    return AetherLegacyKeyboardWindow();
}

@end

/*
 
 === _UIRemoteKeyboards ===
 - startTransition:withInfo: | v32@0:8@16@24
 - setPlacement:quietly:animated:generateSplitNotification: | v36@0:8@16B24B28B32
 - keyboardPosition | {CGRect={CGPoint=dd}{CGSize=dd}}16@0:8
 - isOnScreenRotating | B16@0:8
 - connection | @16@0:8
 - hostBundleIdentifier | @16@0:8
 - keyboardVisible | B16@0:8
 - applicationWillResignActive: | v24@0:8@16
 - updateTransition:withInfo: | v32@0:8@16@24
 - assertionActivationStateChangedToState:forType: | v28@0:8B16Q20
 - assistantBarVisible | B16@0:8
 - proxy | @16@0:8
 - setCurrentState: | v24@0:8@16
 - oldPathForSnapshot | B16@0:8
 - setStickerPrewarmingViewControllerEnabled: | v20@0:8B16
 - queue_keyboardArbiterClientHandleChanged:withCompletion: | v28@0:8B16@?20
 - performRequiredSceneUpdateIfPermittedForChildSceneHostWindow: | v24@0:8@16
 - updateLastScreen: | v24@0:8@16
 - currentHostedPIDs | @16@0:8
 - userSelectedProcessIdentifier:withSceneIdentity:onCompletion: | v36@0:8i16@20@?28
 - prewarmEmojiKeyboard | v16@0:8
 - assertionActivationStateForType: | B24@0:8Q16
 - currentState | @16@0:8
 - addHostedWindowView:fromPID:forScene:callerID: | v44@0:8@16i24@28@36
 - backupState | @16@0:8
 - sceneDidActivate: | v24@0:8@16
 - applicationDidRemoveDeactivationReason: | v24@0:8@16
 - prepareToMoveKeyboard:withIAV:isIAVRelevant:showing:notifyRemote:forScene: | v100@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16{CGRect={CGPoint=dd}{CGSize=dd}}48B80B84B88@92
 - checkState | v16@0:8
 - ignoreLayoutNotifications: | v24@0:8@?16
 - sceneWillEnterForeground: | v24@0:8@16
 - updateCurrentState: | v24@0:8@16
 - intersectionHeightForWindowScene:isLocalMinimumHeightOut:ignoreHorizontalOffset: | d36@0:8@16^B24B32
 - allowedToShowKeyboard | B16@0:8
 - queue_endInputSessionWithCompletion: | v24@0:8@?16
 - _isArbiterClientReadyForWritingToolsToHandleKeyboardTracking | B16@0:8
 - isFloating | B16@0:8
 - sceneUpdated | v16@0:8
 - setDisableBecomeFirstResponder:forSuppressionAssertion: | v24@0:8B16B20
 - restoreKeyboardIfNeeded | v16@0:8
 - queue_setLastEventSource:withCompletion: | v32@0:8q16@?24
 - showsInvisibleKeyboardBehindWTUI | B16@0:8
 - _isWritingToolsReadyToHandleKeyboardTracking | B16@0:8
 - forceKeyboardAway | v16@0:8
 - localSceneCount | Q16@0:8
 - queue_keyboardSuppressed:withCompletion: | v28@0:8B16@?20
 - setLastEventSource: | v24@0:8q16
 - focusedSceneIdentityStringOrIdentifier | @16@0:8
 - _postInputSourceDidChangeNotificationForResponder: | v24@0:8@16
 - setHandlingRemoteEvent: | v20@0:8B16
 - lastEventSource | q16@0:8
 - snapshotting | B16@0:8
 - resetSnapshotWithWindowCheck: | v20@0:8B16
 - prepareForHostedWindowWithScene: | @24@0:8@16
 - isUpdatingKeyWindow | B16@0:8
 - performOnLocalDistributedControllers: | v24@0:8@?16
 - vendKeyboardSuppressionAssertionForReason:type: | @32@0:8@16Q24
 - currentStateHasEqualRect:andIAVPosition: | B80@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16{CGRect={CGPoint=dd}{CGSize=dd}}48
 - applicationDidBecomeActive: | v24@0:8@16
 - pendingAutofillRequest | B16@0:8
 - intersectionHeightForWindowScene: | d24@0:8@16
 - registerController: | v24@0:8@16
 - requiredScene | @16@0:8
 - hasActiveKeyboardSuppressionAssertionsForReason: | B24@0:8@16
 - queue_failedConnection: | v24@0:8@16
 - needsToShowKeyboardForWindow: | B24@0:8@16
 - inputWindowRootViewController | @16@0:8
 - setPendingAutofillRequest: | v20@0:8B16
 - removeIgnoredSceneIdentityTokenString: | v24@0:8@16
 - remoteKeyboardUndocked | B16@0:8
 - applicationDidBecomeActive:forceSignalToProxy: | v28@0:8@16B24
 - shouldSuppressResponseToRemoteKeyboardChange: | B24@0:8@16
 - stopConnection | v16@0:8
 - shouldAllowInputViewsRestoredForId: | B24@0:8@16
 - queue_keyboardIAVChanged:onComplete: | v32@0:8d16@?24
 - setEnableMultiscreenHack: | v20@0:8B16
 - setFocusedSceneIdentityStringOrIdentifier: | v24@0:8@16
 - showingRemoteKeyboard | B16@0:8
 - hasWindowHostingCallerID: | B24@0:8@16
 - setYieldingKeyboardToIgnoredScene: | v24@0:8@16
 - .cxx_destruct | v16@0:8
 - wantsToShowKeyboardForWindow: | B24@0:8@16
 - queue_keyboardUIDidChange:onComplete: | v32@0:8@16@?24
 - checkConnection | v16@0:8
 - setCurrentKeyboard: | v20@0:8B16
 - keyboardChangedCompleted | v16@0:8
 - _updateEventSource:options:responder: | v40@0:8q16Q24@32
 - stickerPrewarmingViewController | @16@0:8
 - clearKeyboardSceneIdentifierEnteringForeground: | v24@0:8@16
 - applicationWillResume: | v24@0:8@16
 - dealloc | v16@0:8
 - _activeScreen | @16@0:8
 - needsToShowKeyboardForViewServiceHostWindow: | B24@0:8@16
 - setDisableBecomeFirstResponder: | v20@0:8B16
 - _sceneFocusPermittedForApplication | B16@0:8
 - setWindowLevel:sceneLevel:forResponder: | v40@0:8d16d24@32
 - screenDidDisconnect: | v24@0:8@16
 - _performOnDistributedControllersExceptSelf: | v24@0:8@?16
 - keyboardWindowClass | #16@0:8
 - setStickerPrewarmingViewController: | v24@0:8@16
 - addIgnoredSceneIdentityTokenString: | v24@0:8@16
 - setHandlingViewServiceEvent: | v20@0:8B16
 - unregisterController: | v24@0:8@16
 - init | @16@0:8
 - vendKeyboardSuppressionAssertionForReason: | @24@0:8@16
 - refreshWithLocalMinimumKeyboardHeight:forScene: | B32@0:8d16@24
 - viewHostForWindow: | @24@0:8@16
 - toggleSuppressionForWritingToolIfNeeded | v16@0:8
 - applicationWillAddDeactivationReason: | v24@0:8@16
 - setSnapshotting: | v20@0:8B16
 - setWantsAssistantWhileSuppressingKeyboard: | v20@0:8B16
 - userTapsOnKeyboard | v16@0:8
 - startConnection | v16@0:8
 - keyboardActive | B16@0:8
 - setUpdatingKeyWindow: | v20@0:8B16
 - isWritingToolsHostingViewService | B16@0:8
 - completeTransition:withInfo: | v32@0:8@16@24
 - _sceneFocusUpdatePermittedForWindow: | B24@0:8@16
 - isShowingModalAutofillPanel: | B24@0:8@16
 - applicationKeyWindowDidChange: | v24@0:8@16
 - willLock: | v24@0:8@16
 - queue_sceneBecameFocused:withCompletion: | v32@0:8@16@?24
 - verifyPlacement | v16@0:8
 - updateEventSource:options: | v32@0:8q16Q24
 - disableBecomeFirstResponder | B16@0:8
 - handlingViewServiceEvent | B16@0:8
 - sceneDidDisconnect: | v24@0:8@16
 - applicationResumedEventsOnly: | v24@0:8@16
 - signalToProxyKeyboardChanged:onCompletion: | v32@0:8@16@?24
 - peekApplicationEvent: | v24@0:8@16
 - keyboardWindow | @16@0:8
 - performOnDistributedControllers: | v24@0:8@?16
 - setWindowEnabled:force: | v24@0:8B16B20
 - setDidSignalKeyboardChangedForCurrentKeyboard: | v20@0:8B16
 - shouldFence | B16@0:8
 - completeMoveKeyboardForWindow: | v24@0:8@16
 - _isWritingToolsHandlingKeyboardTracking | B16@0:8
 - wantsToShowKeyboardForViewServiceHostWindow: | B24@0:8@16
 - setRequiredScene: | v24@0:8@16
 - queue_activeProcessResignWithCompletion: | v24@0:8@?16
 - assertNeedsAutofillUI | v16@0:8
 - _usesInvisibleKeyboardBehindWTUI | B16@0:8
 - setDisableBecomeFirstResponder:forSuppressionAssertion:updatePlacement: | v28@0:8B16B20B24
 - setSuppressingKeyboard:forScene: | v28@0:8B16@20
 - currentKeyboard | B16@0:8
 - preserveKeyboardWithId: | v24@0:8@16
 - didHandleKeyboardChange:shouldConsiderSnapshottingKeyboard:isLocalEvent: | B32@0:8@16B24B28
 - updatingHeight | B16@0:8
 - keyboardIsForSystemService | B16@0:8
 - setConnection: | v24@0:8@16
 - cleanSuppression | v16@0:8
 - performOnControllers: | v24@0:8@?16
 - sceneDidEnterBackground: | v24@0:8@16
 - updateAllVisibleFrames | v16@0:8
 - _updateEventSource:options: | v32@0:8q16Q24
 - userSelectedApp:onCompletion: | v32@0:8@16@?24
 - restoreKeyboardWithId: | v24@0:8@16
 - enableMultiscreenHack | B16@0:8
 - wantsAssistantWhileSuppressingKeyboard | B16@0:8
 - setShouldFence: | v20@0:8B16
 - forceWindowEnabledIfAllowed | v16@0:8
 - queue_keyboardTransition:event:withInfo:onComplete: | v48@0:8@16Q24@32@?40
 - hasLocalMinimumKeyboardHeightForScene: | B24@0:8@16
 - setWindowEnabled: | v20@0:8B16
 - updateEventSource:options:responder: | v40@0:8q16Q24@32
 - _requiredUIScene | @16@0:8
 - applicationKeyWindowWillChange: | v24@0:8@16
 - vendEmojiKeyboardPrewarmingAssertionForReason: | @24@0:8@16
 - updateLocalKeyboardChanged: | v24@0:8@16
 - _lostWindow: | v24@0:8@16
 - hasAnyHostedViews | B16@0:8
 - allowedToEnableKeyboardWindow | B16@0:8
 - restorePreservedInputViewsIfNecessary | v16@0:8
 - queue_keyboardChangedWithCompletion: | v24@0:8@?16
 - queue_getDebugInfoWithCompletion: | v24@0:8@?16
 - handlingRemoteEvent | B16@0:8
 - remoteKeyboardUndocked: | B20@0:8B16
 - reloadForSnapshotting | v16@0:8
 - finishWithHostedWindow | v16@0:8
 - keyboardFrameIncludingRemoteIAV | {CGRect={CGPoint=dd}{CGSize=dd}}16@0:8
 - yieldingKeyboardToIgnoredScene | @16@0:8
 - setBackupState: | v24@0:8@16
 - didSignalKeyboardChangedForCurrentKeyboard | B16@0:8
 - controllerDidLayoutSubviews: | v24@0:8@16
 - heightForRemoteIAVPlaceholderIfNecessary | d16@0:8
 - queue_keyboardChanged:onComplete: | v32@0:8@16@?24
 - persistentOffset | {CGPoint=dd}16@0:8
 - sceneIsFullScreen | B16@0:8
 - applicationDidSuspend: | v24@0:8@16
 - setDisableBecomeFirstResponder:forSuppressionAssertion:updatePlacement:wantsAssistant: | v32@0:8B16B20B24B28
 - setKeyboardSceneIdentifierEnteringForegroundForScene: | v24@0:8@16
 - queue_setKeyboardDisabled:withCompletion: | v28@0:8B16@?20
 + enabled | B16@0:8
 + bundlesThatShouldNotPreventRestoration | @16@0:8
 + createArbiterConnection | @16@0:8
 + sharedRemoteKeyboards | @16@0:8
 + wantsUnassociatedWindowSceneForKeyboardWindow | B16@0:8
 + keyboardWindowSceneForScreen:create: | @28@0:8@16B24
 + serviceName | @16@0:8
 
 */
