//
//  ZPTCPConnectionEx.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "lwIP.h"

@class ZPPacketTunnel;

@interface ZPTCPConnection ()

@property (nonatomic, strong) NSString *identifie;

@property (nonatomic, weak) ZPPacketTunnel *tunnel;

@property (nonatomic, assign) struct tcp_info tcpInfo;

@property (nonatomic, strong) dispatch_source_t timer;

@property (nonatomic, strong) dispatch_queue_t  timerQueue;

@end
