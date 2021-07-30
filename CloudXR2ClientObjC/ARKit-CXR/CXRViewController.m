/*
 * Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#import "CXRViewController.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include "CloudXRClient.h"

static const int cameraImageCacheSize = 32;      // queue size of previous frames & hmd poses
static const int maxTimeSamples = 10;            // profiling metrics
static const int renderBundleRingBufferSize = 3;   // cxrBackgroundThread -> RenderThread

typedef struct shader_data
{
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
} shader_data;

typedef struct line_seg
{
    simd_float3 start, end;
} line_seg;

simd_float3 intersect(line_seg l, simd_float3 planeP, simd_float3 planeN)
{
    simd_float3 dir = simd_normalize(l.end - l.start);
    float d = -simd_dot(planeP, planeN);
    float dist = -(simd_dot(l.start, planeN) + d) / (simd_dot(dir, planeN));
    simd_float3 r = l.start + (dir * dist);
    return r;
}

float distance(simd_float3 a, simd_float3 b)
{
    simd_float3 v = b - a;
    return sqrt(simd_dot(v, v));
}

bool pointInPlaneRect(ARPlaneAnchor* p, simd_float3 x)
{
    simd_float4x4 t = p.transform;
    simd_float4x4 tInverse = simd_inverse(t);
    simd_float3 c = p.center;
    simd_float3 xAnchor = simd_mul(tInverse, simd_make_float4(x, 1)).xyz;
    simd_float3 e = p.extent / 2.f;
    BOOL xIn = (xAnchor.x >= (c.x - e.x)) && (xAnchor.x <= (c.x + e.x));
    BOOL yIn = (xAnchor.y >= (c.y - e.y)) && (xAnchor.y <= (c.y + e.y));
    BOOL r = xIn && yIn;
    return r;
}

int readWriteDistance(int read, int write) {
    if(write < read) {
        return renderBundleRingBufferSize - read + write;
    } else {
        return write-read;
    }
}

CVMetalTextureRef createTexture(CVMetalTextureCacheRef textureCache, CVPixelBufferRef pixelBuffer, MTLPixelFormat pixelFormat, int planeIndex) {
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex);
    CVMetalTextureRef texture = 0;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(0, textureCache, pixelBuffer, 0, pixelFormat, width, height, planeIndex, &texture);
    if(status != kCVReturnSuccess) {
        texture = 0;
    }
    return texture;
}

// Requests the HMD and controller states and poses. Typically called at a fixed frequency.
void GetTrackingState(void* context, cxrVRTrackingState* trackingState) {
    CXRViewController* controller = (__bridge CXRViewController*)context;
    memset(trackingState, 0, sizeof(cxrVRTrackingState));
    simd_float4x4 transform = [controller arTransform];
    simd_float4x4 transposed = simd_transpose(transform);
    for(int i = 0; i < 3; ++i)
    {
        memcpy(trackingState->hmd.pose.deviceToAbsoluteTracking.m[i], &(transposed.columns[i]), sizeof(float) * 4);
    }
    trackingState->hmd.pose.deviceIsConnected = cxrTrue;
    trackingState->hmd.pose.trackingResult = cxrTrackingResult_Running_OK;
    trackingState->hmd.pose.poseIsValid = cxrTrue;
    trackingState->hmd.activityLevel = cxrDeviceActivityLevel_UserInteraction;
    trackingState->poseTimeOffset = 0.042;
}

// A controller vibration must be started.
void TriggerHaptic(void* context, const cxrHapticFeedback* haptic) {
}

// An audio buffer is available for playback.
cxrBool RenderAudio(void* context, const cxrAudioFrame* audioFrame) {
    return false;
}

// Receive user data from server
void ReceiveUserData(void* context, const void* data, uint32_t size) {
}

// Client lib will send connection status to app with this callback
void UpdateClientState(void* context, cxrClientState state, cxrStateReason reason) {
}

// Render bundles are used to pass data (decoded frames)
// from the cxr background thread to the render thread (drawInMtkView:)
@interface DecodedFrameRenderBundle:NSObject
@property(nonatomic) id<MTLTexture> renderBundleImageY;
@property(nonatomic) id<MTLTexture> renderBundleImageCbCr;
@property(nonatomic) id<MTLTexture> renderBundleImageAlphaY;
@property(nonatomic) id<MTLTexture> renderBundleImageAlphaCbCr;
@property(nonatomic) simd_float3x4  pose;
@property(nonatomic) uint64_t       latchTime;
@property(nonatomic) uint64_t       blitCompleteTime;
@property(nonatomic) uint64_t       bundleStartRender;
@property(nonatomic) uint64_t       bundleFinishRender;
@property(nonatomic) BOOL           readyToConsume;
@end

@implementation DecodedFrameRenderBundle
@end

@implementation CXRViewController
{
    // CloudXR
    cxrReceiverHandle     receiver;
    BOOL                  connected;
    int                   framesLatched;
    cxrFramesLatched         latchedFrame;
    simd_float3x4         latchedPose;
    NSThread*             cxrThread;
    SEL                   cxrThreadSelector;
    bool                  cxrThreadIsDone;
    id<MTLTexture>        latchedTextureY;        // blit source images
    id<MTLTexture>        latchedTextureCbCr;
    id<MTLTexture>        latchedTextureAlphaY;
    id<MTLTexture>        latchedTextureAlphaCbCr;
    // CloudXR: Render bundles (cxr bg thread -> render thread)
    NSLock*               renderBundleQueueLock;
    NSMutableArray*       renderBundleRingBuffer;
    int                   renderBundleReadIndex;
    int                   renderBundleWriteIndex;
    MTLTextureDescriptor* texDescY;
    MTLTextureDescriptor* texDescCbCr;
    // Metal
    id<MTLDevice>              device;
    id<MTLCommandQueue>        commandQ;
    CVMetalTextureCacheRef     textureCache;
    id<MTLRenderPipelineState> psoCameraOnly;
    id<MTLRenderPipelineState> psoCompositeXR;
    id<MTLBuffer>              imagePlaneVertexBuffer; // Fullscreen quad for image rendering
    // Metal: Display variables (used for the final draw call to screen)
    id<MTLTexture> displayTextureY;
    id<MTLTexture> displayTextureCbCr;
    id<MTLTexture> displayTextureAlphaY;
    id<MTLTexture> displayTextureAlphaCbCr;
    simd_float3x4  displayPose;
    // Metal: Render debug lines
    id<MTLRenderPipelineState> psoVisPlane;
    id<MTLBuffer>              constantBuffer;
    id<MTLBuffer>              lineVertBuffer;
    NSUInteger                 lineVertCount;
    // Metal: Render ground planes
    id<MTLRenderPipelineState> psoVisTris;
    id<MTLBuffer>              triVertBuffer;
    NSUInteger                 triVertCount;
    id<MTLTexture>             gridTex;
    CGPoint                    tapPoint;
    // Metal: Compute shader for blit operation
    id<MTLComputePipelineState> computePipelineState;
    id<MTLFunction>             copyTextureKernel;
    MTLSize                     computeThreadgroupSize;
    MTLSize                     computeThreadgroupCount;
    // ARKit
    ARSession*                          session;
    ARWorldTrackingConfiguration*       trackingConfig;
    NSMutableArray<__kindof ARAnchor*>* seenAnchors;
    id<MTLTexture>                      cameraTextureY;     // latest image from camera
    id<MTLTexture>                      cameraTextureCbCr;  // latest image from camera
    simd_float4x4                       lastTransform;
    bool                                planeSelected;
    float                               scale;
    float                               rotationAngleDegrees;
    simd_float3                         originPos;
    // ARKit: Client data cache
    id<MTLTexture>  cameraTextureCacheY[cameraImageCacheSize];
    id<MTLTexture>  cameraTextureCacheCbCr[cameraImageCacheSize];
    
    id<MTLTexture>  testcameraTextureCacheY[cameraImageCacheSize];
    id<MTLTexture>  testcameraTextureCacheCbCr[cameraImageCacheSize];
    
    simd_float3x4   cameraPoseMatrixCache[cameraImageCacheSize];
    NSLock*         cameraImageCacheIndexLock;
    int             cameraImageCacheWriteIndex;
    int             cameraImageCacheReadIndex;
    // Timer queries. These are different from the data captured with CAPTURE_PERF.
    // These queries are low precision and only used to estimate FPS of each individual
    // thread (render, cxr, arkit).
    NSDate*        startTimes[TIMER_COUNT];
    NSDate*        endTimes[TIMER_COUNT];
    float          timerSamples[TIMER_COUNT][maxTimeSamples];
    int            timerIndex[TIMER_COUNT];
    BOOL           timerFirstTime[TIMER_COUNT];
    
    BOOL  isReplay;
    NSString *openjson;
    NSString *closejson;
}
#pragma mark --视图生命周期
- (void)viewDidLoad {
    [super viewDidLoad];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    isReplay =NO;
    [self.view addSubview:self.mocxingView];
    self.moxingww.constant=ScreenWidth/3*2;
    self.mocxingView.hidden=YES;
    self.dataSource=[NSMutableArray array];
    
    scale = 1.0f;
    self.errorLabel.text = @"";
    device = MTLCreateSystemDefaultDevice();
    commandQ = [device newCommandQueue];
    self.mtlView.delegate = self;
    self.mtlView.device = device;
    self.mtlView.clearColor = MTLClearColorMake(0.0, 1.0, 0.0, 1.0);
    self.mtlView.enableSetNeedsDisplay = NO;
    self.mtlView.framebufferOnly = false;
    if (self.streamFPS60) {
        self.mtlView.preferredFramesPerSecond = 60;
    } else {
        self.mtlView.preferredFramesPerSecond = 30;
    }
    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    id<MTLLibrary> library = [device newDefaultLibrary];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertexShader"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragmentShader"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.mtlView.colorPixelFormat;
    pipelineDescriptor.depthAttachmentPixelFormat = self.mtlView.depthStencilPixelFormat;
    psoCameraOnly = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:0];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragmentShaderCompositeXR"];
    psoCompositeXR = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:0];
    imagePlaneVertexBuffer = [device newBufferWithLength:sizeof(float) * 12 options:MTLResourceStorageModeShared];
    //
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"basicVS"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"solidColor"];
    psoVisPlane = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:0];
    constantBuffer = [device newBufferWithLength:sizeof(shader_data) options:MTLResourceStorageModeShared];
    lineVertBuffer = [device newBufferWithLength:1024 options:MTLResourceStorageModeShared];
    //
    // Compute shader for blit operations
    copyTextureKernel    = [library newFunctionWithName:@"copyTextureKernel"];
    computePipelineState = [device newComputePipelineStateWithFunction:copyTextureKernel
                                                                 error:nil];
    //
    seenAnchors = [[NSMutableArray alloc] init];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"triVS"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"triFS"];
    //
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    //
    psoVisTris = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:0];
    triVertBuffer = [device newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:device];
    NSURL* url = [[NSBundle mainBundle] URLForResource:@"grid" withExtension:@"png"];
    assert(url);
    gridTex = [loader newTextureWithContentsOfURL:url options:nil error:nil];
    assert(gridTex);
    //
    CVReturn r = CVMetalTextureCacheCreate(kCFAllocatorDefault, 0, device, 0, &textureCache);
    assert(r == 0);
    session = [[ARSession alloc] init];
    session.delegate = self;
    //
    [self.mtlView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
    [self.mtlView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]];
    // ARKit cache of iamges and poses
    cameraImageCacheIndexLock    = [NSLock new];
    cameraImageCacheWriteIndex   = 0;
    cameraImageCacheReadIndex    = 0;
    for(int i=0; i< cameraImageCacheSize; ++i) {
        cameraTextureCacheY[i] = nil;
        cameraTextureCacheCbCr[i] = nil;
        for(int j = 0; j < 3; ++j) {
            cameraPoseMatrixCache[i].columns[j] = simd_make_float4(0.0f);
        }
    }
    

    // CXR background thread
    cxrThreadIsDone = NO;
    cxrThreadSelector = NSSelectorFromString(@"cxrBackgroundThread");
    cxrThread = [[NSThread alloc] initWithTarget:self
                                        selector:cxrThreadSelector
                                          object:nil];
    // Thread FPS timer related
    for (int i = 0; i < TIMER_COUNT; ++i) {
        timerFirstTime[i] = YES;
        timerIndex[i] = 0;
        for (int j=0; j<maxTimeSamples; ++j) {
            timerSamples[i][j] = 0.0f;
        }
    }
    
    // Render bundles (cxrBackgroundThread -> RenderThread)
    renderBundleQueueLock = [NSLock new];
    renderBundleRingBuffer = [NSMutableArray arrayWithCapacity:renderBundleRingBufferSize];
    renderBundleReadIndex = renderBundleWriteIndex = 0;

    texDescY = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                           width:self.mtlView.bounds.size.width
                                                           height:self.mtlView.bounds.size.height
                                                           mipmapped:NO];
    texDescY.storageMode = MTLStorageModePrivate;
    texDescY.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | MTLTextureUsagePixelFormatView;
    
    texDescCbCr = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG8Unorm
                                                           width:self.mtlView.bounds.size.width/2
                                                           height:self.mtlView.bounds.size.height/2
                                                           mipmapped:NO];
    texDescCbCr.storageMode = MTLStorageModePrivate;
    texDescCbCr.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | MTLTextureUsagePixelFormatView;
    
    // Pre-allocate the textures in the ringbuffer of render bundles
    for (int i = 0; i < renderBundleRingBufferSize; ++i) {
        DecodedFrameRenderBundle* bundle = [DecodedFrameRenderBundle new];
        bundle.renderBundleImageY = [device newTextureWithDescriptor:texDescY];
        bundle.renderBundleImageCbCr = [device newTextureWithDescriptor:texDescCbCr];
        bundle.renderBundleImageAlphaY = [device newTextureWithDescriptor:texDescY];
        bundle.renderBundleImageAlphaCbCr = [device newTextureWithDescriptor:texDescCbCr];
        bundle.readyToConsume = NO;
        [renderBundleRingBuffer addObject:bundle];
    }
    //
    trackingConfig = [[ARWorldTrackingConfiguration alloc] init];
        trackingConfig.planeDetection = ARPlaneDetectionHorizontal;
        [session runWithConfiguration:trackingConfig];
    
  //  [self setupCaptureSession];
  
    [self.tableView registerNib:[UINib nibWithNibName:NSStringFromClass([ComponentListCell class]) bundle:nil] forCellReuseIdentifier:@"ComponentListCell"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    [self getData];
    
}
- (void)viewWillAppear:(BOOL)animated
{
    AppDelegate * appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.allowRotation = YES;
    [self setNewOrientation:YES];
    [self.navigationController setNavigationBarHidden:YES];
    [self creatUT];
    [self reconnect];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    AppDelegate * appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.allowRotation = NO;
    [self setNewOrientation:NO];
    [session pause];
    [self.navigationController setNavigationBarHidden:NO];
    
    [self.webSocket close];
    self.webSocket = nil;
    self.webSocket.delegate = nil;
    
}
#pragma mark --UI
-(void)creatUT
{
    CGFloat height=60.0f;
//    if (Is_iPhoneX) {
//        height=90;
//    }
  UIView *   topView = [[UIView alloc] initWithFrame:CGRectMake(0,0 , ScreenWidth, height)];
    topView.backgroundColor = [UIColor colorWithWhite:0.f alpha:0.5];
    [self.view addSubview:topView];
    
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame =CGRectMake(ScreenWidth-54, height-45, 44, 44);
    [btn setTitle:@"操作" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [btn addTarget: self action: @selector(operationAction) forControlEvents: UIControlEventTouchUpInside];
    [topView addSubview:btn];
    
    UIButton *lastbtn = [UIButton buttonWithType:UIButtonTypeCustom];
    lastbtn.frame = CGRectMake(0, height-50, 44, 50);
    lastbtn.imageEdgeInsets = UIEdgeInsetsMake(0,  -10, 0, 0);
    [lastbtn setImage:[UIImage imageNamed:@"黑色返回"] forState:UIControlStateNormal];
    [lastbtn addTarget: self action: @selector(lastViewAction) forControlEvents: UIControlEventTouchUpInside];
    [topView addSubview:lastbtn];
    
}
#pragma mark --Action
-(void)lastViewAction
{
    [self.navigationController popViewControllerAnimated:YES];
}

-(void)operationAction
{
    OperationView*   operationView=[[OperationView alloc]initWithFrame:CGRectMake(0, 0, ScreenWidth, ScreenHeight)];
    
    if (isReplay) {
        [operationView.replayBtn setTitle:@"停止录像" forState:UIControlStateNormal];
    }
    else{
        [operationView.replayBtn setTitle:@"录像" forState:UIControlStateNormal];
    }
    operationView .operationBlock = ^(NSString * _Nonnull reason,BOOL stop) {
      
        if ([reason isEqualToString:@"1"]) {
            [self cameraAction];
        }
        else if ([reason isEqualToString:@"2"])
        {
            if (stop) {
                [self startReplay];
                self->isReplay=YES;
            }
            else
            {
                [self stopReplay];
                self->isReplay=NO;
            }
        }
        else{
            self.mocxingView.hidden=NO;
            self.prejectid=self.appid;
            self.uuid=@"";
            [self.dataSource removeAllObjects];
            [self getComponentNodesLevel:0 atIndexPath:nil];
            
        }
    };
    [self.view.window addSubview:operationView];
}
-(void)cameraAction{
 
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
      UIGraphicsBeginImageContextWithOptions(mainWindow.frame.size, NO, 0);
      [mainWindow drawViewHierarchyInRect:mainWindow.frame afterScreenUpdates:YES];
      UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
    UIImageWriteToSavedPhotosAlbum(image, self,@selector(image:didFinishSavingWithError:contextInfo:),NULL);
      
}
- (void) image: (UIImage *) image didFinishSavingWithError: (NSError *) error contextInfo: (void *) contextInfo{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [MBProgressHUD showSuccess:@"已成功保存到相册!" toView:[UIApplication sharedApplication].delegate.window];
    });
}
-(void)startReplay
{

    RPScreenRecorder* recorder = RPScreenRecorder.sharedRecorder;
    [recorder startRecordingWithHandler:^(NSError * _Nullable error) {
        if (!error) {
            NSLog(@"===启动成功");
        }
    }];
    
}
-(void)stopReplay
{
 
    [[RPScreenRecorder sharedRecorder] stopRecordingWithHandler:^(RPPreviewViewController *previewViewController, NSError *  error){
        
        
        if (error) {
            NSLog(@"失败消息:%@", error);
            //   [weakSelf showTipWithText:error.description activity:NO];
        } else {
            NSLog(@"录制完成");
            
            NSLog(@"显示预览页面");
            
            if ([previewViewController respondsToSelector:@selector(movieURL)]) {
                NSURL *videoURL = [previewViewController.movieURL copy];
                BOOL compatible = UIVideoAtPathIsCompatibleWithSavedPhotosAlbum([videoURL path]);
                if (compatible)
                {
                    UISaveVideoAtPathToSavedPhotosAlbum([videoURL path], self, @selector(savedPhotoImage:didFinishSavingWithError:contextInfo:), nil);
                }
                
            }
        
        }
    }];
}

//保存视频完成之后的回调
- (void)savedPhotoImage:(UIImage*)image didFinishSavingWithError: (NSError *)error contextInfo: (void *)contextInfo {
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [MBProgressHUD showSuccess:@"已成功保存到相册!" toView:[UIApplication sharedApplication].delegate.window];
        });
    }
    
}



- (IBAction)closeMoxingView:(id)sender {
    self.mocxingView.hidden=YES;
}



#pragma mark - getComponent
-(void)getData
{
    NSMutableDictionary *para = [NSMutableDictionary dictionary];
    
    if (SWNOTEmptyStr(self.appid)) {
        [para setValue:self.appid forKey:@"appid"];
    }
    [MBProgressHUD showMessage:nil toView:self.view];
    [[OAAPIClient sharedInstance] GET:@"/vjapi/FileStorge/getProjectConifgJsonAR" parameters:para success:^(NSURLSessionDataTask *task, id responseObject) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        NSDictionary * arr = responseObject;
        int mt = [[arr objectForKey:@"code"] intValue];
        if (mt == 0) {
     
            NSString *messge=[arr objectForKey:@"message"];
            
            NSRange range1 = [messge rangeOfString:@"Z:\\\\wj_FileStorge\\\\"];
            NSRange range2 = [messge rangeOfString:@"\\\\config\\\\config.json"];
            if (range1.location !=NSNotFound &&range2.location !=NSNotFound) {
                NSUInteger location = range1.location + range1.length;
                NSUInteger length = range2.location - location;
                NSString * app = [messge substringWithRange:NSMakeRange(location, length)];
                if (app.length>0) {
                    NSRange range = [app rangeOfString:@"\\\\"];
                    NSString * str1 = [app substringToIndex:range.location];
                    NSString * str2 = [app substringFromIndex:range.location+range.length];
                  
                   NSString *  project_path=[NSString stringWithFormat:@"Z:\\wj_FileStorge\\%@\\%@\\",str1,str2];
                    
                    NSDateFormatter *format=[[NSDateFormatter alloc]init];
                    [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    NSString *date=[format stringFromDate:[NSDate date]];
                    NSString *stitle=[NSString stringWithFormat:@"%@",date];
                    NSString *str=[HelpCommon timeSwitchTimestamp:stitle andFormatter:@"yyyy-MM-dd HH:mm:ss"];
                    
                    NSMutableDictionary *para=[NSMutableDictionary dictionary];
                    [para setValue:@"start_ue_ar" forKey:@"cmd"];
                    [para setValue:@"2" forKey:@"msgDir"];
                    [para setValue:@"2" forKey:@"msgType"];
                    [para setValue:[NSString stringWithFormat:@"[BIMAR%@]",str] forKey:@"recipient"];
                    
                    NSMutableDictionary *dic=[NSMutableDictionary dictionary];
                    [dic setValue:project_path forKey:@"project_path"];
                   
                    
                    NSMutableDictionary *dict=[NSMutableDictionary dictionary];
                    [dict setValue:para forKey:@"msgHdr"];
                    [dict setValue:dic forKey:@"start_struct"];
                    
              
                    self->openjson=[HelpCommon dictionaryToJSONString:dict];
                    
                    
                    NSMutableDictionary *para1=[NSMutableDictionary dictionary];
                    [para1 setValue:@"kill_ue_ar" forKey:@"cmd"];
                    [para1 setValue:@"2" forKey:@"msgDir"];
                    [para1 setValue:@"2" forKey:@"msgType"];
                    [para1 setValue:[NSString stringWithFormat:@"[BIMAR%@]",str] forKey:@"recipient"];
                    NSMutableDictionary *dict1=[NSMutableDictionary dictionary];
                    [dict1 setValue:para1 forKey:@"msgHdr"];
                    
                    self->closejson=[HelpCommon dictionaryToJSONString:dict1];
                    
                }
            }
            
        }else{
            
            [MBProgressHUD showError:@"网络请求失败" toView:self.view];
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        [MBProgressHUD showError:[error localizedDescription] toView:self.view];
    }];
}
-(void)getComponentNodesLevel:(int)level atIndexPath:(NSIndexPath *)indexPath
{
    NSMutableDictionary *para = [NSMutableDictionary dictionary];
    
    if (SWNOTEmptyStr(self.prejectid)) {
        [para setValue:self.prejectid forKey:@"appliId"];
    }
    if (SWNOTEmptyStr(self.uuid)) {
        [para setValue:self.uuid forKey:@"uuid"];
    }
    [MBProgressHUD showMessage:nil toView:self.view];
    [[OAAPIClient sharedInstance] GET:@"/vjapi/appli/getComponent" parameters:para success:^(NSURLSessionDataTask *task, id responseObject) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        NSDictionary * arr = responseObject;
        int mt = [[arr objectForKey:@"code"] intValue];
        if (mt == 0) {
            if (self.uuid.length==0) {
                
                NSMutableArray *data = [arr objectForKey:@"data"];
                for (NSDictionary *dict in data) {
                    ComponentModel *model=[[ComponentModel alloc]init];
                    [model setValuesForKeysWithDictionary:dict];
                    model.level = 1;
                    model.leaf = 0;
                    model.root = YES;
                    model.expand = NO;
                    model.selected = YES;
                    [self.dataSource addObject:model];
                }
                
            }
            else
            {
                
                ComponentModel * nodeModel = self.dataSource[indexPath.row];
                NSMutableArray * insertNodeRows = [NSMutableArray array];
                int insertLocation = (int)indexPath.row + 1;
                
                NSArray *data = [arr objectForKey:@"data"];
                
                for (int i = 0; i < data.count; i++) {
                    ComponentModel * node = [[ComponentModel alloc] init];
                    [node setValuesForKeysWithDictionary:data[i]];
                    node.level = level + 1;
                    node.leaf = NO;
                    node.root = NO;
                    node.expand = NO;
                    node.selected = nodeModel.selected;
                    [self.dataSource insertObject:node atIndex:insertLocation + i];
                    [insertNodeRows addObject:[NSIndexPath indexPathForRow:insertLocation + i inSection:0]];
                }
                
                //插入cell
                [self.tableView beginUpdates];
                [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithArray:insertNodeRows] withRowAnimation:UITableViewRowAnimationNone];
                [self.tableView endUpdates];
                
                //更新新插入的元素之后的所有cell的cellIndexPath
                NSMutableArray * reloadRows = [NSMutableArray array];
                int reloadLocation = insertLocation + (int)insertNodeRows.count;
                for (int i = reloadLocation; i < self.dataSource.count; i++) {
                    [reloadRows addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                [self.tableView reloadRowsAtIndexPaths:reloadRows withRowAnimation:UITableViewRowAnimationNone];
                
                
            }
            
            [self.tableView reloadData];
            
            
        }else{
            
            [MBProgressHUD showError:@"网络请求失败" toView:self.view];
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        [MBProgressHUD showError:[error localizedDescription] toView:self.view];
    }];
}

/**
 获取并展开父结点的子结点数组 数量随机产生
 @param level 父结点的层级
 @param indexPath 父结点所在的位置
 */
- (void)expandChildrenNodesLevel:(int)level atIndexPath:(NSIndexPath *)indexPath {
    
    ComponentModel * nodeModel = self.dataSource[indexPath.row];
    self.prejectid=nodeModel.projectId;
    self.uuid=nodeModel.uuid;
    [self getComponentNodesLevel:level atIndexPath:indexPath];
}

/**
 获取并隐藏父结点的子结点数组
 @param level 父结点的层级
 @param indexPath 父结点所在的位置
 */
- (void)hiddenChildrenNodesLevel:(int)level atIndexPath:(NSIndexPath *)indexPath {
    
    NSMutableArray * deleteNodeRows = [NSMutableArray array];
    int length = 0;
    int deleteLocation = (int)indexPath.row + 1;
    for (int i = deleteLocation; i < self.dataSource.count; i++) {
        ComponentModel * node = self.dataSource[i];
        if (node.level > level) {
            [deleteNodeRows addObject:[NSIndexPath indexPathForRow:i inSection:0]];
            length++;
        }else{
            break;
        }
    }
    [self.dataSource removeObjectsInRange:NSMakeRange(deleteLocation, length)];
    [self.tableView beginUpdates];
    [self.tableView deleteRowsAtIndexPaths:deleteNodeRows withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView endUpdates];
    
    //更新删除的元素之后的所有cell的cellIndexPath
    NSMutableArray * reloadRows = [NSMutableArray array];
    int reloadLocation = deleteLocation;
    for (int i = reloadLocation; i < self.dataSource.count; i++) {
        [reloadRows addObject:[NSIndexPath indexPathForRow:i inSection:0]];
    }
    [self.tableView reloadRowsAtIndexPaths:reloadRows withRowAnimation:UITableViewRowAnimationNone];
}

/**
 更新当前结点下所有子结点的选中状态
 @param level 选中的结点层级
 @param selected 是否选中
 @param indexPath 选中的结点位置
 */
- (void)selectedChildrenNodes:(int)level selected:(BOOL)selected atIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray * selectedNodeRows = [NSMutableArray array];
    int deleteLocation = (int)indexPath.row + 1;
    for (int i = deleteLocation; i < self.dataSource.count; i++) {
        ComponentModel * node = self.dataSource[i];
        if (node.level > level) {
            node.selected = selected;
            [selectedNodeRows addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        }else{
            break;
        }
    }
    [self.tableView reloadRowsAtIndexPaths:selectedNodeRows withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDelegate  UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ComponentListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ComponentListCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    ComponentModel *model=self.dataSource[indexPath.row];
    cell.nameLab.text=model.name;
    cell.node = model;
    cell.delegate = self;
    cell.cellIndexPath = indexPath;
    if(cell.node.expand){
        [cell.expandBtn setImage:[UIImage imageNamed:@"箭头-下"] forState:UIControlStateNormal];
    }else{
        [cell.expandBtn setImage:[UIImage imageNamed:@"箭头-左"] forState:UIControlStateNormal];
    }
    if(model.selected){
        cell.seeImage.image=[UIImage imageNamed:@"selected"];
    }else{
        cell.seeImage.image=[UIImage imageNamed:@"disSelected"];
    }
    
    if ([model.haveChild intValue]==0&&model.level!=1) {
        cell.expandBtn.hidden=YES;
        cell.leadingExpandBtn.constant= (model.level-2) * 31;
    }
    else
    {
        cell.expandBtn.hidden=NO;
        cell.leadingExpandBtn.constant= (model.level - 1) * 31;
    }
    
    return cell;
}

- (void )tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

#pragma mark - SLNodeTableViewCellDelegate

- (void)nodeTableViewCell:(ComponentListCell *)cell selected:(BOOL)selected atIndexPath:(NSIndexPath *)indexPath {
    [self selectedChildrenNodes:cell.node.level selected:selected atIndexPath:indexPath];
}

- (void)nodeTableViewCell:(ComponentListCell *)cell expand:(BOOL)expand atIndexPath:(NSIndexPath *)indexPath {
    if (expand) {
        [self expandChildrenNodesLevel:cell.node.level atIndexPath:indexPath];
    }else{
        [self hiddenChildrenNodesLevel:cell.node.level atIndexPath:indexPath];
    }
}
#pragma mark - CloudXR

- (void) cxrBackgroundThread {
    while (!cxrThreadIsDone) {
    
        if (!connected) {
            cxrThreadIsDone = YES;
            break;
        }
        cxrError e = cxrError_Failed;
        e = cxrLatchFrame(receiver, &latchedFrame, cxrFrameMask_All, 1000);
        if (e == cxrError_Success) {
            if (planeSelected) {
                while(readWriteDistance(renderBundleReadIndex,renderBundleWriteIndex) == renderBundleRingBufferSize-1) {
                    usleep(500);
                }
            }
            DecodedFrameRenderBundle* bundle  = [renderBundleRingBuffer objectAtIndex:renderBundleWriteIndex];
            ++framesLatched;
            // rgb texture (left eye)
            CVPixelBufferRef tex;
            tex = (CVPixelBufferRef) latchedFrame.frames[0].texture;
            CVMetalTextureRef cvTexY = createTexture(textureCache, tex, MTLPixelFormatR8Unorm, 0);
            CVMetalTextureRef cvTexCbCr = createTexture(textureCache, tex, MTLPixelFormatRG8Unorm, 1);
            latchedTextureY = CVMetalTextureGetTexture(cvTexY);
            latchedTextureCbCr = CVMetalTextureGetTexture(cvTexCbCr);
            
            // alpha texture (right eye)
            CVPixelBufferRef texA = (CVPixelBufferRef) latchedFrame.frames[1].texture;
            CVMetalTextureRef cvTexAY = createTexture(textureCache, texA, MTLPixelFormatR8Unorm, 0);
            CVMetalTextureRef cvTexACbCr = createTexture(textureCache, texA, MTLPixelFormatRG8Unorm, 1);
            latchedTextureAlphaY = CVMetalTextureGetTexture(cvTexAY);
            latchedTextureAlphaCbCr = CVMetalTextureGetTexture(cvTexACbCr);
       
            latchedPose = simd_matrix(*(simd_packed_float4 *)&latchedFrame.poseMatrix.m[0],
                                          *(simd_packed_float4 *)&latchedFrame.poseMatrix.m[1],
                                          *(simd_packed_float4 *)&latchedFrame.poseMatrix.m[2]);
            
            //check for dynamic resolution changes and resize if necessary
            if (latchedTextureY.width != bundle.renderBundleImageY.width ||
                latchedTextureY.height != bundle.renderBundleImageY.height) {
                texDescY.width = latchedTextureY.width;
                texDescY.height = latchedTextureY.height;
                bundle.renderBundleImageY = [device newTextureWithDescriptor:texDescY];
                bundle.renderBundleImageAlphaY = [device newTextureWithDescriptor:texDescY];
                NSLog(@"Y Texture resize: %lu, %lu", texDescY.width, texDescY.height);
            }
            
            if (latchedTextureCbCr.width != bundle.renderBundleImageCbCr.width ||
                latchedTextureCbCr.height != bundle.renderBundleImageCbCr.height) {
                texDescCbCr.width = latchedTextureCbCr.width;
                texDescCbCr.height = latchedTextureCbCr.height;
                bundle.renderBundleImageCbCr = [device newTextureWithDescriptor:texDescCbCr];
                bundle.renderBundleImageAlphaCbCr = [device newTextureWithDescriptor:texDescCbCr];
                NSLog(@"CbCr Texture resize: %lu, %lu", texDescCbCr.width, texDescCbCr.height);
            }
            
            // 'blit' via compute shader so we can release the frame
            id<MTLCommandBuffer>         commandBuf     = [commandQ commandBuffer];
            id<MTLComputeCommandEncoder> commandEncoder = [commandBuf computeCommandEncoder];

            // first we blit the Y textures
            computeThreadgroupSize = MTLSizeMake(16, 16, 1);
            computeThreadgroupCount.width  = (latchedTextureY.width  + computeThreadgroupSize.width -  1) / computeThreadgroupSize.width;
            computeThreadgroupCount.height = (latchedTextureY.height + computeThreadgroupSize.height - 1) / computeThreadgroupSize.height;
            computeThreadgroupCount.depth  = 1;
            
            [commandEncoder setComputePipelineState:computePipelineState];
            
            [commandEncoder setTexture:latchedTextureY
                               atIndex:0];
            [commandEncoder setTexture:bundle.renderBundleImageY
                               atIndex:1];
            [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                           threadsPerThreadgroup:computeThreadgroupSize];
            
            [commandEncoder setTexture:latchedTextureAlphaY
                               atIndex:0];
            [commandEncoder setTexture:bundle.renderBundleImageAlphaY
                               atIndex:1];
            [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                           threadsPerThreadgroup:computeThreadgroupSize];
            
            // second we blit the CbCr textures
            computeThreadgroupCount.width  = (latchedTextureCbCr.width  + computeThreadgroupSize.width -  1) / computeThreadgroupSize.width;
            computeThreadgroupCount.height = (latchedTextureCbCr.height + computeThreadgroupSize.height - 1) / computeThreadgroupSize.height;
            
            [commandEncoder setTexture:latchedTextureCbCr
                               atIndex:0];
            [commandEncoder setTexture:bundle.renderBundleImageCbCr
                               atIndex:1];
            [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                           threadsPerThreadgroup:computeThreadgroupSize];
            
            [commandEncoder setTexture:latchedTextureAlphaCbCr
                               atIndex:0];
            [commandEncoder setTexture:bundle.renderBundleImageAlphaCbCr
                               atIndex:1];
            [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                           threadsPerThreadgroup:computeThreadgroupSize];

            [commandEncoder endEncoding];
            [commandBuf commit];
            [commandBuf waitUntilCompleted]; // block until GPU work is finished (aka wait on fence)
            cxrReleaseFrame(receiver, &latchedFrame);

            bundle.pose            = latchedPose;
            bundle.readyToConsume  = YES;
            renderBundleWriteIndex = (renderBundleWriteIndex + 1) % renderBundleRingBufferSize;

            bundle = nil;
            
            // cleanup
            CFRelease(cvTexY);
            CFRelease(cvTexCbCr);
            CFRelease(tex);
            latchedTextureY = nil;
            latchedTextureCbCr = nil;

            CFRelease(cvTexAY);
            CFRelease(cvTexACbCr);
            CFRelease(texA);
            latchedTextureAlphaY    = nil;
            latchedTextureAlphaCbCr = nil;
            
            commandEncoder = nil;
            commandBuf = nil;
        } else {
            if (e != cxrError_Frame_Not_Ready) {
                cxrThreadIsDone = true;
            }
        }
    }

    NSLog(@"cxrBackgroundThread has finished");
}

-(void) connectToServer:(simd_float4x4 *)projectionMatrix {
    //
    cxrReceiverDesc desc = {};
    desc.requestedVersion = CLOUDXR_VERSION_DWORD;
    desc.deviceDesc.deliveryType = cxrDeliveryType_Mono_RGBA;
    desc.deviceDesc.width = self.mtlView.bounds.size.width;
    desc.deviceDesc.height = self.mtlView.bounds.size.height;
    
    float bottom = 0.0f;
    float top    = 0.0f;
    float left   = 0.0f;
    float right  = 0.0f;
    
    if (fabsf((*projectionMatrix).columns[2][0]) > 0.0001f) {
      // Non-symmetric projection
      const float oneOver00 = 1.f/(*projectionMatrix).columns[0][0];
      const float l = -(1.f - (*projectionMatrix).columns[2][0])*oneOver00;
      const float r = 2.f*oneOver00 + l;

      const float oneOver11 = 1.f/(*projectionMatrix).columns[1][1];
      const float b = -(1.f - (*projectionMatrix).columns[2][1])*oneOver11;
      const float t = 2.f*oneOver11 + b;

      left   = -l;
      right  = r;
      top    = -t;
      bottom = -b;
    } else {
      // Symmetric projection
      left   = -1.f/(*projectionMatrix).columns[0][0]; // l
      right  = -left;                                  // r
      top    = -1.f/(*projectionMatrix).columns[1][1]; // t
      bottom = -top;                                   // b
    }

    desc.deviceDesc.maxResFactor = 1.0f;
    if (self.streamFPS60) {
        desc.deviceDesc.fps = 60.0f;
    } else {
        desc.deviceDesc.fps = 30.0f;
    }
  
    desc.deviceDesc.ipd = 0.062f;
    desc.deviceDesc.proj[0][0] = left;
    desc.deviceDesc.proj[0][1] = right;
    desc.deviceDesc.proj[0][2] = top;
    desc.deviceDesc.proj[0][3] = bottom;
    desc.deviceDesc.proj[1][0] = left;
    desc.deviceDesc.proj[1][1] = right;
    desc.deviceDesc.proj[1][2] = 0.0f; // disable right eye rendering on server
    desc.deviceDesc.proj[1][3] = 0.0f; // disable right eye rendering on server
    desc.deviceDesc.predOffset = 0.1;
    desc.deviceDesc.receiveAudio = cxrFalse;
    desc.deviceDesc.sendAudio = cxrFalse;
    desc.deviceDesc.embedInfoInVideo = cxrFalse;
    desc.deviceDesc.disablePosePrediction = cxrTrue;
    desc.deviceDesc.angularVelocityInDeviceSpace = cxrFalse;
    desc.deviceDesc.foveatedScaleFactor = 100;
    desc.deviceDesc.posePollFreq = 0;
    desc.deviceDesc.ctrlType = cxrControllerType_HtcVive;
    desc.deviceDesc.foveationModeCaps = 0;
    desc.deviceDesc.chaperone.universe = cxrUniverseOrigin_Standing;
    cxrMatrix34 identity = {};
    identity.m[0][0] = identity.m[1][1] = identity.m[2][2] = 1.f;
    desc.deviceDesc.chaperone.origin = identity;
    desc.deviceDesc.chaperone.playArea.v[0] = desc.deviceDesc.chaperone.playArea.v[1] = 0;
    desc.clientCallbacks.GetTrackingState = GetTrackingState;
    desc.clientCallbacks.TriggerHaptic = TriggerHaptic;
    desc.clientCallbacks.RenderAudio = RenderAudio;
    desc.clientCallbacks.ReceiveUserData = ReceiveUserData;
    desc.clientCallbacks.UpdateClientState = UpdateClientState;
    desc.clientContext = (__bridge void*)self;
    desc.shareContext = 0;
    desc.numStreams = 2;
    desc.receiverMode = cxrStreamingMode_XR;
    desc.debugFlags = 0;
    desc.logMaxSizeKB = 65536;
    desc.logMaxAgeDays = 30;
    cxrError e = cxrCreateReceiver(&desc, &receiver);
    if(e != cxrError_Success) {
        NSLog(@"Receiver create failed with code %d [%s]", (int)e, cxrErrorString(e));
    }
    e = cxrConnect(receiver, self.address.UTF8String, 0);
    if(e != cxrError_Success) {
        NSLog(@"Receiver connect failed with code %d [%s]", (int)e, cxrErrorString(e));
    }
}

// This function is used to calculate the FPS of each of the different
// threads (cxr, render, arkit). It is a rough estimate only since it
// is averaged over the past 10 frames
-(float)computeElapsedTime: (timer_index) index {
    if(timerFirstTime[index]) {
        startTimes[index] = [NSDate date];
        timerFirstTime[index] = NO;
    } else {
        endTimes[index] = [NSDate date];
        NSTimeInterval executionTime = [endTimes[index] timeIntervalSinceDate:startTimes[index]];
        timerSamples[index][timerIndex[index]] = (float)executionTime;
        startTimes[index] = endTimes[index];
        timerIndex[index] = (timerIndex[index] + 1) % maxTimeSamples;
        
        return (float)executionTime;
    }
    return 0.0;
}

#pragma mark - Render Thread & UI

-(void)updateUILabels {
    // update UI from main thread
    _framesLatchedLabel.text = [NSString stringWithFormat:@"Frames Latched: %d", framesLatched];
    
    float averageTime = 0.0f;
    
    if(timerIndex[TIMER_METAL] == maxTimeSamples-1) {
        for (int i = 0; i< maxTimeSamples; ++i) {
            averageTime += timerSamples[TIMER_METAL][i];
        }
        averageTime /= maxTimeSamples;
        
        self.metalFPSLabel.text = [NSString stringWithFormat:@"Metal FPS: %3.4f", 1.0f / averageTime];
    }
    
    if(timerIndex[TIMER_ARKIT] == maxTimeSamples-1) {
        for (int i = 0; i< maxTimeSamples; ++i) {
            averageTime += timerSamples[TIMER_ARKIT][i];
        }
        averageTime /= maxTimeSamples;
        self.arkitFPSLabel.text = [NSString stringWithFormat:@"ARKit FPS: %3.4f", 1.0f/averageTime];
    }
    
    if(timerIndex[TIMER_CXR] == maxTimeSamples - 1) {
        for (int i = 0; i< maxTimeSamples; ++i) {
            averageTime += timerSamples[TIMER_CXR][i];
        }
        averageTime /= maxTimeSamples;
        self.cxrFPSLabel.text = [NSString stringWithFormat:@"CXR FPS: %3.4f", 1.0f/averageTime];
    }
    
    if (planeSelected) {
        int latencyInFrames = cameraImageCacheReadIndex >= cameraImageCacheWriteIndex ?
                              cameraImageCacheSize - cameraImageCacheReadIndex + cameraImageCacheWriteIndex :
                              cameraImageCacheWriteIndex - cameraImageCacheReadIndex;
        
         self.framesBehindLabel.text = [NSString stringWithFormat:@"Frames behind: %i", latencyInFrames];
    }
    self.scaleLabel.text = [NSString stringWithFormat:@"Scale: %.1f", scale];
}

-(void)drawInMTKView:(nonnull MTKView *)view {
    
    DecodedFrameRenderBundle* bundle = nil;
    
    if (!connected) {
        [self computeElapsedTime: TIMER_METAL];
        return;
    }
    int readAttempts = renderBundleRingBufferSize;
    if (planeSelected) {
        while(readAttempts > 0) {
            bundle = [renderBundleRingBuffer objectAtIndex:renderBundleReadIndex];
            if (bundle.readyToConsume == NO) {
                renderBundleReadIndex = (renderBundleReadIndex + 1) % renderBundleRingBufferSize;
                readAttempts--;
            } else {
                break;
            }
        }
        
        if (readAttempts <= 0)
            return; // could not find a render bundle to consume
        
        displayTextureY         = bundle.renderBundleImageY;
        displayTextureCbCr      = bundle.renderBundleImageCbCr;
        displayTextureAlphaY    = bundle.renderBundleImageAlphaY;
        displayTextureAlphaCbCr = bundle.renderBundleImageAlphaCbCr;
        displayPose             = bundle.pose;
        bundle.readyToConsume   = NO;
        renderBundleReadIndex = (renderBundleReadIndex + 1) % renderBundleRingBufferSize;
    }
    
    // now compare the poseMatrix of the popped frame to the history of cached camera frames & poses
    if (planeSelected) {
        int startIdx = (cameraImageCacheReadIndex - 1);
        if(startIdx < 0) {
            startIdx = cameraImageCacheSize - 1;
        }
        cameraImageCacheReadIndex = [self DetermineArrayOffset:&displayPose queueIndex:startIdx];
    } else {
        // no plane selected, so just display the camera feed (no composition with cxr feed)
        displayTextureY = displayTextureCbCr = displayTextureAlphaY = displayTextureAlphaCbCr = nil;
    }
       
    id<MTLCommandBuffer> commandBuf = [commandQ commandBuffer];
    MTLRenderPassDescriptor* onscreenDescriptor = view.currentRenderPassDescriptor;
    id<MTLRenderCommandEncoder> encoder = [commandBuf renderCommandEncoderWithDescriptor:onscreenDescriptor];
    [encoder setVertexBuffer:imagePlaneVertexBuffer offset:0 atIndex:0];
    
    if (planeSelected) {
        [encoder setRenderPipelineState:psoCompositeXR];
        [encoder setFragmentTexture:cameraTextureCacheY[cameraImageCacheReadIndex] atIndex:0];
        [encoder setFragmentTexture:cameraTextureCacheCbCr[cameraImageCacheReadIndex] atIndex:1];
        [encoder setFragmentTexture:displayTextureY atIndex:2];
        [encoder setFragmentTexture:displayTextureCbCr atIndex:3];
        [encoder setFragmentTexture:displayTextureAlphaY atIndex:4];
        [encoder setFragmentTexture:displayTextureAlphaCbCr atIndex:5];

    } else {
        [encoder setRenderPipelineState:psoCameraOnly];
        // use most recent camera image
        int writeIdx = cameraImageCacheWriteIndex-1;
        if (writeIdx < 0)
            writeIdx = cameraImageCacheSize-1;
        [encoder setFragmentTexture:cameraTextureCacheY[writeIdx] atIndex:0];
        [encoder setFragmentTexture:cameraTextureCacheCbCr[writeIdx] atIndex:1];
    }

    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

    //
#ifdef DRAW_DEBUG_LINES
    [encoder setRenderPipelineState:psoVisPlane];
    [encoder setVertexBuffer:constantBuffer offset:0 atIndex:0];
    [encoder setVertexBuffer:lineVertBuffer offset:0 atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:lineVertCount];
#endif
    // draw the ground planes as a grid
    if (!planeSelected) {
        [encoder setRenderPipelineState:psoVisTris];
        [encoder setVertexBuffer:constantBuffer offset:0 atIndex:0];
        [encoder setVertexBuffer:triVertBuffer offset:0 atIndex:1];
        [encoder setFragmentTexture:gridTex atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:triVertCount];
    }
    //
    [encoder endEncoding];
    [commandBuf presentDrawable:view.currentDrawable];
    
    [commandBuf commit];
        
    [self updateUILabels];
    
    [self computeElapsedTime: TIMER_METAL];
    
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}


-(int)DetermineArrayOffset:(simd_float3x4*)poseFromLatchedFrame
                queueIndex:(int) queueIndex {
    
    int curIdx = queueIndex;
    
    for (int count = 0; count < cameraImageCacheSize; ++count) {
        if (simd_equal(cameraPoseMatrixCache[curIdx], *poseFromLatchedFrame)) {
            return curIdx;
        } else {
            curIdx++;
            if (curIdx >= cameraImageCacheSize)
                curIdx = 0;
        }
    }
    
    // this REALLY should not happen...
    NSLog(@"FATAL ERROR: could not find array index of cameraPoseMatrix");
    NSLog(@"Mismatch: looking for %4.6f %4.6f %4.6f", poseFromLatchedFrame->columns[0][3],
          poseFromLatchedFrame->columns[1][3],
          poseFromLatchedFrame->columns[2][3]);
    
    NSLog(@"Mismatch: using %4.6f %4.6f %4.6f", cameraPoseMatrixCache[0].columns[0][3],
          cameraPoseMatrixCache[0].columns[1][3],
          cameraPoseMatrixCache[0].columns[2][3]);
    return 0;
}

#pragma mark - ARKit

-(void) CachePoseMatrix:(simd_float4x4 *)currentPoseMatrix
{
    simd_float3x4* hmd_matrix = cameraPoseMatrixCache + cameraImageCacheWriteIndex;
    // transpose due to pose coming back from server is row-major (DirectX)
    hmd_matrix->columns[0][0] = currentPoseMatrix->columns[0][0];
    hmd_matrix->columns[0][1] = currentPoseMatrix->columns[1][0];
    hmd_matrix->columns[0][2] = currentPoseMatrix->columns[2][0];
    hmd_matrix->columns[0][3] = currentPoseMatrix->columns[3][0];
    hmd_matrix->columns[1][0] = currentPoseMatrix->columns[0][1];
    hmd_matrix->columns[1][1] = currentPoseMatrix->columns[1][1];
    hmd_matrix->columns[1][2] = currentPoseMatrix->columns[2][1];
    hmd_matrix->columns[1][3] = currentPoseMatrix->columns[3][1];
    hmd_matrix->columns[2][0] = currentPoseMatrix->columns[0][2];
    hmd_matrix->columns[2][1] = currentPoseMatrix->columns[1][2];
    hmd_matrix->columns[2][2] = currentPoseMatrix->columns[2][2];
    hmd_matrix->columns[2][3] = currentPoseMatrix->columns[3][2];
}

-(void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  
    //
    simd_float4x4 matView = [frame.camera viewMatrixForOrientation:UIInterfaceOrientationLandscapeRight];
    simd_float4x4 matProj = [frame.camera projectionMatrixForOrientation:UIInterfaceOrientationLandscapeRight viewportSize:self.mtlView.bounds.size zNear:0.01f zFar:1000.0f];
    //
    if (!connected) {
        // deferred connection since we need to send the projectionMatrix during startup
        [self connectToServer: &matProj];
        connected = YES;
        [cxrThread start];
    }
    //
    [self updateImagePlaneWithFrame:frame];
    lastTransform = frame.camera.transform;
    lastTransform.columns[3].xyz -= originPos; // align the ARKit scene with the Omniverse scene
    
    //Apply scale around the origin
    simd_float4x4 scaleMatrix = matrix_identity_float4x4;
    scaleMatrix.columns[0].x = scaleMatrix.columns[1].y = scaleMatrix.columns[2].z = 1.0/scale;
    lastTransform = simd_mul(scaleMatrix, lastTransform);
    
    // apply rotation from UI slider value
    float radians = rotationAngleDegrees * (M_PI/180.0f);
    simd_float3 y_axis = simd_make_float3(0.0f, 1.0f, 0.0f);
    simd_quatf quat = simd_quaternion(radians, y_axis);
    simd_float4x4 yRotationMatrix = simd_matrix4x4(quat);
    lastTransform = simd_mul(yRotationMatrix, lastTransform);
    
    // update the data for the draw call
    shader_data* shaderData = constantBuffer.contents;
    shaderData->projectionMatrix = matProj;
    shaderData->viewMatrix = matView;
    
    // ray-plane intersection based on touch point
    if((tapPoint.x != 0) && (tapPoint.y != 0)) {
        simd_float4  start = simd_make_float4(frame.camera.transform.columns[3].xyz, 1.f);
        simd_float4* outPtr = lineVertBuffer.contents;
        simd_float3  candidate = simd_make_float3(FLT_MAX);
        for(ARPlaneAnchor* p in seenAnchors) {
            // use ARKit api to unproject
            simd_float3 unprojPoint = [frame.camera unprojectPoint:tapPoint
                                            ontoPlaneWithTransform:p.transform
                                                       orientation:UIInterfaceOrientationLandscapeRight
                                                      viewportSize:self.mtlView.bounds.size];
            
            simd_float4 planeCenter  = simd_mul(p.transform, simd_make_float4(p.center, 1));
            line_seg    ray          = { start.xyz, unprojPoint };
            simd_float3 planeNormal  = simd_make_float3(0, 1, 0);
            simd_float3 intersection = intersect(ray, planeCenter.xyz, planeNormal);
            outPtr[lineVertCount++]  = simd_make_float4(intersection, 1);
            outPtr[lineVertCount++]  = simd_make_float4(intersection + planeNormal, 1);
            BOOL isCloser = distance(start.xyz, intersection) < distance(start.xyz, candidate);
            BOOL isInRect = pointInPlaneRect(p, intersection);
            if(isCloser && isInRect) {
                candidate = intersection;
            }
        }
        
        tapPoint.x = tapPoint.y = 0.f;
        
        if (candidate.x != FLT_MAX) {
            NSLog(@"Plane selected");
            planeSelected = YES;
            // turn off plane detection since it uses a lot of power
            trackingConfig.planeDetection = ARPlaneDetectionNone;
            [session runWithConfiguration:trackingConfig];
            originPos = candidate;
            outPtr[lineVertCount++] = start;
            outPtr[lineVertCount++] = simd_make_float4(candidate, 1);
            self.errorLabel.text = [NSString stringWithFormat:@"orig: [%f, %f, %f]", originPos.x, originPos.y, originPos.z];
                      NSLog(@"origin: x:%3.3f, y:%3.3f, z:%3.3f", originPos.x, originPos.y, originPos.z);
               
          if(openjson.length>0)
          {
            //  [self.webSocket send:openjson];
          }
        
        }
    }
    // camera texture from ARKit
    CVMetalTextureRef cvTexY = createTexture(textureCache, frame.capturedImage, MTLPixelFormatR8Unorm, 0);
    CVMetalTextureRef cvTexCbCr = createTexture(textureCache, frame.capturedImage, MTLPixelFormatRG8Unorm, 1);
    cameraTextureY = CVMetalTextureGetTexture(cvTexY);
    cameraTextureCbCr = CVMetalTextureGetTexture(cvTexCbCr);
    CFRelease(cvTexY);
    CFRelease(cvTexCbCr);
    
    // cache the camera textures and current pose. these will be used later in the draw function (composition)
    if (cameraTextureCacheY[cameraImageCacheWriteIndex] == nil ||
        cameraTextureY.width != cameraTextureCacheY[cameraImageCacheWriteIndex].width ||
        cameraTextureY.height != cameraTextureCacheY[cameraImageCacheWriteIndex].height) {
        
        MTLTextureDescriptor* texDescY;
        texDescY = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                      width:cameraTextureY.width
                                                                     height:cameraTextureY.height
                                                                  mipmapped:NO];
        texDescY.storageMode = MTLStorageModePrivate;
        texDescY.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | MTLTextureUsagePixelFormatView;
        cameraTextureCacheY[cameraImageCacheWriteIndex] = [device newTextureWithDescriptor:texDescY];
    }
    
    if (cameraTextureCacheCbCr[cameraImageCacheWriteIndex] == nil ||
        cameraTextureCbCr.width != cameraTextureCacheCbCr[cameraImageCacheWriteIndex].width ||
        cameraTextureCbCr.height != cameraTextureCacheCbCr[cameraImageCacheWriteIndex].height) {
        
        MTLTextureDescriptor* texDescCbCr;
        
        texDescCbCr = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG8Unorm
                                                                         width:cameraTextureCbCr.width
                                                                        height:cameraTextureCbCr.height
                                                                     mipmapped:NO];
        texDescCbCr.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | MTLTextureUsagePixelFormatView;
        texDescCbCr.storageMode = MTLStorageModePrivate;
        
        cameraTextureCacheCbCr[cameraImageCacheWriteIndex] = [device newTextureWithDescriptor:texDescCbCr];
    }
    
    
    
    id<MTLCommandBuffer>         commandBuf     = [commandQ commandBuffer];
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuf computeCommandEncoder];
    
    // first we blit the Y textures
    computeThreadgroupSize = MTLSizeMake(16, 16, 1);
    computeThreadgroupCount.width  = (cameraTextureCacheY[cameraImageCacheWriteIndex].width  + computeThreadgroupSize.width -  1) / computeThreadgroupSize.width;
    computeThreadgroupCount.height = (cameraTextureCacheY[cameraImageCacheWriteIndex].height + computeThreadgroupSize.height - 1) / computeThreadgroupSize.height;
    computeThreadgroupCount.depth  = 1;
    
    [commandEncoder setComputePipelineState:computePipelineState];
    // blit y
    [commandEncoder setTexture:cameraTextureY
                       atIndex:0];
    [commandEncoder setTexture:cameraTextureCacheY[cameraImageCacheWriteIndex]
                       atIndex:1];
    [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                   threadsPerThreadgroup:computeThreadgroupSize];
    
    // blit CbCr
    computeThreadgroupCount.width  = (cameraTextureCacheCbCr[cameraImageCacheWriteIndex].width  + computeThreadgroupSize.width -  1) / computeThreadgroupSize.width;
    computeThreadgroupCount.height = (cameraTextureCacheCbCr[cameraImageCacheWriteIndex].height + computeThreadgroupSize.height - 1) / computeThreadgroupSize.height;
    
    [commandEncoder setTexture:cameraTextureCbCr
                       atIndex:0];
    [commandEncoder setTexture:cameraTextureCacheCbCr[cameraImageCacheWriteIndex]
                       atIndex:1];
    [commandEncoder dispatchThreadgroups:computeThreadgroupCount
                   threadsPerThreadgroup:computeThreadgroupSize];
    
    [commandEncoder endEncoding];
    [commandBuf commit];
    cameraTextureY = nil;
    cameraTextureCbCr = nil;
    [self CachePoseMatrix: &lastTransform]; // note, transpose happens in this function
    
    [cameraImageCacheIndexLock lock];
    cameraImageCacheWriteIndex = (cameraImageCacheWriteIndex + 1) % cameraImageCacheSize;
    [cameraImageCacheIndexLock unlock];
    
    [self computeElapsedTime: TIMER_ARKIT];
    
}

- (void)session:(ARSession *)session didAddAnchors:(NSArray<__kindof ARAnchor*>*)anchors {
    for(int i = 0; i < anchors.count; ++i)
    {
        if(![anchors[i] isKindOfClass:[ARPlaneAnchor class]]) {
          
          
        }
        else
        {
        ARPlaneAnchor* p = anchors[i];
        [seenAnchors addObject:p];
        simd_float4x4 t = p.transform;
        simd_float3 c = p.center;
        simd_float3 e = p.extent / 2.f;
        simd_float4 i = simd_make_float4(c.x + e.x, c.y, c.z + e.z, 1);
        simd_float4 j = simd_make_float4(c.x - e.x, c.y, c.z + e.z, 1);
        simd_float4 k = simd_make_float4(c.x - e.x, c.y, c.z - e.z, 1);
        simd_float4 l = simd_make_float4(c.x + e.x, c.y, c.z - e.z, 1);
        i = simd_mul(t, i);
        j = simd_mul(t, j);
        k = simd_mul(t, k);
        l = simd_mul(t, l);
#if PLANE_VIS_LINES
        simd_float4* outPtr = lineVertBuffer.contents;
        outPtr[lineVertCount++] = i;
        outPtr[lineVertCount++] = j;
        //
        outPtr[lineVertCount++] = j;
        outPtr[lineVertCount++] = k;
        //
        outPtr[lineVertCount++] = k;
        outPtr[lineVertCount++] = l;
        //
        outPtr[lineVertCount++] = l;
        outPtr[lineVertCount++] = i;
#endif
        //
        NSUInteger nextVert = triVertCount;
        simd_float4* triOut = triVertBuffer.contents;
        triOut[nextVert++] = i;
        triOut[nextVert++] = j;
        triOut[nextVert++] = k;
        triOut[nextVert++] = i;
        triOut[nextVert++] = k;
        triOut[nextVert++] = l;
        triVertCount += 6;
        }
    }
    [self.mtlView setNeedsDisplay];
}

- (void)handleTap:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        tapPoint = [gestureRecognizer locationInView:self.mtlView];
       
//        simd_float4x4 translation = matrix_identity_float4x4;
//        translation.columns[3].z = -0.2;
//
//        simd_float4x4  newtranslation=   simd_mul(session.currentFrame.camera.transform, translation);
//
//        ARAnchor *anchor=[[ARAnchor alloc]initWithTransform:newtranslation];
//        [session addAnchor:anchor ];
      
    }
}

- (void)handleLongPress:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        planeSelected = NO;
        originPos = simd_make_float3(0, 0, 0);
        lineVertCount = 0;
        
        [self.webSocket send:closejson];
    }
}
- (IBAction)scaleChanged:(id)sender {
    UISlider* s = (UISlider*)sender;
    scale = s.value;
    self.scaleLabel.text = [NSString stringWithFormat:@"Scale: %.1f", scale];
}

- (IBAction)rotationChanged:(id)sender {
    UISlider* s = (UISlider*)sender;
    rotationAngleDegrees = s.value;
    self.rotationLabel.text = [NSString stringWithFormat:@"Rotation: %1f", rotationAngleDegrees];
}

- (simd_float4x4) arTransform
{
    return lastTransform;
}

// Vertex data for an image plane
static const float kImagePlaneVertexData[12] = {
    1.0, 1.0,
    0.0, 1.0,
    0.0, 0.0,
    //
    1.0, 1.0,
    0.0, 0.0,
    1.0, 0.0,
};

- (void) updateImagePlaneWithFrame:(ARFrame *)frame {
    // Update the texture coordinates of our image plane to aspect fill the viewport
    CGAffineTransform displayToCameraTransform = CGAffineTransformInvert([frame displayTransformForOrientation:UIInterfaceOrientationLandscapeRight viewportSize:self.mtlView.bounds.size]);
    
    float *vertexData = [imagePlaneVertexBuffer contents];
    for (NSInteger index = 0; index < 6; index++) {
        NSInteger textureCoordIndex = 2 * index;
        CGPoint textureCoord = CGPointMake(kImagePlaneVertexData[textureCoordIndex], kImagePlaneVertexData[textureCoordIndex + 1]);
        CGPoint transformedCoord = CGPointApplyAffineTransform(textureCoord, displayToCameraTransform);
        vertexData[textureCoordIndex] = transformedCoord.x;
        vertexData[textureCoordIndex + 1] = transformedCoord.y;
    }
}

- (void)setNewOrientation:(BOOL)fullscreen

{
    if (fullscreen) {
        NSNumber *resetOrientationTarget = [NSNumber numberWithInt:UIInterfaceOrientationUnknown];
        [[UIDevice currentDevice] setValue:resetOrientationTarget forKey:@"orientation"];
        NSNumber *orientationTarget = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight];
        [[UIDevice currentDevice] setValue:orientationTarget forKey:@"orientation"];
        
    }else{
    
        NSNumber *resetOrientationTarget = [NSNumber numberWithInt:UIInterfaceOrientationUnknown];
        [[UIDevice currentDevice] setValue:resetOrientationTarget forKey:@"orientation"];
        NSNumber *orientationTarget = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
        [[UIDevice currentDevice] setValue:orientationTarget forKey:@"orientation"];
        
    }
    
}
#pragma mark - SRWebSocket
-(void)reconnect{
   self.webSocket.delegate = nil;
   [self.webSocket close];
   self.webSocket = nil;

// url根据公司的要求，样式和参数不同
   self.webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:websocket_url]]];
   self.webSocket.delegate = self;
   
   [self.webSocket open];
}
#pragma mark - SRWebSocketDelegate // 代理方法
// 连接成功
- (void)webSocketDidOpen:(SRWebSocket *)webSocket{

  //  [self sendHeart];
//每90秒发送一次心跳
//    [NSTimer scheduledTimerWithTimeInterval:90 target:self selector:@selector(sendHeart) userInfo:nil repeats:YES];
//  心跳间隔时间和心跳内容询问后台
    NSLog(@"Websocket Connected");
}
// 连接失败
- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error{
// 这里可进行重连
    NSLog(@":( Websocket Failed With Error %@", error);
}
// 接收数据
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message{
// 在这里进行数据的处理
    NSLog(@"%@",message);
}
// 连接关闭
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean{
// 判断是何种情况的关闭，如果是人为的就不需要重连，如果是其他情况，就重连
    NSLog(@"webSocket Closed!");
}
// 接收服务器发送的pong消息
- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload{
    NSLog(@"Websocket received pong");
}
// 发送心跳
- (void)sendHeart{
    NSString *heartBeat = @"心跳";
    @try {
        [self.webSocket send:heartBeat];
    } @catch (NSException *exception) {
       //  发送心跳出错
        [self reconnect];
    }
   
}
////  给服务器发送信息
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    // 信息格式询问后台
   //NSString *message = @"message";
   // [self.webSocket send:message];
}



@end
