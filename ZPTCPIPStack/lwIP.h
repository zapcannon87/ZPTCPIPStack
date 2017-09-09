//
//  lwIP.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#ifndef lwIP_h
#define lwIP_h

#import <netinet/in.h>

#include "lwip/tcp.h"
#include "lwip/prot/tcp.h"
#include "lwip/priv/tcp_priv.h"
#include "lwip/inet_chksum.h"
#include "lwip/ip4_frag.h"
#include "lwip/ip6_frag.h"

#if LWIP_IPV4 && LWIP_IPV6 /* LWIP_IPV4 && LWIP_IPV6 */

#define inet_ntop(af,src,dst,size) \
(((af) == AF_INET6) ? ip6addr_ntoa_r((const ip6_addr_t*)(src),(dst),(size)) \
: (((af) == AF_INET) ? ip4addr_ntoa_r((const ip4_addr_t*)(src),(dst),(size)) : NULL))
#define inet_pton(af,src,dst) \
(((af) == AF_INET6) ? ip6addr_aton((src),(ip6_addr_t*)(dst)) \
: (((af) == AF_INET) ? ip4addr_aton((src),(ip4_addr_t*)(dst)) : 0))

#elif LWIP_IPV4 /* LWIP_IPV4 */

#define inet_ntop(af,src,dst,size) \
(((af) == AF_INET) ? ip4addr_ntoa_r((const ip4_addr_t*)(src),(dst),(size)) : NULL)
#define inet_pton(af,src,dst) \
(((af) == AF_INET) ? ip4addr_aton((src),(ip4_addr_t*)(dst)) : 0)

#else /* LWIP_IPV6 */

#define inet_ntop(af,src,dst,size) \
(((af) == AF_INET6) ? ip6addr_ntoa_r((const ip6_addr_t*)(src),(dst),(size)) : NULL)
#define inet_pton(af,src,dst) \
(((af) == AF_INET6) ? ip6addr_aton((src),(ip6_addr_t*)(dst)) : 0)

#endif /* LWIP_IPV4 && LWIP_IPV6 */


/**
 struct to store tcp header info
 */
struct tcp_info {
    /* These variables are global to all functions involved in the input
     processing of TCP segments. They are set by the tcp_input_pre()
     function. */
    struct tcp_hdr *tcphdr;
    u16_t tcphdr_optlen;
    u16_t tcphdr_opt1len;
    u8_t* tcphdr_opt2;
    u32_t seqno;
    u32_t ackno;
    u16_t tcplen;
    u8_t  flags;
};

/**
 struct to store all the tcp stack global info to all functions involved in the lwIP's tcp stack
 */
struct zp_tcp_block {
    
    struct tcp_pcb *pcb;
    
    struct ip_globals ip_data;
    
    struct tcp_info tcpInfo;
    
    /* Incremented every coarse grained timer shot (typically every 500 ms). */
    u32_t tcp_ticks;
    /* Timer counter to handle calling slow-timer from tcp_tmr() */
    uint64_t tcp_timer;
    
    /* These variables are global to all functions involved in the input
     processing of TCP segments. They are set by the tcp_input()
     function. */
    u16_t          tcp_optidx;
    struct tcp_seg inseg;
    struct pbuf    *recv_data;
    u8_t           recv_flags;
    tcpwnd_size_t  recv_acked;
    
    /* flag to control tcp close after all pending writes have completed */
    u8_t close_after_writing;
    
};

/**
 tcp input preprocess, check and get the info in tcp packet header.

 @param p tcp data pbuf
 @param inp input network interface
 */
void tcp_input_pre(struct pbuf *p, struct netif *inp);

#define LOG_FUNC_NAME 1

#endif /* lwIP_h */
