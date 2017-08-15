//
//  ZPTCPConnection.h
//  ZPTCPIPStack
//
//  Created by ZapCannon87 on 11/08/2017.
//  Copyright © 2017 zapcannon87. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ZPTCPConnection;

@protocol ZPTCPConnectionDelegate <NSObject>

@end

@interface ZPTCPConnection : NSObject

@property (nonatomic, weak, nullable) id<ZPTCPConnectionDelegate> delegate;

@property (nonatomic, strong, readonly, nonnull) NSString *srcAddr;
@property (nonatomic, strong, readonly, nonnull) NSString *destAddr;
@property (nonatomic, assign, readonly) UInt16 srcPort;
@property (nonatomic, assign, readonly) UInt16 destPort;

@end
