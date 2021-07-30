//
//  ComponentModel.h
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/20.
//


#import "OABaseModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface ComponentModel : OABaseModel
@property (nonatomic, strong) NSString *dynamicData;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *projectId;
@property (nonatomic, strong) NSString *revitCode;
@property (nonatomic, strong) NSString *uuid;

@property (nonatomic, strong) NSString *haveChild;
@property (nonatomic, strong) NSString *parentId;

@property (nonatomic, assign) int level; // 结点层级 从1开始

@property (nonatomic, assign) BOOL leaf;  // 树叶(Leaf) If YES：此结点下边没有结点咯；

@property (nonatomic, assign) BOOL root;  // 树根((Root) If YES: parentID = nil

@property (nonatomic, assign) BOOL expand; // 是否展开

@property (nonatomic, assign) BOOL selected; // 是否选中
@end
NS_ASSUME_NONNULL_END
