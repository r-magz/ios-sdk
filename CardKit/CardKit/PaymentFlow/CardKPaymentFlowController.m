//
//  NSObject+CardKPaymentFlow.m
//  CardKit
//
//  Created by Alex Korotkov on 3/26/21.
//  Copyright © 2021 AnjLab. All rights reserved.
//
#import <PassKit/PassKit.h>
#import "CardKPaymentFlowController.h"
#import "CardKKindPaymentViewController.h"
#import "CardKConfig.h"
#import "RSA.h"
#import "ConfirmChoosedCard.h"
#import "CardKPaymentSessionStatus.h"
#import <ThreeDSSDK/ThreeDSSDK.h>
#import "NSBundle+Resources.h"

#import <CardKit/CardKit-Swift.h>
#import "ARes.h"

@protocol TransactionManagerDelegate;

@interface CardKPaymentFlowController () <TransactionManagerDelegate>
@end

@implementation CardKPaymentFlowController {
  CardKKindPaymentViewController *_kindPaymentController;
  UIActivityIndicatorView *_spinner;
  CardKTheme *_theme;
  CardKBinding *_cardKBinding;
  CardKPaymentSessionStatus *_sessionStatus;
  CardKPaymentError *_cardKPaymentError;
  NSString *_seToken;
  TransactionManager *_transactionManager;
  NSBundle *_languageBundle;
  NSBundle *_bundle;
}
- (instancetype)init
  {
    self = [super init];
    if (self) {
      _bundle = [NSBundle resourcesBundle];
      
      NSString *language = CardKConfig.shared.language;
      _languageBundle = [NSBundle languageBundle:language];
      
      _theme = CardKConfig.shared.theme;
      self.view.backgroundColor = CardKConfig.shared.theme.colorTableBackground;
      
      _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
      [self.view addSubview:_spinner];
      _spinner.color = _theme.colorPlaceholder;
      
      [_spinner startAnimating];
      
      _cardKPaymentError = [[CardKPaymentError alloc] init];
      
      _transactionManager = [[TransactionManager alloc] init];
      _transactionManager.rootCertificate = CardKConfig.shared.rootCertificate;

      _transactionManager.delegate = self;
    }
    return self;
  }

  - (void)setDirectoryServerId:(NSString *)directoryServerId {
    _transactionManager.directoryServerId = directoryServerId;
  }

  - (NSString *)directoryServerId {
    return _transactionManager.directoryServerId;
  }

  - (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _spinner.frame = CGRectMake(0, 0, 100, 100);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
  }

  - (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];

    [self _getSessionStatusRequest];
  }

  - (NSString *) _joinParametersInString:(NSArray<NSString *> *) parameters {
    return [parameters componentsJoinedByString:@"&"];
  }

  - (void) _sendErrorWithCardPaymentError:(CardKPaymentError *) cardKPaymentError {
    if (self->_cardKPaymentFlowDelegate != nil) {
      [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
    } else {
      [self _showAlertMessage:cardKPaymentError.message];
    }
  }

  - (void) _sendSuccessMessage:(NSDictionary *) responseDictionary {
    if (self.cardKPaymentFlowDelegate != nil) {
      [self.cardKPaymentFlowDelegate didFinishPaymentFlow:responseDictionary];
      
      return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Оплата успешна завершена" message:@"Оплата успешна завершена" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
      [self.navigationController presentViewController:alert animated:YES completion:nil];
    }]];
  }

  - (void) _sendError {
    self->_cardKPaymentError.message = @"Ошибка запроса";
    [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

    [self _sendErrorWithCardPaymentError: self->_cardKPaymentFlowDelegate];
  }

  - (void)_sendRedirectError {
    self->_cardKPaymentError.message = self->_sessionStatus.redirect;
    [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
  
    [self.navigationController popViewControllerAnimated:YES];
  }

  - (void)_moveChoosePaymentMethodController {
    _kindPaymentController = [[CardKKindPaymentViewController alloc] init];
    _kindPaymentController.verticalButtonsRendered = YES;
    _kindPaymentController.cKitDelegate = self;
    
    self.navigationItem.rightBarButtonItem = _kindPaymentController.navigationItem.rightBarButtonItem;
    
    [self addChildViewController:_kindPaymentController];
    _kindPaymentController.view.frame = self.view.frame;
    [self.view addSubview:_kindPaymentController.view];
    
    [self->_spinner stopAnimating];
  }

  - (void) _showAlertMessage:(NSString *) message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];

    [self.navigationController presentViewController:alert animated:YES completion:nil];
  }

  - (void) _getFinishSessionStatusRequest {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/getSessionStatus.do", mdOrder];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"GET";

    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      
      dispatch_async(dispatch_get_main_queue(), ^{
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode != 200) {
        [self _sendError];
        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      NSString *redirect = [responseDictionary objectForKey:@"redirect"];
      NSInteger remainingSecs = [responseDictionary[@"remainingSecs"] integerValue];
        
      if (redirect == nil || remainingSecs > 0 ) {
        [self _getSessionStatusRequest];
      } else {
        [self _getFinishedPaymentInfo];
      }
      });
    }];
    [dataTask resume];
  }
  
  - (NSArray<CardKBinding *> *) _convertBindingItemsToCardKBinding:(NSArray<NSDictionary *> *) bindingItems {
    NSMutableArray<CardKBinding *> *bindings = [[NSMutableArray alloc] init];
    
    for (NSDictionary *binding in bindingItems) {
      CardKBinding *cardKBinding = [[CardKBinding alloc] init];
      
      NSArray *label = [(NSString *) binding[@"label"] componentsSeparatedByString:@" "];
      cardKBinding.bindingId = binding[@"id"];
      cardKBinding.paymentSystem = binding[@"paymentSystem"];
      
      cardKBinding.cardNumber = label[0];
      cardKBinding.expireDate = label[1];
      
      [bindings addObject:cardKBinding];
    }
  
    return bindings;
  }

  - (void) _getSessionStatusRequest {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/getSessionStatus.do", mdOrder];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"GET";

    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    
        if(httpResponse.statusCode != 200) {
          [self _sendError];
          return;
        }
        
        NSError *parseError = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        
        self->_sessionStatus = [[CardKPaymentSessionStatus alloc] init];
          
        NSArray<NSDictionary *> *bindingItems = (NSArray<NSDictionary *> *) responseDictionary[@"bindingItems"];

        self->_sessionStatus.bindingItems = [self _convertBindingItemsToCardKBinding: bindingItems];
        self->_sessionStatus.bindingEnabled = (BOOL)[responseDictionary[@"bindingEnabled"] boolValue];
        self->_sessionStatus.cvcNotRequired = (BOOL)[responseDictionary[@"cvcNotRequired"] boolValue];
        self-> _sessionStatus.redirect = [responseDictionary objectForKey:@"redirect"];
        
        CardKConfig.shared.bindings = [[NSArray alloc] initWithArray:self->_sessionStatus.bindingItems];
        CardKConfig.shared.bindingCVCRequired = !self->_sessionStatus.cvcNotRequired;
        
        if (self->_sessionStatus.redirect != nil) {
          [self _sendRedirectError];
        } else {
          [self _moveChoosePaymentMethodController];
        }
      });
    }];
    [dataTask resume];
  }

  - (void) _processBindingFormRequest:(ConfirmChoosedCard *) choosedCard callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
    NSString *bindingId = [NSString stringWithFormat:@"%@%@", @"bindingId=", choosedCard.cardKBinding.bindingId];
    NSString *cvc = [NSString stringWithFormat:@"%@%@", @"cvc=", choosedCard.cardKBinding.secureCode];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];
    
    NSString *parameters = @"";
    
    if (CardKConfig.shared.bindingCVCRequired) {
      parameters = [self _joinParametersInString:@[mdOrder, bindingId, cvc, language, threeDSSDK]];
    } else {
      parameters = [self _joinParametersInString:@[mdOrder, bindingId, language, threeDSSDK]];
    }
    
    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processBindingForm.do"];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"POST";
    
    NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    [request setHTTPBody:postData];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode != 200) {
        [self _sendError];
        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      NSString *redirect = [responseDictionary objectForKey:@"redirect"];
      BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
      NSString *errorMessage = [responseDictionary objectForKey:@"error"];
      NSString *info = [responseDictionary objectForKey:@"info"];
      NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
      NSString *message = errorMessage ? errorMessage : info;
        
      if (errorCode != 0) {
        self->_cardKPaymentError.message = message;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      } else if (redirect != nil) {
        self->_cardKPaymentError.message = message;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      } else if (is3DSVer2){
        RequestParams.shared.threeDSServerTransId = [responseDictionary objectForKey:@"threeDSServerTransId"];
        RequestParams.shared.threeDSSDKKey = [responseDictionary objectForKey:@"threeDSSDKKey"];

        self->_transactionManager.pubKey = RequestParams.shared.threeDSSDKKey;
        self->_transactionManager.headerLabel = self.headerLabel;
        [self->_transactionManager setUpUICustomizationWithPrimaryColor:self.primaryColor textDoneButtonColor:self.textDoneButtonColor error:nil];
        [self->_transactionManager initializeSdk];
        [self->_transactionManager showProgressDialog];
        NSDictionary *reqParams = [self->_transactionManager getAuthRequestParameters];
        
        RequestParams.shared.threeDSSDKEncData = reqParams[@"threeDSSDKEncData"];
        RequestParams.shared.threeDSSDKEphemPubKey = reqParams[@"threeDSSDKEphemPubKey"];
        RequestParams.shared.threeDSSDKAppId = reqParams[@"threeDSSDKAppId"];
        RequestParams.shared.threeDSSDKTransId = reqParams[@"threeDSSDKTransId"];

        [self _processBindingFormRequestStep2:(ConfirmChoosedCard *) choosedCard  callback: (void (^)(NSDictionary *)) handler];
      }
    });
      
    }];
    [dataTask resume];
  }

  - (void) _processBindingFormRequestStep2:(ConfirmChoosedCard *) choosedCard callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
    NSString *bindingId = [NSString stringWithFormat:@"%@%@", @"bindingId=", choosedCard.cardKBinding.bindingId];
    NSString *cvc = [NSString stringWithFormat:@"%@%@", @"cvc=", choosedCard.cardKBinding.secureCode];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    
    NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];
    NSString *threeDSSDKEncData = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEncData=", RequestParams.shared.threeDSSDKEncData];
    NSString *threeDSSDKEphemPubKey = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEphemPubKey=", RequestParams.shared.threeDSSDKEphemPubKey];
    NSString *threeDSSDKAppId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKAppId=", RequestParams.shared.threeDSSDKAppId];
    NSString *threeDSSDKTransId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKTransId=", RequestParams.shared.threeDSSDKTransId];
    NSString *threeDSServerTransId = [NSString stringWithFormat:@"%@%@", @"threeDSServerTransId=", RequestParams.shared.threeDSServerTransId];
    NSString *threeDSSDKReferenceNumber = [NSString stringWithFormat:@"%@%@", @"threeDSSDKReferenceNumber=", @"3DS_LOA_SDK_BPBT_020100_00233"];
    
    NSString *parameters = @"";
    
    if (CardKConfig.shared.bindingCVCRequired) {
      parameters = [self _joinParametersInString:@[mdOrder, bindingId, cvc, threeDSSDK, language, threeDSSDKEncData, threeDSSDKEphemPubKey, threeDSSDKAppId, threeDSSDKTransId, threeDSServerTransId, threeDSSDKReferenceNumber]];
    } else {
      parameters = [self _joinParametersInString:@[mdOrder, bindingId, threeDSSDK, language, threeDSSDKEncData, threeDSSDKEphemPubKey, threeDSSDKAppId, threeDSSDKTransId, threeDSServerTransId, threeDSSDKReferenceNumber]];
    }
    
    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processBindingForm.do"];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"POST";
    
    NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    [request setHTTPBody:postData];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session
                                      dataTaskWithRequest:request
                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (httpResponse.statusCode != 200) {
          self->_cardKPaymentError.message = @"Ошибка запроса данных формы";
          [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

          return;
        }
        
        NSError *parseError = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

        NSString *redirect = [responseDictionary objectForKey:@"redirect"];
        BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
        NSString *errorMessage = [responseDictionary objectForKey:@"error"];
        NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
        
        if (errorCode != 0) {
          self->_cardKPaymentError.message = errorMessage;
          [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
          [self->_transactionManager closeProgressDialog];
        } else if (redirect != nil) {
          self->_cardKPaymentError.message = errorMessage;
          [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
          [self->_transactionManager closeProgressDialog];
        } else if (is3DSVer2){
          [self _runChallange: responseDictionary];
        }
      });
    }];
    [dataTask resume];
  }

  - (void)_initSDK:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken allowSaveBinding:(BOOL) allowSaveBinding callback: (void (^)(NSDictionary *)) handler {
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_transactionManager.headerLabel = self.headerLabel;
      [self->_transactionManager setUpUICustomizationWithPrimaryColor:self.primaryColor textDoneButtonColor:self.textDoneButtonColor error:nil];
      [self->_transactionManager initializeSdk];
      [self->_transactionManager showProgressDialog];
      NSDictionary *reqParams = [self->_transactionManager getAuthRequestParameters];
      
      RequestParams.shared.threeDSSDKEncData = reqParams[@"threeDSSDKEncData"];
      RequestParams.shared.threeDSSDKEphemPubKey = reqParams[@"threeDSSDKEphemPubKey"];
      RequestParams.shared.threeDSSDKAppId = reqParams[@"threeDSSDKAppId"];
      RequestParams.shared.threeDSSDKTransId = reqParams[@"threeDSSDKTransId"];

      [self _processFormRequestStep2:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken allowSaveBinding:(BOOL) allowSaveBinding callback: (void (^)(NSDictionary *)) handler];
    });
  }

  - (void) _processFormRequest:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken allowSaveBinding:(BOOL) allowSaveBinding callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    NSString *owner = [NSString stringWithFormat:@"%@%@", @"TEXT=", cardOwner];
    NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];
    NSString *seTokenParam = [NSString stringWithFormat:@"%@%@", @"seToken=", [seToken stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];
    NSString *bindingNotNeeded = [NSString stringWithFormat:@"%@%@", @"bindingNotNeeded=", allowSaveBinding ? @"false" : @"true"];

    NSString *parameters = [self _joinParametersInString:@[mdOrder, seTokenParam, language, owner, bindingNotNeeded, threeDSSDK]];
    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processform.do"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];
    request.HTTPMethod = @"POST";

    NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    [request setHTTPBody:postData];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode != 200) {
        [self _sendError];
        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
      
      NSString *redirect = [responseDictionary objectForKey:@"redirect"];
      BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
      NSString *errorMessage = [responseDictionary objectForKey:@"error"];
      NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
      
      if (errorCode != 0) {
        self->_cardKPaymentError.message = errorMessage;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      } else if (redirect != nil) {
        self->_cardKPaymentError.message = errorMessage;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      } else if (is3DSVer2){
        RequestParams.shared.threeDSServerTransId = [responseDictionary objectForKey:@"threeDSServerTransId"];
        RequestParams.shared.threeDSSDKKey = [responseDictionary objectForKey:@"threeDSSDKKey"];

        self->_transactionManager.pubKey = RequestParams.shared.threeDSSDKKey;
       
        [self _initSDK:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken allowSaveBinding:(BOOL) allowSaveBinding callback: (void (^)(NSDictionary *)) handler];
      }
    });
    }];
    [dataTask resume];
  }

  - (void) _runChallange:(NSDictionary *) responseDictionary {
    ARes *aRes = [[ARes alloc] init];
   
    aRes.acsTransID = [responseDictionary objectForKey:@"threeDSAcsTransactionId"];
    aRes.acsReferenceNumber = [responseDictionary objectForKey:@"threeDSAcsRefNumber"];
    aRes.acsSignedContent = [responseDictionary objectForKey:@"threeDSAcsSignedContent"];
    aRes.threeDSServerTransID = RequestParams.shared.threeDSServerTransId;

    [self->_transactionManager handleResponseWithARes:aRes];
  }

  - (void) _processFormRequestStep2:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken allowSaveBinding:(BOOL) allowSaveBinding callback: (void (^)(NSDictionary *)) handler {
      NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
      NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];
      NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
      NSString *owner = [NSString stringWithFormat:@"%@%@", @"TEXT=", cardOwner];
      NSString *bindingNotNeeded = [NSString stringWithFormat:@"%@%@", @"bindingNotNeeded=", allowSaveBinding ? @"false" : @"true"];
      NSString *seTokenParam = [NSString stringWithFormat:@"%@%@", @"seToken=", [seToken stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];
    
      NSString *threeDSSDKEncData = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEncData=", RequestParams.shared.threeDSSDKEncData];
      NSString *threeDSSDKEphemPubKey = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEphemPubKey=", RequestParams.shared.threeDSSDKEphemPubKey];
      NSString *threeDSSDKAppId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKAppId=", RequestParams.shared.threeDSSDKAppId];
      NSString *threeDSSDKTransId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKTransId=", RequestParams.shared.threeDSSDKTransId];
      NSString *threeDSServerTransId = [NSString stringWithFormat:@"%@%@", @"threeDSServerTransId=", RequestParams.shared.threeDSServerTransId];
      NSString *threeDSSDKReferenceNumber = [NSString stringWithFormat:@"%@%@", @"threeDSSDKReferenceNumber=", @"3DS_LOA_SDK_BPBT_020100_00233"];
    
      NSString *parameters = [self _joinParametersInString:@[mdOrder, threeDSSDK, language, owner, bindingNotNeeded, threeDSSDKEncData, threeDSSDKEphemPubKey, threeDSSDKAppId, threeDSSDKTransId, threeDSServerTransId, seTokenParam, threeDSSDKReferenceNumber]];

      NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
      NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processform.do"];
    
      NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

      request.HTTPMethod = @"POST";
      [request setHTTPBody:postData];
    
      NSURLSession *session = [NSURLSession sharedSession];

      NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if (httpResponse.statusCode != 200) {
          self->_cardKPaymentError.message = @"Ошибка запроса данных формы";
          [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

          return;
        }
        
        NSError *parseError = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

        NSString *redirect = [responseDictionary objectForKey:@"redirect"];
        BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
        NSString *errorMessage = [responseDictionary objectForKey:@"error"];
        NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
        
        if (errorCode != 0) {
          self->_cardKPaymentError.message = errorMessage;
          [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
          [self->_transactionManager closeProgressDialog];
        } else if (redirect != nil) {
          self->_cardKPaymentError.message = errorMessage;
          [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
          [self->_transactionManager closeProgressDialog];
        } else if (is3DSVer2){
          [self _runChallange: responseDictionary];
        }
      }];
      [dataTask resume];
    }

  - (void)_getFinishedPaymentInfo {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
    NSString *withCart = [NSString stringWithFormat:@"%@%@", @"withCart=", @"false"];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];

    NSString *parameters = [self _joinParametersInString:@[mdOrder, withCart, language]];

    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/getFinishedPaymentInfo.do", parameters];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"GET";

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            
          if(httpResponse.statusCode != 200) {
            [self _sendError];
            return;
          }
          
          NSError *parseError = nil;
          NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
          
          [self _sendSuccessMessage:responseDictionary];
      });
    }];
    [dataTask resume];
  }

  - (void)_unbindСardAnon:(CardKBinding *) binding {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"mdOrder=", CardKConfig.shared.mdOrder];
    NSString *bindingId = [NSString stringWithFormat:@"%@%@", @"bindingId=", binding.bindingId];
    
    NSString *parameters = [self _joinParametersInString:@[mdOrder, bindingId]];
    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/unbindcardanon.do", parameters];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"GET";

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if (httpResponse.statusCode != 200) {
        [self _sendError];

        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      NSString *errorMessage = [responseDictionary objectForKey:@"error"];
      NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
      
      if (errorCode != 0) {
        self->_cardKPaymentError.message = errorMessage;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      }
    }];
    [dataTask resume];
  }

  - (void)_applePay:(NSString *) paymentToken {
    NSDictionary *jsonBodyDict = @{@"mdOrder":CardKConfig.shared.mdOrder, @"paymentToken":paymentToken};
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject:jsonBodyDict options:kNilOptions error:nil];

    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/applepay/paymentOrder.do"];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"POST";
    
    [request setHTTPBody:jsonBodyData];
    
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if (httpResponse.statusCode != 200) {
        [self _sendError];

        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      BOOL success = (BOOL)[responseDictionary[@"success"] boolValue];
      NSString *message = responseDictionary[@"error"][@"description"];
      
      if (success) {
        [self _getFinishSessionStatusRequest];
      } else {
        self->_cardKPaymentError.message = message;
        [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      }
    }];
    [dataTask resume];
  }

  // CardKDelegate
  - (void)cardKPaymentView:(nonnull CardKPaymentView *)paymentView didAuthorizePayment:(nonnull PKPayment *)pKPayment {
    if (pKPayment == nil) {
      self->_cardKPaymentError.message = @"Оплата applepay завершилась с ошибкой";
      [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];

      return;
    }
  
    NSDictionary *dict=[NSJSONSerialization JSONObjectWithData:pKPayment.token.paymentData options:kNilOptions error:nil];
    
    if (dict == nil) {
      self->_cardKPaymentError.message = @"Оплата applepay завершилась не успешно";
      [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
      
      return;
    }
    
    NSData * jsonData = [NSJSONSerialization  dataWithJSONObject:dict options:0 error:nil];
   
    NSString *base64Encoded = [jsonData base64EncodedStringWithOptions:0];

    [self _applePay: base64Encoded];
  }

  - (void)cardKitViewController:(nonnull UIViewController *)controller didCreateSeToken:(nonnull NSString *)seToken allowSaveBinding:(BOOL)allowSaveBinding isNewCard:(BOOL)isNewCard {
    _seToken = seToken;
    if (isNewCard) {
      CardKViewController *cardKViewController = (CardKViewController *) controller;
      [self _processFormRequest: [cardKViewController getCardKView]
                 cardOwner:[cardKViewController getCardOwner]
                  seToken:seToken
       allowSaveBinding: allowSaveBinding
                  callback:^(NSDictionary * sessionStatus) {}];
    } else {
      ConfirmChoosedCard *confirmChoosedCardController = (ConfirmChoosedCard *) controller;
      _cardKBinding = confirmChoosedCardController.cardKBinding;
      [self _processBindingFormRequest:confirmChoosedCardController
                          callback:^(NSDictionary * sessionStatus) {}];
    }
  }

  - (void)didLoadController:(nonnull CardKViewController *)controller {
    controller.allowedCardScaner = self.allowedCardScaner;
    controller.purchaseButtonTitle = NSLocalizedStringFromTableInBundle(@"doneButton", nil, _languageBundle, @"Submit payment");
    controller.allowSaveBinding = self->_sessionStatus.bindingEnabled;
    controller.isSaveBinding = false;
    controller.displayCardHolderField = true;
  }

  - (void)didRemoveBindings:(nonnull NSArray<CardKBinding *> *)removedBindings {
    for (CardKBinding *removedBinding in removedBindings) {
      [self _unbindСardAnon: removedBinding];
    }
  }

  - (void)willShowPaymentView:(nonnull CardKPaymentView *)paymentView {
    paymentView.paymentRequest = _cardKPaymentView.paymentRequest;
    paymentView.paymentButtonType =_cardKPaymentView.paymentButtonType;
    paymentView.paymentButtonStyle =_cardKPaymentView.paymentButtonStyle;
    
    if (_cardKPaymentView.cardPaybutton == nil) {
      return;
    }
    
    paymentView.cardPaybutton.backgroundColor = _cardKPaymentView.cardPaybutton.backgroundColor;
    paymentView.cardPaybutton.tintColor = _cardKPaymentView.cardPaybutton.tintColor;
    [paymentView.cardPaybutton setTitleColor:_cardKPaymentView.cardPaybutton.currentTitleColor forState:UIControlStateNormal];
    
    if (![_cardKPaymentView.cardPaybutton.titleLabel.text isEqual:@""] || _cardKPaymentView.cardPaybutton.titleLabel != nil) {
      NSString * title = _cardKPaymentView.cardPaybutton.titleLabel.text;
      [paymentView.cardPaybutton setTitle:title forState:UIControlStateNormal];
    }
  }

  - (void)didCancel {
    [self.cardKPaymentFlowDelegate didCancelPaymentFlow];
  }

  - (void)didCompleteWithTransactionStatus:(NSString *) transactionStatus {
    NSString *threeDSServerTransId = [NSString stringWithFormat:@"%@%@", @"threeDSServerTransId=", RequestParams.shared.threeDSServerTransId];

    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/finish3dsVer2PaymentAnonymous.do"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];
    request.HTTPMethod = @"POST";

    NSData *postData = [threeDSServerTransId dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    [request setHTTPBody:postData];

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      
      dispatch_async(dispatch_get_main_queue(), ^{
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
          
        if(httpResponse.statusCode != 200) {
          [self _sendError];
          return;
        }

        NSError *parseError = nil;
        NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

        NSString *errorMessage = [responseDictionary objectForKey:@"error"];
        NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
          
        if (errorCode != 0) {
          self->_cardKPaymentError.message = errorMessage;
          [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
        }
        
        [self _getFinishSessionStatusRequest];
      });
    }];
    [dataTask resume];
  }

  - (void)errorEventReceivedWithMessage:(NSString * _Nonnull)message {
    self->_cardKPaymentError.message = message;
    [self _sendErrorWithCardPaymentError: self->_cardKPaymentError];
    [self->_transactionManager closeProgressDialog];
  }

  - (void)cardKitViewControllerScanCardRequest:(CardKViewController *)controller {
    [self.cardKPaymentFlowDelegate scanCardRequest:controller];
  }

@end
