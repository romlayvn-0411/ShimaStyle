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

- (UIView *)headerView {
    UILabel *label = [[UILabel alloc] init];
    label.text = @"ShimaReborn";
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
    notify_post("com.romlayvn.shimareborn/prefsChanged");
}

- (void)testNotification {
    notify_post("com.romlayvn.shimareborn/testNotification");
}

- (void)respring {
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char **)args, NULL);
}

@end
