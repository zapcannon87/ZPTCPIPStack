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

/**
 recommend set it use sync func, because that way can known whether tcp_pcb has already been aborted
 */
@property (nonatomic, weak) id<ZPTCPConnectionDelegate> delegate;

/**
 format: "\(source address)-\(source port)-\(destination address)-\(destination port)"
 */
@property (nonatomic, strong) NSString *identifie;

/**
 tunnel instance
 */
@property (nonatomic, weak) ZPPacketTunnel *tunnel;

/**
 tcp block pointer for tcp block instance, convenience for c func
 */
@property (nonatomic, assign) struct zp_tcp_block *block;

/**
 timer source mainly to call tcp_tmr() func at 0.25s interval
 */
@property (nonatomic, strong) dispatch_source_t timer;

/**
 serial queue for timer source event and all API func
 */
@property (nonatomic, strong) dispatch_queue_t  timerQueue;

/**
 use this flag to determine whether receive data from tcp_pcb's receive buffer
 */
@property (nonatomic, assign) BOOL canReadData;

/**
 new tcp connection, this func not manage pbuf's memory
 */
+ (instancetype)newTCPConnectionWith:(ZPPacketTunnel *)tunnel
                           identifie:(NSString *)identifie
                              ipData:(struct ip_globals *)ipData
                             tcpInfo:(struct tcp_info *)tcpInfo
                                pbuf:(struct pbuf *)pbuf;

/**
 set tcp connection's source address and port, destination address and port
 */
- (void)configSrcAddr:(NSString *)srcAddr
              srcPort:(UInt16)srcPort
             destAddr:(NSString *)destAddr
             destPort:(UInt16)destPort;

/**
 called by active tcp connection, this func will manage pbuf's memory
 */
- (void)tcpInputWith:(struct ip_globals)ipdata
             tcpInfo:(struct tcp_info)info
                pbuf:(struct pbuf *)pbuf;

@end
