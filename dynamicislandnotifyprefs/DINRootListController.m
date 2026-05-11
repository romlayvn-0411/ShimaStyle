#import "DINRootListController.h"
#import <notify.h>
#import <spawn.h>

@implementation DINRootListController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.navigationItem.titleView = [self headerView];
    }
    return self;
}

- (UITableViewStyle)tableViewStyle {
    return UITableViewStyleInsetGrouped; // Sử dụng giao diện bo góc chuẩn iOS 18+
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Tạo một View chứa Header với chiều cao 160
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 160)];
    
    // 2. Khởi tạo đối tượng Ảnh (ImageView)
    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.contentMode = UIViewContentModeScaleAspectFit; // Giữ nguyên tỉ lệ ảnh
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 3. Đọc file "logo.png" từ thư mục Resources của Cài đặt
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *imagePath = [bundle pathForResource:@"logo" ofType:@"png"];
    logoView.image = [UIImage imageWithContentsOfFile:imagePath];
    
    // 4. Căn giữa Logo vào trong Header
    [headerView addSubview:logoView];
    [NSLayoutConstraint activateConstraints:@[
        [logoView.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor],
        [logoView.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [logoView.widthAnchor constraintEqualToConstant:120], // Kích thước hiển thị 120x120
        [logoView.heightAnchor constraintEqualToConstant:120],
    ]];
    
    // 5. Đẩy Header lên đầu trang Cài đặt (phía trên các ô tuỳ chọn)
    [self.table setTableHeaderView:headerView];
}

- (UIView *)headerView {
    UILabel *label = [[UILabel alloc] init];
    label.text = @"ShimaStyle";
    label.font = [UIFont boldSystemFontOfSize:17];
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    return label;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post("com.34306.shimastyle/prefsChanged");
}

- (void)testNotification {
    notify_post("com.34306.shimastyle/testNotification");
}

- (void)respring {
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char **)args, NULL);
}

@end
