//
//  ComponentListCell.m
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/20.
//

#import "ComponentListCell.h"

@implementation ComponentListCell


- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}
- (IBAction)expandBtnClicked:(id)sender {
    if (!self.node.expand) {
        [_expandBtn setImage:[UIImage imageNamed:@"箭头-下"] forState:UIControlStateNormal];
        
    }else{
        [_expandBtn setImage:[UIImage imageNamed:@"箭头-左"] forState:UIControlStateNormal];
    }
    self.node.expand = !self.node.expand;
    if ([self.delegate respondsToSelector:@selector(nodeTableViewCell:expand:atIndexPath:)]) {
        [self.delegate nodeTableViewCell:self expand:self.node.expand atIndexPath:self.cellIndexPath];
    }
}
- (IBAction)seepress:(id)sender {
    if(!self.node.selected){
        _seeImage.image=[UIImage imageNamed:@"selected"];
    }else{
        _seeImage.image=[UIImage imageNamed:@"disSelected"];
    }
    self.node.selected = !self.node.selected;
    if ([self.delegate respondsToSelector:@selector(nodeTableViewCell:selected:atIndexPath:)]) {
        [self.delegate nodeTableViewCell:self selected:self.node.selected atIndexPath:self.cellIndexPath];
    }
}

@end
