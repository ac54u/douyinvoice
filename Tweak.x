#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>

// =======================================================
// 全局配置与变量
// =======================================================
#define VOICE_ROOT_PATH [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DouyinVoice"]
#define MAX_DURATION 29.5

static NSString *g_pendingReplacePath = nil;
static BOOL g_isArmed = NO;
static id g_currentVideoModel = nil; 

// 【新增】：用一个弱引用指针保存当前的视频控制器，防内存泄漏
static __weak id g_currentFeedVC = nil; 

#define COLOR_TEXT_MAIN [UIColor labelColor]
#define COLOR_TEXT_SUB [UIColor secondaryLabelColor]
#define COLOR_BG_GRAY [UIColor systemGroupedBackgroundColor]
#define COLOR_ICON_GREEN [UIColor systemGreenColor]
#define COLOR_ICON_BLUE [UIColor systemBlueColor]
#define COLOR_ICON_RED [UIColor systemRedColor]

@interface AWEAwemePlayInteractionViewController : UIViewController @end
@interface AWEPlayInteractionViewController : UIViewController @end
@interface AWEAwemeCellViewController : UIViewController @end
@interface AWEFeedCellViewController : UIViewController @end
@interface AWEAwemePlayVideoViewController : UIViewController @end

// =======================================================
// 工具类 (进度条及音频处理核心)
// =======================================================
@interface VoiceHelper : NSObject
+ (void)processAndReplace:(NSString *)targetPath;
+ (void)performReplaceFrom:(NSString *)srcPath to:(NSString *)targetPath isTrimmed:(BOOL)trimmed;
+ (void)showToast:(NSString *)msg color:(UIColor *)color;
+ (void)showProgressHUD:(NSString *)title;
+ (void)updateProgressHUD:(float)progress title:(NSString *)title;
+ (void)hideProgressHUD;
+ (NSString *)formatDuration:(NSTimeInterval)duration;
+ (NSString *)formatSize:(long long)size;
+ (NSTimeInterval)getAudioDuration:(NSString *)path;
@end

static UIView *g_progressToast = nil;
static UIProgressView *g_progressBar = nil;
static UILabel *g_progressLabel = nil;

@implementation VoiceHelper
+ (void)processAndReplace:(NSString *)targetPath {
    if (!g_isArmed || !g_pendingReplacePath) return;
    g_isArmed = NO; 

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:g_pendingReplacePath]) return;
    
    NSTimeInterval duration = [self getAudioDuration:g_pendingReplacePath];
    
    if (duration <= MAX_DURATION) {
        [self performReplaceFrom:g_pendingReplacePath to:targetPath isTrimmed:NO];
        g_pendingReplacePath = nil;
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self showToast:@"⏳ 音频过长，正在裁剪..." color:[UIColor orangeColor]];
            NSString *tempTrimmedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp_trimmed.m4a"];
            if ([fm fileExistsAtPath:tempTrimmedPath]) [fm removeItemAtPath:tempTrimmedPath error:nil];
            
            AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:g_pendingReplacePath]];
            AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
            exportSession.outputURL = [NSURL fileURLWithPath:tempTrimmedPath];
            exportSession.outputFileType = AVFileTypeAppleM4A;
            exportSession.timeRange = CMTimeRangeFromTimeToTime(CMTimeMake(0, 1), CMTimeMakeWithSeconds(MAX_DURATION, 600));
            
            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            [exportSession exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sema); }];
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
            
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                [self performReplaceFrom:tempTrimmedPath to:targetPath isTrimmed:YES];
            } else {
                [self showToast:@"❌ 裁剪失败，原样替换" color:[UIColor redColor]];
                [self performReplaceFrom:g_pendingReplacePath to:targetPath isTrimmed:NO];
            }
            g_pendingReplacePath = nil;
        });
    }
}
+ (void)performReplaceFrom:(NSString *)srcPath to:(NSString *)targetPath isTrimmed:(BOOL)trimmed {
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:targetPath]) [fm removeItemAtPath:targetPath error:nil];
    [fm copyItemAtPath:srcPath toPath:targetPath error:&err];
    if (!err) {
        NSString *msg = trimmed ? @"✅ 已裁剪并替换 (29s)" : @"✅ 语音替换发送成功！";
        [self showToast:msg color:[UIColor colorWithRed:0 green:0.7 blue:0.4 alpha:0.9]];
    }
}
+ (void)showToast:(NSString *)msg color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].windows.firstObject;
        if (!win) return;
        UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(win.center.x - 110, 100, 220, 44)];
        toast.backgroundColor = color;
        toast.layer.cornerRadius = 22;
        toast.clipsToBounds = YES;
        UILabel *lbl = [[UILabel alloc] initWithFrame:toast.bounds];
        lbl.text = msg; lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter; lbl.font = [UIFont boldSystemFontOfSize:14];
        [toast addSubview:lbl]; [win addSubview:toast];
        toast.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(BOOL f){
            [UIView animateWithDuration:0.5 delay:2.0 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL f){ [toast removeFromSuperview]; }];
        }];
    });
}
+ (void)showProgressHUD:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_progressToast) { [g_progressToast removeFromSuperview]; }
        UIWindow *win = [UIApplication sharedApplication].windows.firstObject;
        if (!win) return;
        g_progressToast = [[UIView alloc] initWithFrame:CGRectMake(win.center.x - 120, 100, 240, 65)];
        g_progressToast.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
        g_progressToast.layer.cornerRadius = 14;
        g_progressToast.clipsToBounds = YES;
        g_progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 12, 220, 20)];
        g_progressLabel.text = title;
        g_progressLabel.textColor = [UIColor whiteColor];
        g_progressLabel.textAlignment = NSTextAlignmentCenter;
        g_progressLabel.font = [UIFont boldSystemFontOfSize:14];
        [g_progressToast addSubview:g_progressLabel];
        g_progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        g_progressBar.frame = CGRectMake(20, 42, 200, 4);
        g_progressBar.progressTintColor = COLOR_ICON_GREEN;
        g_progressBar.trackTintColor = [UIColor darkGrayColor];
        g_progressBar.progress = 0.0;
        g_progressBar.layer.cornerRadius = 2;
        g_progressBar.clipsToBounds = YES;
        [g_progressToast addSubview:g_progressBar];
        g_progressToast.alpha = 0;
        [win addSubview:g_progressToast];
        [UIView animateWithDuration:0.2 animations:^{ g_progressToast.alpha = 1; }];
    });
}
+ (void)updateProgressHUD:(float)progress title:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_progressToast) {
            if (title) g_progressLabel.text = title;
            [g_progressBar setProgress:progress animated:YES];
        }
    });
}
+ (void)hideProgressHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_progressToast) {
            [UIView animateWithDuration:0.3 animations:^{ g_progressToast.alpha = 0; } completion:^(BOOL f) { [g_progressToast removeFromSuperview]; g_progressToast = nil; }];
        }
    });
}
+ (NSString *)formatDuration:(NSTimeInterval)duration {
    int min = (int)duration / 60; int sec = (int)duration % 60;
    return min > 0 ? [NSString stringWithFormat:@"%dm %ds", min, sec] : [NSString stringWithFormat:@"%.1fs", duration];
}
+ (NSString *)formatSize:(long long)size {
    if (size > 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    return size > 1024 ? [NSString stringWithFormat:@"%.1f KB", size / 1024.0] : [NSString stringWithFormat:@"%lld B", size];
}
+ (NSTimeInterval)getAudioDuration:(NSString *)path {
    return CMTimeGetSeconds([AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]].duration);
}
@end

// =======================================================
// UI: 自定义 Cell
// =======================================================
@interface VoiceFileCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *sendBtn;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, copy) void (^onPlayBlock)(void);
@property (nonatomic, copy) void (^onSendBlock)(void);
@end

@implementation VoiceFileCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _cardView.layer.cornerRadius = 12;
        [self.contentView addSubview:_cardView];
        
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_cardView addSubview:_iconView];
        
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont boldSystemFontOfSize:16];
        _nameLabel.textColor = COLOR_TEXT_MAIN;
        [_cardView addSubview:_nameLabel];
        
        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = [UIFont systemFontOfSize:12];
        _metaLabel.textColor = COLOR_ICON_GREEN;
        [_cardView addSubview:_metaLabel];
        
        _sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_sendBtn setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
        [_sendBtn setTintColor:COLOR_ICON_BLUE];
        [_sendBtn addTarget:self action:@selector(didTapSend) forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_sendBtn];
        
        _playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_playBtn setTintColor:COLOR_ICON_GREEN];
        [_playBtn addTarget:self action:@selector(didTapPlay) forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_playBtn];
        [self setIsPlaying:NO]; 
    }
    return self;
}
- (void)setIsPlaying:(BOOL)isPlaying {
    _isPlaying = isPlaying;
    UIImage *img = isPlaying ? [UIImage systemImageNamed:@"pause.fill"] : [UIImage systemImageNamed:@"play.fill"];
    [_playBtn setImage:img forState:UIControlStateNormal];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _cardView.frame = CGRectMake(16, 8, self.contentView.bounds.size.width - 32, 72);
    _iconView.frame = CGRectMake(16, 16, 40, 40);
    _sendBtn.frame = CGRectMake(_cardView.bounds.size.width - 44, 21, 30, 30);
    _playBtn.frame = CGRectMake(_cardView.bounds.size.width - 88, 21, 30, 30);
    CGFloat textX = _iconView.hidden ? 16 : 68;
    CGFloat w = _cardView.bounds.size.width - textX - 100;
    _nameLabel.frame = CGRectMake(textX, 14, w, 22);
    _metaLabel.frame = CGRectMake(textX, 38, w, 18);
}
- (void)didTapPlay { if (self.onPlayBlock) self.onPlayBlock(); }
- (void)didTapSend { if (self.onSendBlock) self.onSendBlock(); }
@end

// =======================================================
// Main Controller
// =======================================================
@interface VoiceManagerVC : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate, AVAudioPlayerDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *files;          
@property (nonatomic, strong) NSMutableArray *filteredFiles;  
@property (nonatomic, assign) BOOL isSearching;               
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSIndexPath *playingIndexPath;
@end

@implementation VoiceManagerVC
- (instancetype)initWithPath:(NSString *)path {
    if (self = [super init]) {
        self.currentPath = path ? path : VOICE_ROOT_PATH;
        self.files = [NSMutableArray array];
        self.filteredFiles = [NSMutableArray array];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = COLOR_BG_GRAY;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.currentPath withIntermediateDirectories:YES attributes:nil error:nil];
    [self setupLayout];
    [self loadFiles];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.player) { [self.player stop]; self.player = nil; }
    self.playingIndexPath = nil;
}
- (void)setupLayout {
    UIView *navBar = [[UIView alloc] init];
    navBar.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    navBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:navBar];
    [navBar.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [navBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [navBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [navBar.heightAnchor constraintEqualToConstant:60].active = YES;
    
    UIButton *leftBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *leftIcon = [self.currentPath.lastPathComponent isEqualToString:@"DouyinVoice"] ? [UIImage systemImageNamed:@"xmark"] : [UIImage systemImageNamed:@"chevron.left"];
    [leftBtn setImage:leftIcon forState:UIControlStateNormal];
    leftBtn.tintColor = COLOR_TEXT_MAIN;
    leftBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [leftBtn addTarget:self action:@selector(leftButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:leftBtn];
    [leftBtn.leadingAnchor constraintEqualToAnchor:navBar.leadingAnchor constant:15].active = YES;
    [leftBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor].active = YES;
    [leftBtn.widthAnchor constraintEqualToConstant:30].active = YES;
    [leftBtn.heightAnchor constraintEqualToConstant:30].active = YES;

    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [addBtn setImage:[UIImage systemImageNamed:@"doc.badge.plus"] forState:UIControlStateNormal];
    addBtn.tintColor = COLOR_TEXT_MAIN;
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [addBtn addTarget:self action:@selector(importFile) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:addBtn];
    [addBtn.trailingAnchor constraintEqualToAnchor:navBar.trailingAnchor constant:-15].active = YES;
    [addBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor].active = YES;
    [addBtn.widthAnchor constraintEqualToConstant:30].active = YES;
    [addBtn.heightAnchor constraintEqualToConstant:30].active = YES;

    UIButton *folderBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [folderBtn setImage:[UIImage systemImageNamed:@"folder.badge.plus"] forState:UIControlStateNormal];
    folderBtn.tintColor = COLOR_TEXT_MAIN;
    folderBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [folderBtn addTarget:self action:@selector(createNewFolder) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:folderBtn];
    [folderBtn.trailingAnchor constraintEqualToAnchor:addBtn.leadingAnchor constant:-10].active = YES;
    [folderBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor].active = YES;
    [folderBtn.widthAnchor constraintEqualToConstant:30].active = YES;
    [folderBtn.heightAnchor constraintEqualToConstant:30].active = YES;

    UIButton *extractBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [extractBtn setTitle:@"提取" forState:UIControlStateNormal];
    extractBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    extractBtn.backgroundColor = COLOR_ICON_BLUE;
    [extractBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    extractBtn.layer.cornerRadius = 6;
    extractBtn.clipsToBounds = YES;
    extractBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [extractBtn addTarget:self action:@selector(extractCurrentVideo) forControlEvents:UIControlEventTouchUpInside];
    [navBar addSubview:extractBtn];
    [extractBtn.trailingAnchor constraintEqualToAnchor:folderBtn.leadingAnchor constant:-15].active = YES;
    [extractBtn.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor].active = YES;
    [extractBtn.widthAnchor constraintEqualToConstant:46].active = YES;
    [extractBtn.heightAnchor constraintEqualToConstant:28].active = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = [self.currentPath.lastPathComponent isEqualToString:@"DouyinVoice"] ? @"语音包" : self.currentPath.lastPathComponent;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:title];
    [title.centerXAnchor constraintEqualToAnchor:navBar.centerXAnchor].active = YES;
    [title.centerYAnchor constraintEqualToAnchor:navBar.centerYAnchor].active = YES;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.backgroundColor = COLOR_BG_GRAY;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 88;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [self.tableView.topAnchor constraintEqualToAnchor:navBar.bottomAnchor].active = YES;
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 110)];
    headerView.backgroundColor = COLOR_BG_GRAY;
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(10, 5, headerView.bounds.size.width - 20, 50)];
    search.placeholder = @"搜索语音包";
    search.backgroundImage = [[UIImage alloc] init];
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.delegate = self;
    [headerView addSubview:search];
    
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 55, headerView.bounds.size.width, 50)];
    infoLabel.text = @"加载中...";
    infoLabel.numberOfLines = 3;
    infoLabel.textAlignment = NSTextAlignmentCenter;
    infoLabel.font = [UIFont systemFontOfSize:13];
    infoLabel.textColor = [UIColor secondaryLabelColor];
    infoLabel.tag = 999;
    [headerView addSubview:infoLabel];
    self.tableView.tableHeaderView = headerView;
}

- (void)createNewFolder {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建文件夹" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"请输入分类名称 (如: 搞笑, 怼人)";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *folderName = alert.textFields.firstObject.text;
        folderName = [folderName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (folderName.length > 0) {
            NSString *folderPath = [self.currentPath stringByAppendingPathComponent:folderName];
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) [VoiceHelper showToast:@"❌ 创建失败" color:COLOR_ICON_RED]; else [self loadFiles]; 
        }
    }];
    [alert addAction:cancelAction];
    [alert addAction:createAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)extractCurrentVideo {
    if (!g_currentVideoModel) { [VoiceHelper showToast:@"❌ 未获取到视频，请退出划动一下再摇" color:COLOR_ICON_RED]; return; }
    id model = g_currentVideoModel;
    NSString *fileName = @"";
    @try {
        NSArray *titleKeys = @[@"shareInfo.shareTitle", @"share_info.share_title", @"awemeModel.shareInfo.shareTitle", @"desc", @"aweme.desc", @"awemeModel.desc", @"title", @"aweme.title", @"awemeModel.title"];
        for (NSString *key in titleKeys) {
            id textObj = [model valueForKeyPath:key];
            if (!textObj) continue;
            if ([textObj isKindOfClass:[NSString class]]) { fileName = (NSString *)textObj; } 
            else if ([textObj isKindOfClass:[NSAttributedString class]]) { fileName = ((NSAttributedString *)textObj).string; } 
            else if ([textObj respondsToSelector:@selector(string)]) { fileName = [textObj performSelector:@selector(string)]; }
            else if ([textObj respondsToSelector:@selector(text)]) { fileName = [textObj performSelector:@selector(text)]; }
            if (fileName.length > 0) break;
        }
        if ([fileName containsString:@"- 抖音"]) fileName = [fileName stringByReplacingOccurrencesOfString:@"- 抖音" withString:@""];
        if ([fileName containsString:@"@"]) fileName = [[fileName componentsSeparatedByString:@"@"] firstObject];
        if (fileName.length == 0) {
            NSArray *authorKeys = @[@"author.nickname", @"aweme.author.nickname", @"awemeModel.author.nickname"];
            for (NSString *key in authorKeys) {
                id nameObj = [model valueForKeyPath:key];
                if ([nameObj isKindOfClass:[NSString class]] && ((NSString *)nameObj).length > 0) {
                    fileName = [NSString stringWithFormat:@"%@_的视频", nameObj]; break;
                }
            }
        }
        if (fileName.length > 25) fileName = [fileName substringToIndex:25]; 
    } @catch(NSException *e) {}
    
    if (!fileName || fileName.length == 0) fileName = [NSString stringWithFormat:@"提取声音_%d", arc4random_uniform(10000)];
    NSCharacterSet *illegalChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:\n\r "];
    fileName = [[fileName componentsSeparatedByCharactersInSet:illegalChars] componentsJoinedByString:@"_"];
    
    BOOL isImagePost = NO;
    @try {
        if ([model valueForKeyPath:@"imageAlbumInfo"] || [model valueForKeyPath:@"awemeModel.imageAlbumInfo"]) { isImagePost = YES; } 
        else {
            NSNumber *aType = [model valueForKey:@"awemeType"];
            if (!aType) aType = [model valueForKey:@"aweme_type"];
            if (aType && ([aType intValue] == 68 || [aType intValue] == 75 || [aType intValue] == 150)) { isImagePost = YES; }
        }
    } @catch(NSException *e){}

    NSString *urlString = nil; NSMutableArray *allUrls = [NSMutableArray array];
    NSArray *videoPaths = @[@"video.playAddr.URLList", @"video.playAddr.urlList", @"video.downloadAddr.URLList", @"video.downloadAddr.urlList", @"video.play_addr.url_list"];
    NSArray *musicPaths = @[@"music.playUrl.URLList", @"music.playUrl.urlList", @"music.play_url.url_list", @"awemeModel.music.playUrl.URLList", @"music.playAddr.URLList", @"music.playAddr.urlList", @"music.play_addr.url_list"];
    NSArray *primaryPaths = isImagePost ? musicPaths : videoPaths;
    NSArray *secondaryPaths = isImagePost ? videoPaths : musicPaths; 
    
    for (NSString *path in primaryPaths) {
        @try { NSArray *list = [model valueForKeyPath:path]; if ([list isKindOfClass:[NSArray class]]) { for (NSString *u in list) { if ([u isKindOfClass:[NSString class]] && [u hasPrefix:@"http"] && ![u containsString:@".jpg"] && ![u containsString:@".jpeg"] && ![u containsString:@".webp"]) { [allUrls addObject:u]; } } } } @catch (NSException *e) {}
    }
    if (allUrls.count == 0) {
        for (NSString *path in secondaryPaths) {
            @try { NSArray *list = [model valueForKeyPath:path]; if ([list isKindOfClass:[NSArray class]]) { for (NSString *u in list) { if ([u isKindOfClass:[NSString class]] && [u hasPrefix:@"http"] && ![u containsString:@".jpg"]) { [allUrls addObject:u]; } } } } @catch (NSException *e) {}
        }
    }
    if (allUrls.count == 0) {
        @try {
            id dict = model;
            if ([model respondsToSelector:@selector(dictionaryValue)]) dict = [model performSelector:@selector(dictionaryValue)];
            else if ([model respondsToSelector:@selector(yy_modelToJSONObject)]) dict = [model performSelector:@selector(yy_modelToJSONObject)];
            NSString *strDump = [NSString stringWithFormat:@"%@", dict];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"https?://[\\w\\-_\\.+/&:?=%%]+" options:NSRegularExpressionCaseInsensitive error:nil];
            NSArray *matches = [regex matchesInString:strDump options:0 range:NSMakeRange(0, strDump.length)];
            for (NSTextCheckingResult *match in matches) {
                NSString *u = [strDump substringWithRange:match.range];
                if (![u containsString:@".jpg"] && ![u containsString:@".png"] && ![u containsString:@".jpeg"] && ![u containsString:@"avatar"]) {
                    if ([u containsString:@"video"] || [u containsString:@"play"] || [u containsString:@"vod"] || [u containsString:@"music"]) { [allUrls addObject:u]; }
                }
            }
        } @catch (NSException *e) {}
    }

    NSArray *cdnKeywords = @[@"douyinvod.com", @"ixigua.com", @"bdxvod.com", @"huoshanvod.com", @"amemv.com", @"volces.com"];
    for (NSString *u in allUrls) { for (NSString *kw in cdnKeywords) { if ([u containsString:kw]) { urlString = u; break; } } if (urlString) break; }
    if (!urlString) { for (NSString *u in allUrls) { if (![u containsString:@"aweme.snssdk.com"]) { urlString = u; break; } } }
    if (!urlString && allUrls.count > 0) urlString = allUrls.firstObject;
    if (!urlString || urlString.length == 0) { [VoiceHelper showToast:@"❌ 链接彻底加密，无法提取" color:COLOR_ICON_RED]; return; }
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"com.ss.iphone.ugc.Aweme/290000 (iPhone; iOS 16.0; Scale/3.00)" forHTTPHeaderField:@"User-Agent"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *shortName = fileName.length > 8 ? [NSString stringWithFormat:@"%@...", [fileName substringToIndex:8]] : fileName;
        [VoiceHelper showProgressHUD:[NSString stringWithFormat:@"准备下载: %@", shortName]];
    });
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error || !data || (httpResponse.statusCode != 200 && httpResponse.statusCode != 206 && httpResponse.statusCode != 302) || data.length < 20000) {
            dispatch_async(dispatch_get_main_queue(), ^{ [VoiceHelper hideProgressHUD]; [VoiceHelper showToast:@"❌ 下载失败或被拒" color:COLOR_ICON_RED]; }); return;
        }
        NSString *tempExt = isImagePost ? @"mp3" : @"mp4";
        NSString *tempVideoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"temp_douyin_extract.%@", tempExt]];
        [data writeToFile:tempVideoPath atomically:YES];
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:tempVideoPath]];
        NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (!isImagePost && audioTracks.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [VoiceHelper hideProgressHUD]; [VoiceHelper showToast:@"❌ 提取失败：该视频无声音或音视频分离" color:COLOR_ICON_RED];
                [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
            }); return;
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:self.currentPath withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *destPath = [self.currentPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", fileName]];
        int i = 1;
        while ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
            destPath = [self.currentPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%d.m4a", fileName, i++]];
        }
        AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
        export.outputURL = [NSURL fileURLWithPath:destPath];
        export.outputFileType = AVFileTypeAppleM4A;
        dispatch_async(dispatch_get_main_queue(), ^{
            [VoiceHelper updateProgressHUD:0.0 title:@"正在解析音频..."];
            NSTimer *exportTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
                if (export.status == AVAssetExportSessionStatusExporting) {
                    [VoiceHelper updateProgressHUD:export.progress title:[NSString stringWithFormat:@"音频提取中 %.0f%%", export.progress * 100]];
                } else if (export.status == AVAssetExportSessionStatusCompleted || export.status == AVAssetExportSessionStatusFailed || export.status == AVAssetExportSessionStatusCancelled) {
                    [timer invalidate];
                }
            }];
            [[NSRunLoop mainRunLoop] addTimer:exportTimer forMode:NSRunLoopCommonModes];
        });
        [export exportAsynchronouslyWithCompletionHandler:^{
            [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [VoiceHelper hideProgressHUD];
                if (export.status == AVAssetExportSessionStatusCompleted) {
                    [VoiceHelper showToast:@"✅ 提取成功！" color:COLOR_ICON_GREEN]; [self loadFiles]; 
                } else {
                    NSString *errMsg = export.error ? [NSString stringWithFormat:@"%@ (码:%ld)", export.error.localizedDescription, (long)export.error.code] : @"未知格式不支持";
                    [VoiceHelper showToast:[NSString stringWithFormat:@"❌ 转换失败: %@", errMsg] color:COLOR_ICON_RED];
                }
            });
        }];
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *dlTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            if (task.state == NSURLSessionTaskStateCompleted || task.state == NSURLSessionTaskStateCanceling) { [timer invalidate]; } 
            else if (task.countOfBytesExpectedToReceive > 0) {
                float p = (float)task.countOfBytesReceived / (float)task.countOfBytesExpectedToReceive;
                [VoiceHelper updateProgressHUD:p title:[NSString stringWithFormat:@"下载流媒体中 %.0f%%", p * 100]];
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:dlTimer forMode:NSRunLoopCommonModes];
    });
    [task resume];
}

- (void)loadFiles {
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.currentPath error:nil];
    [self.files removeAllObjects];
    NSMutableArray *dirList = [NSMutableArray array]; NSMutableArray *fileList = [NSMutableArray array];
    long long totalSize = 0; int fileCount = 0;
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [self.currentPath stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) { [dirList addObject:item]; } else { [fileList addObject:item]; totalSize += [[[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil] fileSize]; fileCount++; }
        }
    }
    [fileList sortUsingComparator:^NSComparisonResult(NSString *file1, NSString *file2) {
        NSString *path1 = [self.currentPath stringByAppendingPathComponent:file1];
        NSString *path2 = [self.currentPath stringByAppendingPathComponent:file2];
        NSDictionary *attr1 = [[NSFileManager defaultManager] attributesOfItemAtPath:path1 error:nil];
        NSDictionary *attr2 = [[NSFileManager defaultManager] attributesOfItemAtPath:path2 error:nil];
        return [attr2.fileModificationDate compare:attr1.fileModificationDate];
    }];
    [self.files addObjectsFromArray:dirList]; [self.files addObjectsFromArray:fileList];
    UILabel *lbl = [self.tableView.tableHeaderView viewWithTag:999];
    if (lbl) lbl.text = [NSString stringWithFormat:@"共 %d 个文件 · 总大小 %@\n左滑可操作文件", fileCount, [VoiceHelper formatSize:totalSize]];
    if (self.isSearching) { [self filterContentForSearchText:((UISearchBar *)[self.tableView.tableHeaderView.subviews firstObject]).text]; } 
    else { [self.tableView reloadData]; }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) { self.isSearching = NO; [self.tableView reloadData]; }
    else { self.isSearching = YES; [self filterContentForSearchText:searchText]; }
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { [self.view endEditing:YES]; }
- (void)filterContentForSearchText:(NSString *)searchText {
    [self.filteredFiles removeAllObjects];
    for (NSString *file in self.files) { if ([file localizedCaseInsensitiveContainsString:searchText]) [self.filteredFiles addObject:file]; }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.isSearching ? self.filteredFiles.count : self.files.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VoiceFileCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[VoiceFileCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    NSString *fileName = self.isSearching ? self.filteredFiles[indexPath.row] : self.files[indexPath.row];
    NSString *path = [self.currentPath stringByAppendingPathComponent:fileName];
    BOOL isDir = NO; [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (isDir) {
        cell.iconView.hidden = NO; cell.iconView.image = [UIImage systemImageNamed:@"folder.fill"]; cell.iconView.tintColor = COLOR_ICON_BLUE;
        cell.nameLabel.text = fileName; cell.metaLabel.text = @"";
        cell.playBtn.hidden = YES; cell.sendBtn.hidden = YES;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.iconView.hidden = YES;
        long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        NSTimeInterval dur = [VoiceHelper getAudioDuration:path];
        cell.nameLabel.text = [fileName stringByDeletingPathExtension];
        cell.metaLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", [fileName pathExtension].uppercaseString, [VoiceHelper formatDuration:dur], [VoiceHelper formatSize:size]];
        cell.playBtn.hidden = NO; cell.sendBtn.hidden = NO;
        cell.accessoryType = UITableViewCellAccessoryNone;
        BOOL isThisRowPlaying = (self.playingIndexPath && indexPath.row == self.playingIndexPath.row && indexPath.section == self.playingIndexPath.section);
        cell.isPlaying = isThisRowPlaying;
        
        cell.onPlayBlock = ^{
            // 【新增体验优化】：点击试听时自动暂停背景的抖音视频
            dispatch_async(dispatch_get_main_queue(), ^{
                if (g_currentFeedVC && [g_currentFeedVC respondsToSelector:@selector(pause)]) {
                    [g_currentFeedVC performSelector:@selector(pause)];
                }
            });
            
            if (isThisRowPlaying) {
                [self.player stop]; self.player = nil; self.playingIndexPath = nil;
                [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            } else {
                if (self.playingIndexPath) {
                    NSIndexPath *prevIndex = self.playingIndexPath;
                    [self.player stop]; self.playingIndexPath = nil;
                    [tableView reloadRowsAtIndexPaths:@[prevIndex] withRowAnimation:UITableViewRowAnimationNone];
                }
                
                // 【新增体验优化】：配置 AVAudioSession，确保试听声音能破除手机静音模式
                [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
                [[AVAudioSession sharedInstance] setActive:YES error:nil];
                
                self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
                self.player.delegate = self; 
                if ([self.player play]) {
                    self.playingIndexPath = indexPath;
                    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
            }
        };
        
        cell.onSendBlock = ^{
            g_pendingReplacePath = path; g_isArmed = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"装填成功！" message:@"请返回【评论区】或【私信框】\n长按麦克风录音 1 秒即可自动替换！" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){ [self dismissViewControllerAnimated:YES completion:nil]; }]];
            [self presentViewController:alert animated:YES completion:nil];
        };
    }
    return cell;
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (self.playingIndexPath) {
        NSIndexPath *prev = self.playingIndexPath; self.playingIndexPath = nil; self.player = nil;
        [self.tableView reloadRowsAtIndexPaths:@[prev] withRowAnimation:UITableViewRowAnimationNone];
    }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *fileName = self.isSearching ? self.filteredFiles[indexPath.row] : self.files[indexPath.row];
    NSString *path = [self.currentPath stringByAppendingPathComponent:fileName];
    BOOL isDir = NO; [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (isDir) {
        VoiceManagerVC *vc = [[VoiceManagerVC alloc] initWithPath:path];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

// 左滑操作：删除/分享/移动/重命名
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *fileName = self.isSearching ? self.filteredFiles[indexPath.row] : self.files[indexPath.row];
    NSString *path = [self.currentPath stringByAppendingPathComponent:fileName];
    
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(UIContextualAction *a, UIView *v, void (^cb)(BOOL)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除" message:fileName preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { cb(NO); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            if (self.playingIndexPath && indexPath.row == self.playingIndexPath.row) { [self.player stop]; self.player = nil; self.playingIndexPath = nil; }
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; [self loadFiles]; cb(YES);
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    del.image = [UIImage systemImageNamed:@"trash.fill"]; del.backgroundColor = COLOR_ICON_RED;
    
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *a, UIView *v, void (^cb)(BOOL)) {
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            activityVC.popoverPresentationController.sourceView = self.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
            activityVC.popoverPresentationController.permittedArrowDirections = 0;
        }
        [self presentViewController:activityVC animated:YES completion:nil];
        cb(YES);
    }];
    share.image = [UIImage systemImageNamed:@"square.and.arrow.up.fill"];
    share.backgroundColor = [UIColor systemIndigoColor];
    
    UIContextualAction *ren = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *a, UIView *v, void (^cb)(BOOL)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *t) { t.text = [fileName stringByDeletingPathExtension]; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { cb(NO); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *newN = alert.textFields.firstObject.text;
            if (newN.length > 0) {
                NSString *newP = [self.currentPath stringByAppendingPathComponent:[newN stringByAppendingPathExtension:fileName.pathExtension]];
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:newP error:nil]; [self loadFiles];
            }
            cb(YES);
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    ren.image = [UIImage systemImageNamed:@"square.and.pencil"]; ren.backgroundColor = COLOR_ICON_BLUE;
    
    UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *a, UIView *v, void (^cb)(BOOL)) {
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.currentPath error:nil];
        NSMutableArray *folders = [NSMutableArray array];
        for (NSString *item in contents) {
            BOOL isDir = NO; NSString *fullPath = [self.currentPath stringByAppendingPathComponent:item];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
                if (![item isEqualToString:fileName]) { [folders addObject:item]; }
            }
        }
        if (folders.count == 0) { [VoiceHelper showToast:@"📂 当前没有可用的目标文件夹" color:COLOR_ICON_RED]; cb(NO); return; }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"移动到..." message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            alert.popoverPresentationController.sourceView = self.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 0, 0);
            alert.popoverPresentationController.permittedArrowDirections = 0;
        }
        for (NSString *folder in folders) {
            [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📂 %@", folder] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *baseName = [fileName stringByDeletingPathExtension];
                NSString *ext = [fileName pathExtension];
                NSString *destPath = [[self.currentPath stringByAppendingPathComponent:folder] stringByAppendingPathComponent:fileName];
                int i = 1;
                while ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
                    NSString *newName = ext.length > 0 ? [NSString stringWithFormat:@"%@_%d.%@", baseName, i++, ext] : [NSString stringWithFormat:@"%@_%d", baseName, i++];
                    destPath = [[self.currentPath stringByAppendingPathComponent:folder] stringByAppendingPathComponent:newName];
                }
                if (self.playingIndexPath && indexPath.row == self.playingIndexPath.row) { [self.player stop]; self.player = nil; self.playingIndexPath = nil; }
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:destPath error:nil];
                [self loadFiles]; cb(YES);
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { cb(NO); }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    move.image = [UIImage systemImageNamed:@"arrow.turn.down.right"]; move.backgroundColor = [UIColor systemOrangeColor];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[del, share, move, ren]];
}

// 导入文件及自动转码
- (void)importFile {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    p.delegate = self; [self presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *src = urls.firstObject; if (!src) return;
    
    BOOL canAccess = [src startAccessingSecurityScopedResource];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:src.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:src toURL:[NSURL fileURLWithPath:tempPath] error:nil];
    if (canAccess) { [src stopAccessingSecurityScopedResource]; }
    
    NSString *ext = tempPath.pathExtension.lowercaseString;
    NSString *baseName = tempPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *destFileName = [baseName stringByAppendingPathExtension:@"m4a"];
    NSString *destPath = [self.currentPath stringByAppendingPathComponent:destFileName];
    
    int i = 1;
    while([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        destFileName = [NSString stringWithFormat:@"%@_%d.m4a", baseName, i++];
        destPath = [self.currentPath stringByAppendingPathComponent:destFileName];
    }
    
    if ([ext isEqualToString:@"m4a"]) {
        [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:destPath error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ [self loadFiles]; });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [VoiceHelper showProgressHUD:[NSString stringWithFormat:@"正在将 %@ 转码...", ext]]; });
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:tempPath]];
        AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
        export.outputURL = [NSURL fileURLWithPath:destPath];
        export.outputFileType = AVFileTypeAppleM4A;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer *exportTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
                if (export.status == AVAssetExportSessionStatusExporting) { [VoiceHelper updateProgressHUD:export.progress title:[NSString stringWithFormat:@"格式转换中 %.0f%%", export.progress * 100]]; } 
                else if (export.status == AVAssetExportSessionStatusCompleted || export.status == AVAssetExportSessionStatusFailed || export.status == AVAssetExportSessionStatusCancelled) { [timer invalidate]; }
            }];
            [[NSRunLoop mainRunLoop] addTimer:exportTimer forMode:NSRunLoopCommonModes];
        });
        [export exportAsynchronouslyWithCompletionHandler:^{
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [VoiceHelper hideProgressHUD];
                if (export.status == AVAssetExportSessionStatusCompleted) { [VoiceHelper showToast:@"✅ 导入并转码成功！" color:COLOR_ICON_GREEN]; [self loadFiles]; } 
                else {
                    NSString *errMsg = export.error ? export.error.localizedDescription : @"格式不支持";
                    [VoiceHelper showToast:[NSString stringWithFormat:@"❌ 转换失败: %@", errMsg] color:COLOR_ICON_RED];
                }
            });
        }];
    }
}
- (void)leftButtonTapped {
    [self.currentPath.lastPathComponent isEqualToString:@"DouyinVoice"] ? [self dismissViewControllerAnimated:YES completion:nil] : [self.navigationController popViewControllerAnimated:YES];
}
@end

// =======================================================
// Hooks (天罗地网四层拦截，彻底封死私信)
// =======================================================

static void _UpdateGlobalModel(id controller) {
    g_currentFeedVC = controller; // 【核心绑定】：每次播放新视频时，把控制器保存下来
    @try {
        id m = nil;
        @try { m = [controller valueForKey:@"awemeModel"]; } @catch(NSException *e){}
        if (!m) { @try { m = [controller valueForKey:@"model"]; } @catch(NSException *e){} }
        if (m) g_currentVideoModel = m;
    } @catch(NSException *e){}
}

%hook UIWindow
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    if (motion == UIEventSubtypeMotionShake) {
        UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        BOOL showing = NO;
        if ([top isKindOfClass:[UINavigationController class]] && [((UINavigationController*)top).topViewController isKindOfClass:[VoiceManagerVC class]]) showing = YES;
        if ([top isKindOfClass:[VoiceManagerVC class]]) showing = YES;
        if (!showing) {
            VoiceManagerVC *vc = [[VoiceManagerVC alloc] initWithPath:nil];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationPageSheet;
            nav.navigationBarHidden = YES;
            [top presentViewController:nav animated:YES completion:nil];
        }
    }
}
%end

%hook AWEAwemeCellViewController
- (void)play { %orig; _UpdateGlobalModel(self); }
%end
%hook AWEFeedCellViewController
- (void)play { %orig; _UpdateGlobalModel(self); }
%end
%hook AWEAwemePlayVideoViewController
- (void)play { %orig; _UpdateGlobalModel(self); }
%end
%hook AWEAwemePlayInteractionViewController
- (void)viewDidAppear:(BOOL)animated { %orig; _UpdateGlobalModel(self); }
%end
%hook AWEPlayInteractionViewController
- (void)viewDidAppear:(BOOL)animated { %orig; _UpdateGlobalModel(self); }
%end

// 第一层：拦截系统录音器
%hook AVAudioRecorder
- (void)stop { 
    %orig; 
    if(g_isArmed && [self url]) [VoiceHelper processAndReplace:[self url].path]; 
}
- (void)finishedRecording { 
    %orig; 
    if(g_isArmed && [self url]) [VoiceHelper processAndReplace:[self url].path]; 
}
%end

// 第二层：拦截文件移动
%hook NSFileManager
- (BOOL)moveItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)err {
    BOOL r = %orig;
    if (g_isArmed && dst) {
        NSString *p = dst.path; NSString *e = p.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"mp3"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[e isEqualToString:@"tmp"]||[p.lowercaseString containsString:@"audio"]||[p.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:p];
        }
    }
    return r;
}
- (BOOL)copyItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)err {
    BOOL r = %orig;
    if (g_isArmed && dst) {
        NSString *p = dst.path; NSString *e = p.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"mp3"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[e isEqualToString:@"tmp"]||[p.lowercaseString containsString:@"audio"]||[p.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:p];
        }
    }
    return r;
}
- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err {
    BOOL r = %orig;
    if (g_isArmed && dst) {
        NSString *p = dst; NSString *e = p.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"mp3"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[e isEqualToString:@"tmp"]||[p.lowercaseString containsString:@"audio"]||[p.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:p];
        }
    }
    return r;
}
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)err {
    BOOL r = %orig;
    if (g_isArmed && dst) {
        NSString *p = dst; NSString *e = p.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"mp3"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[e isEqualToString:@"tmp"]||[p.lowercaseString containsString:@"audio"]||[p.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:p];
        }
    }
    return r;
}
%end

// 第三层：拦截底层数据硬写 (专治私信不服)
%hook NSData
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)errorPtr {
    BOOL r = %orig;
    if (g_isArmed && path) {
        NSString *e = path.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[path.lowercaseString containsString:@"audio"]||[path.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:path];
        }
    }
    return r;
}
- (BOOL)writeToURL:(NSURL *)url options:(NSDataWritingOptions)writeOptionsMask error:(NSError **)errorPtr {
    BOOL r = %orig;
    if (g_isArmed && url) {
        NSString *path = url.path;
        NSString *e = path.pathExtension.lowercaseString;
        if ([e isEqualToString:@"m4a"]||[e isEqualToString:@"wav"]||[e isEqualToString:@"caf"]||[e isEqualToString:@"aac"]||[path.lowercaseString containsString:@"audio"]||[path.lowercaseString containsString:@"voice"]) {
            [VoiceHelper processAndReplace:path];
        }
    }
    return r;
}
%end

// 第四层：在私信发出去的最后一秒强行换掉信封里的文件
%hook AWEIMMessageBaseViewController
- (void)sendMessage:(id)msg {
    if (g_isArmed && g_pendingReplacePath) {
        NSString *msgDesc = [NSString stringWithFormat:@"%@", msg];
        @try {
            if ([msg respondsToSelector:@selector(yy_modelToJSONObject)]) {
                msgDesc = [NSString stringWithFormat:@"%@\n%@", msgDesc, [msg performSelector:@selector(yy_modelToJSONObject)]];
            }
        } @catch(NSException *e){}
        
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:/private)?/var/mobile/Containers/Data/Application/[A-Z0-9\\-]+/[\\w\\-/\\.]+" options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *matches = [regex matchesInString:msgDesc options:0 range:NSMakeRange(0, msgDesc.length)];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSTextCheckingResult *match in matches) {
            NSString *path = [msgDesc substringWithRange:match.range];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
                NSString *ext = path.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"aac"] || [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"wav"] || [ext isEqualToString:@"caf"] || [path.lowercaseString containsString:@"audio"] || [path.lowercaseString containsString:@"voice"]) {
                    [VoiceHelper performReplaceFrom:g_pendingReplacePath to:path isTrimmed:NO];
                    g_isArmed = NO; g_pendingReplacePath = nil;
                    break;
                }
            }
        }
    }
    %orig;
}
%end

// ==========================================
// 优雅触发：將图标嵌在输入框内部 (完美水平居中版)
// ==========================================
%hook UITextView
- (void)layoutSubviews {
    %orig;
    
    UIView *superView = self.superview;
    if (!superView) return;
    
    UIResponder *responder = self;
    BOOL isTargetArea = NO;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *vcName = NSStringFromClass([responder class]);
            if ([vcName containsString:@"Comment"] || 
                [vcName containsString:@"Input"] || 
                [vcName containsString:@"Chat"] ||
                [vcName containsString:@"IM"] ||
                [vcName containsString:@"Message"]) {
                isTargetArea = YES;
                break;
            }
        }
    }
    
    if (isTargetArea) {
        UIButton *musicBtn = (UIButton *)[superView viewWithTag:778899];
        if (!musicBtn) {
            musicBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            musicBtn.tag = 778899;
            
            UIImage *icon = [[UIImage systemImageNamed:@"waveform.circle.fill"] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24]];
            [musicBtn setImage:icon forState:UIControlStateNormal];
            musicBtn.tintColor = [UIColor systemBlueColor];
            
            UIEdgeInsets inset = self.textContainerInset;
            if (inset.right < 35.0) {
                inset.right = 35.0;
                self.textContainerInset = inset;
            }
            
            [musicBtn addTarget:self action:@selector(douyinVoice_openMenu) forControlEvents:UIControlEventTouchUpInside];
            
            // 挂载在父视图上，统一排版
            [superView addSubview:musicBtn];
        }
        
        CGFloat btnWidth = 30;
        CGFloat btnHeight = 30;
        
        // 完美的水平居中绝对坐标计算
        musicBtn.frame = CGRectMake(self.frame.origin.x + self.frame.size.width - btnWidth - 5, 
                                    (superView.bounds.size.height - btnHeight) / 2.0, 
                                    btnWidth, 
                                    btnHeight);
        
        [superView bringSubviewToFront:musicBtn];
    }
}

%new
- (void)douyinVoice_openMenu {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen prepare];
    [gen impactOccurred];
    
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    
    BOOL showing = NO;
    if ([top isKindOfClass:[UINavigationController class]] && [((UINavigationController*)top).topViewController isKindOfClass:[VoiceManagerVC class]]) showing = YES;
    if ([top isKindOfClass:[VoiceManagerVC class]]) showing = YES;
    
    if (!showing) {
        VoiceManagerVC *vc = [[VoiceManagerVC alloc] initWithPath:nil];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        nav.navigationBarHidden = YES;
        [top presentViewController:nav animated:YES completion:nil];
    }
}
%end