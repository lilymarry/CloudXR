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

#import "ViewController.h"
#import "CXRViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <ARKit/ARKit.h>
#import <MetalKit/MetalKit.h>
#import "OAAPIClient.h"
#import "MainViewCell.h"
#import "CXRViewController.h"
#import "ScanCodeViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<UICollectionViewDelegate,UICollectionViewDataSource>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray *collectionArr;

@property (strong, nonatomic) IBOutlet UITextField *addrField;
@property (strong, nonatomic) IBOutlet UIButton *btnConnect;
@property (strong, nonatomic) IBOutlet UISegmentedControl *fpsSetting;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString* address = [NSUserDefaults.standardUserDefaults stringForKey:@"ServerAddress"];
    if(address) {
        self.addrField.text = address;
    } else {
        self.btnConnect.enabled = NO;
    }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        NSLog(@"Camera permission request grant status: %d", (int)granted);
    }];
    
    UICollectionViewFlowLayout *collectionLayout = [[UICollectionViewFlowLayout alloc]init];
    UICollectionView *collectionView = [[UICollectionView alloc]initWithFrame:CGRectMake(0, 30,ScreenWidth ,ScreenHeight-30) collectionViewLayout:collectionLayout];
    self.collectionView=collectionView;
    self.collectionView.backgroundColor =[UIColor whiteColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.view addSubview:collectionView];
    
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    scanBtn.frame =CGRectMake(ScreenWidth-120, ScreenHeight-140, 100, 100);
   //  [scanBtn setTitle:@"扫码" forState:UIControlStateNormal];
    [scanBtn setImage:[UIImage imageNamed:@"Scan"] forState:UIControlStateNormal];
  //  [scanBtn setBackgroundImage:[UIImage imageNamed:@"扫一扫"] forState:UIControlStateNormal];
    scanBtn.backgroundColor=[UIColor whiteColor];
//    [scanBtn setTitleColor:RBGColor(121, 121, 121,1) forState:UIControlStateNormal];
    [scanBtn addTarget: self action: @selector(scanAction) forControlEvents: UIControlEventTouchUpInside];
    scanBtn.layer.cornerRadius=50;
    scanBtn.layer.borderColor=RBGColor(121, 121, 121,1).CGColor;
    scanBtn.layer.borderWidth = 0.65f;
    [self.view addSubview:scanBtn];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame =CGRectMake(0, 0, 46, 46);
    [btn setTitle:@"账号" forState:UIControlStateNormal];
    [btn.titleLabel setFont: [UIFont systemFontOfSize:14]];
    btn.backgroundColor=[UIColor whiteColor];
    [btn setTitleColor:RBGColor(121, 121, 121,1) forState:UIControlStateNormal];
    [btn addTarget: self action: @selector(userAction) forControlEvents: UIControlEventTouchUpInside];
    btn.layer.cornerRadius=23;
    btn.layer.borderColor=RBGColor(121, 121, 121,1).CGColor;
    btn.layer.borderWidth = 0.65f;
    UIBarButtonItem* item=[[UIBarButtonItem alloc]initWithCustomView:btn];
    self.navigationItem.rightBarButtonItem=item;
    
    
    [_collectionView registerNib:[UINib nibWithNibName:@"MainViewCell" bundle:nil] forCellWithReuseIdentifier:@"MainViewCell"];
   [self getData];
}

- (IBAction)addrChanged:(id)sender {
    NSString* text = self.addrField.text;
    if(text && text.length) {
        self.btnConnect.enabled = YES;
    } else {
        self.btnConnect.enabled =  NO;
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue
                 sender:(id)sender
{
    CXRViewController* c = (CXRViewController*)segue.destinationViewController;
    c.address = self.addrField.text;
    if(self.fpsSetting.selectedSegmentIndex == 1) {
        c.streamFPS60 = YES;
    }
    else {
        c.streamFPS60 = NO;
    }
    [NSUserDefaults.standardUserDefaults setObject:self.addrField.text forKey:@"ServerAddress"];
}
-(void)getData
{
    [MBProgressHUD showMessage:nil toView:self.view];
//    GET /appli/getApplicationList
//    获取当前用户项目列表/
    [[OAAPIClient sharedInstance] GET:@"/vjapi/appli/getApplicationList" parameters:@{@"userid":@"757efcc0b8124d86aa94340d2f3101ee"} success:^(NSURLSessionDataTask *task, id responseObject) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        NSDictionary * arr = responseObject;
        int mt = [[arr objectForKey:@"code"] intValue];
            if (mt == 0) {
            NSMutableArray *dic = [arr objectForKey:@"data"];
            self.collectionArr =[NSMutableArray arrayWithArray:dic];
            [self.collectionView reloadData];

        }else{
          
            [MBProgressHUD showError:@"网络请求失败" toView:self.view];
        }
       
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
        [MBProgressHUD showError:[error localizedDescription] toView:self.view];
    }];
}
-(void)userAction
{
    UIStoryboard *story = [UIStoryboard storyboardWithName:@"Login" bundle:[NSBundle mainBundle]];
    UIViewController *setController = [story instantiateViewControllerWithIdentifier:@"Login"];
    setController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:setController animated:YES completion:nil];
    
}
-(void)scanAction
{
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
    ScanCodeViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"Scan"];
    [self.navigationController pushViewController:controller animated:YES ];
}
#pragma mark UICollectionView
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
    
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.collectionArr.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath{
    MainViewCell * cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MainViewCell" forIndexPath:indexPath];
   NSDictionary *dic=  self.collectionArr[indexPath.item];
   cell.nameLab.text=dic[@"appName"];
  NSString* encodedString =[dic[@"screenImg"] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];//URL 含有中文 encode 编码
    [cell.nameImage sd_setImageWithURL:[NSURL URLWithString:encodedString] placeholderImage:[UIImage imageNamed:@"null-picture"]];
    return cell;
}
#pragma mark - CollectionView的item的布局
-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath{
        return CGSizeMake(ScreenWidth/2-8,ScreenWidth/2-8);
}
-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *dic=  self.collectionArr[indexPath.item];
    [MBProgressHUD showMessage:@"正在进入，请稍等" toView:self.view];
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
         
           UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
           CXRViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"CXRvc"];
          // controller.streamingXR = YES;
           controller.address =@"192.168.3.160";
           controller.appid=dic[@"appid"];
           [self.navigationController pushViewController:controller animated:YES ];
      });

}
- (void)viewDidDisappear:(BOOL)animated
{
    [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
}
@end
