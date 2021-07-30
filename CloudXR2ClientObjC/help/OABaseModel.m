//
//  OABaseModel.m
//  Re-OA
//
//  Created by imac-1 on 2016/12/29.
//  Copyright © 2016年 姜任鹏. All rights reserved.
//

#import "OABaseModel.h"

@implementation OABaseModel
- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    if (stuff==nil) {
        stuff=[[NSMutableDictionary alloc] init];
    }
    [stuff setValue:value forKey:key];

}

- (void)setNilValueForKey:(NSString *)key
{
    NSLog(@"setNilValueForKey：%@",key);
}

- (id)valueForUndefinedKey:(NSString *)key
{
    id value=[stuff valueForKey:key];
    return value;
}

@end
