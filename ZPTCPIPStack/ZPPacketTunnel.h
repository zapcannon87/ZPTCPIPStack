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

- (void)tunnel:(ZPPacketTunnel *_Nonnull)tunnel didEstablishNewTCPConnection:(ZPTCPConnection *_Nonnull)conn;

@end

@interface ZPPacketTunnel : NSObject

@property (nonatomic, strong, readonly, nonnull) dispatch_queue_t delegateQueue;

+ (instancetype _Nonnull)shared;

- (void)setDelegate:(id<ZPPacketTunnelDelegate> _Nonnull)delegate
      delegateQueue:(dispatch_queue_t _Nullable)queue;

- (void)mtu:(UInt16)mtu output:(OutputBlock _Nonnull)output;

- (void)ipv4SettingWithAddress:(NSString *_Nonnull)addr netmask:(NSString *_Nonnull)netmask;

- (SInt8)ipPacketInput:(NSData *_Nonnull)data;

@end
