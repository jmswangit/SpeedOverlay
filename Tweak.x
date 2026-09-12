#import <UIKit/UIKit.h>
#import <float.h>
#import <YouTubeHeader/UIView+YouTube.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTDefaultTypeStyle.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTTypeStyle.h>

#define SPEED_COLUMN_WIDTH 96.0
#define SPEED_DISPLAY_HEIGHT 44.0
#define SPEED_STEP_HEIGHT 96.0
#define SPEED_DISPLAY_FONT 24.0
#define SPEED_STEP_FONT 48.0
#define SPEED_BUTTON_GAP 10.0
#define SPEED_LEFT_INSET 10.0
#define SPEED_LANDSCAPE_LEFT_INSET 54.0

// YTVideoOverlay's "Video Overlay" settings section.
#define YT_VIDEO_OVERLAY_SECTION 1222

// View tags for our injected controls.
static const NSInteger kSpeedContainerTag = 'scnt';
static const NSInteger kSpeedMinusTag = 'smns';
static const NSInteger kSpeedDisplayTag = 'sdsp';
static const NSInteger kSpeedPlusTag = 'spls';

static NSString *const SpeedOverlayUpdateNotification = @"SpeedOverlayUpdateNotification";
static NSString *const SpeedOverlayVisibilityNotification = @"SpeedOverlayVisibilityNotification";
static NSString *const SpeedOverlayVisibilityKey = @"visible";
static NSString *const SpeedOverlayEnabledKey = @"SpeedOverlayEnabled";

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
- (void)speedControlsVisibilityChanged:(NSNotification *)note;
- (void)speedRefreshVisibility;
- (void)speedApply:(float)rate;
- (void)speedStep:(int)direction;
@end

@interface YTSettingsViewController (SpeedOverlay)
- (YTSettingsSectionItem *)speedOverlaySettingsItem;
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
static BOOL gControlsVisible = YES;
static __weak YTPlayerViewController *gPlayerViewController = nil;

static BOOL SpeedOverlayEnabled() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:SpeedOverlayEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SpeedOverlayEnabledKey];
}

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

static YTQTMButton *SpeedMakeButton(NSString *title, NSString *accessibilityLabel, NSInteger tag, CGFloat fontSize, CGFloat width, CGFloat height) {
    YTQTMButton *button = [%c(YTQTMButton) textButton];
    button.tag = tag;
    button.accessibilityLabel = accessibilityLabel;
    button.customTitleColor = [%c(YTColor) white1];
    YTDefaultTypeStyle *style = [%c(YTTypeStyle) defaultTypeStyle];
    UIFont *font = [style respondsToSelector:@selector(ytSansFontOfSize:weight:)]
        ? [style ytSansFontOfSize:fontSize weight:UIFontWeightSemibold]
        : [style fontOfSize:fontSize - 1.0 weight:UIFontWeightSemibold];
    button.titleLabel.font = font;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    button.contentEdgeInsets = UIEdgeInsetsZero;
#pragma clang diagnostic pop
    button.sizeWithPaddingAndInsets = NO;
    [button yt_setSize:CGSizeMake(width, height)];
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

%group Controls

%hook YTMainAppControlsOverlayView

- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    %orig;
    BOOL shown = visible && !canceledState;
    [[NSNotificationCenter defaultCenter] postNotificationName:SpeedOverlayVisibilityNotification
                                                        object:nil
                                                      userInfo:@{SpeedOverlayVisibilityKey: @(shown)}];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

    YTQTMButton *plus = SpeedMakeButton(@"+", @"Increase playback speed", kSpeedPlusTag, SPEED_STEP_FONT, SPEED_COLUMN_WIDTH, SPEED_STEP_HEIGHT);
    [plus addTarget:self action:@selector(speedDidTapPlus:) forControlEvents:UIControlEventTouchUpInside];

    YTQTMButton *display = SpeedMakeButton(gCurrentSpeedText, @"Reset playback speed to 1x", kSpeedDisplayTag, SPEED_DISPLAY_FONT, SPEED_COLUMN_WIDTH, SPEED_DISPLAY_HEIGHT);
    [display addTarget:self action:@selector(speedDidTapDisplay:) forControlEvents:UIControlEventTouchUpInside];

    YTQTMButton *minus = SpeedMakeButton(@"−", @"Decrease playback speed", kSpeedMinusTag, SPEED_STEP_FONT, SPEED_COLUMN_WIDTH, SPEED_STEP_HEIGHT);
    [minus addTarget:self action:@selector(speedDidTapMinus:) forControlEvents:UIControlEventTouchUpInside];

    [container addSubview:plus];
    [container addSubview:display];
    [container addSubview:minus];
    [self.view addSubview:container];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedUpdateDisplay:) name:SpeedOverlayUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedControlsVisibilityChanged:) name:SpeedOverlayVisibilityNotification object:nil];
    [self speedRefreshVisibility];
}

%new(v@:)
- (void)speedLayoutControls {
    UIView *container = [self.view viewWithTag:kSpeedContainerTag];
    if (!container) {
        return;
    }

    CGFloat width = SPEED_COLUMN_WIDTH;
    CGFloat displayHeight = SPEED_DISPLAY_HEIGHT;
    CGFloat stepHeight = SPEED_STEP_HEIGHT;
    CGFloat gap = SPEED_BUTTON_GAP;
    CGFloat totalHeight = displayHeight + stepHeight * 2.0 + gap * 2.0;
    CGSize bounds = self.view.bounds.size;

    BOOL landscape = NO;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = self.view.window.windowScene;
        if (windowScene) {
            landscape = UIInterfaceOrientationIsLandscape(windowScene.interfaceOrientation);
        }
    }
    if (!landscape) {
        landscape = bounds.width > bounds.height;
    }

    CGFloat left = landscape ? SPEED_LANDSCAPE_LEFT_INSET : SPEED_LEFT_INSET;
    left = MAX(left, self.view.safeAreaInsets.left + SPEED_LEFT_INSET);

    container.frame = CGRectMake(left, (bounds.height - totalHeight) / 2.0, width, totalHeight);
    [container viewWithTag:kSpeedPlusTag].frame = CGRectMake(0.0, 0.0, width, stepHeight);
    [container viewWithTag:kSpeedDisplayTag].frame = CGRectMake(0.0, stepHeight + gap, width, displayHeight);
    [container viewWithTag:kSpeedMinusTag].frame = CGRectMake(0.0, stepHeight + gap + displayHeight + gap, width, stepHeight);

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
    [self speedRefreshVisibility];
}

%new(v@:@)
- (void)speedControlsVisibilityChanged:(NSNotification *)note {
    gControlsVisible = [note.userInfo[SpeedOverlayVisibilityKey] boolValue];
    [self speedRefreshVisibility];
}

%new(v@:)
- (void)speedRefreshVisibility {
    UIView *container = [self.view viewWithTag:kSpeedContainerTag];
    if (!container) {
        return;
    }
    container.hidden = !(SpeedOverlayEnabled() && gControlsVisible);
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

%group Settings

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)items forCategory:(NSUInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == YT_VIDEO_OVERLAY_SECTION) {
        NSMutableArray *newItems = [items mutableCopy];
        [newItems addObject:[self speedOverlaySettingsItem]];
        %orig(newItems, category, title, titleDescription, headerHidden);
        return;
    }
    %orig;
}

- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)items forCategory:(NSUInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == YT_VIDEO_OVERLAY_SECTION) {
        NSMutableArray *newItems = [items mutableCopy];
        [newItems addObject:[self speedOverlaySettingsItem]];
        %orig(newItems, category, title, icon, titleDescription, headerHidden);
        return;
    }
    %orig;
}

%new(@@:)
- (YTSettingsSectionItem *)speedOverlaySettingsItem {
    return [%c(YTSettingsSectionItem) switchItemWithTitle:@"SpeedOverlay"
                                         titleDescription:@"Replacement speed controls with a live current-speed display"
                                  accessibilityIdentifier:nil
                                                 switchOn:SpeedOverlayEnabled()
                                              switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:SpeedOverlayEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:SpeedOverlayUpdateNotification object:nil];
        return YES;
    }
                                            settingItemId:0];
}

%end

%end

%ctor {
    %init(Video);
    %init(Controls);
    %init(Overlay);
    %init(Settings);
}
