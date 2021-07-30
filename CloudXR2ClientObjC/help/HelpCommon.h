//
//  TimeExchange.h
//  YDLSHOPPING
//
//  Created by mac on 2019/10/18.
//  Copyright © 2019 sunjiayu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HelpCommon : NSObject
//时间戳转时间
+ (NSString *)timeWithTimeIntervalString:(NSString *)timeString  andFormatter:(NSString *)format;
// 将某个时间转化成 时间戳
+(NSString *)timeSwitchTimestamp:(NSString *)formatTime andFormatter:(NSString *)format;
//邮箱验证
+ (BOOL) validateEmail:(NSString *)email;
//手机号验证
+ (NSString *)valiMobile:(NSString *)mobile;


#pragma mark 图片压缩
+(UIImage *)zipImage:(UIImage *)image;
//压缩图片为指定大小
+ (UIImage *)scaleToSize:(UIImage *)img size:(CGSize)size;

#pragma mark 字符串高宽
+ ( CGSize )stringSize:(NSString *)str size:(CGSize)size fontWithName:(NSString *)fontName size:(NSInteger)fontSize;

+ ( CGSize )stringSystemSize:(NSString *)str size:(CGSize)size  fontSize:(NSInteger)fontSize;
+(NSString *)dictionaryToJSONString:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
