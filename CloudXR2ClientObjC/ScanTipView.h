//
//  ScanTipView.h
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/16.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScanTipView : UIView
typedef void(^scanTipViewBlock)(NSString *sure);
@property (weak, nonatomic) IBOutlet UIButton *sureBtn;
@property (weak, nonatomic) IBOutlet UIButton *canselBtn;
@property (strong, nonatomic) IBOutlet UIView *thisView;
@property (nonatomic, copy) scanTipViewBlock scanBlock ;
@end

NS_ASSUME_NONNULL_END
