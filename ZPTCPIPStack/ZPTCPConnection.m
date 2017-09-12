//
//  ZPTCPConnection.m
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "ZPTCPConnection.h"
#import "ZPTCPConnectionEx.h"
#import "ZPPacketTunnel.h"
#import "ZPPacketTunnelEx.h"

static void *IsOnTimerQueueKey = &IsOnTimerQueueKey; /* key to identify the queue */

err_t zp_tcp_sent(void *arg, struct tcp_pcb *tpcb, u16_t len)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    LWIP_ASSERT("Must did set delegateQueue before sent data", conn.delegateQueue);
    dispatch_async(conn.delegateQueue, ^{
        if (conn.delegate) {
            [conn.delegate connection:conn didWriteData:len sendBuf:(tpcb->snd_buf == TCP_SND_BUF)];
        }
    });
    return ERR_OK;
}

err_t zp_tcp_recv(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    if (conn.block->close_after_writing) {
        /* connection has closed, no longer recv data */
        return ERR_INPROGRESS;
    }
    if (p == NULL) {
        /* got FIN */
        if (conn.delegateQueue) {
            dispatch_async(conn.delegateQueue, ^{
                if (conn.delegate
                    && [conn.delegate respondsToSelector:@selector(connectionDidCloseReadStream:)])
                {
                    [conn.delegate connectionDidCloseReadStream:conn];
                }
            });
        }
        return ERR_OK;
    }
    if (conn.canReadData) {
        conn.canReadData = FALSE;
        void *buf = malloc(sizeof(char) * p->tot_len);
        LWIP_ASSERT("error in pbuf_copy_partial",
                    pbuf_copy_partial(p, buf, p->tot_len, 0) != 0);
        NSData *data = [NSData dataWithBytesNoCopy:buf length:p->tot_len];
        LWIP_ASSERT("Must did set delegateQueue before start read data", conn.delegateQueue);
        dispatch_async(conn.delegateQueue, ^{
            if (conn.delegate) {
                [conn.delegate connection:conn didReadData:data];
            }
        });
        pbuf_free(p);
        tcp_recved(tpcb, p->tot_len, conn.block);
        return ERR_OK;
    } else {
        return ERR_INPROGRESS;
    }
}

err_t zp_tcp_connected(void *arg, struct tcp_pcb *tpcb, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    [conn.tunnel tcpConnectionEstablished:conn];
    return ERR_OK;
}

err_t zp_tcp_poll(void *arg, struct tcp_pcb *tpcb)
{
    return ERR_OK;
}

void zp_tcp_err(void *arg, err_t err)
{
    ZPTCPConnection *conn = (__bridge ZPTCPConnection *)(arg);
    LWIP_ASSERT("Must be dispatched on timer queue",
                dispatch_get_specific(IsOnTimerQueueKey) == (__bridge void *)(conn.timerQueue));
    NSString *errorDomain = NULL;
    if (err == ERR_ABRT) {
        /* Connection was aborted by local. */
        errorDomain = @"Connection was aborted by local.";
    } else if (err == ERR_RST) {
        /* Connection was reset by remote. */
        errorDomain = @"Connection was reset by remote.";
    } else if (err == ERR_CLSD) {
        /* Connection was successfully closed by remote. */
        errorDomain = @"Connection was successfully closed by remote.";
    } else {
        errorDomain = @"Unknown error.";
    }
    NSError *error = [NSError errorWithDomain:errorDomain code:err userInfo:NULL];
    if (conn.delegateQueue) {
        dispatch_async(conn.delegateQueue, ^{
            if (conn.delegate) {
                [conn.delegate connection:conn didDisconnectWithError:error];
            }
        });
    }
}


@implementation ZPTCPConnection

+ (instancetype)newTCPConnectionWith:(ZPPacketTunnel *)tunnel
                           identifie:(NSString *)identifie
                              ipData:(struct ip_globals *)ipData
                             tcpInfo:(struct tcp_info *)tcpInfo
                                pbuf:(struct pbuf *)pbuf
{
    return [[self alloc] initWithTunnel:tunnel
                              identifie:identifie
                                 ipData:ipData
                                tcpInfo:tcpInfo
                                   pbuf:pbuf];
}

- (instancetype)initWithTunnel:(ZPPacketTunnel *)tunnel
                     identifie:(NSString *)identifie
                        ipData:(struct ip_globals *)ipData
                       tcpInfo:(struct tcp_info *)tcpInfo
                          pbuf:(struct pbuf *)pbuf
{
    self = [super init];
    if (self) {
        _tunnel = tunnel;
        _identifie = identifie;
        _block = &tcp_block;
        _block->ip_data = *ipData;
        _block->tcpInfo = *tcpInfo;
        _block->tcp_ticks = 0;
        _block->tcp_timer = 0;
        _block->close_after_writing = 0;
        
        _canReadData = FALSE;
        
        if (_block->tcpInfo.flags & TCP_RST) {
            /* An incoming RST should be ignored. Return. */
            return NULL;
        }
        
        /* In the LISTEN state, we check for incoming SYN segments,
         creates a new PCB, and responds with a SYN|ACK. */
        if (_block->tcpInfo.flags & TCP_ACK) {
            /* For incoming segments with the ACK flag set, respond with a
             RST. */
            LWIP_DEBUGF(TCP_RST_DEBUG, ("tcp_listen_input: ACK in LISTEN, sending reset\n"));
            tcp_rst(_block->tcpInfo.ackno, _block->tcpInfo.seqno + _block->tcpInfo.tcplen,
                    (&_block->ip_data.current_iphdr_dest), (&_block->ip_data.current_iphdr_src),
                    _block->tcpInfo.tcphdr->dest, _block->tcpInfo.tcphdr->src,
                    _block);
            return NULL;
            
        } else if (_block->tcpInfo.flags & TCP_SYN) {
            LWIP_DEBUGF(TCP_DEBUG, ("TCP connection request %"U16_F" -> %"U16_F".\n", _block->tcpInfo.tcphdr->src, _block->tcpInfo.tcphdr->dest));
            struct tcp_pcb *npcb = tcp_alloc(TCP_PRIO_NORMAL);
            /* If a new PCB could not be created (probably due to lack of memory),
             we don't do anything, but rely on the sender will retransmit the
             SYN at a time when we have more memory available. */
            if (npcb == NULL) {
                LWIP_DEBUGF(TCP_DEBUG, ("tcp_listen_input: could not allocate PCB\n"));
                TCP_STATS_INC(tcp.memerr);
                return NULL;
            }
            _block->pcb = npcb;
            /* Set up the new PCB. */
            ip_addr_copy(npcb->local_ip, _block->ip_data.current_iphdr_dest);
            ip_addr_copy(npcb->remote_ip, _block->ip_data.current_iphdr_src);
            npcb->local_port = _block->tcpInfo.tcphdr->dest;
            npcb->remote_port = _block->tcpInfo.tcphdr->src;
            npcb->state = SYN_RCVD;
            npcb->rcv_nxt = _block->tcpInfo.seqno + 1;
            npcb->rcv_ann_right_edge = npcb->rcv_nxt;
            u32_t iss = tcp_next_iss(npcb, _block);
            npcb->snd_wl2 = iss;
            npcb->snd_nxt = iss;
            npcb->lastack = iss;
            npcb->snd_lbb = iss;
            npcb->snd_wl1 = _block->tcpInfo.seqno - 1;/* initialise to seqno-1 to force window update */
            npcb->callback_arg = (__bridge void *)(self);
#if LWIP_CALLBACK_API || TCP_LISTEN_BACKLOG
            npcb->listener = NULL;
#endif /* LWIP_CALLBACK_API || TCP_LISTEN_BACKLOG */
            /* inherit socket options */
            npcb->so_options = SOF_KEEPALIVE;
            
            /* lwIP's `NETCONN_TCP_POLL_INTERVAL` is set to 2,
             so we stay the same, let pcb poll once per second */
            npcb->polltmr = 0;
            npcb->pollinterval = 2;
            
            /* set callback func */
            npcb->sent      = zp_tcp_sent;
            npcb->recv      = zp_tcp_recv;
            npcb->connected = zp_tcp_connected;
            npcb->poll      = zp_tcp_poll;
            npcb->errf      = zp_tcp_err;
            
            /* Parse any options in the SYN. */
            tcp_parseopt(npcb, _block);
            npcb->snd_wnd = _block->tcpInfo.tcphdr->wnd;
            npcb->snd_wnd_max = npcb->snd_wnd;
            
#if TCP_CALCULATE_EFF_SEND_MSS
            npcb->mss = tcp_eff_send_mss(npcb->mss, &npcb->local_ip, &npcb->remote_ip, _block);
#endif /* TCP_CALCULATE_EFF_SEND_MSS */
            
            MIB2_STATS_INC(mib2.tcppassiveopens);
            
            /* Send a SYN|ACK together with the MSS option. */
            err_t rc = tcp_enqueue_flags(npcb, TCP_SYN | TCP_ACK);
            if (rc != ERR_OK) {
                tcp_abandon(npcb, 0, _block);
                return NULL;
            }
            tcp_output(npcb, _block);
            
            /* set timer queue */
            _timerQueue = dispatch_queue_create("ZPTCPConnection.timerQueue", NULL);
            dispatch_queue_set_specific(_timerQueue, IsOnTimerQueueKey, (__bridge void *)(_timerQueue), NULL);
            
            /* set timer */
            _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _timerQueue);
            /* lwIP's doc suggest run the timer checkout 4 times per second */
            int64_t interval = NSEC_PER_SEC * 0.25;
            dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, interval);
            dispatch_source_set_timer(_timer, start, interval, interval);
            dispatch_source_set_event_handler(_timer, ^{
                struct tcp_pcb *pcb = _block->pcb;
                if (pcb == NULL) {
                    dispatch_source_cancel(_timer);
                    [_tunnel removeConnectionForKey:_identifie];
                } else {
                    tcp_tmr(_block);
                }
            });
            dispatch_resume(_timer);
        } else {
            return NULL;
        }
    }
    return self;
}

- (void)configSrcAddr:(NSString *)srcAddr
              srcPort:(UInt16)srcPort
             destAddr:(NSString *)destAddr
             destPort:(UInt16)destPort
{
    _srcAddr = srcAddr;
    _srcPort = srcPort;
    _destAddr = destAddr;
    _destPort = destPort;
}

- (void)tcpInputWith:(struct ip_globals)ipdata
             tcpInfo:(struct tcp_info)info
                pbuf:(struct pbuf *)pbuf
{
    dispatch_async(_timerQueue, ^{
        _block->ip_data = ipdata;
        _block->tcpInfo = info;
        tcp_input(pbuf, _block);
    });
}

// MARK: - API

- (BOOL)syncSetDelegate:(id<ZPTCPConnectionDelegate>)delegate delegateQueue:(dispatch_queue_t)queue
{
    NSAssert(dispatch_get_specific(IsOnTimerQueueKey) != (__bridge void *)(_timerQueue),
             @"Must not be dispatched on timer queue");
    __block BOOL pcb_is_valid;
    dispatch_sync(_timerQueue, ^{
        if (_block->pcb) {
            _delegate = delegate;
            if (queue) {
                _delegateQueue = queue;
            } else {
                _delegateQueue = dispatch_queue_create("ZPTCPConnection.delegateQueue", NULL);
            }
            pcb_is_valid = TRUE;
        } else {
            pcb_is_valid = FALSE;
        }
    });
    return pcb_is_valid;
}

- (void)asyncSetDelegate:(id<ZPTCPConnectionDelegate>)delegate delegateQueue:(dispatch_queue_t)queue
{
    dispatch_async(_timerQueue, ^{
        _delegate = delegate;
        if (queue) {
            _delegateQueue = queue;
        } else {
            _delegateQueue = dispatch_queue_create("ZPTCPConnection.delegateQueue", NULL);
        }
    });
}

- (void)write:(NSData *)data
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL || _block->close_after_writing) {
            return;
        }
        err_t err = tcp_write(pcb, data.bytes, data.length, TCP_WRITE_FLAG_COPY);
        if (err == ERR_OK) {
            tcp_output(pcb, _block);
        } else {
            NSString *errDomain;
            if (err == ERR_CONN) {
                errDomain = @"Connection is in invalid state for data transmission.";
            } else if (err == ERR_MEM) {
                errDomain = @"Fail on too much data or there is not enough send buf space for data.";
            } else {
                errDomain = @"Unknown error.";
            }
            NSError *error = [NSError errorWithDomain:errDomain code:err userInfo:NULL];
            dispatch_async(_delegateQueue, ^{
                if (self.delegate) {
                    [self.delegate connection:self didCheckWriteDataWithError:error];
                }
            });
        }
    });
}

- (void)readData
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL) {
            return;
        }
        _canReadData = TRUE;
    });
}

- (void)close
{
    dispatch_async(_timerQueue, ^{
        struct tcp_pcb *pcb = _block->pcb;
        if (pcb == NULL) {
            return;
        }
        tcp_close(pcb, _block);
    });
}

- (void)closeAfterWriting
{
    dispatch_async(_timerQueue, ^{
        _block->close_after_writing = 1;
    });
}

@end
