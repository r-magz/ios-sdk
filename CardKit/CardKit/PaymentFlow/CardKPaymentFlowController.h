//
//  NSObject+CardKPaymentFlow.h
//  CardKit
//
//  Created by Alex Korotkov on 3/26/21.
//  Copyright © 2021 AnjLab. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "CardKViewController.h"
#import "CardKPaymentInfo.h"
#import "CardKPaymentError.h"
#import "RequestParams.h"

@protocol CardKPaymentFlowDelegate <NSObject>

- (void)didFinishPaymentFlow:(NSDictionary *) paymentInfo;
- (void)didErrorPaymentFlow:(CardKPaymentError *) paymentError;
- (void)didCancelPaymentFlow;
- (void)scanCardRequest:(CardKViewController *)controller;
@end

@interface CardKPaymentFlowController: UIViewController<CardKDelegate>
  @property (weak, nonatomic) id<CardKPaymentFlowDelegate> cardKPaymentFlowDelegate;

  @property CardKPaymentView* cardKPaymentView;
  
  @property NSString* url;

  @property UIColor* primaryColor;
  @property UIColor* secondaryColor;
  @property UIColor* textColor;
  @property UIColor* buttonTextColor;
  @property BOOL allowedCardScaner;

@end
