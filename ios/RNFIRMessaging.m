#import "RNFIRMessaging.h"

#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

@import UserNotifications;

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

#define UIUserNotificationTypeAlert UIRemoteNotificationTypeAlert
#define UIUserNotificationTypeBadge UIRemoteNotificationTypeBadge
#define UIUserNotificationTypeSound UIRemoteNotificationTypeSound
#define UIUserNotificationTypeNone  UIRemoteNotificationTypeNone
#define UIUserNotificationType      UIRemoteNotificationType

#endif

NSString *const FCMNotificationReceived = @"FCMNotificationReceived";
NSString *const FCMTokenRefreshed = @"FCMTokenRefreshed";
NSString *const FCMDirectChannelConnectionChanged = @"FCMDirectChannelConnectionChanged";

@implementation RCTConvert (NSCalendarUnit)

RCT_ENUM_CONVERTER(NSCalendarUnit,
                   (@{
                      @"year": @(NSCalendarUnitYear),
                      @"month": @(NSCalendarUnitMonth),
                      @"week": @(NSCalendarUnitWeekOfYear),
                      @"day": @(NSCalendarUnitDay),
                      @"hour": @(NSCalendarUnitHour),
                      @"minute": @(NSCalendarUnitMinute)
                      }),
                   0,
                   integerValue)
@end


@implementation RCTConvert (UNNotificationRequest)

+ (UNNotificationRequest *)UNNotificationRequest:(id)json
{
    NSDictionary<NSString *, id> *details = [self NSDictionary:json];
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title =[RCTConvert NSString:details[@"title"]];
    content.body =[RCTConvert NSString:details[@"body"]];
    NSString* sound = [RCTConvert NSString:details[@"sound"]];
    if(sound != nil){
        if ([sound isEqual:@"default"]) {
            content.sound = [UNNotificationSound defaultSound];
        } else {
            content.sound = [UNNotificationSound soundNamed:sound];
        }
    }
    content.categoryIdentifier = [RCTConvert NSString:details[@"click_action"]];
    content.userInfo = details;
    content.badge = [RCTConvert NSNumber:details[@"badge"]];

    NSDate *fireDate = [RCTConvert NSDate:details[@"fire_date"]];

    if(fireDate == nil){
        return [UNNotificationRequest requestWithIdentifier:[RCTConvert NSString:details[@"id"]] content:content trigger:nil];
    }

    NSCalendarUnit interval = [RCTConvert NSCalendarUnit:details[@"repeat_interval"]];
    NSCalendarUnit unitFlags;
    switch (interval) {
        case NSCalendarUnitMinute: {
            unitFlags = NSCalendarUnitSecond;
            break;
        }
        case NSCalendarUnitHour: {
            unitFlags = NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
        }
        case NSCalendarUnitDay: {
            unitFlags = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
        }
        case NSCalendarUnitWeekOfYear: {
            unitFlags = NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
        }
        case NSCalendarUnitMonth:{
            unitFlags = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
        }
        case NSCalendarUnitYear:{
            unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
        }
        default:
            unitFlags = NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            break;
    }
    NSDateComponents *components = [[NSCalendar currentCalendar] components:unitFlags fromDate:fireDate];
    UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:interval != 0];
    return [UNNotificationRequest requestWithIdentifier:[RCTConvert NSString:details[@"id"]] content:content trigger:trigger];
}

@end

@implementation RCTConvert (UILocalNotification)

+ (UILocalNotification *)UILocalNotification:(id)json
{
    NSDictionary<NSString *, id> *details = [self NSDictionary:json];
    UILocalNotification *notification = [UILocalNotification new];
    notification.fireDate = [RCTConvert NSDate:details[@"fire_date"]] ?: [NSDate date];
    if([notification respondsToSelector:@selector(setAlertTitle:)]){
        [notification setAlertTitle:[RCTConvert NSString:details[@"title"]]];
    }
    notification.alertBody = [RCTConvert NSString:details[@"body"]];
    notification.alertAction = [RCTConvert NSString:details[@"alert_action"]];
    notification.soundName = [RCTConvert NSString:details[@"sound"]] ?: UILocalNotificationDefaultSoundName;
    notification.userInfo = details;
    notification.category = [RCTConvert NSString:details[@"click_action"]];
    notification.repeatInterval = [RCTConvert NSCalendarUnit:details[@"repeat_interval"]];
    notification.applicationIconBadgeNumber = [RCTConvert NSInteger:details[@"badge"]];
    return notification;
}

RCT_ENUM_CONVERTER(UIBackgroundFetchResult, (@{
                                               @"UIBackgroundFetchResultNewData": @(UIBackgroundFetchResultNewData),
                                               @"UIBackgroundFetchResultNoData": @(UIBackgroundFetchResultNoData),
                                               @"UIBackgroundFetchResultFailed": @(UIBackgroundFetchResultFailed),
                                               }), UIBackgroundFetchResultNoData, integerValue)

RCT_ENUM_CONVERTER(UNNotificationPresentationOptions, (@{
                                                         @"UNNotificationPresentationOptionAll": @(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound),
                                                         @"UNNotificationPresentationOptionNone": @(UNNotificationPresentationOptionNone)}), UIBackgroundFetchResultNoData, integerValue)

@end

@interface RNFIRMessaging ()
@property (nonatomic, strong) NSMutableDictionary *notificationCallbacks;
@end

@implementation RNFIRMessaging

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents {
    return @[FCMNotificationReceived, FCMTokenRefreshed, FCMDirectChannelConnectionChanged];
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

+ (void)didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo fetchCompletionHandler:(nonnull RCTRemoteNotificationCallback)completionHandler {
    NSMutableDictionary* data = [[NSMutableDictionary alloc] initWithDictionary: userInfo];
    [data setValue:@"remote_notification" forKey:@"_notificationType"];
    [data setValue:@(RCTSharedApplication().applicationState == UIApplicationStateInactive) forKey:@"opened_from_tray"];
    [[NSNotificationCenter defaultCenter] postNotificationName:FCMNotificationReceived object:self userInfo:@{@"data": data, @"completionHandler": completionHandler}];
}

+ (void)didReceiveLocalNotification:(UILocalNotification *)notification {
    NSMutableDictionary* data = [[NSMutableDictionary alloc] initWithDictionary: notification.userInfo];
    [data setValue:@"local_notification" forKey:@"_notificationType"];
    [data setValue:@(RCTSharedApplication().applicationState == UIApplicationStateInactive) forKey:@"opened_from_tray"];
    [[NSNotificationCenter defaultCenter] postNotificationName:FCMNotificationReceived object:self userInfo:@{@"data": data}];
}

+ (void)didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(nonnull RCTNotificationResponseCallback)completionHandler
{
    NSMutableDictionary* data = [[NSMutableDictionary alloc] initWithDictionary: response.notification.request.content.userInfo];
    [data setValue:@"notification_response" forKey:@"_notificationType"];
    [data setValue:@YES forKey:@"opened_from_tray"];
    if (response.actionIdentifier) {
        [data setValue:response.actionIdentifier forKey:@"_actionIdentifier"];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:FCMNotificationReceived object:self userInfo:@{@"data": data, @"completionHandler": completionHandler}];
}

+ (void)willPresentNotification:(UNNotification *)notification withCompletionHandler:(nonnull RCTWillPresentNotificationCallback)completionHandler
{
    NSMutableDictionary* data = [[NSMutableDictionary alloc] initWithDictionary: notification.request.content.userInfo];
    [data setValue:@"will_present_notification" forKey:@"_notificationType"];
    [[NSNotificationCenter defaultCenter] postNotificationName:FCMNotificationReceived object:self userInfo:@{@"data": data, @"completionHandler": completionHandler}];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [super init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNotificationReceived:)
                                                 name:FCMNotificationReceived
                                               object:nil];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(sendDataMessageFailure:)
     name:FIRMessagingSendErrorNotification object:nil];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(sendDataMessageSuccess:)
     name:FIRMessagingSendSuccessNotification object:nil];

    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(connectionStateChanged:)
     name:FIRMessagingConnectionStateChangedNotification object:nil];

    // For iOS 10 data message (sent via FCM)
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FIRMessaging messaging] setDelegate:self];
    });
    return self;
}

RCT_EXPORT_METHOD(enableDirectChannel)
{
    [[FIRMessaging messaging] setShouldEstablishDirectChannel:@YES];
}

RCT_EXPORT_METHOD(isDirectChannelEstablished:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve([[FIRMessaging messaging] isDirectChannelEstablished] ? @YES: @NO);
}

RCT_EXPORT_METHOD(getInitialNotification:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    UILocalNotification *localUserInfo = self.bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (localUserInfo) {
        resolve([[localUserInfo userInfo] copy]);
    } else {
        resolve([self.bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] copy]);
    }
}

RCT_EXPORT_METHOD(getAPNSToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSData * deviceToken = [FIRMessaging messaging].APNSToken;
    const char *data = [deviceToken bytes];
    NSMutableString *token = [NSMutableString string];
    for (NSUInteger i = 0; i < [deviceToken length]; i++) {
        [token appendFormat:@"%02.2hhX", data[i]];
    }
    resolve([token copy]);
}

RCT_EXPORT_METHOD(getFCMToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve([FIRMessaging messaging].FCMToken);
}

RCT_EXPORT_METHOD(deleteInstanceId:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
  [[FIRInstanceID instanceID]deleteIDWithHandler:^(NSError * _Nullable error) {
    
    if (error != nil) {
      reject([NSString stringWithFormat:@"%ld",error.code],error.localizedDescription,nil);
    } else {
      resolve(nil);
    }
  }];
}

- (void)messaging:(nonnull FIRMessaging *)messaging didRefreshRegistrationToken:(nonnull NSString *)fcmToken {
    [self sendEventWithName:FCMTokenRefreshed body:fcmToken];
}

RCT_EXPORT_METHOD(requestPermissions:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (RCTRunningInAppExtension()) {
        resolve(nil);
        return;
    }
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        UIUserNotificationType allNotificationTypes =
        (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
        UIApplication *app = RCTSharedApplication();
        if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
            //iOS 8 or later
            UIUserNotificationSettings *notificationSettings =
            [UIUserNotificationSettings settingsForTypes:(NSUInteger)allNotificationTypes categories:nil];
            [app registerUserNotificationSettings:notificationSettings];
        }
        resolve(nil);
    } else {
        // iOS 10 or later
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
        UNAuthorizationOptions authOptions =
        UNAuthorizationOptionAlert
        | UNAuthorizationOptionSound
        | UNAuthorizationOptionBadge;
        [[UNUserNotificationCenter currentNotificationCenter]
         requestAuthorizationWithOptions:authOptions
         completionHandler:^(BOOL granted, NSError * _Nullable error) {
             if(granted){
                 resolve(nil);
             } else{
                 reject(@"notification_error", @"Failed to grant permission", error);
             }
         }
         ];
#endif
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    });
}

RCT_EXPORT_METHOD(subscribeToTopic: (NSString*) topic)
{
    [[FIRMessaging messaging] subscribeToTopic:topic];
}

RCT_EXPORT_METHOD(unsubscribeFromTopic: (NSString*) topic)
{
    [[FIRMessaging messaging] unsubscribeFromTopic:topic];
}

// Receive data message on iOS 10 devices.
- (void)applicationReceivedRemoteMessage:(FIRMessagingRemoteMessage *)remoteMessage {
    [self sendEventWithName:FCMNotificationReceived body:[remoteMessage appData]];
}

RCT_EXPORT_METHOD(presentLocalNotification:(id)data resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        UNNotificationRequest* request = [RCTConvert UNNotificationRequest:data];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if (!error) {
                resolve(nil);
            }else{
                reject(@"notification_error", @"Failed to present local notificaton", error);
            }
        }];
    }else{
        UILocalNotification* notif = [RCTConvert UILocalNotification:data];
        [RCTSharedApplication() presentLocalNotificationNow:notif];
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(scheduleLocalNotification:(id)data resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        UNNotificationRequest* request = [RCTConvert UNNotificationRequest:data];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if (!error) {
                resolve(nil);
            }else{
                reject(@"notification_error", @"Failed to present local notificaton", error);
            }
        }];
    }else{
        UILocalNotification* notif = [RCTConvert UILocalNotification:data];
        [RCTSharedApplication() scheduleLocalNotification:notif];
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(removeDeliveredNotification:(NSString*) notificationId)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notificationId]];
    }
}

RCT_EXPORT_METHOD(removeAllDeliveredNotifications)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [RCTSharedApplication() setApplicationIconBadgeNumber: 0];
        });
    }
}

RCT_EXPORT_METHOD(cancelAllLocalNotifications)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
    } else {
        [RCTSharedApplication() cancelAllLocalNotifications];
    }
}

RCT_EXPORT_METHOD(cancelLocalNotification:(NSString*) notificationId)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[notificationId]];
    }else {
        for (UILocalNotification *notification in [UIApplication sharedApplication].scheduledLocalNotifications) {
            NSDictionary<NSString *, id> *notificationInfo = notification.userInfo;
            if([notificationId isEqualToString:[notificationInfo valueForKey:@"id"]]){
                [[UIApplication sharedApplication] cancelLocalNotification:notification];
            }
        }
    }
}

RCT_EXPORT_METHOD(getScheduledLocalNotifications:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if([UNUserNotificationCenter currentNotificationCenter] != nil){
        [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
            NSMutableArray* list = [[NSMutableArray alloc] init];
            for(UNNotificationRequest * notif in requests){
                UNNotificationContent *content = notif.content;
                [list addObject:content.userInfo];
            }
            resolve(list);
        }];
    }else{
        NSMutableArray* list = [[NSMutableArray alloc] init];
        for(UILocalNotification * notif in [RCTSharedApplication() scheduledLocalNotifications]){
            [list addObject:notif.userInfo];
        }
        resolve(list);
    }
}

RCT_EXPORT_METHOD(setBadgeNumber: (NSInteger) number)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [RCTSharedApplication() setApplicationIconBadgeNumber:number];
    });
}

RCT_EXPORT_METHOD(getBadgeNumber: (RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(@([RCTSharedApplication() applicationIconBadgeNumber]));
}

RCT_EXPORT_METHOD(send:(NSString*)senderId withPayload:(NSDictionary *)message)
{
    NSMutableDictionary * mMessage = [message mutableCopy];
    NSMutableDictionary * upstreamMessage = [[NSMutableDictionary alloc] init];
    for (NSString* key in mMessage) {
        upstreamMessage[key] = [NSString stringWithFormat:@"%@", [mMessage valueForKey:key]];
    }

    NSDictionary *imMessage = [NSDictionary dictionaryWithDictionary:upstreamMessage];

    int64_t ttl = 3600;
    NSString * receiver = [NSString stringWithFormat:@"%@@gcm.googleapis.com", senderId];

    NSUUID *uuid = [NSUUID UUID];
    NSString * messageID = [uuid UUIDString];

    [[FIRMessaging messaging]sendMessage:imMessage to:receiver withMessageID:messageID timeToLive:ttl];
}

RCT_EXPORT_METHOD(finishRemoteNotification: (NSString *)completionHandlerId fetchResult:(UIBackgroundFetchResult)result){
    RCTRemoteNotificationCallback completionHandler = self.notificationCallbacks[completionHandlerId];
    if (!completionHandler) {
        RCTLogError(@"There is no completion handler with completionHandlerId: %@", completionHandlerId);
        return;
    }
    completionHandler(result);
    [self.notificationCallbacks removeObjectForKey:completionHandlerId];
}

RCT_EXPORT_METHOD(finishWillPresentNotification: (NSString *)completionHandlerId fetchResult:(UNNotificationPresentationOptions)result){
    RCTWillPresentNotificationCallback completionHandler = self.notificationCallbacks[completionHandlerId];
    if (!completionHandler) {
        RCTLogError(@"There is no completion handler with completionHandlerId: %@", completionHandlerId);
        return;
    }
    completionHandler(result);
    [self.notificationCallbacks removeObjectForKey:completionHandlerId];
}

RCT_EXPORT_METHOD(finishNotificationResponse: (NSString *)completionHandlerId){
    RCTNotificationResponseCallback completionHandler = self.notificationCallbacks[completionHandlerId];
    if (!completionHandler) {
        RCTLogError(@"There is no completion handler with completionHandlerId: %@", completionHandlerId);
        return;
    }
    completionHandler();
    [self.notificationCallbacks removeObjectForKey:completionHandlerId];
}

- (void)handleNotificationReceived:(NSNotification *)notification
{
    id completionHandler = notification.userInfo[@"completionHandler"];
    NSMutableDictionary* data = notification.userInfo[@"data"];
    if(completionHandler != nil){
        NSString *completionHandlerId = [[NSUUID UUID] UUIDString];
        if (!self.notificationCallbacks) {
            // Lazy initialization
            self.notificationCallbacks = [NSMutableDictionary dictionary];
        }
        self.notificationCallbacks[completionHandlerId] = completionHandler;
        data[@"_completionHandlerId"] = completionHandlerId;
    }

    [self sendEventWithName:FCMNotificationReceived body:data];

}

- (void)sendDataMessageFailure:(NSNotification *)notification
{
    NSString *messageID = (NSString *)notification.userInfo[@"messageID"];

    NSLog(@"sendDataMessageFailure: %@", messageID);
}

- (void)sendDataMessageSuccess:(NSNotification *)notification
{
    NSString *messageID = (NSString *)notification.userInfo[@"messageID"];

    NSLog(@"sendDataMessageSuccess: %@", messageID);
}

- (void)connectionStateChanged:(NSNotification *)notification
{
    [self sendEventWithName:FCMDirectChannelConnectionChanged body:[FIRMessaging messaging].isDirectChannelEstablished ? @YES: @NO];
    NSLog(@"connectionStateChanged: %@", [FIRMessaging messaging].isDirectChannelEstablished ? @"connected": @"disconnected");
}

@end
