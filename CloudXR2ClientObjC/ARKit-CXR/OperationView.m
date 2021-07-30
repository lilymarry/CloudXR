//
//  OperationView.m
//  CloudXRSDK
//
//  Created by 万间科技 on 2021/7/14.
//

#import "OperationView.h"

@implementation OperationView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"OperationView" owner:self options:nil];
        [self addSubview:_thisView];
        
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
    UIButton *but=(UIButton *)sender;
    BOOL isreplay=NO;
    if ([_replayBtn.titleLabel.text isEqualToString:@"正在录像"]) {
        isreplay=YES;
    }
  
    if (but.tag==1001) {
        [self removeFromSuperview];
        self.operationBlock(@"1",isreplay);
    }
    else  if (but.tag==1002){
        [self removeFromSuperview];
        if ([_replayBtn.titleLabel.text isEqualToString:@"录像"]) {
            self.operationBlock(@"2",YES);
        }
        else
        {
            self.operationBlock(@"2",NO);
        }
    
      
    }
   else
   {
       self.operationBlock(@"3",isreplay);
       [self removeFromSuperview];
   }
   
}

@end
