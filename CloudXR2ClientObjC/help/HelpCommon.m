//
//  TimeExchange.m
//  YDLSHOPPING
//
//  Created by mac on 2019/10/18.
//  Copyright © 2019 sunjiayu. All rights reserved.
//

#import "HelpCommon.h"

@implementation HelpCommon
//时间戳转时间
+ (NSString *)timeWithTimeIntervalString:(NSString *)timeString  andFormatter:(NSString *)format
{
    // 格式化时间
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
     formatter.timeZone = [NSTimeZone localTimeZone];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    [formatter setDateFormat:format];
    NSDate* date ;
    // 毫秒值转化为秒 // *1000 是精确到毫秒，不乘就是精确到秒
    if(timeString.length>13)
        
    {
        date = [NSDate dateWithTimeIntervalSince1970:[timeString longLongValue]/ 1000.0]; //返回的是13位的时间戳的话,是精确到了毫秒,需要除以1000
    }
    else
    {
        date = [NSDate dateWithTimeIntervalSince1970:[timeString longLongValue]];
    }
    
    NSString* dateString = [formatter stringFromDate:date];
    return dateString;
}
#pragma mark - 将某个时间转化成 时间戳
+(NSString *)timeSwitchTimestamp:(NSString *)formatTime andFormatter:(NSString *)format
{    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    
    [formatter setDateFormat:format];
    //(@"YYYY-MM-dd hh:mm:ss") ----------设置你想要的格式,hh与HH的区别:分别表示12小时制,24小时制
    NSTimeZone* timeZone = [NSTimeZone localTimeZone];
    [formatter setTimeZone:timeZone];
    NSDate* date = [formatter dateFromString:formatTime]; //------------将字符串按formatter转成nsdate    //时间转时间戳的方法:
    NSInteger timeSp = [[NSNumber numberWithDouble:[date timeIntervalSince1970]] integerValue];
    //NSLog(@"将某个时间转化成 时间戳&&&&&&&timeSp:%ld",(long)timeSp); //时间戳的值
    NSString *str =[NSString stringWithFormat:@"%ld",(long)timeSp];
    return str;
    
}
//邮箱验证
+ (BOOL) validateEmail:(NSString *)email

{ NSString *emailRegex = @"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,4}";
 NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegex];
  BOOL isTrue =[emailTest evaluateWithObject:email];
    return isTrue;
   
}
+ (NSString *)valiMobile:(NSString *)mobile{
    if (mobile.length != 11)
    {
        return @"手机号长度只能是11位";
    }else{
        NSString *regex = @"^(13[0-9]|14[579]|15[0-3,5-9]|16[6]|17[0135678]|18[0-9]|19[89])\\d{8}$";
        NSPredicate *pred3 = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regex];
        BOOL isMatch3 = [pred3 evaluateWithObject:mobile];
        
        if ( isMatch3) {
            return nil;
        }else{
            return @"请输入正确的电话号码";
        }
        
    }
   
}
//压缩图片为指定大小
+ (UIImage *)scaleToSize:(UIImage *)img size:(CGSize)size
{
    // 并把它设置成为当前正在使用的context
    UIGraphicsBeginImageContext(size);
    // 绘制改变大小的图片
    [img drawInRect:CGRectMake(0,0, size.width, size.height)];
    // 从当前context中创建一个改变大小后的图片
    UIImage* scaledImage =UIGraphicsGetImageFromCurrentImageContext();
    // 使当前的context出堆栈
    UIGraphicsEndImageContext();
    //返回新的改变大小后的图片
    return scaledImage;
}

+(UIImage *)zipImage:(UIImage *)image
{
    CGSize imagesize = image.size;
    float XX=imagesize.width/ScreenWidth;//宽度比
    float YY=imagesize.height/XX;//在屏幕上的高度
    imagesize.width = ScreenWidth;//放大倍数
    imagesize.height =YY;
    UIImage *ima = [HelpCommon scaleToSize:image size:imagesize];
    
    return ima;
}
#pragma mark 字符串高宽、自定字体
+ ( CGSize )stringSize:(NSString *)str size:(CGSize)size fontWithName:(NSString *)fontName size:(NSInteger)fontSize
{
    CGSize labelsize1  = [str
                    boundingRectWithSize:size
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: [UIFont fontWithName:fontName size:fontSize]}
            context:nil].size;
    return labelsize1;
}
#pragma mark 字符串高宽、系统字体
+ ( CGSize )stringSystemSize:(NSString *)str size:(CGSize)size  fontSize:(NSInteger)fontSize
{
    CGSize labelsize1  = [str
                    boundingRectWithSize:size
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: font(fontSize)}
            context:nil].size;
    return labelsize1;
}
//字典转json
+(NSString *)dictionaryToJSONString:(NSDictionary *)dictionary
{
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}
@end
