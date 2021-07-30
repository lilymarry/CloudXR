//
//  OAAPIClient.h
//  OASystemSass
//
//  Created by Bob Chen on 27/03/2017.
//  Copyright © 2017 Eric. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OAAPIClient : NSObject
{
    NSProgress *pross;
    
    //取消上传
    NSURLSessionDataTask *_yunCancletask;
    
}
+ (instancetype)sharedInstance;

- (NSURLSessionDataTask *)POST:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *task, id obj))success failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure;
- (NSURLSessionDataTask *)UpdatePOST:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure;
- (NSURLSessionDataTask *)WenJianPOST:(NSString *)URLString wenjianMessageID:(NSString *)wenjianMessageID
                          wenjianType:(NSString *)wenjianType parameters:(id)parameters wenjianData:(NSData *)wenjianData success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure;
- (NSURLSessionDataTask *)WenjianGET:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure;
- (NSURLSessionDataTask *)GET:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure;


@end
