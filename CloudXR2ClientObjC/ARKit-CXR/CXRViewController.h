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

#import <Foundation/Foundation.h>
#import <ARKit/ARKit.h>
#import <MetalKit/MetalKit.h>
#import <ReplayKit/ReplayKit.h>

#import "OperationView.h"
#import "AppDelegate.h"
#import "ScanTipView.h"
#import <ReplayKit/ReplayKit.h>
#import "ComponentListCell.h"
#import "ComponentModel.h"
#import "SRWebSocket.h"
#import "RPPreviewViewController+MovieURL.h"
#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef enum {
    TIMER_METAL = 0,
    TIMER_CXR   = 1,
    TIMER_ARKIT = 2,
    TIMER_COUNT = 3
} timer_index;
#define AnimationDuration (0.3)
@interface CXRViewController : UIViewController <MTKViewDelegate, ARSessionDelegate,RPPreviewViewControllerDelegate,UITableViewDelegate,UITableViewDataSource,ComponentListCellCellDelegate,SRWebSocketDelegate,AVCaptureMetadataOutputObjectsDelegate>

@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@property (strong, nonatomic) IBOutlet UILabel *framesLatchedLabel;
@property (strong, nonatomic) IBOutlet UILabel *rotationLabel;
@property (strong, nonatomic) IBOutlet MTKView *mtlView;
@property (strong, nonatomic) IBOutlet UILabel *metalFPSLabel;
@property (strong, nonatomic) IBOutlet UILabel *cxrFPSLabel;
@property (strong, nonatomic) IBOutlet UILabel *arkitFPSLabel;
@property (strong, nonatomic) IBOutlet UILabel *framesBehindLabel;
@property (strong, nonatomic) IBOutlet UILabel *scaleLabel;

@property (nonatomic, strong) NSString *appid;
@property (nonatomic, strong) NSString *uuid;
@property(nonatomic) BOOL streamFPS60;
@property(nonatomic, copy) NSString* address;

@property (nonatomic, strong) NSString *prejectid;
@property (weak, nonatomic) IBOutlet UIView *mocxingView;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) NSMutableArray * dataSource;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *moxingww;

@property(strong,nonatomic)SRWebSocket *webSocket;




@property(nonatomic,strong) AVCaptureSession *mCaptureSession;
//负责从AVCaptureDevice获得输入数据
@property (nonatomic, strong) AVCaptureDeviceInput *mCaptureDeviceInput;
//输出设备
@property(nonatomic,strong)AVCaptureMetadataOutput *mCaptureVideoDataOutput;

- (simd_float4x4) arTransform;

@end

NS_ASSUME_NONNULL_END
