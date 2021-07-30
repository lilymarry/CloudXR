//
//  ScanTipView.m
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/16.
//

#import "ScanTipView.h"

@implementation ScanTipView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"ScanTipView" owner:self options:nil];
        [self addSubview:_thisView];
        
        _sureBtn.layer.cornerRadius=12;
        _sureBtn.layer.borderColor=[UIColor blackColor].CGColor;
        _sureBtn.layer.borderWidth = 1.65f;
        
        _canselBtn.layer.cornerRadius=12;
        _canselBtn.layer.borderColor=[UIColor blackColor].CGColor;
        _canselBtn.layer.borderWidth = 1.65f;
        
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _thisView.frame = self.bounds;
}
- (IBAction)cancelPress:(id)sender {
    [self removeFromSuperview];
}
- (IBAction)surePress:(id)sender {
    self.scanBlock(@"sure");
    [self removeFromSuperview];
}


@end
