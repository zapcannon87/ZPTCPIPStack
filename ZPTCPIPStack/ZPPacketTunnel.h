//
//  ZPPacketTunnel.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^OutputBlock)(NSArray<NSData *> *_Nullable packets, NSArray<NSNumber *> *_Nullable protocols);

@class ZPPacketTunnel;
@class ZPTCPConnection;

@protocol ZPPacketTunnelDelegate <NSObject>

/**
 Called when a new tcp connection established.

 @param tunnel ip data tunnel manager
 @param conn new tcp connection
 */
- (void)tunnel:(ZPPacketTunnel *_Nonnull)tunnel didEstablishNewTCPConnection:(ZPTCPConnection *_Nonnull)conn;

@end

@interface ZPPacketTunnel : NSObject

/**
 Queue for the delegate, it should be a serial queue.
 */
@property (nonatomic, strong, readonly, nonnull) dispatch_queue_t delegateQueue;

- (instancetype _Nonnull)init NS_UNAVAILABLE;
+ (instancetype _Nonnull)new NS_UNAVAILABLE;

/**
 Singleton

 @return tunnel instance
 */
+ (instancetype _Nonnull)shared;

/**
 Set delegate and delegate queue, must be called before `ipPacketInput:`.

 @param delegate can not be NULL
 @param queue can be NULL
 */
- (void)setDelegate:(id<ZPPacketTunnelDelegate> _Nonnull)delegate delegateQueue:(dispatch_queue_t _Nullable)queue;

/**
 Set MTU and tunnel ip data output block, must be called before `ipPacketInput:`.

 @param mtu not support TCP win scale, so max number is uint16_max
 @param output ip data output block
 */
- (void)mtu:(UInt16)mtu output:(OutputBlock _Nonnull)output;

/**
 Set tunnel ipv4 address and subnetmask, must be called before `ipPacketInput:`.

 @param addr ipv4 address
 @param netmask subnetmask
 */
- (void)ipv4SettingWithAddress:(NSString *_Nonnull)addr netmask:(NSString *_Nonnull)netmask;

/**
 IP packet input, accept both ipv4 and ipv6 data.

 @param data ip data
 @return 0 means OK
 */
- (SInt8)ipPacketInput:(NSData *_Nonnull)data;

@end
