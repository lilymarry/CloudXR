//
//  OAAPIClient.m
//  OASystemSass
//
//  Created by Bob Chen on 27/03/2017.
//  Copyright © 2017 Eric. All rights reserved.
//

#import "OAAPIClient.h"
#import <AFNetworking/AFHTTPSessionManager.h>
NSString * const LoginUrl = @"/api/V1/Login/UserLogin";

@interface OAAPIClient ()

@property (strong, nonatomic) AFHTTPSessionManager *sessionManager;

@end

@implementation OAAPIClient

+ (instancetype)sharedInstance
{
    static OAAPIClient *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [OAAPIClient new];
    });
    return _instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:Base_url]];
        _sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
        _sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];
        _sessionManager.completionQueue = dispatch_queue_create("OAAPIClient", NULL);
    }
    return self;
}


#pragma mark - 常用post数据发送处理
- (NSURLSessionDataTask *)POST:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
    return [self postWithToken:URLString parameters:parameters success:success failure:failure];
    
}
#pragma mark - get方法处理
- (NSURLSessionDataTask *)GET:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
        
    return [self getWithToken:URLString parameters:parameters success:success failure:failure];
    
}
//#pragma mark - 文件服务器get处理
//- (NSURLSessionDataTask *)WenjianGET:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
//{
//
//    return [self WenjiangetWithToken:URLString parameters:parameters success:success failure:failure];
//
//}
//#pragma mark - 文件get上传设置头信息
//- (NSURLSessionDataTask *)WenjiangetWithToken:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
//{
//    NSMutableURLRequest *request = [self.sessionManager.requestSerializer requestWithMethod:@"GET" URLString:[NSURL URLWithString:URLString relativeToURL:[NSURL URLWithString:WenjianHttp]].absoluteString parameters:parameters error:nil];
//    if ([USER_DEFAULT objectForKey:kUSEREpID] && ![[USER_DEFAULT objectForKey:kUSEREpID] isEqualToString:@""]) {
//        request.allHTTPHeaderFields = @{@"Token":[OATokenManager gainToken],@"AuthCode":[USER_DEFAULT objectForKey:kUSERID],@"EnterpriseId":@"0",@"TerminalType":@"1"};
//    }else{
//        request.allHTTPHeaderFields = @{@"Token":[OATokenManager gainToken],@"AuthCode":[USER_DEFAULT objectForKey:kUSERID],@"TerminalType":@"1"};
//    }
//    NSURLSessionDataTask *task = [self.sessionManager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
//
//        NSLog(@"%@",responseObject);
//
//        if (!error && [responseObject isKindOfClass:[NSDictionary class]]) {
//
//            [self callBlockOnMainQueue:success task:task obj:responseObject];
//        } else {
//            if ([[(NSHTTPURLResponse*)response allHeaderFields][@"StatusCode"] hasPrefix:@"1000"]) {//token验证失败
//                [self postTokenExpiredNotification];
//            }
//            [self callBlockOnMainQueue:failure task:task obj:error];
//        }
//    }];
//    [task resume];
//    return task;
//}
#pragma mark - post上传设置头信息
- (NSURLSessionDataTask *)postWithToken:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
    NSMutableURLRequest *request = [self.sessionManager.requestSerializer requestWithMethod:@"POST" URLString:[NSURL URLWithString:URLString relativeToURL:self.sessionManager.baseURL].absoluteString parameters:parameters error:nil];
//    if ([USER_DEFAULT objectForKey:kUSEREpID] && ![[USER_DEFAULT objectForKey:kUSEREpID] isEqualToString:@""]) {
//        request.allHTTPHeaderFields = @{@"Token":[OATokenManager gainToken],@"AuthCode":[USER_DEFAULT objectForKey:kUSERID],@"EnterpriseId":@"0",@"TerminalType":@"1"};
//    }else{
//        request.allHTTPHeaderFields = @{@"Token":[OATokenManager gainToken],@"AuthCode":[USER_DEFAULT objectForKey:kUSERID],@"TerminalType":@"1"};
//    }
    
    NSURLSessionDataTask *task = [self.sessionManager dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (!error && [responseObject isKindOfClass:[NSDictionary class]]) {
            NSString *re = [NSString stringWithFormat:@"%@",[responseObject objectForKey:@"ResultCode"]];
            if (![responseObject[@"ResultCode"] isKindOfClass:[NSNull class]]){
                [self callBlockOnMainQueue:success task:task obj:responseObject];
            }else{
                //                [self postTokenExpiredNotification];
                [self callBlockOnMainQueue:failure task:task obj:nil];
            }
            
        } else {
            
            [self callBlockOnMainQueue:failure task:task obj:error];
        }
    }];
    
    
    
    [task resume];
    return task;
}

//get方法获取
- (NSURLSessionDataTask *)getWithToken:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
    NSMutableURLRequest *request = [self.sessionManager.requestSerializer requestWithMethod:@"GET" URLString:[NSURL URLWithString:URLString relativeToURL:self.sessionManager.baseURL].absoluteString parameters:parameters error:nil];
    
    NSURLSessionDataTask *task = [self.sessionManager dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (!error && [responseObject isKindOfClass:[NSDictionary class]]) {
            if (![responseObject[@"ResultCode"] isKindOfClass:[NSNull class]]){
                [self callBlockOnMainQueue:success task:task obj:responseObject];
            }else{
                //                [self postTokenExpiredNotification];
                [self callBlockOnMainQueue:failure task:task obj:nil];
            }

            
        } else {
            
            [self callBlockOnMainQueue:failure task:task obj:error];
        }
    }];
    
    [task resume];
    return task;
}
////获取socket
//- (NSURLSessionDataTask *)socketget:(NSString *)URLString parameters:(id)parameters success:(void (^)(NSURLSessionDataTask *, id))success failure:(void (^)(NSURLSessionDataTask *, NSError *))failure
//{
//    NSMutableURLRequest *request = [self.sessionManager.requestSerializer requestWithMethod:@"GET" URLString:[NSURL URLWithString:URLString].absoluteString parameters:parameters error:nil];
//    NSURLSessionDataTask *task = [self.sessionManager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
//        if (!error && [responseObject isKindOfClass:[NSArray class]]) {
//            [self callBlockOnMainQueue:success task:task obj:responseObject];
//        } else {
//            if ([[(NSHTTPURLResponse*)response allHeaderFields][@"StatusCode"] hasPrefix:@"1000"]) {//token验证失败
//                [USER_DEFAULT setObject:[(NSHTTPURLResponse*)response allHeaderFields][@"StatusCode"] forKey:kStatueCode];
//                [self postTokenExpiredNotification];
//            }
//            [self callBlockOnMainQueue:failure task:task obj:error];
//        }
//    }];
//    [task resume];
//    return task;
//}
- (void)callBlockOnMainQueue:(void (^)(NSURLSessionDataTask *, id))block task:(NSURLSessionDataTask*)task obj:(id)obj
{
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(task, obj);
        });
    }
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    //拿到进度
    if ([keyPath isEqualToString:@"fractionCompleted"] && [object isKindOfClass:[NSProgress class]]) {
        NSProgress *progress = (NSProgress *)object;
        NSLog(@"Progress is %.1f", progress.fractionCompleted);
        
        //进度到1的时候说明加载完成了，移除观察者
        //不知道这么写对不对，有人发现不对请指出来，非常感谢~
        if (progress.fractionCompleted == 1) {
            @try {//如果没有写@try @catch 的话，在 dealloc 中，那个被监听的对象（appdelegate）必须要全局变量
                [progress removeObserver:self forKeyPath:keyPath];
            }
            @catch (NSException *exception) {
                
            }
            
            CFBridgingRelease(context);
        }
    }else{
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
}


-(NSString *)dirDoc{
    //[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    //    NSLog(@"app_home_doc: %@",documentsDirectory);
    return documentsDirectory;
}
-(void)createFile:(NSString *)filename{
    NSString *documentsPath =[self dirDoc];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *testDirectory = [documentsPath stringByAppendingPathComponent:filename];
    // 创建目录
    BOOL existed = [fileManager fileExistsAtPath:testDirectory isDirectory:false];
    if (!existed) {
        BOOL res=[fileManager createDirectoryAtPath:testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        if (res) {
            //            NSLog(@"文件夹创建成功");
        }else
        {
            //            NSLog(@"文件创建失败");
        }
        
    }else{
        //        NSLog(@"文件夹存在");
    }
    
}
@end
