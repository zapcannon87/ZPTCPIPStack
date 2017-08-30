//
//  ZPPacketTunnelEx.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "lwIP.h"

@class ZPTCPConnection;

@interface ZPPacketTunnel ()

/**
 must be set before call `ipPacketInput:`
 */
@property (nonatomic, weak) id<ZPPacketTunnelDelegate> delegate;

/**
 ip data out put block
 */
@property (nonatomic, copy) OutputBlock output;

/**
 a container for all active TCP connection
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *, ZPTCPConnection *> *dic;

/**
 serial queue for TCP connection dic's actions: set, get and remove. for thread safe
 */
@property (nonatomic, strong) dispatch_queue_t dicQueue;

/**
 lwIP's network interface
 */
@property (nonatomic, assign) struct netif netif;

/**
 Called when a new tcp connection established by TCP connection

 @param conn new tcp connection
 */
- (void)tcpConnectionEstablished:(ZPTCPConnection *)conn;

/**
 Asynchronously. remove tcp connection from dic by connnection
 
 @param key tcp connection's identifie
 */
- (void)removeConnectionForKey:(NSString *)key;

/**
 Synchronously. get a active tcp connection by tunnel

 @param key tcp connection's identifie
 @return a active tcp connection
 */
- (ZPTCPConnection *)connectionForKey:(NSString *)key;

/**
 Synchronously. set a active tcp connection to dic by tunnel

 @param conn a new active tcp connection
 @param key tcp connection's identifie
 */
- (void)setConnection:(ZPTCPConnection *)conn forKey:(NSString *)key;

@end
