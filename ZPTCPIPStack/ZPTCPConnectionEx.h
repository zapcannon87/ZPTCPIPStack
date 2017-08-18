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

@property (nonatomic, assign) struct zp_tcp_block tcpBlock;

@property (nonatomic, strong) dispatch_source_t timer;

@property (nonatomic, strong) dispatch_queue_t  timerQueue;

+ (instancetype)newTCPConnectionWith:(ZPPacketTunnel *)tunnel
                           identifie:(NSString *)identifie
                              ipData:(struct ip_globals *)ipData
                             tcpInfo:(struct tcp_info *)tcpInfo
                                pbuf:(struct pbuf *)pbuf;

- (void)tcpInputWith:(struct tcp_info)info pbuf:(struct pbuf *)pbuf;

@end
