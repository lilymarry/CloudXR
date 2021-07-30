//
//  ComponentListCell.h
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/20.
//

#import <UIKit/UIKit.h>
#import "ComponentModel.h"
NS_ASSUME_NONNULL_BEGIN
@class ComponentListCell;
@protocol ComponentListCellCellDelegate <NSObject>
- (void)nodeTableViewCell:(ComponentListCell *)cell selected:(BOOL)selected atIndexPath:(NSIndexPath *)indexPath; //选中的代理
- (void)nodeTableViewCell:(ComponentListCell *)cell expand:(BOOL)expand atIndexPath:(NSIndexPath *)indexPath;  //展开的代理
@end
@interface ComponentListCell : UITableViewCell
@property (nonatomic, strong) ComponentModel *node; // 结点
@property (nonatomic, strong) NSIndexPath *cellIndexPath; // cell的位置
@property (weak, nonatomic) IBOutlet UIButton *expandBtn;
@property (weak, nonatomic) IBOutlet UIImageView *seeImage;
@property (weak, nonatomic) IBOutlet UIButton *seeBtn;
@property (weak, nonatomic) IBOutlet UILabel *nameLab;
@property (nonatomic, weak) id <ComponentListCellCellDelegate> delegate;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leadingExpandBtn;


@end

NS_ASSUME_NONNULL_END
