//
//  OperationView.h
//  CloudXRSDK
//
//  Created by 万间科技 on 2021/7/14.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN


typedef void(^OperationViewBlock)(NSString *reason,BOOL stop);
@interface OperationView : UIView
@property (weak, nonatomic) IBOutlet UIView *thisView;
@property (weak, nonatomic) IBOutlet UIButton *replayBtn;
@property (nonatomic, copy) OperationViewBlock operationBlock ;
@end

NS_ASSUME_NONNULL_END
