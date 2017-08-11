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

@property (nonatomic, weak) id<ZPPacketTunnelDelegate> delegate;

@property (nonatomic, copy) OutputBlock output;

@property (nonatomic, strong) NSMutableDictionary<NSString *, ZPTCPConnection *> *dic;

@property (nonatomic, strong) dispatch_queue_t dicQueue;

@property (nonatomic, assign) struct netif netif;

@end
