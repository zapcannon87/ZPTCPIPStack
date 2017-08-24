//
//  ZPPacketTunnel.m
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "ZPPacketTunnel.h"
#import "ZPPacketTunnelEx.h"
#import "ZPTCPConnection.h"
#import "ZPTCPConnectionEx.h"

err_t netif_output(struct pbuf *p, BOOL is_ipv4)
{
    void *buf = malloc(sizeof(char) * p->tot_len);
    LWIP_ASSERT("error in pbuf_copy_partial", pbuf_copy_partial(p, buf, p->tot_len, 0) != 0);
    
    NSData *data = [NSData dataWithBytesNoCopy:buf length:p->tot_len];
    NSNumber *ipVersion = [NSNumber numberWithInt:(is_ipv4 ? AF_INET : AF_INET6)];
    
    NSArray *datas = [NSArray arrayWithObject:data];
    NSArray *numbers = [NSArray arrayWithObject:ipVersion];
    
    ZPPacketTunnel.shared.output(datas, numbers);
    
    return ERR_OK;
}

err_t netif_output_ip4(struct netif *netif, struct pbuf *p, const ip4_addr_t *ipaddr)
{
    return netif_output(p, TRUE);
}

err_t netif_output_ip6(struct netif *netif, struct pbuf *p, const ip6_addr_t *ipaddr)
{
    return netif_output(p, FALSE);
}

void
tcp_input_pre(struct pbuf *p, struct netif *inp)
{
    u8_t hdrlen_bytes;
    
    LWIP_UNUSED_ARG(inp);
    
    PERF_START;
    
    TCP_STATS_INC(tcp.recv);
    MIB2_STATS_INC(mib2.tcpinsegs);
    
    struct tcp_hdr * tcphdr = (struct tcp_hdr *)p->payload;
    
#if TCP_INPUT_DEBUG
    tcp_debug_print(tcphdr);
#endif
    
    /* Check that TCP header fits in payload */
    if (p->len < TCP_HLEN) {
        /* drop short packets */
        LWIP_DEBUGF(TCP_INPUT_DEBUG, ("tcp_input: short packet (%"U16_F" bytes) discarded\n", p->tot_len));
        TCP_STATS_INC(tcp.lenerr);
        
        TCP_STATS_INC(tcp.drop);
        MIB2_STATS_INC(mib2.tcpinerrs);
        pbuf_free(p);
        return;
    }
    
    /* Don't even process incoming broadcasts/multicasts. */
    if (ip_addr_isbroadcast(ip_current_dest_addr(), ip_current_netif()) ||
        ip_addr_ismulticast(ip_current_dest_addr())) {
        TCP_STATS_INC(tcp.proterr);
        
        TCP_STATS_INC(tcp.drop);
        MIB2_STATS_INC(mib2.tcpinerrs);
        pbuf_free(p);
        return;
    }
    
#if CHECKSUM_CHECK_TCP
    IF__NETIF_CHECKSUM_ENABLED(inp, NETIF_CHECKSUM_CHECK_TCP) {
        /* Verify TCP checksum. */
        u16_t chksum = ip_chksum_pseudo(p, IP_PROTO_TCP, p->tot_len,
                                        ip_current_src_addr(), ip_current_dest_addr());
        if (chksum != 0) {
            LWIP_DEBUGF(TCP_INPUT_DEBUG, ("tcp_input: packet discarded due to failing checksum 0x%04"X16_F"\n",
                                          chksum));
            tcp_debug_print(tcphdr);
            TCP_STATS_INC(tcp.chkerr);
            
            TCP_STATS_INC(tcp.drop);
            MIB2_STATS_INC(mib2.tcpinerrs);
            pbuf_free(p);
            return;
        }
    }
#endif /* CHECKSUM_CHECK_TCP */
    
    /* sanity-check header length */
    hdrlen_bytes = TCPH_HDRLEN(tcphdr) * 4;
    if ((hdrlen_bytes < TCP_HLEN) || (hdrlen_bytes > p->tot_len)) {
        LWIP_DEBUGF(TCP_INPUT_DEBUG, ("tcp_input: invalid header length (%"U16_F")\n", (u16_t)hdrlen_bytes));
        TCP_STATS_INC(tcp.lenerr);
        
        TCP_STATS_INC(tcp.drop);
        MIB2_STATS_INC(mib2.tcpinerrs);
        pbuf_free(p);
        return;
    }
    
    /* Move the payload pointer in the pbuf so that it points to the
     TCP data instead of the TCP header. */
    u16_t tcphdr_optlen = hdrlen_bytes - TCP_HLEN;
    u8_t* tcphdr_opt2 = NULL;
    u16_t tcphdr_opt1len;
    if (p->len >= hdrlen_bytes) {
        /* all options are in the first pbuf */
        tcphdr_opt1len = tcphdr_optlen;
        pbuf_header(p, -(s16_t)hdrlen_bytes); /* cannot fail */
    } else {
        u16_t opt2len;
        /* TCP header fits into first pbuf, options don't - data is in the next pbuf */
        /* there must be a next pbuf, due to hdrlen_bytes sanity check above */
        LWIP_ASSERT("p->next != NULL", p->next != NULL);
        
        /* advance over the TCP header (cannot fail) */
        pbuf_header(p, -TCP_HLEN);
        
        /* determine how long the first and second parts of the options are */
        tcphdr_opt1len = p->len;
        opt2len = tcphdr_optlen - tcphdr_opt1len;
        
        /* options continue in the next pbuf: set p to zero length and hide the
         options in the next pbuf (adjusting p->tot_len) */
        pbuf_header(p, -(s16_t)tcphdr_opt1len);
        
        /* check that the options fit in the second pbuf */
        if (opt2len > p->next->len) {
            /* drop short packets */
            LWIP_DEBUGF(TCP_INPUT_DEBUG, ("tcp_input: options overflow second pbuf (%"U16_F" bytes)\n", p->next->len));
            TCP_STATS_INC(tcp.lenerr);
            
            TCP_STATS_INC(tcp.drop);
            MIB2_STATS_INC(mib2.tcpinerrs);
            pbuf_free(p);
            return;
        }
        
        /* remember the pointer to the second part of the options */
        tcphdr_opt2 = (u8_t*)p->next->payload;
        
        /* advance p->next to point after the options, and manually
         adjust p->tot_len to keep it consistent with the changed p->next */
        pbuf_header(p->next, -(s16_t)opt2len);
        p->tot_len -= opt2len;
        
        LWIP_ASSERT("p->len == 0", p->len == 0);
        LWIP_ASSERT("p->tot_len == p->next->tot_len", p->tot_len == p->next->tot_len);
    }
    
    /* Convert fields in TCP header to host byte order. */
    tcphdr->src = lwip_ntohs(tcphdr->src);
    tcphdr->dest = lwip_ntohs(tcphdr->dest);
    u32_t seqno = tcphdr->seqno = lwip_ntohl(tcphdr->seqno);
    u32_t ackno = tcphdr->ackno = lwip_ntohl(tcphdr->ackno);
    tcphdr->wnd = lwip_ntohs(tcphdr->wnd);
    
    u8_t flags = TCPH_FLAGS(tcphdr);
    u16_t tcplen = p->tot_len + ((flags & (TCP_FIN | TCP_SYN)) ? 1 : 0);
    
    struct tcp_info tcpInfo = {
        .tcphdr         = tcphdr,
        .tcphdr_optlen  = tcphdr_optlen,
        .tcphdr_opt1len = tcphdr_opt1len,
        .tcphdr_opt2    = tcphdr_opt2,
        .seqno          = seqno,
        .ackno          = ackno,
        .tcplen         = tcplen,
        .flags          = flags
    };
    
    /* Get tcp_pcb identifie */
    int addr_str_len = ip_current_is_v6() ? INET6_ADDRSTRLEN : INET_ADDRSTRLEN;
    char src_addr_chars[addr_str_len];
    char dest_addr_chars[addr_str_len];
    if (ip_current_is_v6()) {
        LWIP_ASSERT("error in ip6 ntop",
                    inet_ntop(AF_INET6, ip6_current_src_addr(), src_addr_chars, addr_str_len) != NULL);
        LWIP_ASSERT("error in ip6 ntop",
                    inet_ntop(AF_INET6, ip6_current_dest_addr(), dest_addr_chars, addr_str_len) != NULL);
    } else {
        LWIP_ASSERT("error in ip4 ntop",
                    inet_ntop(AF_INET, ip4_current_src_addr(), src_addr_chars, addr_str_len) != NULL);
        LWIP_ASSERT("error in ip4 ntop",
                    inet_ntop(AF_INET, ip4_current_dest_addr(), dest_addr_chars, addr_str_len) != NULL);
    }
    NSString *src_addr_str = [NSString stringWithCString:src_addr_chars
                                                encoding:NSASCIIStringEncoding];
    NSString *dest_addr_str = [NSString stringWithCString:dest_addr_chars
                                                 encoding:NSASCIIStringEncoding];
    NSString *identifie = [NSString stringWithFormat:@"%@-%d-%@-%d",
                           src_addr_str, tcphdr->src, dest_addr_str, tcphdr->dest];
    
    ZPTCPConnection *conn = [ZPPacketTunnel.shared connectionForKey:identifie];
    if (conn) {
        [conn tcpInputWith:ip_data
                   tcpInfo:tcpInfo
                      pbuf:p];
    } else {
        conn = [ZPTCPConnection newTCPConnectionWith:ZPPacketTunnel.shared
                                           identifie:identifie
                                              ipData:&ip_data
                                             tcpInfo:&tcpInfo
                                                pbuf:p];
        if (conn) {
            [conn configSrcAddr:src_addr_str
                        srcPort:tcphdr->src
                       destAddr:dest_addr_str
                       destPort:tcphdr->dest];
            [ZPPacketTunnel.shared setConnection:conn forKey:identifie];
        }
        pbuf_free(p);
    }
}

@implementation ZPPacketTunnel

+ (instancetype)shared
{
    static dispatch_once_t once;
    static id shared;
    dispatch_once(&once, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dic = [[NSMutableDictionary alloc] init];
        _dicQueue = dispatch_queue_create("ZPPacketTunnel.dicQueue", NULL);
    }
    return self;
}

- (void)setDelegate:(id<ZPPacketTunnelDelegate> _Nonnull)delegate
      delegateQueue:(dispatch_queue_t _Nullable)queue;
{
    _delegate = delegate;
    if (queue) {
        _delegateQueue = queue;
    } else {
        _delegateQueue = dispatch_queue_create("ZPPacketTunnel.delegateQueue", NULL);
    }
}

-(void)mtu:(UInt16)mtu output:(OutputBlock)output
{
    _netif.mtu = mtu;
    _output = output;
}

-(void)ipv4SettingWithAddress:(NSString *)addr netmask:(NSString *)netmask
{
    struct netif *netif = &_netif;
    
    /* set address */
    ip4_addr_t ip4_addr;
    const char *addr_chars = [addr cStringUsingEncoding:NSASCIIStringEncoding];
    NSAssert(inet_pton(AF_INET, addr_chars, &ip4_addr) != 0 && !ip4_addr_isany(&ip4_addr),
             @"error in ipv4 address");
    ip4_addr_set(ip_2_ip4(&netif->ip_addr), &ip4_addr);
    IP_SET_TYPE_VAL(netif->ip_addr, IPADDR_TYPE_V4);
    
    /* set netmask */
    ip4_addr_t ip4_netmask;
    const char *netmask_chars = [netmask cStringUsingEncoding:NSASCIIStringEncoding];
    NSAssert(inet_pton(AF_INET, netmask_chars, &ip4_netmask) != 0,
             @"error in ipv4 netmask");
    ip4_addr_set(ip_2_ip4(&netif->netmask), &ip4_netmask);
    IP_SET_TYPE_VAL(netif->netmask, IPADDR_TYPE_V4);
    
    /* set gateway */
    ip4_addr_set(ip_2_ip4(&netif->gw), &ip4_addr);
    IP_SET_TYPE_VAL(netif->gw, IPADDR_TYPE_V4);
    
    netif->output = netif_output_ip4;
}

// MARK: - IP

- (err_t)ipPacketInput:(NSData *)data
{
    NSAssert(data.length <= _netif.mtu, @"error in data length or mtu value");
    
    /* copy data bytes to pbuf */
    struct pbuf *p = pbuf_alloc(PBUF_RAW, data.length, PBUF_RAM);
    NSAssert(p != NULL, @"error in pbuf_alloc");
    NSAssert(pbuf_take(p, data.bytes, data.length) == ERR_OK, @"error in pbuf_take");
    
    if (IP_HDR_GET_VERSION(p->payload) == 6) {
        return ip6_input(p, &_netif);
    } else {
        return ip4_input(p, &_netif);
    }
}

// MARK: - Misc

- (void)tcpConnectionEstablished:(ZPTCPConnection *)conn
{
    dispatch_async(_delegateQueue, ^{
        if (_delegate) {
            [_delegate tunnel:self didEstablishNewTCPConnection:conn];
        }
    });
}

- (ZPTCPConnection *)connectionForKey:(NSString *)key
{
    __block ZPTCPConnection *conn = NULL;
    dispatch_sync(_dicQueue, ^{
        conn = [_dic objectForKey:key];
    });
    return conn;
}

- (void)setConnection:(ZPTCPConnection *)conn forKey:(NSString *)key
{
    dispatch_sync(_dicQueue, ^{
        [_dic setObject:conn forKey:key];
    });
}

- (void)removeConnectionForKey:(NSString *)key
{
    dispatch_async(_dicQueue, ^{
        [_dic removeObjectForKey:key];
    });
}

@end
