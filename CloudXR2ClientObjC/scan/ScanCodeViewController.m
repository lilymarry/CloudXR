//
//  ScanCodeViewController.m
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/19.
//

#import "ScanCodeViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "ScanerView.h"
#import "CXRViewController.h"
@interface ScanCodeViewController ()<AVCaptureMetadataOutputObjectsDelegate,CAAnimationDelegate>

//! 扫码区域动画视图
@property (strong, nonatomic)  ScanerView *scanerView;

//AVFoundation
//! AV协调器
@property (strong,nonatomic) AVCaptureSession           *session;
//! 取景视图
@property (strong,nonatomic) AVCaptureVideoPreviewLayer *previewLayer;


@end

@implementation ScanCodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.scanerView.alpha = 0;
    //设置扫描区域边长
    self.scanerView.scanAreaEdgeLength = [[UIScreen mainScreen] bounds].size.width - 2 * 50;
}


- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    
    if (!self.session){
        
        //添加镜头盖开启动画
        CATransition *animation = [CATransition animation];
        animation.duration = 0.5;
        animation.type = @"cameraIrisHollowOpen";
        animation.timingFunction = UIViewAnimationOptionCurveEaseInOut;
        animation.delegate = self;
        [self.view.layer addAnimation:animation forKey:@"animation"];
        
        //初始化扫码
        [self setupAVFoundation];
        
        //调整摄像头取景区域
        self.previewLayer.frame = self.view.bounds;
        
        //调整扫描区域
        AVCaptureMetadataOutput *output = self.session.outputs.firstObject;
        //        //根据实际偏差调整y轴
        CGRect rect = CGRectMake((self.scanerView.scanAreaRect.origin.y + 20) / HEIGHT(self.scanerView),
                                 self.scanerView.scanAreaRect.origin.x / WIDTH(self.scanerView),
                                 self.scanerView.scanAreaRect.size.height / HEIGHT(self.scanerView),
                                 self.scanerView.scanAreaRect.size.width / WIDTH(self.scanerView));
        output.rectOfInterest = rect;
    } else {
        
        _scanerView = [[ScanerView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, ScreenHeight)];
//        self.scanerView.alpha = 0;
        self.scanerView.scanAreaEdgeLength = [[UIScreen mainScreen] bounds].size.width - 2 * 50;
        [self.view addSubview:_scanerView];
        //开始扫码
        [self.session startRunning];
    }
}

//! 动画结束回调
- (void)animationDidStop:(CAAnimation *)theAnimation finished:(BOOL)flag{
    
    [MBProgressHUD hideHUDForView:self.view];
    [UIView animateWithDuration:0.25
                     animations:^{
                         self.scanerView.alpha = 1;
                     }];
}

//! 初始化扫码
- (void)setupAVFoundation{
    //创建会话
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetHigh;
    //获取摄像头设备
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    
    //创建输入流
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if(input) {
        [self.session addInput:input];
    } else {
        //出错处理
        //        SNLog(@"%@", error);
        NSString *msg = [NSString stringWithFormat:@"请在手机【设置】-【隐私】-【相机】选项中，允许【%@】访问您的相机",[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"]];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提醒" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self.navigationController popViewControllerAnimated:YES];

        }]];
        [self presentViewController:alertController animated:YES completion:nil];

        return;
    }
    
    //创建输出流
    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [self.session addOutput:output];
    
    //设置扫码类型
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode,  //条形码
                                   AVMetadataObjectTypeEAN13Code,
                                   AVMetadataObjectTypeEAN8Code,
                                   AVMetadataObjectTypeCode128Code];

    
    //设置代理，在主线程刷新
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    //创建摄像头取景区域
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];
    
    if ([self.previewLayer connection].isVideoOrientationSupported)
        [self.previewLayer connection].videoOrientation = AVCaptureVideoOrientationPortrait;
    
    //开始扫码
    [self.session startRunning];
}

#pragma mark - AVCaptureMetadataOutputObjects Delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection{
    for (AVMetadataMachineReadableCodeObject *metadata in metadataObjects) {

        NSString *string = metadata.stringValue;
        //声音
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"scan.wav" withExtension:nil];
        SystemSoundID soundID = 0;
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)(url), &soundID);
        AudioServicesPlaySystemSound(soundID);
        [self.session stopRunning];
        
        NSRange range1 = [string rangeOfString:@"appid="];
        NSRange range2 = [string rangeOfString:@"&locale"];
        if (range1.location !=NSNotFound &&range2.location !=NSNotFound) {
            NSUInteger location = range1.location + range1.length;
            NSUInteger length = range2.location - location;
            NSString * appid = [string substringWithRange:NSMakeRange(location, length)];
            if (appid.length>0) {
                [MBProgressHUD showMessage:@"正在进入，请稍等" toView:self.view];
                   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                     
                       UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
                       CXRViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"CXRvc"];
                     //  controller.streamingXR = YES;
                       controller.address =@"192.168.3.160";
                       controller.appid=appid;
                       [self.navigationController pushViewController:controller animated:YES ];
                  });
            }
        }
        [_scanerView removeFromSuperview];
     
    }
}

- (ScanerView *)scanerView {
    if (!_scanerView) {
        _scanerView = [[ScanerView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, ScreenHeight)];
        [self.view addSubview:_scanerView];
    }
    return _scanerView;
}


@end
