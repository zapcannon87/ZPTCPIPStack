//
//  ZPPacketTunnel.m
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import "ZPPacketTunnel.h"
#import "ZPPacketTunnelEx.h"

err_t netif_output(struct pbuf *p, BOOL ipv4)
{
    void *buf = malloc(sizeof(char) * p->tot_len);
    if (buf == NULL) {
        return ERR_MEM;
    }
    if (pbuf_copy_partial(p, buf, p->tot_len, 0) == 0) {
        return ERR_BUF;
    }
    
    NSData *data = [NSData dataWithBytesNoCopy:buf length:p->tot_len];
    NSNumber *ipVersion = [NSNumber numberWithInt:(ipv4 ? AF_INET : AF_INET6)];
    
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
        NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
        if (dic == NULL) {
            return NULL;
        }
        _dic = dic;
        dispatch_queue_t queue = dispatch_queue_create("ZPPacketTunnel.dicQueue", NULL);
        if (queue == NULL) {
            return NULL;
        }
        _dicQueue = queue;
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
        NSAssert(_delegateQueue != NULL, @"delegate queue should not be null");
    }
}

-(void)mtu:(UInt16)mtu output:(OutputBlock)output
{
    _netif.mtu = mtu;
    _output = output;
}

-(void)ipv4SettingWithAddress:(NSString *)addr
                      netmask:(NSString *)netmask
                        error:(NSError *__autoreleasing  _Nullable *)errPtr
{
    struct netif *netif = &_netif;
    
    /* set address */
    ip4_addr_t ip4_addr;
    const char *addr_chars = [addr cStringUsingEncoding:NSASCIIStringEncoding];
    if (inet_pton(AF_INET, addr_chars, &ip4_addr) == 0 ||
        ip4_addr_isany(&ip4_addr)) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:@"ipv4 address setting is not right" code:-1 userInfo:NULL];
        }
        return;
    }
    ip4_addr_set(ip_2_ip4(&netif->ip_addr), &ip4_addr);
    IP_SET_TYPE_VAL(netif->ip_addr, IPADDR_TYPE_V4);
    
    /* set netmask */
    ip4_addr_t ip4_netmask;
    const char *netmask_chars = [netmask cStringUsingEncoding:NSASCIIStringEncoding];
    if (inet_pton(AF_INET, netmask_chars, &ip4_netmask) == 0) {
        if (errPtr) {
            *errPtr = [NSError errorWithDomain:@"ipv4 netmask setting is not right" code:-1 userInfo:NULL];
        }
        return;
    }
    ip4_addr_set(ip_2_ip4(&netif->netmask), &ip4_netmask);
    IP_SET_TYPE_VAL(netif->netmask, IPADDR_TYPE_V4);
    
    /* set gateway */
    ip4_addr_set(ip_2_ip4(&netif->gw), &ip4_addr);
    IP_SET_TYPE_VAL(netif->gw, IPADDR_TYPE_V4);
    
    netif->output = netif_output_ip4;
}

@end
