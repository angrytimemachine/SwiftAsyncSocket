//
//  GCDAsyncSocket.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

import Foundation
import SwiftCWrapper

/**
* A socket file descriptor is really just an integer.
* It represents the index of the socket within the kernel.
* This makes invalid file descriptor comparisons easier to read.
**/
let SOCKET_NULL : Int32 = -1

let GCDAsyncSocketException = "GCDAsyncSocketException"
let GCDAsyncSocketErrorDomain = "GCDAsyncSocketErrorDomain"

let GCDAsyncSocketQueueName = "GCDAsyncSocket"
let GCDAsyncSocketThreadName = "GCDAsyncSocket-CFStream"

let GCDAsyncSocketManuallyEvaluateTrust = "GCDAsyncSocketManuallyEvaluateTrust"
#if iOS
let GCDAsyncSocketUseCFStreamForTLS = "GCDAsyncSocketUseCFStreamForTLS"
#endif
let GCDAsyncSocketSSLPeerID = "GCDAsyncSocketSSLPeerID"
let GCDAsyncSocketSSLProtocolVersionMin = "GCDAsyncSocketSSLProtocolVersionMin"
let GCDAsyncSocketSSLProtocolVersionMax = "GCDAsyncSocketSSLProtocolVersionMax"
let GCDAsyncSocketSSLSessionOptionFalseStart = "GCDAsyncSocketSSLSessionOptionFalseStart"
let GCDAsyncSocketSSLSessionOptionSendOneByteRecord = "GCDAsyncSocketSSLSessionOptionSendOneByteRecord"
let GCDAsyncSocketSSLCipherSuites = "GCDAsyncSocketSSLCipherSuites"
#if !iOS
let GCDAsyncSocketSSLDiffieHellmanParameters = "GCDAsyncSocketSSLDiffieHellmanParameters"
#endif

struct GCDAsyncSocketFlags : OptionSetType {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static let SocketStarted                 = GCDAsyncSocketFlags(rawValue: 0)  // If set, socket has been started (accepting/connecting)
    static let Connected                     = GCDAsyncSocketFlags(rawValue: 1)  // If set, the socket is connected
    static let ForbidReadsWrites             = GCDAsyncSocketFlags(rawValue: 2)  // If set, no new reads or writes are allowed
    static let ReadsPaused                   = GCDAsyncSocketFlags(rawValue: 3)  // If set, reads are paused due to possible timeout
    static let WritesPaused                  = GCDAsyncSocketFlags(rawValue: 4)  // If set, writes are paused due to possible timeout
    static let DisconnectAfterReads          = GCDAsyncSocketFlags(rawValue: 5)  // If set, disconnect after no more reads are queued
    static let DisconnectAfterWrites         = GCDAsyncSocketFlags(rawValue: 6)  // If set, disconnect after no more writes are queued
    static let SocketCanAcceptBytes          = GCDAsyncSocketFlags(rawValue: 7)  // If set, we know socket can accept bytes. If unset, it's unknown.
    static let ReadSourceSuspended           = GCDAsyncSocketFlags(rawValue: 8)  // If set, the read source is suspended
    static let WriteSourceSuspended          = GCDAsyncSocketFlags(rawValue: 9)  // If set, the write source is suspended
    static let QueuedTLS                     = GCDAsyncSocketFlags(rawValue: 10)  // If set, we've queued an upgrade to TLS
    static let StartingReadTLS               = GCDAsyncSocketFlags(rawValue: 11)  // If set, we're waiting for TLS negotiation to complete
    static let StartingWriteTLS              = GCDAsyncSocketFlags(rawValue: 12)  // If set, we're waiting for TLS negotiation to complete
    static let SocketSecure                  = GCDAsyncSocketFlags(rawValue: 13)  // If set, socket is using secure communication via SSL/TLS
    static let SocketHasReadEOF              = GCDAsyncSocketFlags(rawValue: 14)  // If set, we have read EOF from socket
    static let ReadStreamClosed              = GCDAsyncSocketFlags(rawValue: 15)  // If set, we've read EOF plus prebuffer has been drained
    static let Dealloc                       = GCDAsyncSocketFlags(rawValue: 16)  // If set, the socket is being deallocated
    #if iOS
    static let AddedStreamsToRunLoop         = GCDAsyncSocketFlags(rawValue: 17)  // If set, CFStreams have been added to listener thread
    static let UsingCFStreamForTLS           = GCDAsyncSocketFlags(rawValue: 18)  // If set, we're forced to use CFStream instead of SecureTransport
    static let SecureSocketHasBytesAvailable = GCDAsyncSocketFlags(rawValue: 19)  // If set, CFReadStream has notified us of bytes available
    #endif
};

struct GCDAsyncSocketConfig : OptionSetType {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    static let IPv4Disabled              = GCDAsyncSocketConfig(rawValue: 0)  // If set, IPv4 is disabled
    static let IPv6Disabled              = GCDAsyncSocketConfig(rawValue: 1)  // If set, IPv6 is disabled
    static let PreferIPv6                = GCDAsyncSocketConfig(rawValue: 2)  // If set, IPv6 is preferred over IPv4
    static let AllowHalfDuplexConnection = GCDAsyncSocketConfig(rawValue: 3)  // If set, the socket will stay open even if the read stream closes
};

enum GCDAsyncSocketError: ErrorType {
    case PosixError(message:String)
    case BadConfigError(message:String)
}



class GCDAsyncSocket {
    var flags  = [GCDAsyncSocketFlags]()
    var config = [GCDAsyncSocketConfig]()
    
    var socket4FD : Int32 = SOCKET_NULL
    var socket6FD : Int32 = SOCKET_NULL
    var socketUN : Int32 = SOCKET_NULL
    var socketUrl : NSURL? = nil
    var stateIndex : Int = 0
    var connectInterface4 : NSData? = nil
    var connectInterface6 : NSData? = nil
    var connectInterfaceUN : NSData? = nil
    
    let socketQueue : dispatch_queue_t
    
    var accept4Source : dispatch_source_t? = nil
    var accept6Source : dispatch_source_t? = nil
    var acceptUNSource : dispatch_source_t? = nil
    var connectTimer : dispatch_source_t? = nil
    var readSource : dispatch_source_t? = nil
    var writeSource : dispatch_source_t? = nil
    var readTimer : dispatch_source_t? = nil
    var writeTimer : dispatch_source_t? = nil
    
    var readQueue : [CInt] = []
    var writeQueue : [CInt] = []
    
    var currentRead : GCDAsyncReadPacket? = nil
    var currentWrite : GCDAsyncReadPacket? = nil
    
    var socketFDBytesAvailable : Int = 0
    
    var preBuffer : GCDAsyncSocketPreBuffer? = nil
    
    #if iOS
    var streamContext : CFStreamClientContext
    var readStream : CFReadStreamRef
    var writeStream : CFWriteStreamRef
    #endif
    var sslContext : SSLContextRef? = nil
    var sslPreBuffer : GCDAsyncSocketPreBuffer? = nil
    var sslWriteCachedLength : size_t = 0
    var sslErrCode : OSStatus = 0
    var lastSSLHandshakeError : OSStatus = 0
    
//    var IsOnSocketQueueOrTargetQueueKey : UnsafeMutablePointer<Void>
    
    
    weak var _delegate : AnyObject? = nil
    var delegate : AnyObject?
        {
        get {
            var result : AnyObject? = nil
            if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
                result = self._delegate
            }
            else {
                
                dispatch_sync(socketQueue, { () -> Void in
                    result = self._delegate
                })
            }
            return result
        }
    }
    func setDelegate(newDelegate : AnyObject?, synchronously : Bool){
        let block = {
            self._delegate = newDelegate
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            if synchronously {
                dispatch_sync(socketQueue, block)
            }else{
                dispatch_async(socketQueue, block)
            }
        }
    }
    func setDelegate(newDelegate : AnyObject?) {
        setDelegate(newDelegate, synchronously: false)
    }
    func synchronouslySetDelegate(newDelegate : AnyObject?) {
        setDelegate(newDelegate, synchronously: true)
    }
    
    var _delegateQueue : dispatch_queue_t? = nil
    var delegateQueue : dispatch_queue_t?
        {
        get {
            var result : dispatch_queue_t? = nil
            if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
                result = self._delegateQueue
            }
            else {
                
                dispatch_sync(socketQueue, { () -> Void in
                    result = self._delegateQueue
                })
            }
            return result
        }
    }
    func setDelegateQueue(newDelegateQueue : dispatch_queue_t?, synchronously : Bool){
        let block = {
//            #if !OS_OBJECT_USE_OBJC
//                if (delegateQueue) dispatch_release(delegateQueue);
//                if (newDelegateQueue) dispatch_retain(newDelegateQueue);
//            #endif
            
            self._delegateQueue = newDelegateQueue
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            if synchronously {
                dispatch_sync(socketQueue, block)
            }else{
                dispatch_async(socketQueue, block)
            }
        }
    }
    func setDelegateQueue(newDelegateQueue : dispatch_queue_t?) {
        setDelegateQueue(newDelegateQueue, synchronously: false)
    }
    func synchronouslySetDelegateQueue(newDelegateQueue : dispatch_queue_t?) {
        setDelegateQueue(newDelegateQueue, synchronously: true)
    }
    func getDelegate(inout delegatePtr : UnsafeMutablePointer<AnyObject?>, inout delegateQueuePtr : UnsafeMutablePointer<dispatch_queue_t?>){
        let block = {
            var d = self._delegate
            if delegatePtr != nil {
                withUnsafeMutablePointer(&d) { v in
                    delegatePtr = v
                }
            }
            var dq = self._delegateQueue
            if delegateQueuePtr != nil {
                withUnsafeMutablePointer(&dq) { v in
                    delegateQueuePtr = v
                }
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
            
        }else {
            dispatch_sync(socketQueue, block)
        }
    }
    func setDelegate(newDelegate : AnyObject?, newDelegateQueue : dispatch_queue_t?, synchronously : Bool ){
        let block = {
            self._delegate = newDelegate
            
            //Always using ARC don't need this
//            #if !OS_OBJECT_USE_OBJC
//                if (_delegateQueue) dispatch_release(_delegateQueue);
//                if (newDelegateQueue) dispatch_retain(newDelegateQueue);
//            #endif
           self._delegateQueue = newDelegateQueue
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        } else {
            if synchronously {
                dispatch_sync(socketQueue, block)
            }else{
                dispatch_async(socketQueue, block)
            }
        }
        
    }
    func setDelegate(newDelegate : AnyObject?, delegateQueue newDelegateQueue : dispatch_queue_t?){
        setDelegate(newDelegate, newDelegateQueue: newDelegateQueue, synchronously: false)
    }
    func synchronouslySetDelegate(newDelegate : AnyObject?, delegateQueue newDelegateQueue : dispatch_queue_t?){
        setDelegate(newDelegate, newDelegateQueue: newDelegateQueue, synchronously: true)
    }
    func isIPv4Enabled() -> Bool {
        var result = false
        // Note: YES means IPv4Disabled is OFF
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            result = !config.contains(.IPv4Disabled)
        }else {
            dispatch_sync(socketQueue, { () -> Void in
                result = !self.config.contains(.IPv4Disabled)
            })
        }
        return result
    }
    func setIPv4Enabled(flag : Bool) {
        let block = {
            if flag {
                //if it was disabled, remove it
                if let index = self.config.indexOf(.IPv4Disabled) {
                    self.config.removeAtIndex(index)
                }
            }else{
                //disable it
                self.config.append(.IPv4Disabled)
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            
            dispatch_sync(socketQueue, block)
        }
    }
    func isIPv6Enabled() -> Bool {
        var result = false
        // Note: YES means kIPv6Disabled is OFF
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            result = !config.contains(.IPv6Disabled)
        }else {
            dispatch_sync(socketQueue, { () -> Void in
                result = !self.config.contains(.IPv6Disabled)
            })
        }
        return result
    }
    func setIPv6Enabled(flag : Bool) {
        let block = {
            if flag {
                //if it was disabled, remove it
                if let index = self.config.indexOf(.IPv6Disabled) {
                    self.config.removeAtIndex(index)
                }
            } else {
                //disable it
                self.config.append(.IPv6Disabled)
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            
            dispatch_sync(socketQueue, block)
        }
    }
    var isIPv4PreferredOverIPv6 : Bool {
        get {
            var result : Bool = false
            if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
                result = config.contains(.PreferIPv6)
            }
            else {
                
                dispatch_sync(socketQueue, { () -> Void in
                    result = self.config.contains(.PreferIPv6)
                })
            }
            return result
        }
    }

    func preferIPv4OverIPv6(flag : Bool) {
        // Note: YES means PreferIPv6 is OFF
        let block = {
            if flag {
                let index = self.config.indexOf(.PreferIPv6)
                if let i = index {
                    self.config.removeAtIndex(i)
                }
            } else {
                self.config.append(.PreferIPv6)
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        } else {
            dispatch_async(socketQueue, block)
        }
    }
    var _userData : AnyObject? = nil
    var userData : AnyObject?
        {
        get {
            var result : AnyObject? = nil
            if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
                result = self._userData
            }
            else {
                
                dispatch_sync(socketQueue, { () -> Void in
                    result = self._userData
                })
            }
            return result
        }
    }
    func setUserData(newUserData : AnyObject?){
        let block = {
            self._userData = newUserData
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
    }
    
    init(withDelegate aDelegate : AnyObject?, delegateQueue dq : dispatch_queue_t?, socketQueue aSocketQueue : dispatch_queue_t!) {
        if let sq = aSocketQueue {
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), "The given socketQueue parameter must not be a concurrent queue.");
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), "The given socketQueue parameter must not be a concurrent queue.");
            assert(sq !== dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), "The given socketQueue parameter must not be a concurrent queue.");
            
            socketQueue = aSocketQueue;
            //always using ARC, don't need this
            //            #if !OS_OBJECT_USE_OBJC
            //                dispatch_retain(sq);
            //            #endif
        }
        else
        {
            socketQueue = dispatch_queue_create(GCDAsyncSocketQueueName, nil);
        }
        
        setDelegate(aDelegate, synchronously: true)
        if let dQueue = dq {
            //Always using ARC don't need this
//            #if !OS_OBJECT_USE_OBJC
//                dispatch_retain(dQueue);
//            #endif
            setDelegateQueue(dQueue, synchronously: true)
        }
        

        
        // The dispatch_queue_set_specific() and dispatch_get_specific() functions take a "void *key" parameter.
        // From the documentation:
        //
        // > Keys are only compared as pointers and are never dereferenced.
        // > Thus, you can use a pointer to a static variable for a specific subsystem or
        // > any other value that allows you to identify the value uniquely.
        //
        // We're just going to use the memory address of an ivar.
        // Specifically an ivar that is explicitly named for our purpose to make the code more readable.
        //
        // However, it feels tedious (and less readable) to include the "&" all the time:
        // dispatch_get_specific(&IsOnSocketQueueOrTargetQueueKey)
        //
        // So we're going to make it so it doesn't matter if we use the '&' or not,
        // by assigning the value of the ivar to the address of the ivar.
        // Thus: IsOnSocketQueueOrTargetQueueKey == &IsOnSocketQueueOrTargetQueueKey;
        
//        IsOnSocketQueueOrTargetQueueKey = &IsOnSocketQueueOrTargetQueueKey;
        
       
//        let context = UnsafeMutablePointer<GCDAsyncSocket>.alloc(1)
//        context.initialize(self)
        var selfPtr = self
        withUnsafeMutablePointer(&selfPtr) { v in
            dispatch_queue_set_specific(socketQueue, GCDAsyncSocketQueueName, v, nil);
        }

        preBuffer = GCDAsyncSocketPreBuffer.init(withCapacity: 1024 * 4)
        
    }
    convenience init() {
        self.init(withDelegate:.None, delegateQueue:.None, socketQueue:.None)
    }
    convenience init(withSocketQueue sq: dispatch_queue_t) {
        self.init(withDelegate:.None, delegateQueue:.None, socketQueue:sq)
    }
    convenience init(withDelegate aDelegate : AnyObject, withDelegateQueue dq: dispatch_queue_t) {
        self.init(withDelegate:aDelegate, delegateQueue:dq, socketQueue:.None)
    }
    
    deinit {
        // Set dealloc flag.
        // This is used by closeWithError to ensure we don't accidentally retain ourself.
        flags.append(GCDAsyncSocketFlags.Dealloc)
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            close(withError: nil)
            
        } else {
            dispatch_sync(socketQueue, { () -> Void in
                self.close(withError: nil)
            })
        }
        
        _delegate = nil
        
        //Always using ARC, don't need this
//        #if !OS_OBJECT_USE_OBJC
//            if (delegateQueue) dispatch_release(delegateQueue);
//        #endif
        _delegateQueue = nil
        
        //Always using ARC, don't need this
//        #if !OS_OBJECT_USE_OBJC
//            if (socketQueue) dispatch_release(socketQueue);
//        #endif
//        socketQueue = nil;
        
//        LogInfo(@"%@ - %@ (finish)", THIS_METHOD, self);
    }
     /***********************************************************/
     // MARK: Accepting
     /***********************************************************/
    func acceptOnPort(port : UInt16) throws {
        try acceptOnInterface(nil, port: port)
    }
    /*!
    * @function acceptOnInterface
    *
    * @param inputInterface
    * By default this is nil, which causes the server to listen on all available 
    * interfaces like en1, wifi etc.
    * The interface may be specified by name (e.g. "en1" or "lo0") or by IP
    * address (e.g. "192.168.4.34").
    * You may also use the special strings "localhost" or "loopback" to specify that
    * the socket only accept connections from the local machine.
    *
    * @throw GCDAsyncSocketError
    */
    func acceptOnInterface(inputInterface : String?, port : UInt16) throws {

        let interface = inputInterface != nil ? inputInterface! : ""
        
        // CreateSocket Block returns the file descriptor that it connected with
        // This block will be invoked within the dispatch block below.
        let createSocket = { (domain: Int32, interfaceAddress : NSData?) throws -> Int32 in
            let socketFD = socket(domain, SOCK_STREAM, 0 )
            if socketFD == SOCKET_NULL {
                throw GCDAsyncSocketError.PosixError(message: "Error in socket() function")
            }
            
            // Set socket options
            if swift_fcntl(socketFD, F_SETFL, O_NONBLOCK) == -1 {
                swift_close(socketFD)
                throw GCDAsyncSocketError.PosixError(message: "Error enabling non-blocking IO on socket (fcntl)")
            }
            
            // Bind socket
            var reuseOn = 1
            if setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseOn, socklen_t(sizeofValue(reuseOn))) == -1 {
                swift_close(socketFD)
                throw GCDAsyncSocketError.PosixError(message: "Error enabling address reuse (setsockopt)")
            }
            
            // Listen
            if listen(socketFD, 1024) == -1 {
                swift_close(socketFD)
                throw GCDAsyncSocketError.PosixError(message: "Error in listen() function")
            }
            
            return socketFD
        }
        
        // Create dispatch block and run on socketQueue
        let block = {
            guard let d = self._delegate else {
                throw GCDAsyncSocketError.BadConfigError(message: "Attempting to accept without a delegate. Set a delegate first.")
            }
            guard let dq = self._delegateQueue else {
                throw GCDAsyncSocketError.BadConfigError(message: "Attempting to accept without a delegate queue. Set a delegate queue first.")
            }
            let isIPv4Disabled = self.config.contains(.IPv4Disabled)
            let isIPv6Disabled = self.config.contains(.IPv6Disabled)
            if isIPv4Disabled && isIPv6Disabled { // Must have IPv4 or IPv6 enabled
                throw GCDAsyncSocketError.BadConfigError(message: "Both IPv4 and IPv6 have been disabled. Must enable at least one protocol first.")
            }
            
            if !self.isDisconnected() {
                throw GCDAsyncSocketError.BadConfigError(message: "Attempting to accept while connected or accepting connections. Disconnect first.")
            }
            
            // Clear queues (spurious read/write requests post disconnect)
            self.readQueue.removeAll()
            self.writeQueue.removeAll()
            
            // Resolve interface from description
            var interface4 = NSMutableData.init()
            var interface6 = NSMutableData.init()
            self.getInterfaceAddress4(&interface4, address6: &interface6, fromDescription: interface, port: port)
            
            if interface4.length == 0 && interface6.length == 0 {
                throw GCDAsyncSocketError.BadConfigError(message: "Unknown interface. Specify valid interface by name (e.g. \"en1\") or IP address.")
            }
            
            if isIPv4Disabled && interface6.length == 0 {
                throw GCDAsyncSocketError.BadConfigError(message: "IPv4 has been disabled and specified interface doesn't support IPv6.")
            }
            if isIPv6Disabled && interface4.length == 0 {
                throw GCDAsyncSocketError.BadConfigError(message: "IPv6 has been disabled and specified interface doesn't support IPv4.")
            }
            let enableIPv4 = !isIPv4Disabled && interface4.length != 0
            let enableIPv6 = !isIPv6Disabled && interface6.length != 0
            
            // Create sockets, configure, bind, and listen
            if enableIPv4 {
                self.socket4FD = try createSocket(AF_INET, interface4)
                if self.socket4FD == SOCKET_NULL {
                    return
                }
            }
            
            if enableIPv6 {
                if enableIPv4 && port == 0 {
                    // No specific port was specified, so we allowed the OS to pick an available port for us.
                    // Now we need to make sure the IPv6 socket listens on the same port as the IPv4 socket.
//                    struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)[interface6 mutableBytes];
//                    addr6->sin6_port = htons([self localPort4]);
                }
                self.socket6FD = try createSocket(AF_INET6, interface6)
                if self.socket6FD == SOCKET_NULL {
                    if self.socket4FD != SOCKET_NULL {
                        swift_close(self.socket4FD)
                        return
                    }
                }
            }
            
            // Create accept sources
            if enableIPv4 {
//                accept4Source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.socket4FD, 0 self.socketQueue)
                
                
            }
            
        }
        
//        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
//            block()
//        } else {
//            dispatch_sync(socketQueue, block)
//        }
        
        if let err = error {
            throw err
        }
    }
    
     /***********************************************************/
     // MARK: Connecting
     /***********************************************************/
    func endConnectTimeout() {
        if let timer = connectTimer {
            dispatch_source_cancel(timer)
        }
        // Increment stateIndex.
        // This will prevent us from processing results from any related background asynchronous operations.
        //
        // Note: This should be called from close method even if connectTimer is NULL.
        // This is because one might disconnect a socket prior to a successful connection which had no timeout.
        
        stateIndex++;
        
        if connectInterface4 != nil {
            connectInterface4 = nil;
        }
        if connectInterface6 != nil {
            connectInterface6 = nil;
        }
    }
    
     /***********************************************************/
     // MARK: Disconnecting
     /***********************************************************/
    
     /***********************************************************/
     // MARK: Errors
     /***********************************************************/
    
     /***********************************************************/
     // MARK: Diagnostics
     /***********************************************************/
    func isDisconnected() -> Bool {
        return false
    }
    func close(withError error: String?) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue");
        endConnectTimeout()
        
        if let cr = currentRead {
//            endCurrentRead()
        }
    }
     /***********************************************************/
     // MARK: Utilities
     /***********************************************************/
    /**
    * Finds the address of an interface description.
    * An inteface description may be an interface name (en0, en1, lo0) or corresponding IP (192.168.4.34).
    *
    * The interface description may optionally contain a port number at the end, separated by a colon.
    * If a non-zero port parameter is provided, any port number in the interface description is ignored.
    *
    * The returned value is a 'struct sockaddr' wrapped in an NSMutableData object.
    **/
    func getInterfaceAddress4(inout interfaceAddr4Ptr : NSMutableData, inout address6 interfaceAddr6Ptr : NSMutableData, fromDescription interfaceDescription : String, port : UInt16) {
        
    }
     /***********************************************************/
     // MARK: Read
     /***********************************************************/
     
     /***********************************************************/
     // MARK: Writing
     /***********************************************************/
     
     /***********************************************************/
     // MARK: Security
     /***********************************************************/
     
     /***********************************************************/
     // MARK: Security via SecureTransport
     /***********************************************************/
    
     /***********************************************************/
     // MARK: Security via CFStream
     /***********************************************************/
    
     /***********************************************************/
     // MARK: CFStream
     /***********************************************************/
    
     /***********************************************************/
     // MARK: Advanced
     /***********************************************************/
    
     /***********************************************************/
     // MARK: Class Utilities
     /***********************************************************/
    
}