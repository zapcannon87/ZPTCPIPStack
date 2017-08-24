//
//  ZPTCPConnectionEx.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "lwIP.h"

@class ZPPacketTunnel;

@interface ZPTCPConnection () {
    
    struct zp_tcp_block tcp_block; /* tcp block instance */
    
}

@property (nonatomic, weak) id<ZPTCPConnectionDelegate> delegate;

@property (nonatomic, strong) NSString *identifie;

@property (nonatomic, weak) ZPPacketTunnel *tunnel;

@property (nonatomic, assign) struct zp_tcp_block *block;

@property (nonatomic, strong) dispatch_source_t timer;

@property (nonatomic, strong) dispatch_queue_t  timerQueue;

@property (nonatomic, assign) BOOL canReadData;

+ (instancetype)newTCPConnectionWith:(ZPPacketTunnel *)tunnel
                           identifie:(NSString *)identifie
                              ipData:(struct ip_globals *)ipData
                             tcpInfo:(struct tcp_info *)tcpInfo
                                pbuf:(struct pbuf *)pbuf;

- (void)configSrcAddr:(NSString *)srcAddr
              srcPort:(UInt16)srcPort
             destAddr:(NSString *)destAddr
             destPort:(UInt16)destPort;

- (void)tcpInputWith:(struct ip_globals)ipdata
             tcpInfo:(struct tcp_info)info
                pbuf:(struct pbuf *)pbuf;

@end
