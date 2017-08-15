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
    if (pbuf_copy_partial(p, buf, p->tot_len, 0) == 0) {
        free(buf);
        return ERR_BUF;
    }
    
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
    
    struct tcp_info tcpinfo = {
        .ip_data        = ip_data,
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
        LWIP_ASSERT("error in ntop", inet_ntop(AF_INET6, ip6_current_src_addr(),
                                               src_addr_chars, addr_str_len) != NULL);
        LWIP_ASSERT("error in ntop", inet_ntop(AF_INET6, ip6_current_dest_addr(),
                                               dest_addr_chars, addr_str_len) != NULL);
    } else {
        LWIP_ASSERT("error in ntop", inet_ntop(AF_INET, ip4_current_src_addr(),
                                               src_addr_chars, addr_str_len) != NULL);
        LWIP_ASSERT("error in ntop", inet_ntop(AF_INET, ip4_current_dest_addr(),
                                               dest_addr_chars, addr_str_len) != NULL);
    }
    NSString *src_addr_str = [NSString stringWithCString:src_addr_chars
                                                encoding:NSASCIIStringEncoding];
    NSString *dest_addr_str = [NSString stringWithCString:dest_addr_chars
                                                 encoding:NSASCIIStringEncoding];
    NSString *identifie = [NSString stringWithFormat:@"%@-%d-%@-%d",
                           src_addr_str, tcphdr->src, dest_addr_str, tcphdr->dest];
    
    ZPTCPConnection *conn = [ZPPacketTunnel.shared connectionForKey:identifie];
    if (conn) {
        
    } else {
        
        if (conn) {
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

-(void)delegate:(id<ZPPacketTunnelDelegate>)delegate delegateQueue:(dispatch_queue_t)queue
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
    NSAssert(inet_pton(AF_INET, addr_chars, &ip4_addr) != 0 &&
             !ip4_addr_isany(&ip4_addr),
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
    if (p == NULL) {
        return ERR_BUF;
    }
    err_t err = pbuf_take(p, data.bytes, data.length);
    if (err != ERR_OK) {
        return err;
    }
    
    if (IP_HDR_GET_VERSION(p->payload) == 6) {
        return ip6_input(p, &_netif);
    } else {
        return ip4_input(p, &_netif);
    }
}

- (err_t)ip4_input:(struct pbuf *)p
{
    struct netif *netif = &(_netif);
    
    /* identify the IP header */
    struct ip_hdr *iphdr = (struct ip_hdr *)p->payload;
    if (IPH_V(iphdr) != 4) {
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* obtain IP header length in number of 32-bit words */
    u16_t iphdr_hlen = IPH_HL(iphdr);
    /* calculate IP header length in bytes */
    iphdr_hlen *= 4;
    /* obtain ip length in bytes */
    u16_t iphdr_len = lwip_ntohs(IPH_LEN(iphdr));
    
    /* Trim pbuf. This is especially required for packets < 60 bytes. */
    if (iphdr_len < p->tot_len) {
        pbuf_realloc(p, iphdr_len);
    }
    
    /* header length exceeds first pbuf length, or ip length exceeds total pbuf length? */
    if (iphdr_hlen > p->len ||
        iphdr_len > p->tot_len ||
        iphdr_hlen < IP_HLEN) {
        /* free (drop) packet pbufs */
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* verify checksum */
#if CHECKSUM_CHECK_IP
    if (inet_chksum(iphdr, iphdr_hlen) != 0) {
        pbuf_free(p);
        return ERR_OK;
    }
#endif
    
    struct ip_globals ipdata;
    /* copy IP addresses to aligned ip_addr_t */
    ip_addr_copy_from_ip4(ipdata.current_iphdr_src, iphdr->src);
    ip_addr_copy_from_ip4(ipdata.current_iphdr_dest, iphdr->dest);
    
    /* broadcast or multicast packet source address? Compliant with RFC 1122: 3.2.1.3 */
    if (ip4_addr_isbroadcast(&iphdr->src, netif) ||
        ip4_addr_ismulticast(&iphdr->src)) {
        /* free (drop) packet pbufs */
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* packet consists of multiple fragments? */
    if ((IPH_OFFSET(iphdr) & PP_HTONS(IP_OFFMASK | IP_MF)) != 0) {
#if IP_REASSEMBLY /* packet fragment reassembly code present? */
        /* reassemble the packet*/
        p = ip4_reass(p);
        /* packet not fully reassembled yet? */
        if (p == NULL) {
            return ERR_OK;
        }
        iphdr = (struct ip_hdr *)p->payload;
#else /* IP_REASSEMBLY == 0, no packet fragment reassembly code present */
        pbuf_free(p);
        return ERR_OK;
#endif /* IP_REASSEMBLY */
    }
    
#if IP_OPTIONS_ALLOWED == 0 /* no support for IP options in the IP header? */
    if (iphdr_hlen > IP_HLEN) {
        pbuf_free(p);
        return ERR_OK;
    }
#endif /* IP_OPTIONS_ALLOWED == 0 */
    
    ipdata.current_netif = netif;
    ipdata.current_input_netif = netif;
    ipdata.current_ip4_header = iphdr;
    ipdata.current_ip_header_tot_len = IPH_HL(iphdr) * 4;
    
    pbuf_header(p, -(s16_t)iphdr_hlen); /* Move to payload, no check necessary. */
    
    switch (IPH_PROTO(iphdr)) {
        case IP_PROTO_TCP:
            [self tcp_input:p ip_data:&ipdata is_ipv4:true];
            break;
        default:
            pbuf_free(p);
    }
    
    return ERR_OK;
}

- (err_t)ip6_input:(struct pbuf *)p
{
    struct netif *netif = &_netif;
    
    /* identify the IP header */
    struct ip6_hdr *ip6hdr = (struct ip6_hdr *)p->payload;
    if (IP6H_V(ip6hdr) != 6) {
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* header length exceeds first pbuf length, or ip length exceeds total pbuf length? */
    if (IP6_HLEN > p->len ||
        IP6H_PLEN(ip6hdr) + IP6_HLEN > p->tot_len) {
        /* free (drop) packet pbufs */
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* Trim pbuf. This should have been done at the netif layer,
     * but we'll do it anyway just to be sure that its done. */
    pbuf_realloc(p, IP6_HLEN + IP6H_PLEN(ip6hdr));
    
    /* copy IP addresses to aligned ip6_addr_t */
    struct ip_globals ipdata;
    ip_addr_copy_from_ip6(ipdata.current_iphdr_src, ip6hdr->src);
    ip_addr_copy_from_ip6(ipdata.current_iphdr_dest, ip6hdr->dest);
    
    int inet_addr_str_len = INET6_ADDRSTRLEN;
    int ip_v = AF_INET6;
    char src_addr_chars[inet_addr_str_len];
    char dest_addr_chars[inet_addr_str_len];
    inet_ntop(ip_v, &ipdata.current_iphdr_src, src_addr_chars, inet_addr_str_len);
    inet_ntop(ip_v, &ipdata.current_iphdr_dest, dest_addr_chars, inet_addr_str_len);
    NSString *src_addr_str = [NSString stringWithCString:src_addr_chars
                                                encoding:NSASCIIStringEncoding];
    NSString *dest_addr_str = [NSString stringWithCString:dest_addr_chars
                                                 encoding:NSASCIIStringEncoding];
    NSLog(@"%@  %@", src_addr_str, dest_addr_str);
    
    /* Don't accept virtual IPv4 mapped IPv6 addresses.
     * Don't accept multicast source addresses. */
    if (ip6_addr_isipv4mappedipv6(ip_2_ip6(&ipdata.current_iphdr_dest)) ||
        ip6_addr_isipv4mappedipv6(ip_2_ip6(&ipdata.current_iphdr_src)) ||
        ip6_addr_ismulticast(ip_2_ip6(&ipdata.current_iphdr_src))) {
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* current header pointer. */
    ipdata.current_ip6_header = ip6hdr;
    /* In netif, used in case we need to send ICMPv6 packets back. */
    ipdata.current_netif = netif;
    ipdata.current_input_netif = netif;
    
    /* "::" packet source address? (used in duplicate address detection) */
    if (ip6_addr_isany(ip_2_ip6(&ipdata.current_iphdr_src)) &&
        !ip6_addr_issolicitednode(ip_2_ip6(&ipdata.current_iphdr_dest))) {
        /* packet source is not valid */
        /* free (drop) packet pbufs */
        pbuf_free(p);
        return ERR_OK;
    }
    
    /* Save next header type. */
    u8_t nexth = IP6H_NEXTH(ip6hdr);
    
    /* Init header length. */
    u16_t hlen = ipdata.current_ip_header_tot_len = IP6_HLEN;
    
    /* Move to payload. */
    pbuf_header(p, -IP6_HLEN);
    
    /* Process known option extension headers, if present. */
    u8_t break_while_flag = 0; /* use it to break while loop */
    while (nexth != IP6_NEXTH_NONE && break_while_flag == 0)
    {
        switch (nexth)
        {
            case IP6_NEXTH_HOPBYHOP:
                
                /* Get next header type. */
                nexth = *((u8_t *)p->payload);
                
                /* Get the header length. */
                hlen = 8 * (1 + *((u8_t *)p->payload + 1));
                ipdata.current_ip_header_tot_len += hlen;
                
                /* Skip over this header. */
                if (hlen > p->len) {
                    /* free (drop) packet pbufs */
                    pbuf_free(p);
                    return ERR_OK;
                }
                
                pbuf_header(p, -(s16_t)hlen);
                break;
                
            case IP6_NEXTH_DESTOPTS:
                
                /* Get next header type. */
                nexth = *((u8_t *)p->payload);
                
                /* Get the header length. */
                hlen = 8 * (1 + *((u8_t *)p->payload + 1));
                ipdata.current_ip_header_tot_len += hlen;
                
                /* Skip over this header. */
                if (hlen > p->len) {
                    /* free (drop) packet pbufs */
                    pbuf_free(p);
                    return ERR_OK;
                }
                
                pbuf_header(p, -(s16_t)hlen);
                break;
                
            case IP6_NEXTH_ROUTING:
                
                /* Get next header type. */
                nexth = *((u8_t *)p->payload);
                
                /* Get the header length. */
                hlen = 8 * (1 + *((u8_t *)p->payload + 1));
                ipdata.current_ip_header_tot_len += hlen;
                
                /* Skip over this header. */
                if (hlen > p->len) {
                    /* free (drop) packet pbufs */
                    pbuf_free(p);
                    return ERR_OK;
                }
                
                pbuf_header(p, -(s16_t)hlen);
                break;
                
            case IP6_NEXTH_FRAGMENT:
            {
                struct ip6_frag_hdr *frag_hdr;
                
                frag_hdr = (struct ip6_frag_hdr *)p->payload;
                
                /* Get next header type. */
                nexth = frag_hdr->_nexth;
                
                /* Fragment Header length. */
                hlen = 8;
                ipdata.current_ip_header_tot_len += hlen;
                
                /* Make sure this header fits in current pbuf. */
                if (hlen > p->len) {
                    /* free (drop) packet pbufs */
                    pbuf_free(p);
                    return ERR_OK;
                }
                
                /* Offset == 0 and more_fragments == 0? */
                if ((frag_hdr->_fragment_offset & PP_HTONS(IP6_FRAG_OFFSET_MASK | IP6_FRAG_MORE_FLAG)) == 0) {
                    /* This is a 1-fragment packet, usually a packet that we have
                     * already reassembled. Skip this header anc continue. */
                    pbuf_header(p, -(s16_t)hlen);
                } else {
#if LWIP_IPV6_REASS
                    /* reassemble the packet */
                    p = ip6_reass(p);
                    /* packet not fully reassembled yet? */
                    if (p == NULL) {
                        return ERR_OK;
                    }
                    
                    /* Returned p point to IPv6 header.
                     * Update all our variables and pointers and continue. */
                    ip6hdr = (struct ip6_hdr *)p->payload;
                    nexth = IP6H_NEXTH(ip6hdr);
                    hlen = ipdata.current_ip_header_tot_len = IP6_HLEN;
                    pbuf_header(p, -IP6_HLEN);
#else /* LWIP_IPV6_REASS */
                    /* free (drop) packet pbufs */
                    pbuf_free(p);
                    return ERR_OK;
#endif /* LWIP_IPV6_REASS */
                }
                break;
            }
            default:
                break_while_flag = 1;
                break;
        }
    }
    
    /* p points to IPv6 header again. */
    pbuf_header_force(p, (s16_t)ipdata.current_ip_header_tot_len);
    
    switch (nexth) {
        case IP6_NEXTH_TCP:
            /* Point to payload. */
            pbuf_header(p, -(s16_t)ipdata.current_ip_header_tot_len);
            [self tcp_input:p ip_data:&ipdata is_ipv4:false];
            break;
        default:
            pbuf_free(p);
    }
    
    return ERR_OK;
}

// MARK: - TCP

- (void)tcp_input:(struct pbuf *)p
          ip_data:(struct ip_globals *)ipdata
          is_ipv4:(BOOL)ipv4
{
    struct tcp_hdr *tcphdr = (struct tcp_hdr *)p->payload;
    
    /* Check that TCP header fits in payload */
    if (p->len < TCP_HLEN) {
        /* drop short packets */
        pbuf_free(p);
        return;
    }
    
#if CHECKSUM_CHECK_TCP
    /* Verify TCP checksum. */
    u16_t chksum = ip_chksum_pseudo(p, IP_PROTO_TCP, p->tot_len,
                                    &(ipdata->current_iphdr_src),
                                    &(ipdata->current_iphdr_dest));
    if (chksum != 0) {
        pbuf_free(p);
        return;
    }
#endif /* CHECKSUM_CHECK_TCP */
    
    /* sanity-check header length */
    u8_t hdrlen_bytes = TCPH_HDRLEN(tcphdr) * 4;
    if (hdrlen_bytes < TCP_HLEN ||
        hdrlen_bytes > p->tot_len) {
        pbuf_free(p);
        return;
    }
    
    /* Move the payload pointer in the pbuf so that it points to the
     TCP data instead of the TCP header. */
    u16_t tcphdr_optlen = hdrlen_bytes - TCP_HLEN;
    u8_t *tcphdr_opt2 = NULL;
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
    
    struct tcp_info tcpinfo = {
        .tcphdr         = tcphdr,
        .tcphdr_optlen  = tcphdr_optlen,
        .tcphdr_opt1len = tcphdr_opt1len,
        .tcphdr_opt2    = tcphdr_opt2,
        .seqno          = seqno,
        .ackno          = ackno,
        .tcplen         = tcplen,
        .flags          = flags
    };
    NSLog(@"%@", &tcpinfo);
    
    /* Get tcp_pcb identifie */
    int inet_addr_str_len = ipv4 ? INET_ADDRSTRLEN : INET6_ADDRSTRLEN;
    int ip_v = ipv4 ? AF_INET : AF_INET6;
    char src_addr_chars[inet_addr_str_len];
    char dest_addr_chars[inet_addr_str_len];
    inet_ntop(ip_v, &ipdata->current_iphdr_src, src_addr_chars, inet_addr_str_len);
    inet_ntop(ip_v, &ipdata->current_iphdr_dest, dest_addr_chars, inet_addr_str_len);
    NSString *src_addr_str = [NSString stringWithCString:src_addr_chars
                                                encoding:NSASCIIStringEncoding];
    NSString *dest_addr_str = [NSString stringWithCString:dest_addr_chars
                                                 encoding:NSASCIIStringEncoding];
    NSString *identifie = [NSString stringWithFormat:@"%@-%d-%@-%d",
                           src_addr_str, tcphdr->src, dest_addr_str, tcphdr->dest];
    
    ZPTCPConnection *conn = [self connectionForKey:identifie];
    if (conn) {
//        [block tcpInput:p tcpInfo:tcpinfo];
    } else {
//        block = [ZPTCPBlock newBlockWith:identifie
//                                    pbuf:p
//                                  ipdata:ipdata
//                                 tcpinfo:&tcpinfo
//                                  tunnel:self];
        if (conn) {
//            [block configSrcAddr:src_addr_str
//                         srcPort:tcphdr->src
//                        destAddr:dest_addr_str
//                        destPort:tcphdr->dest];
            [self setConnection:conn forKey:identifie];
        }
        pbuf_free(p);
    }
}

- (void)tcp_connection_established:(ZPTCPConnection *)conn
{
    dispatch_async(_delegateQueue, ^{
        [_delegate tunnel:self didEstablishNewTCPConnection:conn];
    });
}

// MARK: - Misc

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
