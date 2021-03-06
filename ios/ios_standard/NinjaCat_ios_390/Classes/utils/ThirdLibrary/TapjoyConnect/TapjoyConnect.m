// Copyright (C) 2011-2012 by Tapjoy Inc.
//
// This file is part of the Tapjoy SDK.
//
// By using the Tapjoy SDK in your software, you agree to the terms of the Tapjoy SDK License Agreement.
//
// The Tapjoy SDK is bound by the Tapjoy SDK License Agreement and can be found here: https://www.tapjoy.com/sdk/license



#import "TapjoyConnect.h"
#import "TJCConfig.h"
#import <CommonCrypto/CommonHMAC.h>
#include <sys/socket.h> // Per msqr
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <mach-o/dyld.h>
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1
#import <AdSupport/AdSupport.h>
#endif
#if TJC_OPENUDID_OPT_IN
#import "TJCOpenUDID.h"
#endif



static TapjoyConnect *sharedInstance_ = nil; //To make TapjoyConnect Singleton

@implementation TapjoyConnect

@synthesize appID = appID_;
@synthesize secretKey = secretKey_;
@synthesize userID = userID_;
@synthesize plugin = plugin_;
@synthesize isInitialConnect = isInitialConnect_;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
@synthesize backgroundTaskID;
#endif

+ (TapjoyConnect*)sharedTapjoyConnect
{
	if(!sharedInstance_)
	{
		sharedInstance_ = [[super alloc] init];
	}
	
	return sharedInstance_;
}


- (NSMutableDictionary*)genericParameters
{
	// Device info.
	UIDevice *device = [UIDevice currentDevice];
	NSString *model = [device model];
	NSString *systemVersion = [device systemVersion];
	
#if !defined (TJC_CONNECT_SDK)
	NSString *device_name = [device platform];
	//NSLog(@"device name: %@", device_name);
#endif
	
	// Locale info.
	NSLocale *locale = [NSLocale currentLocale];
	NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
	NSString *language;
	if ([[NSLocale preferredLanguages] count] > 0)
	{
		language = [[NSLocale preferredLanguages] objectAtIndex:0];
	}
	else
	{
		language = [locale objectForKey:NSLocaleLanguageCode];
	}
	
	// App info.
	NSString *bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
	
	NSString *lad = [self isJailBrokenStr];
	
	// Get seconds since Jan 1st, 1970.
	NSString *timeStamp = [TapjoyConnect getTimeStamp];
	
	// Compute verifier.
	NSString *verifier = [TapjoyConnect TJCSHA256CommonParamsWithTimeStamp:timeStamp string:nil];
	
	if (!appID_)
	{
		NSLog(@"requestTapjoyConnect:secretKey: must be called before any other Tapjoy methods!");
	}
	
	if (!plugin_)
	{
		plugin_ = TJC_PLUGIN_NATIVE;
	}
	
	NSString *multStr = [NSString stringWithFormat:@"%f", currencyMultiplier_];
	
#if !defined (TJC_CONNECT_SDK)
	NSString *connectionType = [TJCNetReachability getReachibilityType];
#endif
	
	NSString *macID = [TapjoyConnect getMACID];
	NSString *sha1macAddress = [TapjoyConnect getSHA1MacAddress];
	
#if TJC_OPENUDID_OPT_IN
	NSString *openUDID = [TJCOpenUDID value];
	NSString *openUDIDSlotCount = [NSString stringWithFormat:@"%d", [TJCOpenUDID getOpenUDIDSlotCount]];
#endif
	
	NSMutableDictionary * genericDict = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
										 macID, TJC_UNIQUE_MAC_ID,
										 sha1macAddress, TJC_UNIQUE_MAC_ID_SHA1,
#if TJC_OPENUDID_OPT_IN
										 openUDID, TJC_OPEN_UDID,
										 openUDIDSlotCount, TJC_OPEN_UDID_COUNT,
#endif
										 model, TJC_DEVICE_TYPE_NAME,
										 systemVersion, TJC_DEVICE_OS_VERSION_NAME,
										 appID_, TJC_APP_ID_NAME,
										 bundleVersion, TJC_APP_VERSION_NAME,
										 TJC_LIBRARY_VERSION_NUMBER, TJC_CONNECT_LIBRARY_VERSION_NAME,
										 countryCode, TJC_DEVICE_COUNTRY_CODE,
										 language, TJC_DEVICE_LANGUAGE,
										 lad, TJC_DEVICE_LAD,
										 timeStamp, TJC_TIMESTAMP,
										 verifier, TJC_VERIFIER,
										 multStr, TJC_URL_PARAM_CURRENCY_MULTIPLIER,
										 plugin_, TJC_PLUGIN,
										 TJC_SDK_TYPE_VALUE, TJC_SDK_TYPE,
										 TJC_PLATFORM_IOS, TJC_PLATFORM,
#if !defined (TJC_CONNECT_SDK)
										 device_name, TJC_DEVICE_NAME,
										 connectionType, TJC_CONNECTION_TYPE_NAME,
#endif
										 nil];
	
	// Only send UDID as a parameter if it's not nil, namely opted-in.
	NSString *uniqueIdentifier = [TapjoyConnect getUniqueIdentifier];
	if (uniqueIdentifier)
	{
		[genericDict setObject:uniqueIdentifier forKey:TJC_UDID];
	}
	
	NSString *advertiserIdentifier = [TapjoyConnect getAdvertisingIdentifier];
	if (advertiserIdentifier)
	{
		[genericDict setObject:advertiserIdentifier forKey:TJC_ID_FOR_ADVERTISING];
	}
	
	NSString *isAdTrackingEnabled = [TapjoyConnect isAdvertisingTrackingEnabled];
	if (isAdTrackingEnabled)
	{
		[genericDict setObject:isAdTrackingEnabled forKey:TJC_AD_TRACKING_ENABLED];
	}
	
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
	// Carrier info.
	CTTelephonyNetworkInfo *netinfo = [[CTTelephonyNetworkInfo alloc] init];
	CTCarrier *carrier = [netinfo subscriberCellularProvider];
	NSString *carrierName = [carrier carrierName];
	
	if (carrierName)
	{
		[genericDict setObject:carrierName forKey:TJC_CARRIER_NAME];
		
		// VOIP check only valid if carrier exists.
		NSString *allowsVOIP = @"no";
		if ([carrier allowsVOIP])
		{
			allowsVOIP = @"yes";
		}
		
		[genericDict setObject:allowsVOIP forKey:TJC_ALLOWS_VOIP];
		
	}
	
	NSString *isoCountryCode = [carrier isoCountryCode];
	
	if (isoCountryCode)
	{
		[genericDict setObject:isoCountryCode forKey:TJC_CARRIER_COUNTRY_CODE];
	}
	
	NSString *mobileCountryCode = [carrier mobileCountryCode];
	
	if (mobileCountryCode)
	{
		[genericDict setObject:mobileCountryCode forKey:TJC_MOBILE_COUNTRY_CODE];
	}
	
	NSString *mobileNetworkCode = [carrier mobileNetworkCode];
	
	if (mobileNetworkCode)
	{
		[genericDict setObject:mobileNetworkCode forKey:TJC_MOBILE_NETWORK_CODE];
	}
	
	[netinfo release];
#endif
	
	return [genericDict autorelease];
}


- (NSString*)createQueryStringFromDict:(NSDictionary*)paramDict
{
	if(!paramDict)
	{
#if !defined (TJC_CONNECT_SDK)
		[TJCLog logWithLevel:LOG_DEBUG format:@"Sending Nil Getting Generic Dictionary Now"];
#endif
		paramDict = [[TapjoyConnect sharedTapjoyConnect] genericParameters];
	}
	
	NSMutableArray *parts = [NSMutableArray array];
	for (id key in [paramDict allKeys])
	{
		id value = [paramDict objectForKey: key];
		NSString *stringValue = value;
		
		// Encode string to a legal URL string.
		if ([value isKindOfClass:[NSNumber class]])
		{
			stringValue = [value stringValue];
		}
		
		NSString *encodedString = [[TapjoyConnect sharedTapjoyConnect] createQueryStringFromString:stringValue];
		
		NSString *part = [NSString stringWithFormat: @"%@=%@", key, encodedString];

		[parts addObject: part];
	}
	return [parts componentsJoinedByString: @"&"];
}


+ (NSString*)createQueryStringFromDict:(NSDictionary*)paramDict
{
	return [[TapjoyConnect sharedTapjoyConnect] createQueryStringFromDict:paramDict];
}


- (NSString*)createQueryStringFromString:(NSString*)string
{
	NSString *encodedString = (NSString*)CFURLCreateStringByAddingPercentEscapes(NULL,
																				 (CFStringRef)string,
																				 NULL,
																				 (CFStringRef)@"!*'();:@&=+$,/?%#[]|",
																				 kCFStringEncodingUTF8);
	
	return [encodedString autorelease];
}


+ (NSString*)createQueryStringFromString:(NSString*)string
{
	return [[TapjoyConnect sharedTapjoyConnect] createQueryStringFromString:string];
}


- (void)connectWithType:(int)connectionType withParams:(NSDictionary*)params
{	
	NSString *URLString = [self getURLStringWithConnectionType:connectionType];
	
	[self initiateConnectionWithConnectionType:connectionType requestString:URLString paramsString:[self createQueryStringFromDict:params]];
}


- (NSString*)getURLStringWithConnectionType:(int)connectionType
{
	NSString *URLString = nil;
	
	switch (connectionType)
	{			
		case TJC_CONNECT_TYPE_SDK_LESS:
		{
			URLString = [NSString stringWithFormat:@"%@%@", TJC_SERVICE_URL, TJC_SDK_LESS_CONNECT_API];	
		}
			break;
			
		case TJC_CONNECT_TYPE_USER_ID:
		{
			URLString = [NSString stringWithFormat:@"%@%@", TJC_SERVICE_URL, TJC_SET_USER_ID_API];
		}
			break;
			
		case TJC_CONNECT_TYPE_ALT_CONNECT:
		{
			URLString = [NSString stringWithFormat:@"%@%@", TJC_SERVICE_URL_ALTERNATE, TJC_CONNECT_API];
		}
			break;
			
        case TJC_CONNECT_TYPE_EVENT_SHUTDOWN:
        {
            URLString = [NSString stringWithFormat:@"%@%@", TJC_SERVICE_URL, TJC_EVENT_TRACKING_API];
        }
			break;
			
		case TJC_CONNECT_TYPE_CONNECT:
		default:
		{
			URLString = [NSString stringWithFormat:@"%@%@", TJC_SERVICE_URL, TJC_CONNECT_API];
		}
			break;
	}
	
	return URLString;
}


- (void)initiateConnectionWithConnectionType:(int)connectionType requestString:(NSString*)requestString paramsString:(NSString *)paramsString
{
	NSURL *myURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@?%@", requestString, paramsString]];
	NSMutableURLRequest *myRequest = [NSMutableURLRequest requestWithURL:myURL
															 cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
														 timeoutInterval:30];
	
	[myURL release];
	
	if (data_)
	{
		[data_ release];
		data_ = nil;
	}
	
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
	dispatch_async(dispatch_get_main_queue(), ^{
#endif
		switch (connectionType)
		{
            case TJC_CONNECT_TYPE_EVENT_SHUTDOWN:
            {
                if (eventTrackingConnection_)
                {
                    [eventTrackingConnection_ release];
                    eventTrackingConnection_ = nil;
                }
                
				NSURL *postURL = [[NSURL alloc] initWithString:requestString];
				NSMutableURLRequest *postRequest = [NSMutableURLRequest requestWithURL:postURL
																		 cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
																	 timeoutInterval:30];
				[postURL release];
				
                [postRequest setHTTPMethod:@"POST"];
				[postRequest setHTTPBody:[paramsString dataUsingEncoding:NSUTF8StringEncoding]];
				
                // Launch the connection
                eventTrackingConnection_ = [[NSURLConnection alloc] initWithRequest:postRequest delegate:self];

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
                // Check if device supports multitasking
                if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)])
                {
                    // Start a background task to kill the connection if it hangs.
                    // Starting a background task will extend the life of the application long enough for us to get the callback.
                    self.backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                        [eventTrackingConnection_ cancel];
                    }];
                }
#endif
            }
                break;
                
			case TJC_CONNECT_TYPE_SDK_LESS:
			{
				if (SDKLessConnection_)
				{
					[SDKLessConnection_ release];
					SDKLessConnection_ = nil;
				}
				SDKLessConnection_ = [[NSURLConnection alloc] initWithRequest:myRequest delegate:self];
			}
				break;
				
			case TJC_CONNECT_TYPE_USER_ID:
			{
				if (userIDConnection_)
				{
					[userIDConnection_ release];
					userIDConnection_ = nil;
				}
				userIDConnection_ = [[NSURLConnection alloc] initWithRequest:myRequest delegate:self];
			}
				break;
				
			case TJC_CONNECT_TYPE_ALT_CONNECT:
			case TJC_CONNECT_TYPE_CONNECT:
			default:
			{
				if (connectConnection_)
				{
					[connectConnection_ release];
					connectConnection_ = nil;
					
				}
				connectConnection_ = [[NSURLConnection alloc] initWithRequest:myRequest delegate:self];
			}
				break;
		}
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
	});
#endif
	
	connectAttempts_++;
}


- (NSCachedURLResponse*)connection:(NSURLConnection*)connection willCacheResponse:(NSCachedURLResponse*)cachedResponse 
{
	// Returning nil will ensure that no cached response will be stored for the connection.
	// This is in case the cache is being used by something else.
	return nil;
}


static const char* jailbreak_apps[] =
{
	"/bin/bash",
	"/Applications/Cydia.app", 
	"/Applications/limera1n.app", 
	"/Applications/greenpois0n.app", 
	"/Applications/blackra1n.app",
	"/Applications/blacksn0w.app",
	"/Applications/redsn0w.app",
	NULL,
};

- (BOOL)isJailBroken
{
#if TARGET_IPHONE_SIMULATOR
	return NO;
#endif
	
	// Check for known jailbreak apps. If we encounter one, the device is jailbroken.
	for (int i = 0; jailbreak_apps[i] != NULL; ++i)
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:jailbreak_apps[i]]])
		{
			//NSLog(@"isjailbroken: %s", jailbreak_apps[i]);
			return YES;
		}		
	}
	
	return NO;
}

- (NSString*)isJailBrokenStr
{
	if ([self isJailBroken])
	{
		return @"42";
	}
	
	return @"0";
}


- (void)initConnectWithAppID:(NSString*)appID withSecretKey:(NSString*)secretKey
{
	appID_ = [appID retain];
	secretKey_ = [secretKey retain];
	connectAttempts_ = 0;
	
	if (connectConnection_)
	{
		[connectConnection_ cancel];
		[connectConnection_ release];
		connectConnection_ = nil;
	}
}


+ (void)deviceNotificationReceived
{
	// Since we're relying on UIApplicationDidBecomeActiveNotification, we need to make sure we don't call connect twice in a row
	// upon initial start-up of the applicaiton.
	if ([[TapjoyConnect sharedTapjoyConnect] isInitialConnect])
	{
		[TapjoyConnect sharedTapjoyConnect].isInitialConnect = NO;
	}
	else
	{
		[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_CONNECT 
												  withParams:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];
	}
	
#if !defined (TJC_CONNECT_SDK)
	// When the app goes into the background, refresh the offers web view to clear out stale offers.
	if ([[[TJCOffersViewHandler sharedTJCOffersViewHandler] offersWebView] isViewVisible] &&
		![[[TJCOffersViewHandler sharedTJCOffersViewHandler] offersWebView] isAlertViewVisible])
	{
		[[[TJCOffersViewHandler sharedTJCOffersViewHandler] offersWebView] refreshWebView];
	}
	
	// iOS5 apparently automatically pauses videos on app resume.
	// If a video is currently playing, ensure that it continues when the application is brought back to the foreground.
	if ([[[TJCVideoManager sharedTJCVideoManager] videoView] videoAdCurrentlyPlaying])
	{
		[[[TJCVideoManager sharedTJCVideoManager] videoView] videoActionFromAppResume];
	}
	else
	{
		// Videos are not supported on iOS versions < 3.2
		NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
		if ([systemVersion floatValue] >= 3.2)
		{
			[[TJCVideoManager sharedTJCVideoManager] initVideoAdsWifiOnly];
		}
	}
	
#if !defined (TJC_GAME_STATE_SDK)
	// Update tap points.
	[TapjoyConnect getTapPoints];
#endif
	
#endif
}

+ (void)exitNotificationReceived
{
    NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithDictionary:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];

    [params setObject:@"2" forKey:TJC_URL_PARAM_EVENT_TYPE];

	NSString *verifier = [TapjoyConnect TJCSHA256CommonParamsWithTimeStamp:nil string:@"2"];
	[params setObject:verifier forKey:TJC_VERIFIER];
	
    // Ping server with user id.
    [[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_EVENT_SHUTDOWN 
                                              withParams:params];
    
    [params release];
}

#if defined (TJC_GAME_STATE_SDK)
+ (void)forceGameStateSave
{
	[[TJCGameState sharedTJCGameState] forceResave];
}
#endif


+ (TapjoyConnect*)requestTapjoyConnect:(NSString*)appID secretKey:(NSString*)secretKey
{
	[[TapjoyConnect sharedTapjoyConnect] initConnectWithAppID:appID withSecretKey:secretKey];
	
	// Default the currency multiplier to 1.
	[[TapjoyConnect sharedTapjoyConnect] setCurrencyMultiplier:1.0f];
	
	if (![[TapjoyConnect sharedTapjoyConnect] plugin])
	{
		// Default user id to the UDID.
		[[TapjoyConnect sharedTapjoyConnect] setPlugin:TJC_PLUGIN_NATIVE];
	}
	
	// This should really only be set to YES here ever.
	[TapjoyConnect sharedTapjoyConnect].isInitialConnect = YES;
	
	[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_CONNECT 
											  withParams:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];
	
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
	[[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(deviceNotificationReceived) 
                                                 name:UIApplicationWillEnterForegroundNotification 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(exitNotificationReceived)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
#else
	[[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(deviceNotificationReceived) 
                                                 name:UIApplicationDidBecomeActiveNotification 
                                               object:nil];	
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(exitNotificationReceived)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];

#endif
	
	// Force a game state save on app pause/exit.
#if defined (TJC_GAME_STATE_SDK)
	// Set the application pausing notification.
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(forceGameStateSave) 
												 name:UIApplicationWillResignActiveNotification
											   object:nil];
	
	// We want to make sure that if the app is set to not run in the background (quit), we also force a save.
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(forceGameStateSave) 
												 name:UIApplicationWillTerminateNotification
											   object:nil];
#endif
	
	// Only the Offers and VG SDKs will need to grab tap points upon init.
#if !defined (TJC_CONNECT_SDK) && !defined (TJC_GAME_STATE_SDK)
	// Update tap points.
	[TapjoyConnect getTapPoints];
#endif
	
#if !defined (TJC_CONNECT_SDK)
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(orientationChanged:)
												 name:UIApplicationDidChangeStatusBarFrameNotification
											   object:nil];

	// Videos are not supported on iOS versions < 3.2
	NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
	if ([systemVersion floatValue] >= 3.2)
	{
		[[TJCVideoManager sharedTJCVideoManager] initVideoAdsWifiOnly];
	}
	else
	{
		NSLog(@"Error: Videos require iOS version 3.2 or higher, initialization ignored");
	}

#endif
	
	return [TapjoyConnect sharedTapjoyConnect];
}


#if !defined (TJC_CONNECT_SDK)
+ (void)orientationChanged:(NSNotification*)notifyObj
{
	//UIInterfaceOrientation orientation = [[notifyObj userInfo] objectForKey:UIApplicationStatusBarOrientationUserInfoKey];
	[TapjoyConnect updateViewsWithOrientation:[UIApplication sharedApplication].statusBarOrientation];
	
	// HACK: Scroll view frame wasn't being updated properly. It seems to be updated some time after this notification is sent...
	[self performSelector:@selector(orientationChangedDelay)
			   withObject:nil 
			   afterDelay:.2f];
}

+ (void)orientationChangedDelay
{
	[TapjoyConnect updateViewsWithOrientation:[UIApplication sharedApplication].statusBarOrientation];
}
#endif


+ (TapjoyConnect*)actionComplete:(NSString*)actionID
{
	// Get the generic params.
 	NSMutableDictionary *paramDict = [[TapjoyConnect sharedTapjoyConnect] genericParameters];
	
	// Overwrite the appID with the actionID. This is how actions are sent.
	[paramDict setObject:[NSString stringWithString:actionID] forKey:TJC_APP_ID_NAME];
	
	[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_CONNECT 
											  withParams:paramDict];
	
	return [TapjoyConnect sharedTapjoyConnect];
}


+ (NSString*)getAppID
{
	return [[TapjoyConnect sharedTapjoyConnect] appID];
}


+ (void)setUserID:(NSString*)theUserID
{
	[[TapjoyConnect sharedTapjoyConnect] setUserID:theUserID];
	
	NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithDictionary:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];
	
	[params setObject:[TapjoyConnect getUserID] forKey:TJC_URL_PARAM_USER_ID];
	
	// Ping server with user id.
	[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_USER_ID 
											  withParams:params];
	
	[params release];
}


+ (NSString*)getUserID
{
	if (![[TapjoyConnect sharedTapjoyConnect] userID])
	{
		NSString *uniqueID = [[TapjoyConnect getUniqueIdentifier] lowercaseString];
		if (uniqueID)
		{
			[[TapjoyConnect sharedTapjoyConnect] setUserID:uniqueID];
		}		
	}
	
	return [[TapjoyConnect sharedTapjoyConnect] userID];
}


+ (NSString*)getSecretKey
{
	return [[TapjoyConnect sharedTapjoyConnect] secretKey];
}


+ (void)setPlugin:(NSString*)thePlugin
{
	[[TapjoyConnect sharedTapjoyConnect] setPlugin:thePlugin];
}


- (void)setCurrencyMultiplier:(float)mult
{
	currencyMultiplier_ = mult;
}


+ (void)setCurrencyMultiplier:(float)mult
{
	[[TapjoyConnect sharedTapjoyConnect] setCurrencyMultiplier:mult];
}


- (float)getCurrencyMultiplier
{
	return currencyMultiplier_;	
}


+ (float)getCurrencyMultiplier
{
	return [[TapjoyConnect sharedTapjoyConnect] getCurrencyMultiplier];
}


+ (NSString*)TJCSHA256CommonParamsWithTimeStamp:(NSString*)timeStamp string:(NSString*)string
{
	NSString *appID = [TapjoyConnect getAppID];
	
	NSString *keyStr = [TapjoyConnect getSecretKey];
	
	NSString *deviceID = [TapjoyConnect getUniqueIdentifier];
	if (!deviceID)
	{
		deviceID = [TapjoyConnect getMACID];
	}
		
	NSMutableString *verifierStr = [[NSMutableString alloc] initWithFormat:@"%@:%@", appID, deviceID];
	
	if (timeStamp)
	{
		[verifierStr appendFormat:@":%@", timeStamp];
	}
	
	[verifierStr appendFormat:@":%@", keyStr];
	
	if (string)
	{
		[verifierStr appendFormat:@":%@", string];
	}
	
	NSString *hashStr = [TapjoyConnect TJCSHA256WithString:verifierStr];    
	
	[verifierStr release];
	
	return hashStr;
}


+ (NSString*)TJCSHA256WithString:(NSString*)dataStr
{
	unsigned char SHAStr[CC_SHA256_DIGEST_LENGTH];
	
	CC_SHA256([dataStr UTF8String],
			  [dataStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
			  SHAStr);
	
	NSData *SHAData = [[NSData alloc] initWithBytes:SHAStr
											 length:sizeof(SHAStr)];
	
	NSString *result = [[SHAData description] stringByReplacingOccurrencesOfString:@" " withString:@""];
	result = [result substringWithRange:NSMakeRange(1, [result length] - 2)];
	
	[SHAData release];
	
	return result;
}


- (void)dealloc 
{
	[appID_ release];
	[secretKey_ release];
	[userID_ release];
	[sharedInstance_ release];
	[data_ release];
	[super dealloc];
}







#pragma mark delegate methods for asynchronous requests

- (void)connection:(NSURLConnection*)myConnection didReceiveResponse:(NSURLResponse*)myResponse
{
	NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse*)myResponse;
	
	responseCode_ = [HTTPResponse statusCode];
	//NSLog(@"Tapjoy Connect reponse:%d", responseCode_);
}


- (void)connection:(NSURLConnection*)myConnection didReceiveData:(NSData*)myData
{
	if (myConnection == connectConnection_)
	{
		if (!data_) 
		{
			data_ = [[NSMutableData alloc] init];
		}
		
		[data_ appendData: myData];
	}
}


- (void)connection:(NSURLConnection*)myConnection didFailWithError:(NSError*)myError
{
	if (myConnection == connectConnection_)
	{
		if (connectAttempts_ >=2)
		{	
			[[NSNotificationCenter defaultCenter] postNotificationName:TJC_CONNECT_FAILED object:nil];
			return;
		}
		
		if (connectAttempts_ < 2)
		{
			[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_CONNECT 
													  withParams:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];
		}
	}
    else if (myConnection == userIDConnection_)
    {
        [userIDConnection_ release];
        userIDConnection_ = nil;
    }
    else if (myConnection == SDKLessConnection_)
    {
        [SDKLessConnection_ release];
        SDKLessConnection_ = nil;
    }
    else if (myConnection == eventTrackingConnection_)
    {
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskID];
        self.backgroundTaskID = UIBackgroundTaskInvalid;
#endif
        [eventTrackingConnection_ release];
        eventTrackingConnection_ = nil;
    }
}


- (void)connectionDidFinishLoading:(NSURLConnection*)myConnection;
{
#if defined(TJC_CONNECT_SDK)
    if (myConnection == connectConnection_)
    {
        if (responseCode_ == 200)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:TJC_CONNECT_SUCCESS object:nil];
        }
        else
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:TJC_CONNECT_FAILED object:nil];
        }
        
        [connectConnection_ release];
        connectConnection_ = nil;
    }
#else
    if (myConnection == connectConnection_)
    {
        if (responseCode_ == 200)
        {
			TJCTBXML *responseXML = [TJCTBXML tbxmlWithXMLData:data_];
			
			if (responseXML && [responseXML rootXMLElement])
			{
				TJCTBXMLElement *connectReturnObj = [TJCTBXML childElementNamed:@"ConnectReturnObject" parentElement:[responseXML rootXMLElement]];
				
				// The package names contains all the URL schemes, comma separated.
				NSString *packageNames = [TJCTBXML textForElement:[TJCTBXML childElementNamed:@"PackageNames" parentElement:connectReturnObj]];
				
				if ([packageNames length] > 0)
				{
					// Remove any possible whitespace.
					NSString *trimmedPackageNames = [packageNames stringByReplacingOccurrencesOfString:@" " withString:@""];
					NSArray *parts = [trimmedPackageNames componentsSeparatedByString:@","];
					NSMutableString *installedApps = [[NSMutableString alloc] init];
					
					for (NSString *URLScheme in parts)
					{
						NSURL *theURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", URLScheme]];
						// Check for existing apps installed on the device and create a comma separated list to send back to the server.
						if ([[UIApplication sharedApplication] canOpenURL:theURL])
						{
							[installedApps appendFormat:@"%@,", URLScheme];
						}
					}
					
					if ([installedApps length] > 0)
					{
						// Remove last comma.
						NSString *trimmedString = [installedApps substringToIndex:[installedApps length] - 1];
						NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithDictionary:[[TapjoyConnect sharedTapjoyConnect] genericParameters]];
						[params setObject:trimmedString forKey:TJC_PACKAGE_NAMES];						
						
						// Get seconds since Jan 1st, 1970.
						NSString *timeStamp = [TapjoyConnect getTimeStamp];
						// Computer special verifier for SDKless API.
						NSString *verifier = [TapjoyConnect TJCSHA256CommonParamsWithTimeStamp:timeStamp string:trimmedString];
						[params setObject:verifier forKey:TJC_VERIFIER];
						
						[[TapjoyConnect sharedTapjoyConnect] connectWithType:TJC_CONNECT_TYPE_SDK_LESS 
																  withParams:params];
						
						[params release];
					}
					
					[installedApps release];
				}
			}
			
			// Only fired for connect, not other APIs.
			[[NSNotificationCenter defaultCenter] postNotificationName:TJC_CONNECT_SUCCESS object:nil];
        }
        else
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:TJC_CONNECT_FAILED object:nil];
        }

        [connectConnection_ release];
        connectConnection_ = nil;
    }
#endif
    else if (myConnection == userIDConnection_)
    {
        [userIDConnection_ release];
        userIDConnection_ = nil;
    }
    else if (myConnection == SDKLessConnection_)
    {
        [SDKLessConnection_ release];
        SDKLessConnection_ = nil;
    }
    else if (myConnection == eventTrackingConnection_)
    {
		NSString *responseString = [[NSString alloc] initWithData:data_ encoding:NSUTF8StringEncoding];
		NSLog(@"Tapjoy Connect event tracking reponse code: %d string: %@", responseCode_, responseString);
		[responseString release];
		
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskID];
        self.backgroundTaskID = UIBackgroundTaskInvalid;
#endif
        [eventTrackingConnection_ release];
        eventTrackingConnection_ = nil;
    }
	
}


+ (NSString*)getMACAddress
{
	int                 mib[6];
	size_t              len;
	char                *buf;
	unsigned char       *ptr;
	struct if_msghdr    *ifm;
	struct sockaddr_dl  *sdl;
	
	mib[0] = CTL_NET;
	mib[1] = AF_ROUTE;
	mib[2] = 0;
	mib[3] = AF_LINK;
	mib[4] = NET_RT_IFLIST;
	
	if ((mib[5] = if_nametoindex("en0")) == 0) 
	{
		NSLog(@"Error: if_nametoindex error\n");
		return NULL;
	}
	
	if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0)
	{
		NSLog(@"Error: sysctl, take 1\n");
		return NULL;
	}
	
	if ((buf = (char *)malloc(len)) == NULL)
	{
		NSLog(@"Could not allocate memory. error!\n");
		return NULL;
	}
	
	if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) 
	{
		NSLog(@"Error: sysctl, take 2");
        free(buf);
		return NULL;
	}
	
	ifm = (struct if_msghdr *)buf;
	sdl = (struct sockaddr_dl *)(ifm + 1);
	ptr = (unsigned char *)LLADDR(sdl);
	NSString *macAddress = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", 
							*ptr, *(ptr+1), *(ptr+2), *(ptr+3), *(ptr+4), *(ptr+5)];
	macAddress = [macAddress lowercaseString];
	free(buf);
	
	return macAddress;
}


+ (NSString*)getMACID
{
	NSString *macID = [[TapjoyConnect getMACAddress] stringByReplacingOccurrencesOfString:@":" withString:@""];
	
	return macID;
}


+ (NSString*)getSHA1MacAddress
{
	NSString *dataStr = [[TapjoyConnect getMACAddress] uppercaseString];
	
	unsigned char SHAStr[CC_SHA1_DIGEST_LENGTH];
	
	CC_SHA1([dataStr UTF8String],
			[dataStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
			SHAStr);
	
	NSData *SHAData = [[NSData alloc] initWithBytes:SHAStr
											 length:sizeof(SHAStr)];
	
	NSString *result = [[SHAData description] stringByReplacingOccurrencesOfString:@" " withString:@""];
	// Chop off '<' and '>'
	result = [result substringWithRange:NSMakeRange(1, [result length] - 2)];
	
	[SHAData release];
	
	return result;
}


+ (NSString*)getUniqueIdentifier
{	
#if (TJC_UDID_OPT_IN)
    if ([[UIDevice currentDevice] respondsToSelector:@selector(uniqueIdentifier)])
    {
        return [[UIDevice currentDevice] uniqueIdentifier];
    }
#endif
    
	return nil;
}


+ (NSString*)getAdvertisingIdentifier
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1
	id adSupport = NSClassFromString(@"ASIdentifierManager");
    if (adSupport != nil)
	{
		return [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
	}
#endif
	
	return nil;
}


+ (NSString*)isAdvertisingTrackingEnabled
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1
	id adSupport = NSClassFromString(@"ASIdentifierManager");
    if (adSupport != nil)
	{
		if ([[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled])
		{
			return @"true";
		}
		else
		{
			return @"false";
		}
	}
#endif
	
	return nil;
}


+ (NSString*)getTimeStamp
{
	NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
	// Get seconds since Jan 1st, 1970.
	NSString *timeStamp = [NSString stringWithFormat:@"%d", (int)timeInterval];
	
	return timeStamp;
}


+ (void)clearCache
{
	NSURLCache *sharedCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:0 diskPath:nil];
	[NSURLCache setSharedURLCache:sharedCache];
	[sharedCache removeAllCachedResponses];
	[sharedCache release];
}

@end