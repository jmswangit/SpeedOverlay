#import <UIKit/UIKit.h>
#import <float.h>
#import <YouTubeHeader/UIView+YouTube.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTDefaultTypeStyle.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTTypeStyle.h>

#define OVERLAY_BUTTON_SIZE 24.0
#define SPEED_DISPLAY_WIDTH 42.0

static NSString *const SpeedOverlayUpdateNotification = @"SpeedOverlayUpdateNotification";

// Properties/methods that exist at runtime but are missing from the public
// YouTubeHeader set.
@interface YTQTMButton (SpeedOverlay)
@property (nonatomic, strong, readwrite) UIColor *customTitleColor;
@end

@interface YTPlayerViewController (SpeedOverlay)
- (void)setPlaybackRate:(float)rate;
- (float)playbackRate;
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

static YTQTMButton *SpeedMakeButton(NSString *title, NSString *accessibilityLabel, CGFloat width) {
    YTQTMButton *button = [%c(YTQTMButton) textButton];
    button.accessibilityLabel = accessibilityLabel;
    button.customTitleColor = [%c(YTColor) white1];
    YTDefaultTypeStyle *style = [%c(YTTypeStyle) defaultTypeStyle];
    UIFont *font = [style respondsToSelector:@selector(ytSansFontOfSize:weight:)]
        ? [style ytSansFontOfSize:10 weight:UIFontWeightSemibold]
        : [style fontOfSize:9.5 weight:UIFontWeightSemibold];
    button.titleLabel.font = font;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    button.contentEdgeInsets = UIEdgeInsetsZero;
#pragma clang diagnostic pop
    button.sizeWithPaddingAndInsets = NO;
    [button yt_setWidth:width];
    [button setTitle:title forState:UIControlStateNormal];
    button.alpha = 0.0;
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

%group Top

%hook YTMainAppControlsOverlayView

%property (retain, nonatomic) YTQTMButton *speedMinusButton;
%property (retain, nonatomic) YTQTMButton *speedDisplayButton;
%property (retain, nonatomic) YTQTMButton *speedPlusButton;

- (id)initWithDelegate:(id)delegate {
    self = %orig;
    [self speedSetup];
    return self;
}

- (id)initWithDelegate:(id)delegate autoplaySwitchEnabled:(BOOL)autoplaySwitchEnabled {
    self = %orig;
    [self speedSetup];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SpeedOverlayUpdateNotification object:nil];
    %orig;
}

- (NSMutableArray *)topButtonControls {
    NSMutableArray *controls = %orig;
    return [self speedInject:controls];
}

- (NSMutableArray *)topControls {
    NSMutableArray *controls = %orig;
    return [self speedInject:controls];
}

- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    %orig;
    CGFloat alpha = (canceledState || !visible) ? 0.0 : 1.0;
    self.speedMinusButton.alpha = alpha;
    self.speedDisplayButton.alpha = alpha;
    self.speedPlusButton.alpha = alpha;
}

%new(v@:)
- (void)speedSetup {
    if (self.speedDisplayButton) {
        return;
    }

    self.speedMinusButton = SpeedMakeButton(@"−", @"Decrease playback speed", OVERLAY_BUTTON_SIZE);
    [self.speedMinusButton addTarget:self action:@selector(speedDidTapMinus:) forControlEvents:UIControlEventTouchUpInside];

    self.speedDisplayButton = SpeedMakeButton(gCurrentSpeedText, @"Reset playback speed to 1x", SPEED_DISPLAY_WIDTH);
    [self.speedDisplayButton addTarget:self action:@selector(speedDidTapDisplay:) forControlEvents:UIControlEventTouchUpInside];

    self.speedPlusButton = SpeedMakeButton(@"+", @"Increase playback speed", OVERLAY_BUTTON_SIZE);
    [self.speedPlusButton addTarget:self action:@selector(speedDidTapPlus:) forControlEvents:UIControlEventTouchUpInside];

    UIView *container = nil;
    @try {
        container = [self valueForKey:@"_topControlsAccessibilityContainerView"];
    } @catch (__unused NSException *exception) {
    }
    UIView *host = container ?: self;
    [host addSubview:self.speedMinusButton];
    [host addSubview:self.speedDisplayButton];
    [host addSubview:self.speedPlusButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedUpdateDisplay:) name:SpeedOverlayUpdateNotification object:nil];
}

%new(@@:@)
- (NSMutableArray *)speedInject:(NSMutableArray *)controls {
    if (!controls || !self.speedDisplayButton) {
        return controls;
    }
    if ([controls containsObject:self.speedDisplayButton]) {
        return controls;
    }
    [controls insertObject:self.speedMinusButton atIndex:0];
    [controls insertObject:self.speedDisplayButton atIndex:1];
    [controls insertObject:self.speedPlusButton atIndex:2];
    return controls;
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
    [self.speedDisplayButton setTitle:gCurrentSpeedText forState:UIControlStateNormal];
}

%new(@@:)
- (YTPlayerViewController *)speedPlayer {
    if (self.playerViewController) {
        return self.playerViewController;
    }
    return gPlayerViewController;
}

%new(v@:f)
- (void)speedApply:(float)rate {
    YTPlayerViewController *player = [self speedPlayer];
    if (player && [player respondsToSelector:@selector(setPlaybackRate:)]) {
        [player setPlaybackRate:rate];
    }
}

%new(v@:i)
- (void)speedStep:(int)direction {
    YTPlayerViewController *player = [self speedPlayer];
    float rate = gCurrentRate;
    if (player && [player respondsToSelector:@selector(playbackRate)]) {
        float current = [player playbackRate];
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
    %init(Top);
}
