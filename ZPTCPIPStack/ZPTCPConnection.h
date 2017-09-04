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

/**
 Called when a connection has received send data's ack.

 @param connection tcp stack controller
 @param length transfered data's length
 @param isEmpty True means all send data complete transfer or no data sent, False means exist send data in buffer wait for acking or retransmiting
 */
- (void)connection:(ZPTCPConnection *_Nonnull)connection didWriteData:(UInt16)length sendBuf:(BOOL)isEmpty;

/**
 Called when a connection has set the read data flag and exist received data in tcp stack buffer.

 @param connection tcp stack controller
 @param data read data
 */
- (void)connection:(ZPTCPConnection *_Nonnull)connection didReadData:(NSData *_Nonnull)data;

/**
 Called when a connection close with error.

 @param connection tcp stack controller
 @param err error in closing
 */
- (void)connection:(ZPTCPConnection *_Nonnull)connection didDisconnectWithError:(NSError *_Nonnull)err;

/**
 Called when a connection has checked an error when writing data.

 @param connection tcp stack controller
 @param err error in writing data
 */
- (void)connection:(ZPTCPConnection *_Nonnull)connection didCheckWriteDataWithError:(NSError *_Nonnull)err;

/**
 Conditionally called if the read stream closes, but the write stream may still be writeable.
 
 @param connection tcp stack controller
 */
@optional
- (void)connectionDidCloseReadStream:(ZPTCPConnection *_Nonnull)connection;

@end

@interface ZPTCPConnection : NSObject

/**
 Queue for delegate, it should be a serial queue.
 */
@property (nonatomic, strong, readonly, nonnull) dispatch_queue_t delegateQueue;

/**
 TCP connection source address.
 */
@property (nonatomic, strong, readonly, nonnull) NSString *srcAddr;

/**
 TCP connection destination address.
 */
@property (nonatomic, strong, readonly, nonnull) NSString *destAddr;

/**
 TCP connection source port.
 */
@property (nonatomic, assign, readonly) UInt16 srcPort;

/**
 TCP connection destination port.
 */
@property (nonatomic, assign, readonly) UInt16 destPort;

/**
 Synchronously. Set the delegate and delegate queue.

 @param delegate can not be NULL
 @param queue can be NULL
 @return a flag to indicate whether the tcp_pcb has been aborted. False means tcp has aborted, True means tcp not aborted.
 */
- (BOOL)syncSetDelegate:(id<ZPTCPConnectionDelegate> _Nonnull)delegate delegateQueue:(dispatch_queue_t _Nullable)queue;

/**
 Asynchronously. Set the delegate and delegate queue.

 @param delegate can not be NULL
 @param queue can be NULL
 */
- (void)asyncSetDelegate:(id<ZPTCPConnectionDelegate> _Nonnull)delegate delegateQueue:(dispatch_queue_t _Nullable)queue;

/**
 Asynchronously. Writes data to the tcp_pcb, and calls the delegate when finished.

 @param data writing data
 */
- (void)write:(NSData *_Nonnull)data;

/**
 Asynchronously. This is not directly read the data in received buffer, it will set a flag up to let the tcp_pcb can read data from buffer. when the read delegate has been called, the flag will be set down.
 */
- (void)readData;

/**
 Asynchronously. Close the connection.
 */
- (void)close;

/**
 Asynchronously. Close the connection after all pending writes have completed.
 */
- (void)closeAfterWriting;

@end
