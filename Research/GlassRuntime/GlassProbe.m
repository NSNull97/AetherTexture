#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

// Standalone research executable; never linked into AetherUI.
static BOOL Matches(NSString *s, NSString *pattern) {
    return [s rangeOfString:pattern options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location != NSNotFound;
}
static NSArray *Methods(Class cls) {
    unsigned count = 0;
    Method *items = class_copyMethodList(cls, &count);
    NSMutableArray *result = [NSMutableArray new];
    for (unsigned i = 0; i < count; i++) {
        [result addObject:@{@"selector": NSStringFromSelector(method_getName(items[i])),
                            @"encoding": @(method_getTypeEncoding(items[i]))}];
    }
    free(items);
    return [result sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [a[@"selector"] compare:b[@"selector"]];
    }];
}
static NSDictionary *ClassInfo(Class cls) {
    NSMutableArray *properties = [NSMutableArray new], *ivars = [NSMutableArray new], *protocols = [NSMutableArray new];
    unsigned n = 0;
    objc_property_t *pp = class_copyPropertyList(cls, &n);
    for (unsigned i = 0; i < n; i++) [properties addObject:@{@"name": @(property_getName(pp[i])), @"attributes": @(property_getAttributes(pp[i]))}];
    free(pp);
    Ivar *ii = class_copyIvarList(cls, &n);
    for (unsigned i = 0; i < n; i++) [ivars addObject:@{@"name": @(ivar_getName(ii[i])), @"encoding": @(ivar_getTypeEncoding(ii[i]) ?: ""), @"offset": @(ivar_getOffset(ii[i]))}];
    free(ii);
    Protocol *__unsafe_unretained *ps = class_copyProtocolList(cls, &n);
    for (unsigned i = 0; i < n; i++) [protocols addObject:@(protocol_getName(ps[i]))];
    free(ps);
    return @{@"name": NSStringFromClass(cls), @"runtimeName": @(class_getName(cls)), @"superclass": NSStringFromClass(class_getSuperclass(cls)) ?: @"",
             @"image": @(class_getImageName(cls) ?: ""), @"instanceMethods": Methods(cls),
             @"classMethods": Methods(object_getClass(cls)), @"properties": properties, @"ivars": ivars, @"protocols": protocols};
}
static NSDictionary *Inventory(void) {
    NSMutableArray *loads = [NSMutableArray new];
    for (NSString *name in @[@"SwiftUI", @"SwiftUICore", @"MaterialKit", @"CoreMaterial", @"DesignLibrary", @"AnimationKit", @"RenderBox", @"BaseBoardUI"]) {
        NSString *path = [NSString stringWithFormat:@"/System/Library/%@/%@.framework/%@", [name hasPrefix:@"SwiftUI"] ? @"Frameworks" : @"PrivateFrameworks", name, name];
        void *handle = dlopen(path.UTF8String, RTLD_LAZY);
        [loads addObject:@{@"path": path, @"loaded": @(handle != NULL)}];
    }
    unsigned total = 0;
    Class *classes = objc_copyClassList(&total);
    NSMutableArray *selected = [NSMutableArray new], *selectorHits = [NSMutableArray new];
    NSString *classPattern = @"glass|liquid|lens|^CASDF|backdrop|visualeffect|material|lumaanchor|luminance|scrolledge|cornerconfiguration|intelligence.*light|flexinteraction|^AnimationKit\\.|^DesignLibrary\\.";
    NSString *selectorPattern = @"glass|liquid|materializ|lumaMin|lumaMax|luminance|monochromatic|sdf|refraction|refraction|specular|displacement|backdropgroup";
    NSSet *extras = [NSSet setWithArray:@[@"CAFilter", @"CALayer", @"UIView", @"UIVisualEffectView", @"UITraitCollection", @"UISettings", @"UIFocusHaloEffect"]];
    for (unsigned i = 0; i < total; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (Matches(name, classPattern) || [extras containsObject:name]) [selected addObject:ClassInfo(classes[i])];
        if (![name hasPrefix:@"UI"] && ![name hasPrefix:@"_UI"] && ![name hasPrefix:@"CA"] && ![name hasPrefix:@"MT"] && ![name hasPrefix:@"_Tt"]) continue;
        for (NSDictionary *method in Methods(classes[i])) if (Matches(method[@"selector"], selectorPattern)) {
            [selectorHits addObject:@{@"class": name, @"selector": method[@"selector"], @"encoding": method[@"encoding"]}];
        }
    }
    free(classes);
    [selected sortUsingComparator:^NSComparisonResult(id a, id b) { return [a[@"name"] compare:b[@"name"]]; }];
    NSMutableArray *protocols = [NSMutableArray new];
    unsigned protocolCount = 0;
    Protocol *__unsafe_unretained *allProtocols = objc_copyProtocolList(&protocolCount);
    for (unsigned i = 0; i < protocolCount; i++) {
        NSString *name = @(protocol_getName(allProtocols[i]));
        if (!Matches(name, @"glass|liquid|lens|sdf|backdrop|visualeffect|material|luma|scrolledge|flexinteraction")) continue;
        NSMutableArray *methods = [NSMutableArray new];
        for (int required = 0; required < 2; required++) for (int instance = 0; instance < 2; instance++) {
            unsigned count = 0;
            struct objc_method_description *list = protocol_copyMethodDescriptionList(allProtocols[i], required, instance, &count);
            for (unsigned j = 0; j < count; j++) [methods addObject:@{@"selector": NSStringFromSelector(list[j].name), @"encoding": @(list[j].types ?: ""), @"required": @(required), @"instance": @(instance)}];
            free(list);
        }
        [protocols addObject:@{@"name": name, @"methods": methods}];
    }
    free(allProtocols);
    return @{@"os": NSProcessInfo.processInfo.operatingSystemVersionString, @"totalClassCount": @(total), @"loads": loads, @"classes": selected, @"selectorHits": selectorHits, @"protocols": protocols};
}
static id Read(id object, NSString *key) {
    @try {
        id value = [object valueForKey:key];
        if (!value) return NSNull.null;
        if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) return value;
        if ([value isKindOfClass:NSArray.class]) {
            NSMutableArray *items = [NSMutableArray new];
            for (id item in value) [items addObject:[item description] ?: @""];
            return items;
        }
        return [value description] ?: @"";
    } @catch (NSException *e) { return @{@"exception": e.name, @"reason": e.reason ?: @""}; }
}
static NSDictionary *Properties(id object) {
    if (!object) return @{};
    NSMutableDictionary *result = [@{@"class": NSStringFromClass([object class]), @"description": [object description] ?: @""} mutableCopy];
    unsigned count = 0;
    objc_property_t *properties = class_copyPropertyList([object class], &count);
    for (unsigned i = 0; i < count; i++) {
        NSString *name = @(property_getName(properties[i]));
        result[name] = Read(object, name);
    }
    free(properties);
    return result;
}
// Calls only runtime-verified scalar setters, preserving their actual ABI.
static NSString *SetScalar(id object, NSString *selectorName, NSNumber *value) {
    SEL sel = NSSelectorFromString(selectorName);
    NSMethodSignature *signature = [object methodSignatureForSelector:sel];
    if (!signature || signature.numberOfArguments != 3) return @"missing or unexpected signature";
    const char *arg = [signature getArgumentTypeAtIndex:2];
    @try {
        if (strcmp(arg, @encode(BOOL)) == 0) ((void (*)(id, SEL, BOOL))objc_msgSend)(object, sel, value.boolValue);
        else if (strcmp(arg, @encode(double)) == 0) ((void (*)(id, SEL, double))objc_msgSend)(object, sel, value.doubleValue);
        else if (strcmp(arg, @encode(NSInteger)) == 0) ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, sel, value.integerValue);
        else return [@"unsupported encoding: " stringByAppendingString:@(arg)];
        return @"invoked";
    } @catch (NSException *e) { return e.reason ?: e.name; }
}
static NSDictionary *ObjectProbes(void) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    result[@"accessibility"] = @{@"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()), @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()), @"darkerSystemColors": @(UIAccessibilityDarkerSystemColorsEnabled())};
    Class lumaClass = NSClassFromString(@"GlassProbe.EffectSettingsContainerView");
    if (lumaClass) {
        id object = [lumaClass new];
        result[@"aetherLumaContainer"] = @{@"class": NSStringFromClass(lumaClass), @"lumaMin": @([object respondsToSelector:NSSelectorFromString(@"lumaMin")]), @"lumaMax": @([object respondsToSelector:NSSelectorFromString(@"lumaMax")]), @"setLumaMin:": @([object respondsToSelector:NSSelectorFromString(@"setLumaMin:")]), @"setLumaMax:": @([object respondsToSelector:NSSelectorFromString(@"setLumaMax:")])};
    }
    Class glassClass = NSClassFromString(@"_UIViewGlass");
    if ([glassClass respondsToSelector:NSSelectorFromString(@"systemTintAmount")]) result[@"systemTintAmount"] = Read(glassClass, @"systemTintAmount");
    UIGlassEffect *regular = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    UIGlassEffect *clear = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
    regular.tintColor = clear.tintColor = UIColor.redColor;
    regular.interactive = clear.interactive = YES;
    result[@"aetherStyleComparison"] = @{@"currentGuardWouldSkip": @([regular.tintColor isEqual:clear.tintColor] && regular.isInteractive == clear.isInteractive), @"effectsEqual": @([regular isEqual:clear]), @"regularStyle": Read(regular, @"style"), @"clearStyle": Read(clear, @"style")};
    for (NSString *name in @[@"CASDFEffect", @"CASDFGlassDisplacementEffect", @"CASDFGlassHighlightEffect", @"CASDFShadowEffect", @"CASDFFillEffect", @"CASDFGradientEffect", @"CASDFGradientContourEffect", @"CASDFKeyFillHighlightEffect", @"CASDFOutputEffect", @"CASDFElementLayer", @"CASDFLayer", @"_UIViewGlassGroup", @"_UIViewGlass"]) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        @try {
            id object = [cls new];
            NSMutableDictionary *entry = [Properties(object) mutableCopy];
            if ([cls respondsToSelector:NSSelectorFromString(@"defaultValues")]) entry[@"defaultValues"] = Read(cls, @"defaultValues");
            result[name] = entry;
        } @catch (NSException *e) { result[name] = e.reason ?: e.name; }
    }
    Class filterClass = NSClassFromString(@"CAFilter");
    if ([filterClass respondsToSelector:NSSelectorFromString(@"filterTypes")]) result[@"CAFilter.types"] = Read(filterClass, @"filterTypes");
    for (NSString *name in @[@"displacementMap", @"variableBlur", @"gaussianBlur", @"sdf", @"glass", @"luminanceCurveMap", @"vibrantColorMatrix"]) {
        if (![filterClass respondsToSelector:NSSelectorFromString(@"filterWithName:")]) break;
        id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, NSSelectorFromString(@"filterWithName:"), name);
        if (!filter) { result[[@"CAFilter." stringByAppendingString:name]] = NSNull.null; continue; }
        NSMutableDictionary *values = [NSMutableDictionary new];
        for (NSString *key in @[@"inputAmount", @"inputScale", @"inputRadius", @"inputSourceSublayerName", @"inputNormalizeEdges", @"inputNormalizeEdgesTransparent", @"inputMaskImage", @"inputHardEdges", @"inputQuality"]) values[key] = Read(filter, key);
        result[[@"CAFilter." stringByAppendingString:name]] = values;
    }
    return result;
}
static NSDictionary *ImageStrings(void) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        NSString *path = @(_dyld_get_image_name(i));
        if (!Matches(path, @"/(UIKitCore|QuartzCore|DesignLibrary|AnimationKit|RenderBox|SwiftUICore)\\.framework/")) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64) continue;
        unsigned long length = 0;
        const uint8_t *base = getsectiondata(header, "__TEXT", "__cstring", &length);
        if (!base || !length) continue;
        base += _dyld_get_image_vmaddr_slide(i);
        NSMutableSet *strings = [NSMutableSet new];
        for (unsigned long off = 0; off < length;) {
            size_t size = strnlen((const char *)base + off, length - off);
            if (size > 1 && size < 500) {
                NSString *value = [[NSString alloc] initWithBytes:base + off length:size encoding:NSUTF8StringEncoding];
                if (value && Matches(value, @"glass|liquid|luma|lensing|materializ|^input|refraction|specular|^SDF|monochrom|tintamount|flexinteraction")) [strings addObject:value];
            }
            off += size + 1;
        }
        result[path] = [[strings allObjects] sortedArrayUsingSelector:@selector(compare:)];
    }
    return result;
}
static NSDictionary *LayerTree(CALayer *layer, int depth) {
    NSMutableDictionary *result = [@{@"class": NSStringFromClass(layer.class), @"bounds": NSStringFromCGRect(layer.bounds), @"name": layer.name ?: @"", @"opacity": @(layer.opacity)} mutableCopy];
    NSMutableArray *filters = [NSMutableArray new], *children = [NSMutableArray new];
    for (id filter in layer.filters) {
        NSMutableDictionary *entry = [@{@"class": NSStringFromClass([filter class]), @"description": [filter description]} mutableCopy];
        for (NSString *key in @[@"name", @"type", @"inputKeys"]) if ([filter respondsToSelector:NSSelectorFromString(key)]) entry[key] = Read(filter, key);
        static NSArray *inputKeys;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSMutableSet *keys = [NSMutableSet new];
            NSDictionary *strings = ImageStrings();
            for (NSString *image in strings) if ([image containsString:@"QuartzCore.framework"]) for (NSString *key in strings[image]) if (Matches(key, @"^input[A-Z][A-Za-z0-9]+$")) [keys addObject:key];
            inputKeys = [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)];
        });
        NSMutableDictionary *values = [NSMutableDictionary new];
        for (NSString *key in inputKeys) { id value = Read(filter, key); if (value != NSNull.null) values[key] = value; }
        entry[@"observedInputs"] = values;
        [filters addObject:entry];
    }
    result[@"filters"] = filters;
    NSMutableArray *animations = [NSMutableArray new];
    for (NSString *key in layer.animationKeys) {
        CAAnimation *animation = [layer animationForKey:key];
        NSMutableDictionary *entry = [@{@"key": key, @"class": NSStringFromClass(animation.class), @"duration": @(animation.duration), @"beginTime": @(animation.beginTime)} mutableCopy];
        if ([animation isKindOfClass:CAPropertyAnimation.class]) entry[@"keyPath"] = ((CAPropertyAnimation *)animation).keyPath ?: @"";
        if ([animation isKindOfClass:CABasicAnimation.class]) { entry[@"from"] = Read(animation, @"fromValue"); entry[@"to"] = Read(animation, @"toValue"); }
        [animations addObject:entry];
    }
    result[@"animations"] = animations;
    for (NSString *key in @[@"effect", @"groupName", @"scale", @"marginWidth", @"allowsInPlaceFiltering", @"disablesOccludedBackdropBlurs", @"lumaSamplingLayer", @"sublayerTransform"]) if ([layer respondsToSelector:NSSelectorFromString(key)]) result[key] = Read(layer, key);
    if ([layer respondsToSelector:NSSelectorFromString(@"effect")]) {
        id effect = ((id (*)(id, SEL))objc_msgSend)(layer, NSSelectorFromString(@"effect"));
        result[@"effectProperties"] = Properties(effect);
    }
    if (depth < 14) for (CALayer *child in layer.sublayers) [children addObject:LayerTree(child, depth + 1)];
    result[@"sublayers"] = children;
    return result;
}
static NSDictionary *ViewTree(UIView *view, int depth) {
    NSMutableArray *children = [NSMutableArray new];
    if (depth < 14) for (UIView *child in view.subviews) [children addObject:ViewTree(child, depth + 1)];
    NSMutableDictionary *result = [@{@"class": NSStringFromClass(view.class), @"frame": NSStringFromCGRect(view.frame), @"subviews": children} mutableCopy];
    if ([view isKindOfClass:UIVisualEffectView.class]) result[@"effect"] = [((UIVisualEffectView *)view).effect description] ?: @"nil";
    return result;
}
static id JSONReady(id object) {
    if ([object isKindOfClass:NSNumber.class]) return isfinite([object doubleValue]) ? object : [object description];
    if ([object isKindOfClass:NSArray.class]) { NSMutableArray *array = [NSMutableArray new]; for (id item in object) [array addObject:JSONReady(item)]; return array; }
    if ([object isKindOfClass:NSDictionary.class]) { NSMutableDictionary *dictionary = [NSMutableDictionary new]; for (id key in object) dictionary[key] = JSONReady(object[key]); return dictionary; }
    return object;
}
static void WriteJSON(id object, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:JSONReady(object) options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) { fprintf(stderr, "%s\n", error.description.UTF8String); exit(2); }
}

@interface ProbeDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSMutableDictionary *samples;
@property(nonatomic, strong) NSMutableDictionary *configurations;
@end
@implementation ProbeDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *vc = [UIViewController new];
    self.window.rootViewController = vc;
    vc.overrideUserInterfaceStyle = [NSProcessInfo.processInfo.environment[@"GLASS_PROBE_APPEARANCE"] isEqual:@"dark"] ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    for (int y = 0; y < 20; y++) for (int x = 0; x < 10; x++) {
        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(x * 46, y * 46, 46, 46)];
        tile.backgroundColor = (x + y) % 2 ? UIColor.systemTealColor : UIColor.systemYellowColor;
        [vc.view addSubview:tile];
    }
    self.samples = [NSMutableDictionary new];
    self.configurations = [NSMutableDictionary new];
    NSArray *names = @[@"regular", @"clear", @"interactive", @"tinted", @"container", @"noShadow", @"noForeground", @"noPlatter", @"noLensing", @"noDisplacement", @"contentLensing", @"fixedLuma0", @"fixedLuma1", @"smoothness0", @"smoothness40", @"ungrouped", @"boostWhite", @"fixedBackground"];
    NSDictionary *changes = @{@"noShadow": @[@"setExcludingShadow:", @YES], @"noForeground": @[@"setExcludingForeground:", @YES], @"noPlatter": @[@"setExcludingPlatter:", @YES], @"noLensing": @[@"setExcludingControlLensing:", @YES], @"noDisplacement": @[@"setExcludingControlDisplacement:", @YES], @"contentLensing": @[@"setContentLensing:", @YES], @"fixedLuma0": @[@"setAdaptiveFixedLuminance:", @0.0], @"fixedLuma1": @[@"setAdaptiveFixedLuminance:", @1.0], @"smoothness0": @[@"setSmoothness:", @0.0], @"smoothness40": @[@"setSmoothness:", @40.0], @"ungrouped": @[@"setAllowsGrouping:", @NO], @"boostWhite": @[@"setBoostWhitePoint:", @YES]};
    for (NSUInteger index = 0; index < names.count; index++) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:index == 1 ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        effect.interactive = index == 2;
        if (index == 3) effect.tintColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.3];
        NSMutableDictionary *config = [NSMutableDictionary new];
        id glass = nil;
        if ([effect respondsToSelector:NSSelectorFromString(@"glass")]) glass = ((id (*)(id, SEL))objc_msgSend)(effect, NSSelectorFromString(@"glass"));
        if (changes[names[index]] && glass) {
            NSArray *change = changes[names[index]];
            config[@"setter"] = change[0]; config[@"value"] = change[1];
            config[@"status"] = SetScalar(glass, change[0], change[1]);
        }
        if ([names[index] isEqual:@"fixedBackground"] && [glass respondsToSelector:NSSelectorFromString(@"setFixedBackgroundColor:")]) {
            ((void (*)(id, SEL, id))objc_msgSend)(glass, NSSelectorFromString(@"setFixedBackgroundColor:"), UIColor.blackColor);
        }
        if (index >= 5 && glass && [UIGlassEffect respondsToSelector:NSSelectorFromString(@"effectWithGlass:")]) effect = ((id (*)(id, SEL, id))objc_msgSend)(UIGlassEffect.class, NSSelectorFromString(@"effectWithGlass:"), glass);
        config[@"descriptor"] = Properties(glass);
        config[@"effectClass"] = NSStringFromClass(effect.class);
        self.configurations[names[index]] = config;
        UIVisualEffect *actualEffect = index == 4 ? [UIGlassContainerEffect new] : effect;
        UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:actualEffect];
        CGFloat width = (vc.view.bounds.size.width - 40) / 3;
        view.frame = CGRectMake(10 + (index % 3) * (width + 10), 75 + (index / 3) * 125, width, 90);
        view.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:24]];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(6, 15, width - 12, 60)]; label.text = names[index]; label.font = [UIFont boldSystemFontOfSize:12]; label.numberOfLines = 2;
        [view.contentView addSubview:label];
        if (index == 4) {
            for (int j = 0; j < 2; j++) {
                UIVisualEffectView *child = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]];
                child.frame = CGRectMake(j * 45 + 5, 5, 42, 80);
                child.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:24]];
                [view.contentView addSubview:child];
            }
        }
        [vc.view addSubview:view];
        self.samples[names[index]] = view;
    }
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSMutableDictionary *report = [NSMutableDictionary new];
        for (NSString *name in self.samples) {
            UIView *view = self.samples[name];
            NSMutableDictionary *entry = [@{@"views": ViewTree(view, 0), @"layers": LayerTree(view.layer, 0), @"configuration": self.configurations[name]} mutableCopy];
            if ([NSStringFromClass(view.layer.superlayer.class) isEqual:@"_UIMultiLayer"]) entry[@"renderContainer"] = LayerTree(view.layer.superlayer, 0);
            for (NSString *key in @[@"_resolvedBackgroundMaterial", @"_glassEffect"]) if ([view respondsToSelector:NSSelectorFromString(key)]) entry[key] = Read(view, key);
            report[name] = entry;
        }
        report[@"window"] = @{@"views": ViewTree(self.window, 0), @"layers": LayerTree(self.window.layer, 0)};
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        WriteJSON(report, [dir stringByAppendingPathComponent:@"hierarchy.json"]);
        WriteJSON(Inventory(), [dir stringByAppendingPathComponent:@"inventory.json"]);
        WriteJSON(ObjectProbes(), [dir stringByAppendingPathComponent:@"objects.json"]);
        WriteJSON(ImageStrings(), [dir stringByAppendingPathComponent:@"strings.json"]);
        NSLog(@"GLASS_PROBE_COMPLETE %@", dir);
        UIVisualEffectView *regular = self.samples[@"regular"];
        regular.effect = nil;
        [self.window layoutIfNeeded];
        [UIView animateWithDuration:1 animations:^{ regular.effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 6), dispatch_get_main_queue(), ^{
            WriteJSON(LayerTree(self.window.layer, 0), [dir stringByAppendingPathComponent:@"materialization.json"]);
        });
        // Aether uses an empty effect instead of nil on iOS 26.0. Capture
        // that exact alternative as a separate experiment on both systems.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 3 / 2), dispatch_get_main_queue(), ^{
            regular.effect = [UIVisualEffect new];
            [self.window layoutIfNeeded];
            [UIView animateWithDuration:1 animations:^{ regular.effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 6), dispatch_get_main_queue(), ^{
                WriteJSON(LayerTree(self.window.layer, 0), [dir stringByAppendingPathComponent:@"materialization-empty.json"]);
            });
        });
    });
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc >= 3 && strcmp(argv[1], "inventory") == 0) { WriteJSON(Inventory(), @(argv[2])); return 0; }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class));
    }
}
