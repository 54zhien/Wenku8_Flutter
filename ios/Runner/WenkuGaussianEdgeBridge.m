#import "WenkuGaussianEdgeBridge.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static BOOL InstallAdapter(void);

// These selectors belong to the pinned open-source Flutter engine, NOT UIKit
// private classes. Do not extract CAFilter objects or change blur/tint here.
@protocol WenkuEngineGaussianFilter <NSObject>
@property(nonatomic, readonly) CGRect frame;
@property(nonatomic, readonly) CGFloat blurRadius;
@property(nonatomic, readonly) UIVisualEffectView *backdropFilterView;
@end

@interface NSObject (WenkuEngineGaussianConstruction)
- (instancetype)initWithFrame:(CGRect)frame blurRadius:(CGFloat)blurRadius
                 cornerRadius:(CGFloat)cornerRadius visualEffectView:(UIVisualEffectView *)view;
- (void)applyBlurBackdropFilters:(NSArray *)filters;
@end

@interface WenkuFeatherMask : UIView
@end

#if DEBUG
UIView *WenkuGaussianProbeClip(CGRect frame) {
  if (!InstallAdapter()) return nil;
  return [[NSClassFromString(@"ChildClippingView") alloc] initWithFrame:frame];
}
BOOL WenkuGaussianProbeApply(UIView *clip, CGFloat sigma) {
  Class cls = NSClassFromString(@"PlatformViewFilter");
  if (!InstallAdapter() || ![cls instancesRespondToSelector:
      @selector(initWithFrame:blurRadius:cornerRadius:visualEffectView:)]) return NO;
  id filter = [[cls alloc] initWithFrame:clip.bounds blurRadius:sigma cornerRadius:0
    visualEffectView:[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]]];
  if (!filter) return NO;
  [clip applyBlurBackdropFilters:@[filter]];
  return YES;
}
#endif
@implementation WenkuFeatherMask
+ (Class)layerClass { return CAGradientLayer.class; }
@end

static NSHashTable<WenkuGaussianEdgeBridge *> *bridges;
static void (*originalApply)(id, SEL, NSArray *);
static char maskKey;
static char maskViewKey;
static char originalHitKey;

@interface WenkuGaussianEdgeBridge ()
@property(nonatomic) NSMutableDictionary<NSNumber *, NSDictionary *> *edges;
@property(nonatomic) NSMapTable<UIView *, NSArray *> *clips;
@property(nonatomic) NSHashTable<UIView *> *trackedViews;
- (BOOL)owns:(UIView *)clip;
- (void)apply:(NSArray *)filters clip:(UIView *)clip;
- (void)refresh;
@end

static void ApplyWithFeather(id clip, SEL selector, NSArray *filters) {
  originalApply(clip, selector, filters);
  if (![NSThread isMainThread]) return;
  for (WenkuGaussianEdgeBridge *bridge in bridges) {
    if ([bridge owns:clip]) {
      [bridge.clips setObject:filters forKey:clip];
      [bridge apply:filters clip:clip];
    }
  }
}

static BOOL HasReturnType(Class cls, SEL selector, const char *type, unsigned arguments) {
  Method method = class_getInstanceMethod(cls, selector);
  if (!method || method_getNumberOfArguments(method) != arguments) return NO;
  char *actual = method_copyReturnType(method);
  BOOL valid = actual && strcmp(actual, type) == 0;
  free(actual);
  return valid;
}

static BOOL InstallAdapter(void) {
  static dispatch_once_t once;
  static BOOL installed = NO;
  dispatch_once(&once, ^{
    Class clip = NSClassFromString(@"ChildClippingView");
    Class filter = NSClassFromString(@"PlatformViewFilter");
    SEL apply = NSSelectorFromString(@"applyBlurBackdropFilters:");
    // Fail closed on an incompatible engine ABI. No guessed ivars, class-name
    // traversal, Apple-private selectors, or replacement system blur material.
    if (!clip || ![clip isSubclassOfClass:UIView.class] || !filter ||
        !HasReturnType(clip, apply, @encode(void), 3) ||
        !HasReturnType(filter, @selector(frame), @encode(CGRect), 2) ||
        !HasReturnType(filter, @selector(blurRadius), @encode(CGFloat), 2) ||
        !HasReturnType(filter, @selector(backdropFilterView), @encode(id), 2)) return;
    Method method = class_getInstanceMethod(clip, apply);
    char *argument = method_copyArgumentType(method, 2);
    BOOL arrayArgument = argument && strcmp(argument, @encode(id)) == 0;
    free(argument);
    if (!arrayArgument) return;
    bridges = [NSHashTable weakObjectsHashTable];
    originalApply = (void (*)(id, SEL, NSArray *))method_setImplementation(method, (IMP)ApplyWithFeather);
    installed = originalApply != NULL;
  });
  return installed;
}

static CGFloat AlphaAt(NSDictionary *edge, CGFloat y) {
  CGFloat height = [edge[@"height"] doubleValue];
  CGFloat p = fmin(.99, fmax(0, [edge[@"plateau"] doubleValue] / height));
  CGFloat t = fmin(1, fmax(0, (y - [edge[@"y"] doubleValue]) / height));
  if ([edge[@"fromBottom"] boolValue]) t = 1 - t;
  // Same eight stops and smoothstep samples as LiquidGlassScrollEdge's
  // _rampGradient; interpolate the stops, rather than inventing a new curve.
  CGFloat scaled = t * 7;
  NSInteger lo = MIN(6, (NSInteger)floor(scaled));
  CGFloat a[2];
  for (NSInteger i = 0; i < 2; i++) {
    CGFloat x = fmin(1, fmax(0, (((lo + i) / 7.0) - p) / (1 - p)));
    // Flutter Color.withValues stores floating alpha; no 8-bit quantization.
    a[i] = 1 - x * x * (3 - 2 * x);
  }
  return a[0] + (a[1] - a[0]) * (scaled - lo);
}

@implementation WenkuGaussianEdgeBridge
- (instancetype)init {
  self = [super init];
  if (self) {
    _edges = [NSMutableDictionary dictionary];
    _clips = [NSMapTable weakToStrongObjectsMapTable];
    _trackedViews = [NSHashTable weakObjectsHashTable];
    if (InstallAdapter()) [bridges addObject:self];
  }
  return self;
}
- (BOOL)compatible { return InstallAdapter(); }
+ (BOOL)viewHasExternalFilter:(UIView *)view {
  for (WenkuGaussianEdgeBridge *bridge in bridges) {
    for (UIView *clip in bridge.clips) {
      if ([view isDescendantOfView:clip] && [bridge.clips objectForKey:clip].count > 0) return YES;
    }
  }
  return NO;
}
- (void)trackView:(UIView *)view { [self.trackedViews addObject:view]; }
- (BOOL)owns:(UIView *)clip {
  if (!self.flutterView) return NO;
  if ([clip isDescendantOfView:self.flutterView]) return YES;
  // Engine compositeView/applyMutators runs BEFORE bringLayersIntoView on
  // first insertion and after a texture-only route. The factory-owned child
  // already belongs to this clipping view even though its parent is nil.
  if (!clip.superview) {
    for (UIView *view in self.trackedViews) {
      if ([view isDescendantOfView:clip]) return YES;
    }
  }
  return NO;
}
- (BOOL)setEdge:(NSDictionary *)edge {
  NSNumber *identifier = edge[@"id"];
  if (![identifier isKindOfClass:NSNumber.class]) return NO;
  BOOL valid = self.compatible;
  for (NSString *key in @[@"y", @"height", @"plateau", @"sigma"]) {
    if (![edge[key] isKindOfClass:NSNumber.class] || !isfinite([edge[key] doubleValue])) valid = NO;
  }
  if (!valid) { [self removeEdge:identifier]; return NO; }
  if ([edge[@"height"] doubleValue] <= 0 || [edge[@"sigma"] doubleValue] <= 0 ||
      ![edge[@"fromBottom"] isKindOfClass:NSNumber.class]) valid = NO;
  if (!valid) { [self removeEdge:identifier]; return NO; }
  self.edges[identifier] = [edge copy];
  [self refresh];
  return YES;
}
- (void)removeEdge:(NSNumber *)identifier {
  [self.edges removeObjectForKey:identifier];
  [self refresh];
}
- (void)refresh {
  for (UIView *clip in self.clips) [self apply:[self.clips objectForKey:clip] clip:clip];
}
- (NSUInteger)maskedFilterCount {
  NSUInteger count = 0;
  for (UIView *clip in self.clips) {
    for (id<WenkuEngineGaussianFilter> filter in [self.clips objectForKey:clip]) {
      if ([objc_getAssociatedObject(filter.backdropFilterView, &maskKey)[@"edge"] isKindOfClass:NSDictionary.class]) count++;
    }
  }
  return count;
}
- (void)apply:(NSArray *)filters clip:(UIView *)clip {
  UIView *root = self.flutterView;
  if (!root || ![self owns:clip]) return;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  // Detached ChildClippingView.frame is already in Flutter-view coordinates
  // in the pinned engine. Do not convert between disconnected view trees.
  CGRect clipRect = clip.superview ? [clip convertRect:clip.bounds toView:root] : clip.frame;
  for (id<WenkuEngineGaussianFilter> filter in filters) {
    UIVisualEffectView *effect = filter.backdropFilterView;
    if (![effect isKindOfClass:UIVisualEffectView.class]) continue;
    CGRect rect = clip.superview ? [effect convertRect:effect.bounds toView:root] :
      CGRectOffset([effect convertRect:effect.bounds toView:clip], clip.frame.origin.x, clip.frame.origin.y);
    NSDictionary *chosen = nil;
    BOOL ambiguous = NO, candidate = NO;
    for (NSDictionary *edge in self.edges.allValues) {
      CGFloat top = fmax([edge[@"y"] doubleValue], CGRectGetMinY(clipRect));
      CGFloat bottom = fmin([edge[@"y"] doubleValue] + [edge[@"height"] doubleValue], CGRectGetMaxY(clipRect));
      if (fabs([edge[@"sigma"] doubleValue] - filter.blurRadius) > .00001) continue;
      candidate = YES;
      CGFloat tolerance = 1 / MAX(1, root.traitCollection.displayScale) + .001;
      if (bottom <= top || fabs(top - CGRectGetMinY(rect)) > tolerance ||
          fabs(bottom - CGRectGetMaxY(rect)) > tolerance) continue;
      if (chosen) {
        // Distinct cropped profiles are ambiguous; identical routes deduplicate.
        for (NSString *key in @[@"y", @"height", @"plateau", @"fromBottom"]) {
          if (![chosen[key] isEqual:edge[key]]) ambiguous = YES;
        }
      } else chosen = edge;
    }
    NSDictionary *previous = objc_getAssociatedObject(effect, &maskKey);
    if (candidate && (!chosen || ambiguous)) {
      // A likely edge with ambiguous/stale coordinates must not expose the
      // engine's unfeathered rectangular Gaussian. Keep an explicit zero mask.
      WenkuFeatherMask *mask = objc_getAssociatedObject(effect, &maskViewKey);
      if (!mask) {
        mask = [[WenkuFeatherMask alloc] initWithFrame:effect.bounds];
        objc_setAssociatedObject(effect, &maskViewKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(effect, &originalHitKey, @(effect.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }
      NSDictionary *key = @{@"rejected": @YES, @"y": @(rect.origin.y), @"bounds": [NSValue valueWithCGRect:effect.bounds]};
      if (![previous isEqual:key]) {
        ((CAGradientLayer *)mask.layer).colors = @[(__bridge id)UIColor.clearColor.CGColor, (__bridge id)UIColor.clearColor.CGColor];
        ((CAGradientLayer *)mask.layer).locations = @[@0, @1];
        mask.frame = effect.bounds; mask.userInteractionEnabled = NO;
        effect.maskView = nil; effect.maskView = mask;
        effect.userInteractionEnabled = NO;
        objc_setAssociatedObject(effect, &maskKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }
      continue;
    }
    if (!chosen || effect.bounds.size.height <= 0) {
      if (previous) {
        effect.maskView = nil;
        effect.userInteractionEnabled = [objc_getAssociatedObject(effect, &originalHitKey) boolValue];
        objc_setAssociatedObject(effect, &maskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(effect, &maskViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(effect, &originalHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }
      continue;
    }
    NSDictionary *key = @{@"edge": chosen, @"y": @(rect.origin.y),
                          @"bounds": [NSValue valueWithCGRect:effect.bounds]};
    if ([previous isEqual:key]) continue;
    WenkuFeatherMask *mask = objc_getAssociatedObject(effect, &maskViewKey);
    if (!mask) {
      mask = [[WenkuFeatherMask alloc] initWithFrame:CGRectZero];
      objc_setAssociatedObject(effect, &maskViewKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(effect, &originalHitKey, @(effect.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    mask.userInteractionEnabled = NO;
    CAGradientLayer *gradient = (CAGradientLayer *)mask.layer;
    // Keep the SAME full-height mask and stops as a native control scrolls.
    // Its relative origin changes; no new mask view/colours/Gaussian per frame.
    if (![previous[@"edge"] isEqual:chosen]) {
      NSMutableArray *colors = [NSMutableArray array];
      NSMutableArray *locations = [NSMutableArray array];
      for (NSInteger i = 0; i < 8; i++) {
        CGFloat y = [chosen[@"y"] doubleValue] + [chosen[@"height"] doubleValue] * i / 7;
        [colors addObject:(__bridge id)[UIColor colorWithWhite:0 alpha:AlphaAt(chosen, y)].CGColor];
        [locations addObject:@(i / 7.0)];
      }
      gradient.colors = colors; gradient.locations = locations;
      gradient.startPoint = CGPointMake(.5, 0); gradient.endPoint = CGPointMake(.5, 1);
    }
    mask.frame = CGRectMake(0, [chosen[@"y"] doubleValue] - CGRectGetMinY(rect),
                            effect.bounds.size.width, [chosen[@"height"] doubleValue]);
    // Apple's supported mask API forwards the mask to the effect's internals.
    // A mask on the SUPERview would break the effect. Reset after size changes.
    effect.maskView = nil; effect.maskView = mask;
    effect.userInteractionEnabled = NO;
    objc_setAssociatedObject(effect, &maskKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  [CATransaction commit];
}
@end
