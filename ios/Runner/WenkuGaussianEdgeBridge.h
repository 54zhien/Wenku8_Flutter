#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Compatibility adapter for Flutter engine 052f31d (Flutter 3.41.5).
/// Preserves the engine's Gaussian; forwards only the app's pinned feather.
@interface WenkuGaussianEdgeBridge : NSObject
@property(nonatomic, weak, nullable) UIView *flutterView;
@property(nonatomic, readonly) BOOL compatible;
@property(nonatomic, readonly) NSUInteger maskedFilterCount;
- (BOOL)setEdge:(NSDictionary *)edge;
- (void)removeEdge:(NSNumber *)identifier;
- (void)trackView:(UIView *)view;
+ (BOOL)viewHasExternalFilter:(UIView *)view;
@end

#if DEBUG
/// Hosted tests exercise the real pinned engine classes, not a fake filter.
FOUNDATION_EXPORT UIView * _Nullable WenkuGaussianProbeClip(CGRect frame);
FOUNDATION_EXPORT BOOL WenkuGaussianProbeApply(UIView *clip, CGFloat sigma);
FOUNDATION_EXPORT BOOL WenkuGaussianProbeClear(UIView *clip);
#endif

/// One full-width untinted Gaussian, using the pinned engine's filter factory.
/// Its mask is directly on the effect; it does not hook ancestor clipping.
FOUNDATION_EXPORT UIVisualEffectView * _Nullable WenkuGaussianCreatePlaneEffect(
    CGRect frame, CGFloat sigma, CGFloat plateau, BOOL fromBottom);

NS_ASSUME_NONNULL_END
