#import <UIKit/UIKit.h>
#import <float.h>
#import <objc/runtime.h>
#import <YouTubeHeader/UIView+YouTube.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTDefaultTypeStyle.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTTypeStyle.h>

#define OVERLAY_BUTTON_HEIGHT 24.0
#define SPEED_BUTTON_WIDTH 44.0
#define SPEED_BUTTON_GAP 6.0
#define SPEED_LEFT_INSET 10.0

// View tags for our injected controls.
static const NSInteger kSpeedContainerTag = 'scnt';
static const NSInteger kSpeedMinusTag = 'smns';
static const NSInteger kSpeedDisplayTag = 'sdsp';
static const NSInteger kSpeedPlusTag = 'spls';

static NSString *const SpeedOverlayUpdateNotification = @"SpeedOverlayUpdateNotification";

// Methods that exist at runtime but are missing from YouTubeHeader.
@interface YTQTMButton (SpeedOverlay)
@property (nonatomic, strong, readwrite) UIColor *customTitleColor;
@end

@interface YTPlayerViewController (SpeedOverlay)
- (void)setPlaybackRate:(float)rate;
- (float)playbackRate;
- (void)speedStoreRate:(float)rate;
@end

@interface YTMainAppVideoPlayerOverlayViewController (SpeedOverlay)
- (void)speedSetupControls;
- (void)speedLayoutControls;
- (void)speedDidTapMinus:(id)sender;
- (void)speedDidTapPlus:(id)sender;
- (void)speedDidTapDisplay:(id)sender;
- (void)speedUpdateDisplay:(id)note;
- (void)speedApply:(float)rate;
- (void)speedStep:(int)direction;
@end

static NSArray<NSNumber *> *SpeedValues() {
    static NSArray<NSNumber *> *values;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        values = @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0,
                   @2.25, @2.5, @2.75, @3.0, @3.5, @4.0, @4.5, @5.0];
    });
    return values;
}

static NSString *SpeedLabel(float rate) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;
    return [NSString stringWithFormat:@"%@x", [formatter stringFromNumber:@(rate)]];
}

static float gCurrentRate = 1.0f;
static NSString *gCurrentSpeedText = @"1x";
static __weak YTPlayerViewController *gPlayerViewController = nil;

static NSUInteger NearestSpeedIndex(float rate) {
    NSArray<NSNumber *> *values = SpeedValues();
    NSUInteger best = 0;
    float bestDelta = FLT_MAX;
    for (NSUInteger i = 0; i < values.count; i++) {
        float delta = fabsf(values[i].floatValue - rate);
        if (delta < bestDelta) {
            bestDelta = delta;
            best = i;
        }
    }
    return best;
}

static YTQTMButton *SpeedMakeButton(NSString *title, NSString *accessibilityLabel, NSInteger tag) {
    YTQTMButton *button = [%c(YTQTMButton) textButton];
    button.tag = tag;
    button.accessibilityLabel = accessibilityLabel;
    button.customTitleColor = [%c(YTColor) white1];
    YTDefaultTypeStyle *style = [%c(YTTypeStyle) defaultTypeStyle];
    UIFont *font = [style respondsToSelector:@selector(ytSansFontOfSize:weight:)]
        ? [style ytSansFontOfSize:12 weight:UIFontWeightSemibold]
        : [style fontOfSize:11 weight:UIFontWeightSemibold];
    button.titleLabel.font = font;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    button.contentEdgeInsets = UIEdgeInsetsZero;
#pragma clang diagnostic pop
    button.sizeWithPaddingAndInsets = NO;
    [button yt_setSize:CGSizeMake(SPEED_BUTTON_WIDTH, OVERLAY_BUTTON_HEIGHT)];
    [button setTitle:title forState:UIControlStateNormal];
    return button;
}

%group Video

%hook YTPlayerViewController

- (void)viewDidLoad {
    %orig;
    gPlayerViewController = self;
    float rate = 1.0f;
    if ([self respondsToSelector:@selector(playbackRate)]) {
        float current = [self playbackRate];
        if (current > 0.0f) {
            rate = current;
        }
    }
    [self speedStoreRate:rate];
}

- (void)setPlaybackRate:(float)rate {
    if (rate > 0.0f) {
        [self speedStoreRate:rate];
    }
    %orig;
}

%new(v@:f)
- (void)speedStoreRate:(float)rate {
    gPlayerViewController = self;
    gCurrentRate = rate;
    gCurrentSpeedText = SpeedLabel(rate);
    [[NSNotificationCenter defaultCenter] postNotificationName:SpeedOverlayUpdateNotification object:nil];
}

%end

%end

%group Overlay

%hook YTMainAppVideoPlayerOverlayViewController

- (void)viewDidLoad {
    %orig;
    [self speedSetupControls];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [self speedLayoutControls];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SpeedOverlayUpdateNotification object:nil];
    %orig;
}

%new(v@:)
- (void)speedSetupControls {
    if ([self.view viewWithTag:kSpeedContainerTag]) {
        return;
    }

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.tag = kSpeedContainerTag;
    container.backgroundColor = [UIColor clearColor];

    YTQTMButton *plus = SpeedMakeButton(@"+", @"Increase playback speed", kSpeedPlusTag);
    [plus addTarget:self action:@selector(speedDidTapPlus:) forControlEvents:UIControlEventTouchUpInside];

    YTQTMButton *display = SpeedMakeButton(gCurrentSpeedText, @"Reset playback speed to 1x", kSpeedDisplayTag);
    [display addTarget:self action:@selector(speedDidTapDisplay:) forControlEvents:UIControlEventTouchUpInside];

    YTQTMButton *minus = SpeedMakeButton(@"−", @"Decrease playback speed", kSpeedMinusTag);
    [minus addTarget:self action:@selector(speedDidTapMinus:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:plus];
    [container addSubview:display];
    [container addSubview:minus];
    [self.view addSubview:container];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedUpdateDisplay:) name:SpeedOverlayUpdateNotification object:nil];
}

%new(v@:)
- (void)speedLayoutControls {
    UIView *container = [self.view viewWithTag:kSpeedContainerTag];
    if (!container) {
        return;
    }

    CGFloat width = SPEED_BUTTON_WIDTH;
    CGFloat height = OVERLAY_BUTTON_HEIGHT;
    CGFloat gap = SPEED_BUTTON_GAP;
    CGFloat totalHeight = height * 3.0 + gap * 2.0;
    CGSize bounds = self.view.bounds.size;

    container.frame = CGRectMake(SPEED_LEFT_INSET,
                                 (bounds.height - totalHeight) / 2.0,
                                 width,
                                 totalHeight);
    [container viewWithTag:kSpeedPlusTag].frame = CGRectMake(0.0, 0.0, width, height);
    [container viewWithTag:kSpeedDisplayTag].frame = CGRectMake(0.0, height + gap, width, height);
    [container viewWithTag:kSpeedMinusTag].frame = CGRectMake(0.0, (height + gap) * 2.0, width, height);

    [self.view bringSubviewToFront:container];
}

%new(v@:@)
- (void)speedDidTapMinus:(id)sender {
    [self speedStep:-1];
}

%new(v@:@)
- (void)speedDidTapPlus:(id)sender {
    [self speedStep:1];
}

%new(v@:@)
- (void)speedDidTapDisplay:(id)sender {
    [self speedApply:1.0f];
}

%new(v@:@)
- (void)speedUpdateDisplay:(id)note {
    YTQTMButton *display = (YTQTMButton *)[self.view viewWithTag:kSpeedDisplayTag];
    [display setTitle:gCurrentSpeedText forState:UIControlStateNormal];
}

%new(v@:f)
- (void)speedApply:(float)rate {
    if (gPlayerViewController && [gPlayerViewController respondsToSelector:@selector(setPlaybackRate:)]) {
        [gPlayerViewController setPlaybackRate:rate];
    }
}

%new(v@:i)
- (void)speedStep:(int)direction {
    float rate = gCurrentRate;
    if (gPlayerViewController && [gPlayerViewController respondsToSelector:@selector(playbackRate)]) {
        float current = [gPlayerViewController playbackRate];
        if (current > 0.0f) {
            rate = current;
        }
    }

    NSArray<NSNumber *> *values = SpeedValues();
    NSInteger index = (NSInteger)NearestSpeedIndex(rate) + direction;
    if (index < 0) {
        index = 0;
    }
    if (index >= (NSInteger)values.count) {
        index = (NSInteger)values.count - 1;
    }
    [self speedApply:values[index].floatValue];
}

%end

%end

%ctor {
    %init(Video);
    %init(Overlay);
}
