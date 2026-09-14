#import <ASDisplayNode.h>
#import <ASControlNode.h>

NS_ASSUME_NONNULL_BEGIN

/// Texture deliberately allows node construction off the main thread, while
/// Aether's node layer is UIKit-facing and is always created and mutated by
/// the main actor. Objective-C actor annotations let Swift subclasses inherit
/// that contract without illegally strengthening an override of Texture's
/// nonisolated initializers.
NS_SWIFT_UI_ACTOR
@interface AetherMainActorDisplayNode : ASDisplayNode
@end

NS_SWIFT_UI_ACTOR
@interface AetherMainActorControlNode : ASControlNode
@end

NS_ASSUME_NONNULL_END
