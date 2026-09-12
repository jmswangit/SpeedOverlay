#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <float.h>
#import <YouTubeHeader/UIView+YouTube.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTDefaultTypeStyle.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTSettingsPickerViewController.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTTypeStyle.h>

// Base metrics (Medium size).
#define SPEED_STEP_BASE 52.0
#define SPEED_STEP_FONT_BASE 26.0
#define SPEED_DISPLAY_HEIGHT_BASE 28.0
#define SPEED_DISPLAY_FONT_BASE 16.0
#define SPEED_COLUMN_WIDTH_BASE 52.0
#define SPEED_GAP_BASE 8.0
#define SPEED_SIDE_PAD 8.0
#define SPEED_VERTICAL_PAD 0.0

#define SPEED_LEFT_INSET 0.0
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
static NSString *const SpeedOverlaySizeKey = @"SpeedOverlaySize";

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
- (NSArray<YTSettingsSectionItem *> *)speedOverlaySettingsItems;
- (YTSettingsSectionItem *)speedPickerRowWithTitle:(NSString *)title key:(NSString *)key value:(NSInteger)value;
- (void)speedSetInteger:(NSInteger)value forKey:(NSString *)key;
@end

static float gCurrentRate = 1.0f;
static NSString *gCurrentSpeedText = @"1x";
static BOOL gControlsVisible = YES;
static __weak YTPlayerViewController *gPlayerViewController = nil;

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

static BOOL SpeedOverlayEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:SpeedOverlayEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:SpeedOverlayEnabledKey];
}

static NSInteger SpeedOverlaySize(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:SpeedOverlaySizeKey] == nil) {
        return 1; // Medium
    }
    NSInteger size = [defaults integerForKey:SpeedOverlaySizeKey];
    if (size < 0) {
        size = 0;
    }
    if (size > 1) {
        size = 1;
    }
    return size;
}

static CGFloat SpeedSizeScale(void) {
    return SpeedOverlaySize() == 0 ? 0.70 : 1.00;
}

static NSString *SpeedSizeName(NSInteger size) {
    return size == 0 ? @"Small" : @"Medium";
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

static UIFont *SpeedFont(CGFloat size) {
    YTDefaultTypeStyle *style = [%c(YTTypeStyle) defaultTypeStyle];
    if ([style respondsToSelector:@selector(ytSansFontOfSize:weight:)]) {
        return [style ytSansFontOfSize:size weight:UIFontWeightSemibold];
    }
    return [style fontOfSize:size - 1.0 weight:UIFontWeightSemibold];
}

static YTQTMButton *SpeedMakeButton(NSString *title, NSString *accessibilityLabel, NSInteger tag) {
    YTQTMButton *button = [%c(YTQTMButton) textButton];
    button.tag = tag;
    button.accessibilityLabel = accessibilityLabel;
    button.customTitleColor = [%c(YTColor) white1];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    button.contentEdgeInsets = UIEdgeInsetsZero;
#pragma clang diagnostic pop
    button.sizeWithPaddingAndInsets = NO;
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

    CAShapeLayer *oval = [CAShapeLayer layer];
    oval.name = @"SpeedOverlayOval";
    oval.fillColor = [[UIColor blackColor] colorWithAlphaComponent:0.32].CGColor;
    oval.shadowColor = [UIColor blackColor].CGColor;
    oval.shadowOpacity = 0.55;
    oval.shadowRadius = 10.0;
    oval.shadowOffset = CGSizeMake(0.0, 3.0);
    [container.layer insertSublayer:oval atIndex:0];

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedControlsVisibilityChanged:) name:SpeedOverlayVisibilityNotification object:nil];
    [self speedRefreshVisibility];
}

%new(v@:)
- (void)speedLayoutControls {
    UIView *container = [self.view viewWithTag:kSpeedContainerTag];
    if (!container) {
        return;
    }

    CGFloat scale = SpeedSizeScale();
    CGFloat column = SPEED_COLUMN_WIDTH_BASE * scale;
    CGFloat stepHeight = SPEED_STEP_BASE * scale;
    CGFloat displayHeight = SPEED_DISPLAY_HEIGHT_BASE * scale;
    CGFloat gap = SPEED_GAP_BASE * scale;
    CGFloat padX = SPEED_SIDE_PAD;
    CGFloat padY = SPEED_VERTICAL_PAD;

    CGFloat contentHeight = displayHeight + stepHeight * 2.0 + gap * 2.0;
    CGFloat width = column + padX * 2.0;
    CGFloat height = contentHeight + padY * 2.0;
    CGSize bounds = self.view.bounds.size;

    // Use the window (full screen) rather than the video view, which is 16:9
    // and therefore wider than tall even in portrait.
    CGRect referenceBounds = self.view.window ? self.view.window.bounds : [UIScreen mainScreen].bounds;
    BOOL landscape = referenceBounds.size.width > referenceBounds.size.height;

    CGFloat left = SPEED_LEFT_INSET;
    if (landscape) {
        left = MAX(SPEED_LANDSCAPE_LEFT_INSET, self.view.safeAreaInsets.left + SPEED_LEFT_INSET);
    }

    CGFloat top = (bounds.height - height) / 2.0;

    container.frame = CGRectMake(left, top, width, height);

    CAShapeLayer *oval = nil;
    for (CALayer *sublayer in container.layer.sublayers) {
        if ([sublayer.name isEqualToString:@"SpeedOverlayOval"]) {
            oval = (CAShapeLayer *)sublayer;
            break;
        }
    }
    if (oval) {
        CGFloat ovalWidth = width / 2.0;
        CGRect ovalRect = CGRectMake((width - ovalWidth) / 2.0, 0.0, ovalWidth, height);
        oval.frame = container.bounds;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:ovalRect cornerRadius:ovalWidth / 2.0];
        oval.path = path.CGPath;
        oval.shadowPath = path.CGPath;
    }

    UIView *plus = [container viewWithTag:kSpeedPlusTag];
    UIView *display = [container viewWithTag:kSpeedDisplayTag];
    UIView *minus = [container viewWithTag:kSpeedMinusTag];

    plus.frame = CGRectMake(padX, padY, column, stepHeight);
    display.frame = CGRectMake(padX, padY + stepHeight + gap, column, displayHeight);
    minus.frame = CGRectMake(padX, padY + stepHeight + gap + displayHeight + gap, column, stepHeight);

    ((YTQTMButton *)plus).titleLabel.font = SpeedFont(SPEED_STEP_FONT_BASE * scale);
    ((YTQTMButton *)minus).titleLabel.font = SpeedFont(SPEED_STEP_FONT_BASE * scale);
    ((YTQTMButton *)display).titleLabel.font = SpeedFont(SPEED_DISPLAY_FONT_BASE * scale);

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
    [self speedLayoutControls];
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
    BOOL visible = SpeedOverlayEnabled() && gControlsVisible;
    container.userInteractionEnabled = visible;
    // Use alpha (not hidden) so this animates with YouTube's own controls,
    // which fade inside a UIView animation block.
    container.alpha = visible ? 1.0 : 0.0;
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

- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == YT_VIDEO_OVERLAY_SECTION) {
        NSMutableArray *newItems = [sectionItems mutableCopy];
        [newItems addObjectsFromArray:[self speedOverlaySettingsItems]];
        %orig(newItems, category, title, titleDescription, headerHidden);
        return;
    }
    %orig;
}

- (void)setSectionItems:(NSMutableArray<YTSettingsSectionItem *> *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(YTIIcon *)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == YT_VIDEO_OVERLAY_SECTION) {
        NSMutableArray *newItems = [sectionItems mutableCopy];
        [newItems addObjectsFromArray:[self speedOverlaySettingsItems]];
        %orig(newItems, category, title, icon, titleDescription, headerHidden);
        return;
    }
    %orig;
}

%new(v@:q@)
- (void)speedSetInteger:(NSInteger)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:SpeedOverlayUpdateNotification object:nil];
    [self reloadData];
}

%new(@@:@q)
- (YTSettingsSectionItem *)speedPickerRowWithTitle:(NSString *)title key:(NSString *)key value:(NSInteger)value {
    return [%c(YTSettingsSectionItem) checkmarkItemWithTitle:title selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger index) {
        [self speedSetInteger:value forKey:key];
        return YES;
    }];
}

%new(@@:)
- (NSArray<YTSettingsSectionItem *> *)speedOverlaySettingsItems {
    Class itemClass = %c(YTSettingsSectionItem);
    NSMutableArray<YTSettingsSectionItem *> *items = [NSMutableArray array];

    YTSettingsSectionItem *header = [itemClass itemWithTitle:@"SpeedOverlay" accessibilityIdentifier:nil detailTextBlock:nil selectBlock:nil];
    header.enabled = NO;
    [items addObject:header];

    [items addObject:[itemClass switchItemWithTitle:@"Enabled"
                                   titleDescription:nil
                            accessibilityIdentifier:nil
                                           switchOn:SpeedOverlayEnabled()
                                        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:SpeedOverlayEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:SpeedOverlayUpdateNotification object:nil];
        [self reloadData];
        return YES;
    }
                                      settingItemId:0]];

    [items addObject:[itemClass itemWithTitle:@"Size"
                          accessibilityIdentifier:nil
                              detailTextBlock:^NSString *() {
        return SpeedSizeName(SpeedOverlaySize());
    }
                                  selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger index) {
        NSArray *rows = @[
            [self speedPickerRowWithTitle:@"Small" key:SpeedOverlaySizeKey value:0],
            [self speedPickerRowWithTitle:@"Medium" key:SpeedOverlaySizeKey value:1],
        ];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Size"
                                                                                          pickerSectionTitle:nil
                                                                                                        rows:rows
                                                                                           selectedItemIndex:SpeedOverlaySize()
                                                                                             parentResponder:[self parentResponder]];
        [self pushViewController:picker];
        return YES;
    }]];

    return items;
}

%end

%end

%ctor {
    %init(Video);
    %init(Controls);
    %init(Overlay);
    %init(Settings);
}
