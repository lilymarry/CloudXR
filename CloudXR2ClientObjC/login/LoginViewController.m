//
//  LoginViewController.m
//  CloudXR2ClientObjC
//
//  Created by 万间科技 on 2021/7/29.
//

#import "LoginViewController.h"
#import "ZQTColorSwitch.h"
@interface LoginViewController ()
@property (weak, nonatomic) IBOutlet UITextField *ph_tf;
@property (weak, nonatomic) IBOutlet UITextField *pw_tf;
@property (weak, nonatomic) IBOutlet UIView *switchView;

@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(keyHiden:) name: UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(keyWillAppear:) name:UIKeyboardWillChangeFrameNotification object:nil];
    

    [_pw_tf setSecureTextEntry:YES];
    ZQTColorSwitch *nkColorSwitch1 = [[ZQTColorSwitch alloc] initWithFrame:CGRectMake(2, 14, self.switchView.frame.size.width-4, 35)];
    [nkColorSwitch1 addTarget:self action:@selector(switchPressed:) forControlEvents:UIControlEventValueChanged];
    nkColorSwitch1.onBackLabel.text = @"123";
    nkColorSwitch1.offBackLabel.text = @"***";
    nkColorSwitch1.onBackLabel.textColor = [UIColor whiteColor];
    [nkColorSwitch1 setTintColor:[UIColor groupTableViewBackgroundColor]];
    [nkColorSwitch1 setOnTintColor:RBGColor(52, 119, 245, 1)];
    [nkColorSwitch1 setThumbTintColor:[UIColor whiteColor]];
    [self.switchView addSubview:nkColorSwitch1];
    
}
-(void)keyHiden:(NSNotification *)notification
{
    
    [UIView animateWithDuration:0.25 animations:^{
        //恢复原样
        self.view.transform = CGAffineTransformIdentity;
        
    }];
    
    
}
-(void)keyWillAppear:(NSNotification *)notification
{
    //获得通知中的info字典
    NSDictionary *userInfo = [notification userInfo];
    CGRect rect= [[userInfo objectForKey:@"UIKeyboardFrameEndUserInfoKey"]CGRectValue];
    
    [UIView animateWithDuration:0.25 animations:^{
        self.view.transform = CGAffineTransformMakeTranslation(0, -([UIScreen mainScreen].bounds.size.height-rect.origin.y)+100);
    }];
    
    
}
- (IBAction)loginPress:(id)sender {
    
       if (_ph_tf.text.length==0) {
           [MBProgressHUD showSuccess:@"请输入手机号" toView:self.view];
           return;
       }
       NSString *str =[HelpCommon valiMobile:_ph_tf.text];
       if (str.length>0) {
           [MBProgressHUD showSuccess:str toView:self.view];
           return;
       }
}
- (IBAction)lastPress:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
}
- (void)switchPressed:(id)sender
{
    ZQTColorSwitch *nkswitch = (ZQTColorSwitch *)sender;
    if (nkswitch.isOn)
    {
        [_pw_tf setSecureTextEntry:NO];
        
    }
       
    else
       
    {
       
        [_pw_tf setSecureTextEntry:YES];
    }
}

@end
