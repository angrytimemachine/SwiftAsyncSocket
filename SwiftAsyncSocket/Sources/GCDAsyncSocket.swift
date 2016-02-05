//
//  GCDAsyncSocket.swift
//  SwiftAsyncSocket
//
//  Created by Joel Saltzman on 1/10/16.
//  Copyright © 2016 Joel Saltzman. All rights reserved.
//

/*
    TODO: replace Security framework with OpenSSL?

*/

import Foundation
import SwiftCWrapper

#if iOS
    import CFNetwork
#endif

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
    case BadParamError(message:String)
    case OtherError(message:String)
    case TimeoutError()
    
    var description : String {
        get {
            switch (self) {
            case .TimeoutError: return "Attempt to connect to host timed out"
            case let .PosixError(message): return message
            case let .BadConfigError(message): return message
            case let .BadParamError(message): return message
            case let .OtherError(message): return message
            }
        }
    }
}

/**
 * GCDAsyncSocket uses the standard delegate paradigm,
 * but executes all delegate callbacks on a given delegate dispatch queue.
 * This allows for maximum concurrency, while at the same time providing easy thread safety.
 *
 * You MUST set a delegate AND delegate dispatch queue before attempting to
 * use the socket, or you will get an error.
 *
 * The socket queue is optional.
 * If you pass NULL, GCDAsyncSocket will automatically create it's own socket queue.
 * If you choose to provide a socket queue, the socket queue must not be a concurrent queue.
 * If you choose to provide a socket queue, and the socket queue has a configured target queue,
 * then please see the discussion for the method markSocketQueueTargetQueue.
 *
 * The delegate queue and socket queue can optionally be the same.
 **/
class GCDAsyncSocket {
    var flags  = [GCDAsyncSocketFlags]()
    var config = [GCDAsyncSocketConfig]()
    
    var _socket4FD : Int32 = SOCKET_NULL
    var _socket6FD : Int32 = SOCKET_NULL
    var socketUN : Int32 = SOCKET_NULL
    var socketUrl : NSURL? = nil
    var stateIndex : Int = 0
    var connectInterface4 : NSMutableData? = nil
    var connectInterface6 : NSMutableData? = nil
    var connectInterfaceUN : NSMutableData? = nil
    
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
    var streamContext : CFStreamClientContext? = nil
    var readStream : CFReadStreamRef? = nil
    var writeStream : CFWriteStreamRef? = nil
    #endif
    var _sslContext : SSLContextRef? = nil
    var sslPreBuffer : GCDAsyncSocketPreBuffer? = nil
    var sslWriteCachedLength : size_t = 0
    var sslErrCode : OSStatus = 0
    var lastSSLHandshakeError : OSStatus = 0
    
//    var IsOnSocketQueueOrTargetQueueKey : UnsafeMutablePointer<Void>
    
    
    weak var _delegate : GCDAsyncSocketDelegate? = nil
    var delegate : GCDAsyncSocketDelegate?
        {
        get {
            var result : GCDAsyncSocketDelegate? = nil
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
    func setDelegate(newDelegate : GCDAsyncSocketDelegate?, synchronously : Bool){
        let block = {
            self._delegate = newDelegate
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            if synchronously {
                dispatch_sync(socketQueue, block)
            }
            else{
                dispatch_async(socketQueue, block)
            }
        }
    }
    func setDelegate(newDelegate : GCDAsyncSocketDelegate?) {
        setDelegate(newDelegate, synchronously: false)
    }
    /**
     * If you are setting the delegate to nil within the delegate's dealloc method,
     * you may need to use the synchronous versions below.
     **/
    func synchronouslySetDelegate(newDelegate : GCDAsyncSocketDelegate?) {
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
            }
            else{
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
    func getDelegate(inout delegatePtr : UnsafeMutablePointer<GCDAsyncSocketDelegate?>, inout delegateQueuePtr : UnsafeMutablePointer<dispatch_queue_t?>){
        let block = {
            var d = self._delegate
            if delegatePtr != nil {
                withUnsafeMutablePointer(&d) {
                    delegatePtr = $0
                }
            }
            var dq = self._delegateQueue
            if delegateQueuePtr != nil {
                withUnsafeMutablePointer(&dq) {
                    delegateQueuePtr = $0
                }
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
            
        }
            else {
            dispatch_sync(socketQueue, block)
        }
    }
    func setDelegate(newDelegate : GCDAsyncSocketDelegate?, newDelegateQueue : dispatch_queue_t?, synchronously : Bool ){
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
        }
        else {
            if synchronously {
                dispatch_sync(socketQueue, block)
            }
            else{
                dispatch_async(socketQueue, block)
            }
        }
        
    }
    func setDelegate(newDelegate : GCDAsyncSocketDelegate?, delegateQueue newDelegateQueue : dispatch_queue_t?){
        setDelegate(newDelegate, newDelegateQueue: newDelegateQueue, synchronously: false)
    }
    func synchronouslySetDelegate(newDelegate : GCDAsyncSocketDelegate?, delegateQueue newDelegateQueue : dispatch_queue_t?){
        setDelegate(newDelegate, newDelegateQueue: newDelegateQueue, synchronously: true)
    }
    
    /**
     * By default, both IPv4 and IPv6 are enabled.
     *
     * For accepting incoming connections, this means GCDAsyncSocket automatically supports both protocols,
     * and can simulataneously accept incoming connections on either protocol.
     *
     * For outgoing connections, this means GCDAsyncSocket can connect to remote hosts running either protocol.
     * If a DNS lookup returns only IPv4 results, GCDAsyncSocket will automatically use IPv4.
     * If a DNS lookup returns only IPv6 results, GCDAsyncSocket will automatically use IPv6.
     * If a DNS lookup returns both IPv4 and IPv6 results, the preferred protocol will be chosen.
     * By default, the preferred protocol is IPv4, but may be configured as desired.
     **/
    func isIPv4Enabled() -> Bool {
        var result = false
        // Note: YES means IPv4Disabled is OFF
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            result = !config.contains(.IPv4Disabled)
        }
            else {
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
            }
            else{
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
        }
            else {
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
            }
            else {
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
            }
            else {
                self.config.append(.PreferIPv6)
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_async(socketQueue, block)
        }
    }
    
    /**
     * User data allows you to associate arbitrary information with the socket.
     * This data is not used internally by socket in any way.
     **/
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
    
    init(withDelegate aDelegate : GCDAsyncSocketDelegate?, delegateQueue dq : dispatch_queue_t?, socketQueue aSocketQueue : dispatch_queue_t!) {
        connectInterface4 = NSMutableData()
        connectInterface6 = NSMutableData()
        connectInterfaceUN = NSMutableData()
        
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
        withUnsafeMutablePointer(&selfPtr) {
            dispatch_queue_set_specific(socketQueue, GCDAsyncSocketQueueName, $0, nil);
        }

        preBuffer = GCDAsyncSocketPreBuffer.init(withCapacity: 1024 * 4)
        
    }
    convenience init() {
        self.init(withDelegate:.None, delegateQueue:.None, socketQueue:.None)
    }
    convenience init(withSocketQueue sq: dispatch_queue_t) {
        self.init(withDelegate:.None, delegateQueue:.None, socketQueue:sq)
    }
    convenience init(withDelegate aDelegate : GCDAsyncSocketDelegate, withDelegateQueue dq: dispatch_queue_t) {
        self.init(withDelegate:aDelegate, delegateQueue:dq, socketQueue:.None)
    }
    
    deinit {
        // Set dealloc flag.
        // This is used by closeWithError to ensure we don't accidentally retain ourself.
        flags.append(GCDAsyncSocketFlags.Dealloc)
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            close(withError: nil)
            
        }
        else {
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
    
     /**
     * Tells the socket to begin listening and accepting connections on the given port.
     * When a connection is accepted, a new instance of GCDAsyncSocket will be spawned to handle it,
     * and the socket:didAcceptNewSocket: delegate method will be invoked.
     *
     * The socket will listen on all available interfaces (e.g. wifi, ethernet, etc)
     **/
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
    /**
    * This method is the same as acceptOnPort:error: with the
    * additional option of specifying which interface to listen on.
    *
    * For example, you could specify that the socket should only accept connections over ethernet,
    * and not other interfaces such as wifi.
    *
    * The interface may be specified by name (e.g. "en1" or "lo0") or by IP address (e.g. "192.168.4.34").
    * You may also use the special strings "localhost" or "loopback" to specify that
    * the socket only accept connections from the local machine.
    *
    * You can see the list of interfaces via the command line utility "ifconfig",
    * or programmatically via the getifaddrs() function.
    *
    * To accept connections on any interface pass nil, or simply use the acceptOnPort:error: method.
    **/
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
            try self.setNonBlocking(socket: socketFD)
            try self.setReuseOn(socket: socketFD)
            
            // Bind socket
            
            // Listen
            if listen(socketFD, 1024) == -1 {
                swift_close(socketFD)
                throw GCDAsyncSocketError.PosixError(message: "Error in listen() function")
            }
            
            return socketFD
        }
        
        // Create dispatch block and run on socketQueue
        let block = {
            guard let _ = self._delegate else {
                throw GCDAsyncSocketError.BadConfigError(message: "Attempting to accept without a delegate. Set a delegate first.")
            }
            guard let _ = self._delegateQueue else {
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
                self._socket4FD = try createSocket(AF_INET, interface4)
                if self._socket4FD == SOCKET_NULL {
                    return
                }
            }
            
            if enableIPv6 {
                if enableIPv4 && port == 0 {
                    // No specific port was specified, so we allowed the OS to pick an available port for us.
                    // Now we need to make sure the IPv6 socket listens on the same port as the IPv4 socket.
                    
                    var addr6 : sockaddr_in6 = UnsafePointer<sockaddr_in6>(interface6.mutableBytes).memory
                    addr6.sin6_port = swift_htons(self.localPort4());
                }
                self._socket6FD = try createSocket(AF_INET6, interface6)
                if self._socket6FD == SOCKET_NULL {
                    if self._socket4FD != SOCKET_NULL {
                        swift_close(self._socket4FD)
                        return
                    }
                }
            }
            
            // Create accept sources
            var socketFD = SOCKET_NULL
            var source : dispatch_source_t? = nil
            if enableIPv4 {
                self.accept4Source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(self._socket4FD), 0, self.socketQueue)
                source = self.accept4Source
                socketFD = self._socket4FD
            } else if enableIPv6 {
                self.accept6Source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(self._socket6FD), 0, self.socketQueue)
                source = self.accept6Source
                socketFD = self._socket6FD
            }
            
            
            
            if let acceptSource = source {
                weak var weakSelf = self
                
                dispatch_source_set_event_handler(acceptSource)  {
                    autoreleasepool{
                        guard let strongSelf = weakSelf else {
                            return;
                        }
                        
                        var i : UInt = 0
                        let numPendingConnections = dispatch_source_get_data(acceptSource)
                        while strongSelf.doAccept(socketFD) && (++i < numPendingConnections) {
                            
                        }
                    }
                }
                
                dispatch_source_set_cancel_handler(acceptSource){
                    //always using ARC, don't need this
//                        if !OS_OBJECT_USE_OBJC
//                        dispatch_release(acceptSource);
//                        #endif
                    swift_close(socketFD)
                }
                
                dispatch_resume(acceptSource)
                self.flags.append(.SocketStarted)
            }
            
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            try block()
        }
        else {
            var error : ErrorType? = nil
            dispatch_sync(socketQueue){
                do {
                    try block()
                } catch let e  {
                    error = e
                }
            }
            if let e = error {
                throw e
            }
        }
    }
    /**
     * Tells the socket to begin listening and accepting connections on the unix domain at the given url.
     * When a connection is accepted, a new instance of GCDAsyncSocket will be spawned to handle it,
     * and the socket:didAcceptNewSocket: delegate method will be invoked.
     *
     * The socket will listen on all available interfaces (e.g. wifi, ethernet, etc)
     **/
    func acceptOnUrl(url : NSURL) throws -> Bool {
        return true
    }
    func doAccept(parentSocketFD : Int32) -> Bool {
        
        var socketType = -1
        var childSocketFD = SOCKET_NULL
        var childSocketAddress : NSData? = nil
        
        
        if parentSocketFD == _socket4FD {
            socketType = 0
            var addr4 = sockaddr()
            var addr4Len = socklen_t(sizeofValue(addr4))
            
            childSocketFD = withUnsafeMutablePointer(&addr4){
                accept(parentSocketFD, $0, &addr4Len)
            }
            
            guard childSocketFD != -1 else {
                print("Warning: Accept failed with error \(strerror(errno))")
                return false;
            }
            
            childSocketAddress = NSData.init(bytes: &addr4, length: Int(addr4Len))
        }
        else if parentSocketFD == _socket6FD {
            
            socketType = 1
            var addr6 = sockaddr_in6()
            var addr6Len = socklen_t(sizeofValue(addr6))
            
            childSocketFD = withUnsafeMutablePointer(&addr6){ (addrPtr) -> Int32 in
                withUnsafeMutablePointer(&addr6Len){ (addrLenPtr) -> Int32 in
                    accept(parentSocketFD, UnsafeMutablePointer(addrPtr), UnsafeMutablePointer(addrLenPtr))
                }
            }
            
            guard childSocketFD != -1 else {
                print("Warning: Accept failed with error \(strerror(errno))")
                return false;
            }
            
            childSocketAddress = NSData.init(bytes: &addr6, length: Int(addr6Len))
        }
        else // if (parentSocketFD == socketUN)
        {
            socketType = 2;
            
            var addrUn = sockaddr_un()
            var addrUnLen = socklen_t(sizeofValue(addrUn))
            
            childSocketFD = withUnsafeMutablePointer(&addrUn){ (addrPtr) -> Int32 in
                withUnsafeMutablePointer(&addrUnLen){ (addrLenPtr) -> Int32 in
                    accept(parentSocketFD, UnsafeMutablePointer(addrPtr), UnsafeMutablePointer(addrLenPtr))
                }
            }
            
            guard childSocketFD != -1 else {
                print("Warning: Accept failed with error \(strerror(errno))")
                return false;
            }
            
            childSocketAddress = NSData.init(bytes: &addrUn, length: Int(addrUnLen))
        }
        
        // Enable non-blocking IO on the socket
        do {
            try setNonBlocking(socket: childSocketFD)
        }catch _ {
            print("Warning: Error enabling non-blocking IO on accepted socket (fcntl)")
            return false
        }
        
        // Prevent SIGPIPE signals
        do {
            try setNoSigPipe(socket: childSocketFD)
        }catch _{
            print("Warning: Error setting no sig pipe on accepted socket (fcntl)")
            return false
        }
        
        // Notify delegate
        if let d = _delegate, let dq = _delegateQueue, let csa = childSocketAddress {
            dispatch_async(dq){
                autoreleasepool {
                    // Query delegate for custom socket queue
                    if let childSocketQueue = d.newSocketQueueForConnection(fromAddress:csa, onSocket:self) {
                        let acceptedSocket = GCDAsyncSocket.init(withDelegate: self._delegate, delegateQueue: self._delegateQueue, socketQueue: childSocketQueue)
                        switch socketType {
                        case 0:
                            acceptedSocket._socket4FD = childSocketFD
                        case 1:
                            acceptedSocket._socket6FD = childSocketFD
                        default:
                            acceptedSocket.socketUN = childSocketFD
                        }
                        acceptedSocket.flags.append(.Connected)
                        
                        // Setup read and write sources for accepted socket
                        
                        dispatch_async(acceptedSocket.socketQueue){
                            acceptedSocket.setupReadAndWriteSourcesForNewlyConnectedSocket(childSocketFD)
                        }
                        
                        // Notify delegate
                        d.socket(self, didAcceptNewSocket: acceptedSocket)

                        //always using ARC, don't need this
//                        // Release the socket queue returned from the delegate (it was retained by acceptedSocket)
//                        #if !OS_OBJECT_USE_OBJC
//                            if (childSocketQueue) dispatch_release(childSocketQueue);
//                        #endif
                        
                        // The accepted socket should have been retained by the delegate.
                        // Otherwise it gets properly released when exiting the block.
                    }
                }
            }
        }
        return true
    }
    
     /***********************************************************/
     // MARK: Connecting
     /***********************************************************/
     /**
     * This method runs through the various checks required prior to a connection attempt.
     * It is shared between the connectToHost and connectToAddress methods.
     * 
     **/
    func preConnectWithInterface(interface:String) throws -> Bool {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        
        if delegate == nil {
            throw GCDAsyncSocketError.BadConfigError(message: "Attempting to connect without a delegate. Set a delegate first.")
        }
        
        if delegateQueue == nil {
            throw GCDAsyncSocketError.BadConfigError(message: "Attempting to connect without a delegate queue. Set a delegate queue first.")
        }
        
        if !isDisconnected() {
            throw GCDAsyncSocketError.BadConfigError(message: "Attempting to connect while connected or accepting connections. Disconnect first.")
        }
        
        let isIPv4Disabled = config.contains(.IPv4Disabled)
        let isIPv6Disabled = config.contains(.IPv6Disabled)
        
        if isIPv4Disabled && isIPv6Disabled {
            throw GCDAsyncSocketError.BadConfigError(message: "Both IPv4 and IPv6 have been disabled. Must enable at least one protocol first.")
        }
        
//        if interface?.characters.count > 0, let iface = interface {
            var interface4 = NSMutableData()
            var interface6 = NSMutableData()
            
            getInterfaceAddress4(&interface4, address6: &interface6, fromDescription:interface, port: 0)
            if interface4.length == 0 && interface6.length == 0 {
                throw GCDAsyncSocketError.BadParamError(message: "Unknown interface. Specify valid interface by name (e.g. \"en1\") or IP address.")
            }
            if isIPv4Disabled && interface6.length == 0 {
                throw GCDAsyncSocketError.BadParamError(message: "IPv4 has been disabled and specified interface doesn't support IPv6.")
            }
            if isIPv6Disabled && interface4.length == 0 {
                throw GCDAsyncSocketError.BadParamError(message: "IPv6 has been disabled and specified interface doesn't support IPv4")
            }
            
            connectInterface4 = interface4
            connectInterface6 = interface6
            return true
//        }
        
    }
    func preConnectWithUrl(url:NSURL) throws {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        
        if delegate == nil {
            throw GCDAsyncSocketError.BadConfigError(message: "Attempting to connect without a delegate. Set a delegate first.")
        }
        if delegateQueue == nil {
            throw GCDAsyncSocketError.BadConfigError(message: "Attempting to connect without a delegate queue. Set a delegate queue first.")
        }
        guard let interface = getInterfaceAddressFromUrl(url) else {
            throw GCDAsyncSocketError.BadConfigError(message: "Unknown interface. Specify valid interface by name (e.g. \"en1\") or IP address.")
        }
        connectInterfaceUN = interface
        
        // Clear queues (spurious read/write requests post disconnect)
        readQueue.removeAll()
        writeQueue.removeAll()
    }
    /**
     * Connects to the given host and port.
     *
     * This method invokes connectToHost:onPort:viaInterface:withTimeout:error:
     * and uses the default interface, and no timeout.
     **/
    func connectToHost(host:String, onPort port:UInt16) throws {
        return try connectToHost(host, onPort: port, withTimeout: -1)
    }
    /**
     * Connects to the given host and port with an optional timeout.
     *
     * This method invokes connectToHost:onPort:viaInterface:withTimeout:error: and uses the default interface.
     **/
    func connectToHost(host:String, onPort port:UInt16, withTimeout timeout:NSTimeInterval) throws {
        try connectToHost(host, onPort: port, viaInterface:"", withTimeout: timeout)
    }
    /**
     * Connects to the given host & port, via the optional interface, with an optional timeout.
     *
     * The host may be a domain name (e.g. "deusty.com") or an IP address string (e.g. "192.168.0.2").
     * The host may also be the special strings "localhost" or "loopback" to specify connecting
     * to a service on the local machine.
     *
     * The interface may be a name (e.g. "en1" or "lo0") or the corresponding IP address (e.g. "192.168.4.35").
     * The interface may also be used to specify the local port (see below).
     *
     * To not time out use a negative time interval.
     *
     * This method will return NO if an error is detected, and set the error pointer (if one was given).
     * Possible errors would be a nil host, invalid interface, or socket is already connected.
     *
     * If no errors are detected, this method will start a background connect operation and immediately return YES.
     * The delegate callbacks are used to notify you when the socket connects, or if the host was unreachable.
     *
     * Since this class supports queued reads and writes, you can immediately start reading and/or writing.
     * All read/write operations will be queued, and upon socket connection,
     * the operations will be dequeued and processed in order.
     *
     * The interface may optionally contain a port number at the end of the string, separated by a colon.
     * This allows you to specify the local port that should be used for the outgoing connection. (read paragraph to end)
     * To specify both interface and local port: "en1:8082" or "192.168.4.35:2424".
     * To specify only local port: ":8082".
     * Please note this is an advanced feature, and is somewhat hidden on purpose.
     * You should understand that 99.999% of the time you should NOT specify the local port for an outgoing connection.
     * If you think you need to, there is a very good chance you have a fundamental misunderstanding somewhere.
     * Local ports do NOT need to match remote ports. In fact, they almost never do.
     * This feature is here for networking professionals using very advanced techniques.
     **/
    func connectToHost(host:String, onPort port:UInt16, viaInterface interface:String, withTimeout timeout:NSTimeInterval) throws {
        print("connectToHost:onPort:viaInterface:withTimeout")
        var error : ErrorType? = nil
        // Just in case immutable objects were passed
        let block = {
            autoreleasepool {
                do {
                    // Check for problems with host parameter
                    guard host.characters.count > 0 else {
                        GCDAsyncSocketError.BadParamError(message: "Invalid host parameter (nil or \"\"). Should be a domain name or IP address string.")
                        return
                    }
                    // Run through standard pre-connect checks
                    guard try self.preConnectWithInterface(interface) else {
                        return
                    }
                    
                    // We've made it past all the checks.
                    // It's time to start the connection process.
                    self.flags.append(.SocketStarted)
                    
                    print("Dispatching DNS lookup...")
                    
                    
                    //---From what I can tell, you don't have to worry about this with Swift
                    // It's possible that the given host parameter is actually a NSMutableString.
                    // So we want to copy it now, within this block that will be executed synchronously.
                    // This way the asynchronous lookup block below doesn't have to worry about it changing.
                    let aStateIndex = self.stateIndex
                    weak var weakSelf = self
                    let globalConcurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                    dispatch_async(globalConcurrentQueue, {
                        do {
                            let addresses = try GCDAsyncSocket.lookupHost(host, port: port)
                            guard let strongSelf = weakSelf else {
                                return
                            }
                            var address4 : NSData?
                            var address6 : NSData?
                            for address in addresses {
                                if address4 == nil && GCDAsyncSocket.isIPv4Address(address) {
                                    address4 = address
                                }
                                else if address6 == nil && GCDAsyncSocket.isIPv6Address(address) {
                                    address6 = address
                                }
                            }
                            
                            dispatch_async(strongSelf.socketQueue, {
                                strongSelf.lookupDidSucceed(aStateIndex, withAddress4:address4, address6:address6)
                            })
                            
                        }catch let lookupError {
                            autoreleasepool {
                                if let strongSelf = weakSelf {
                                    strongSelf.lookupDidFail(aStateIndex, withError:lookupError)
                                }
                            }
                        }
                    })
                    self.startConnectTimeout(timeout)
                } catch let e {
                    error = e
                }
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        if let err = error {
            throw err
        }
    }
    /**
     * Connects to the given address, specified as a sockaddr structure wrapped in a NSData object.
     * For example, a NSData object returned from NSNetService's addresses method.
     *
     * If you have an existing struct sockaddr you can convert it to a NSData object like so:
     * struct sockaddr sa  -> NSData *dsa = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sa_len];
     * struct sockaddr *sa -> NSData *dsa = [NSData dataWithBytes:remoteAddr length:remoteAddr->sa_len];
     *
     * This method invokes connectToAdd
     **/
    func connectToAddress(remoteAddr:NSData) throws {
        try connectToAddress(remoteAddr, viaInterace:"", withTimeout:-1)
    }
    /**
     * This method is the same as connectToAddress:error: with an additional timeout option.
     * To not time out use a negative time interval, or simply use the connectToAddress:error: method.
     **/
    func connectToAddress(remoteAddr:NSData, withTimeout timeout:NSTimeInterval) throws {
        try connectToAddress(remoteAddr, viaInterace:"", withTimeout:timeout)
    }
    /**
     * Connects to the given address, using the specified interface and timeout.
     *
     * The address is specified as a sockaddr structure wrapped in a NSData object.
     * For example, a NSData object returned from NSNetService's addresses method.
     *
     * If you have an existing struct sockaddr you can convert it to a NSData object like so:
     * struct sockaddr sa  -> NSData *dsa = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sa_len];
     * struct sockaddr *sa -> NSData *dsa = [NSData dataWithBytes:remoteAddr length:remoteAddr->sa_len];
     *
     * The interface may be a name (e.g. "en1" or "lo0") or the corresponding IP address (e.g. "192.168.4.35").
     * The interface may also be used to specify the local port (see below).
     *
     * The timeout is optional. To not time out use a negative time interval.
     *
     * This method will return NO if an error is detected, and set the error pointer (if one was given).
     * Possible errors would be a nil host, invalid interface, or socket is already connected.
     *
     * If no errors are detected, this method will start a background connect operation and immediately return YES.
     * The delegate callbacks are used to notify you when the socket connects, or if the host was unreachable.
     *
     * Since this class supports queued reads and writes, you can immediately start reading and/or writing.
     * All read/write operations will be queued, and upon socket connection,
     * the operations will be dequeued and processed in order.
     *
     * The interface may optionally contain a port number at the end of the string, separated by a colon.
     * This allows you to specify the local port that should be used for the outgoing connection. (read paragraph to end)
     * To specify both interface and local port: "en1:8082" or "192.168.4.35:2424".
     * To specify only local port: ":8082".
     * Please note this is an advanced feature, and is somewhat hidden on purpose.
     * You should understand that 99.999% of the time you should NOT specify the local port for an outgoing connection.
     * If you think you need to, there is a very good chance you have a fundamental misunderstanding somewhere.
     * Local ports do NOT need to match remote ports. In fact, they almost never do.
     * This feature is here for networking professionals using very advanced techniques.
     **/
    func connectToAddress(remoteAddr:NSData, viaInterace interface:String, withTimeout timeout:NSTimeInterval) throws {
        
        var error : ErrorType? = nil
        let block = {
            autoreleasepool {
                // Check for problems with remoteAddr parameter
                var address4 : NSData?
                var address6 : NSData?
                if remoteAddr.length >= sizeof(sockaddr) {
                    let socketaddr = sockaddr(remoteAddr.bytes.memory)
                    switch socketaddr.sa_family {
                    case sa_family_t(AF_INET) where remoteAddr.length == sizeof(sockaddr_in):
                        address4 = remoteAddr
                        break
                    case sa_family_t(AF_INET6) where remoteAddr.length == sizeof(sockaddr_in6):
                        address6 = remoteAddr
                        break
                    default:
                        error = GCDAsyncSocketError.BadParamError(message: "A valid IPv4 or IPv6 address was not given")
                        return
                    }
                }
                
                let isIPv4Disabled = self.config.contains(.IPv4Disabled)
                let isIPv6Disabled = self.config.contains(.IPv6Disabled)
                
                if isIPv4Disabled && address4 != nil {
                    error = GCDAsyncSocketError.BadParamError(message: "IPv4 has been disabled and an IPv4 address was passed.")
                    return
                }
                if isIPv6Disabled && address6 != nil {
                    error = GCDAsyncSocketError.BadParamError(message: "IPv6 has been disabled and an IPv6 address was passed.")
                    return
                }
                
                
                do {
                    // Run through standard pre-connect checks
                    try self.preConnectWithInterface(interface)
                    
                    // We've made it past all the checks.
                    // It's time to start the connection process.
                    try self.connectWithAddress4(address4, address6: address6)
                    
                    self.flags.append(.SocketStarted)
                    
                    self.startConnectTimeout(timeout)
                    
                }catch let e {
                    error = e
                }
            }
        }
        
        if let err = error {
            throw err
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
            else{
            dispatch_sync(socketQueue, block)
        }
    }
    /**
     * Connects to the unix domain socket at the given url, using the specified timeout.
     */
    func connectToUrl(url:NSURL, withTimeout timeout:NSTimeInterval) throws {
        var error : ErrorType? = nil
        let block : dispatch_block_t = {
            autoreleasepool {
                do {
                    // Check for problems with host parameter
                    if url.path?.characters.count == 0 {
                        throw GCDAsyncSocketError.BadParamError(message: "Invalid unix domain socket url.")
                    }
                    
                    // Run through standard pre-connect checks
                    try self.preConnectWithUrl(url)
                    
                    // We've made it past all the checks.
                    // It's time to start the connection process.
                    self.flags.append(.SocketStarted)
                    
                    // Start the normal connection process
                    self.startConnectTimeout(timeout)
                    
                }catch let e {
                    error = e
                }
            }
        }
        if let err = error {
            throw err
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
            else{
            dispatch_sync(socketQueue, block)
        }
    }
    func lookupDidSucceed(aStateIndex:Int, withAddress4 address4:NSData?, address6:NSData?) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        assert(address4 == nil && address6 == nil, "Expected at least one valid address")
        if aStateIndex != self.stateIndex {
            // The connect operation has been cancelled.
            // That is, socket was disconnected, or connection has already timed out.
            print("Ignoring lookupDidSucceed, already disconnected")
            return
        }
        // Check for problems
        let isIPv4Disabled = config.contains(.IPv4Disabled)
        let isIPv6Disabled = config.contains(.IPv6Disabled)
        if isIPv4Disabled && address6 == nil {
            close(withError: GCDAsyncSocketError.OtherError(message: 
                "IPv4 has been disabled and DNS lookup found no IPv6 address."))
            return
        }
        if isIPv6Disabled && address4 == nil {
            close(withError: GCDAsyncSocketError.OtherError(message:
                "IPv4 has been disabled and DNS lookup found no IPv6 address."))
            return
        }
        // Start the normal connection process
        do {
            try connectWithAddress4(address4, address6: address6)
        }catch let e {
            close(withError:e)
        }
    }
    /**
     * This method is called if the DNS lookup fails.
     * This method is executed on the socketQueue.
     *
     * Since the DNS lookup executed synchronously on a global concurrent queue,
     * the original connection request may have already been cancelled or timed-out by the time this method is invoked.
     * The lookupIndex tells us whether the lookup is still valid or not.
     **/
    func lookupDidFail(aStateIndex:Int, withError error:ErrorType) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) == nil, "Must be dispatched on socketQueue")
        
        if aStateIndex != self.stateIndex {
            print("Ignoring lookup:didFail: - already disconnected")
            // The connect operation has been cancelled.
            // That is, socket was disconnected, or connection has already timed out.
            return;
        }
        self.endConnectTimeout()
        self.close(withError: error)
    }
    func connectWithAddress4(address4:NSData?, address6:NSData?) throws {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) == nil, "Must be dispatched on socketQueue")
        
        print("Verbose: IPv4: \(self.dynamicType.hostFromAddress(address4))")
        print("Verbose: IPv6: \(self.dynamicType.hostFromAddress(address6))")
        
        // Determine socket type
        let preferIPv6 = config.contains(.PreferIPv6)
        let useIPv6 = ((preferIPv6 && address6 != nil) || (address4 == nil))
        
        // Create the socket
        var socketFD = SOCKET_NULL
        var address:NSData? = nil
        var connectInterface:NSData? = nil
        if useIPv6 {
            print("Verbose: Creating IPv6 socket")
            _socket6FD = socket(AF_INET6, SOCK_STREAM, 0)
            socketFD = _socket6FD
            address = address6
            connectInterface = connectInterface6
        }
        else {
            print("Verbose: Creating IPv4 socket")
            _socket4FD = socket(AF_INET, SOCK_STREAM, 0)
            socketFD = _socket4FD
            address = address4
            connectInterface = connectInterface4
        }
        guard socketFD != SOCKET_NULL else {
            throw GCDAsyncSocketError.PosixError(message: "Error in socket() function")
        }
        guard let connInterace = connectInterface else {
            throw GCDAsyncSocketError.BadParamError(message: "Connection interface not set.")
        }
        guard let addr = address else {
            throw GCDAsyncSocketError.BadParamError(message: "Socket address not set.")
        }
        
        // Bind the socket to the desired interface (if needed)
        if let connInterface = connectInterface {
            print("Verbose: Binding socket...")
            if self.dynamicType.portFromAddress(connInterface) > 0 {
                // Since we're going to be binding to a specific port,
                // we should turn on reuseaddr to allow us to override sockets in time_wait.
                try setReuseOn(socket: socketFD)
            }
        }
        var interfaceAddr = sockaddr(connInterace.bytes.memory)
        let interfaceSize = socklen_t(sizeofValue(interfaceAddr))
        try withUnsafePointer(&interfaceAddr){
            let bindResult = bind(socketFD, $0, interfaceSize)
            guard bindResult == 0 else {
                throw GCDAsyncSocketError.PosixError(message: "Error in bind() function #\(bindResult)")
            }
        }
        
        // Prevent SIGPIPE signals
        try setNoSigPipe(socket: socketFD)
        
        // Start the connection process in a background queue
        try connectOnBackground(usingSocket:socketFD, address:addr)
    }
    func connectOnBackground(usingSocket socketFD:Int32, address:NSData) throws {
        let aStateIndex = self.stateIndex
        let globalConcurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(globalConcurrentQueue, {
            [weak self] in
            var sockAddr = sockaddr(address.bytes.memory)
            let sockAddrSize = socklen_t(sizeofValue(sockAddr))
            withUnsafePointer(&sockAddr){
                let connectResult = connect(socketFD, $0, sockAddrSize)
                guard connectResult == 0 else {
                    let error = GCDAsyncSocketError.PosixError(message: "Error in connect() function #\(connectResult)")
                    if let socketQueue = self?.socketQueue {
                        dispatch_async(socketQueue, {
                            autoreleasepool {
                                self?.didNotConnect(aStateIndex, withError: error)
                            }
                        })
                    }
                    return;
                }
                if self != nil {
                    self?.didConnect(aStateIndex)
                }
                
            }
            })
        print("Verbose: Connecting...");
    }
    func connectWithAddressUN(address:NSData?) throws {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        
        print("Verbose: Creating unix domain socket")
        
        // Create the socket
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD != SOCKET_NULL else {
            throw GCDAsyncSocketError.PosixError(message: "Error in socket() function")
        }
        socketUN = socketFD
        guard let addr = address else {
            throw GCDAsyncSocketError.BadParamError(message: "Socket address not set.")
        }
        
        // Bind the socket to the desired interface (if needed)
        print("Binding socket...")
        try setReuseOn(socket: socketUN)
        try setNoSigPipe(socket: socketUN)
        
        // Start the connection process in a background queue
        try connectOnBackground(usingSocket:socketFD, address:addr)
        
        
        print("Connecting...")
    }
    func didConnect(aStateIndex:Int) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        
        if aStateIndex != self.stateIndex {
            print("Info: Ignoring didConnect, already disconnected")
            // The connect operation has been cancelled.
            // That is, socket was disconnected, or connection has already timed out.
            return;
        }
        
        flags.append(.Connected)
        endConnectTimeout()
        #if iOS
            // The endConnectTimeout method executed above incremented the aStateIndex.
            aStateIndex = self.stateIndex;
        #endif
        
        // Setup read/write streams (as workaround for specific shortcomings in the iOS platform)
        //
        // Note:
        // There may be configuration options that must be set by the delegate before opening the streams.
        // The primary example is the kCFStreamNetworkServiceTypeVoIP flag, which only works on an unopened stream.
        //
        // Thus we wait until after the socket:didConnectToHost:port: delegate method has completed.
        // This gives the delegate time to properly configure the streams if needed.
        #if TARGET_OS_IPHONE
        let SetupStreamsPart1 = {
                guard self.createReadAndWriteStream() else {
                    self.close(withError: GCDAsyncSocketError.OtherError(message: "Error creating CFStreams"))
                    return;
                }
                guard self.registerForStreamCallbacks(includingReadWrite:false) else {
                    self.close(withError: GCDAsyncSocketError.OtherError(message: "Error in CFStreamSetClient"))
                    return;
                }
        }
        let SetupStreamsPart2 = {
            
            guard aStateIndex == self.stateIndex else {
                // The socket has been disconnected.
                return;
            }
            guard self.addStreamsToRunLoop() else {
                self.close(withError: GCDAsyncSocketError.OtherError(message: "Error in CFStreamScheduleWithRunLoop"))
                return;
            }
            guard self.openStreams() else {
                self.close(withError: GCDAsyncSocketError.OtherError(message: "Error creating CFStreams"))
                return;
            }

        }
        #endif
        
        // Notify delegate
        if let aDelegateQueue = self.delegateQueue, let theDelegate = self.delegate {
            if let host = connectedHost() {
                #if iOS
                    SetupStreamsPart1()
                #endif
                dispatch_async(aDelegateQueue) {
                    autoreleasepool {
                        theDelegate.socket(self, didConnectToHost:host, port:self.connectedPort())
                        #if iOS
                            dispatch_async(aDelegateQueue){
                                autoreleasepool{
                                    SetupStreamsPart2()
                                }
                            }
                        #endif
                    }
                }
            } else if let url = self.connectedUrl() {
                #if iOS
                    SetupStreamsPart1()
                #endif
                dispatch_async(aDelegateQueue) {
                    autoreleasepool {
                        theDelegate.socket(self, didConnectToUrl:url)
                        #if iOS
                            dispatch_async(aDelegateQueue){
                                autoreleasepool{
                                    SetupStreamsPart2()
                                }
                            }
                        #endif
                    }
                }
            }
        }
        else {
            #if iOS
                SetupStreamsPart1()
                SetupStreamsPart2()
            #endif
        }
        
        // Get the connected socket
        let socketFD = (_socket4FD != SOCKET_NULL) ? _socket4FD : (_socket6FD != SOCKET_NULL) ? _socket6FD : socketUN
        // Enable non-blocking IO on the socket
        do {
            try setNonBlocking(socket: socketFD)
        } catch let e{
            close(withError:e)
            return
        }
        
        // Setup our read/write sources
        setupReadAndWriteSourcesForNewlyConnectedSocket(socketFD)
        // Dequeue any pending read/write requests
        maybeDequeueRead()
        maybeDequeueWrite()
    }
    func didNotConnect(aStateIndex:Int, withError error:ErrorType?) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        if aStateIndex != self.stateIndex {
            print("Info: Ignoring didNotConnect, already disconnected")
            // The connect operation has been cancelled.
            // That is, socket was disconnected, or connection has already timed out.
            return;
        }
        close(withError: error)
    }
    func startConnectTimeout(timeout:NSTimeInterval) {
        if timeout < 0.0 {
            return
        }
        if let connectTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, socketQueue) {
            dispatch_source_set_event_handler(connectTimer){
                [weak self] in
                guard self != nil else {
                    return
                }
                self?.doConnectTimeout()
            }
            //always using ARC, don't need this
//            #if !OS_OBJECT_USE_OBJC
//                dispatch_source_t theConnectTimer = connectTimer;
//                dispatch_source_set_cancel_handler(connectTimer, ^{
//                    #pragma clang diagnostic push
//                    #pragma clang diagnostic warning "-Wimplicit-retain-self"
//                    
//                    LogVerbose(@"dispatch_release(connectTimer)");
//                    dispatch_release(theConnectTimer);
//                    
//                    #pragma clang diagnostic pop
//                    });
//            #endif
            let tt = dispatch_time(DISPATCH_TIME_NOW, Int64(timeout)*Int64(NSEC_PER_SEC))
            dispatch_source_set_timer(connectTimer, tt, DISPATCH_TIME_FOREVER, 0);
            dispatch_resume(connectTimer)
        }
    }
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
            connectInterface4 = nil
        }
        if connectInterface6 != nil {
            connectInterface6 = nil
        }
    }
    func doConnectTimeout() {
        endConnectTimeout()
        close(withError:GCDAsyncSocketError.TimeoutError())
    }
    func setNonBlocking(socket socketFD:Int32) throws {
        if swift_fcntl(socketFD, F_SETFL, O_NONBLOCK) == -1 {
            swift_close(socketFD)
            throw GCDAsyncSocketError.PosixError(message: "Error enabling non-blocking IO on socket (fcntl)")
        }
    }
    func setNoSigPipe(socket socketFD:Int32) throws {
//        var nosigpipe = 1
//        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(sizeofValue(nosigpipe)))
        var noSigPipe:CInt = 1
        try withUnsafePointer(&noSigPipe) {
            let setSockOptResult = setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(sizeofValue(noSigPipe)));
            guard setSockOptResult == 0 else {
                throw GCDAsyncSocketError.PosixError(message: "Error in setsockopt() #\(setSockOptResult)")
            }
        }
    }
    func setReuseOn(socket socketFD:Int32) throws {
//        var reuseOn = 1
//        if setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseOn, socklen_t(sizeofValue(reuseOn))) == -1 {
//            swift_close(socketFD)
//            throw GCDAsyncSocketError.PosixError(message: "Error enabling address reuse (setsockopt)")
//        }
        var reuseOn:CInt = 1
        try withUnsafePointer(&reuseOn) {
            let setSockOptResult = setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(sizeofValue(reuseOn)));
            guard setSockOptResult == 0 else {
                throw GCDAsyncSocketError.PosixError(message: "Error in setsockopt() #\(setSockOptResult)")
            }
        }
    }
    
    
     /***********************************************************/
     // MARK: Disconnecting
     /***********************************************************/
    func close(withError error:ErrorType?) {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil, "Must be dispatched on socketQueue")
        endConnectTimeout()
        if currentRead != nil {
            endCurrentRead()
        }
        if currentWrite != nil {
            endCurrentWrite()
        }
        readQueue.removeAll()
        writeQueue.removeAll()
        if let thePreBuffer = self.preBuffer {
            thePreBuffer.reset()
        }
        #if iOS
            if readStream != nil || writeStream != nil {
                removeStreamsFromRunLoop()
                if let theReadStream = readStream {
                    CFReadStreamSetClient(theReadStream, CFStreamEventType.None.rawValue, nil, nil)
                    CFReadStreamClose(theReadStream)
//                    CFRelease(theReadStream)
                    readStream = nil
                }
                if let theWriteStream = writeStream {
                    CFWriteStreamSetClient(theWriteStream, CFStreamEventType.None.rawValue, nil, nil)
                    CFWriteStreamClose(theWriteStream)
//                    CFRelease(theWriteStream)
                    writeStream = nil
                }
            }
        #endif
        
        if let theSslPrebuffer = sslPreBuffer {
            theSslPrebuffer.reset()
            sslErrCode = noErr
            lastSSLHandshakeError = noErr
        }
        if let theSslContext = sslContext() {
            // Getting a linker error here about the SSLx() functions?
            // You need to add the Security Framework to your application.
            SSLClose(theSslContext)
//            CFRelease(sslContext);
            _sslContext = nil
        }
        
        
        // For some crazy reason (in my opinion), cancelling a dispatch source doesn't
        // invoke the cancel handler if the dispatch source is paused.
        // So we have to unpause the source if needed.
        // This allows the cancel handler to be run, which in turn releases the source and closes the socket.
        if accept4Source != nil && accept6Source != nil && acceptUNSource != nil && readSource != nil && writeSource != nil {
            print("Verbose: manually closing close")
            
            if _socket4FD != SOCKET_NULL {
                print("Verbose: close(socket4FD)")
                swift_close(_socket4FD)
                _socket4FD = SOCKET_NULL
            }
            if _socket6FD != SOCKET_NULL {
                print("Verbose: close(socket6FD)")
                swift_close(_socket6FD)
                _socket6FD = SOCKET_NULL
            }
            if socketUN != SOCKET_NULL {
                print("Verbose: close(socketUN)")
                swift_close(socketUN)
                socketUN = SOCKET_NULL
                if let url = socketUrl {
                    unlink(url.fileSystemRepresentation)
                    socketUrl = nil
                }
            }
        }
        else {
            if let theAccept4Source = accept4Source {
                print("Verbose: dispatch_source_cancel(accept4Source)")
                dispatch_source_cancel(theAccept4Source)
                // We never suspend accept4Source
                accept4Source = nil;
            }
            if let theAccept6Source = accept6Source {
                print("Verbose: dispatch_source_cancel(accept6Source)")
                dispatch_source_cancel(theAccept6Source)
                // We never suspend accept6Source
                accept6Source = nil;
            }
            if let theAcceptUNSource = acceptUNSource {
                print("Verbose: dispatch_source_cancel(acceptUNSource)")
                dispatch_source_cancel(theAcceptUNSource)
                // We never suspend acceptUNSource
                accept4Source = nil;
            }
            if let theReadSource = readSource {
                print("Verbose: dispatch_source_cancel(readSource)")
                dispatch_source_cancel(theReadSource)
                resumeReadSource()
                readSource = nil
            }
            if let theWriteSource = writeSource {
                print("Verbose: dispatch_source_cancel(writeSource)")
                dispatch_source_cancel(theWriteSource)
                resumeWriteSource()
                writeSource = nil
            }
            // The sockets will be closed by the cancel handlers of the corresponding source
            _socket4FD = SOCKET_NULL
            _socket6FD = SOCKET_NULL
            socketUN = SOCKET_NULL
        }
        // If the client has passed the connect/accept method, then the connection has at least begun.
        // Notify delegate that it is now ending.
        let shouldCallDelegate = flags.contains(.SocketStarted)
        let isDeallocating = flags.contains(.Dealloc)
        
        // Clear stored socket info and all flags (config remains as is)
        socketFDBytesAvailable = 0
        flags.removeAll()
        sslWriteCachedLength = 0
        
        if shouldCallDelegate {
            var theSelf: GCDAsyncSocket? = nil
            if !isDeallocating {
                theSelf = self
            }
            if let theDelegateQueue = delegateQueue, let theDelegate = delegate {
                dispatch_async(theDelegateQueue){
                    autoreleasepool {
                        theDelegate.socketDidDisconnect(theSelf, withError: error)
                    }
                }
            }
        }
    }
    /**
     * Disconnects immediately (synchronously). Any pending reads or writes are dropped.
     *
     * If the socket is not already disconnected, an invocation to the socketDidDisconnect:withError: delegate method
     * will be queued onto the delegateQueue asynchronously (behind any previously queued delegate methods).
     * In other words, the disconnected delegate method will be invoked sometime shortly after this method returns.
     *
     * Please note the recommended way of releasing a GCDAsyncSocket instance (e.g. in a dealloc method)
     * [asyncSocket setDelegate:nil];
     * [asyncSocket disconnect];
     * [asyncSocket release];
     *
     * If you plan on disconnecting the socket, and then immediately asking it to connect again,
     * you'll likely want to do so like this:
     * [asyncSocket setDelegate:nil];
     * [asyncSocket disconnect];
     * [asyncSocket setDelegate:self];
     * [asyncSocket connect...];
     **/
    func disconnect() {
        let block = {
            autoreleasepool {
                if self.flags.contains(.SocketStarted) {
                    self.close(withError: nil)
                }
            }
        }
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
            else{
            dispatch_sync(socketQueue, block)
        }
    }
    /**
     * Disconnects after all pending reads have completed.
     * After calling this, the read and write methods will do nothing.
     * The socket will disconnect even if there are still pending writes.
     **/
    func disconnectAfterReading() {
        dispatch_async(socketQueue){
            autoreleasepool{
                if self.flags.contains(.SocketStarted) {
                    self.flags.append(.ForbidReadsWrites)
                    self.flags.append(.DisconnectAfterReads)
                    self.maybeClose()
                }
            }
        }
    }
    /**
     * Disconnects after all pending writes have completed.
     * After calling this, the read and write methods will do nothing.
     * The socket will disconnect even if there are still pending reads.
     **/
    func disconnectAfterWriting() {
        dispatch_async(socketQueue){
            autoreleasepool{
                if self.flags.contains(.SocketStarted) {
                    self.flags.append(.ForbidReadsWrites)
                    self.flags.append(.DisconnectAfterWrites)
                    self.maybeClose()
                }
            }
        }
    }
    /**
     * Disconnects after all pending reads and writes have completed.
     * After calling this, the read and write methods will do nothing.
     **/
    func disconnectAfterReadingAndWriting() {
        dispatch_async(socketQueue){
            autoreleasepool{
                if self.flags.contains(.SocketStarted) {
                    self.flags.append(.ForbidReadsWrites)
                    self.flags.append(.DisconnectAfterReads)
                    self.flags.append(.DisconnectAfterWrites)
                    self.maybeClose()
                }
            }
        }
    }
    /**
     * Closes the socket if possible.
     * That is, if all writes have completed, and we're set to disconnect after writing,
     * or if all reads have completed, and we're set to disconnect after reading.
     **/
    func maybeClose() {
        assert(dispatch_get_specific(GCDAsyncSocketQueueName) != nil)
        var shouldClose = false
        if flags.contains(.DisconnectAfterReads) {
            if readQueue.count == 0 && currentRead == nil {
                if flags.contains(.DisconnectAfterWrites) {
                    if writeQueue.count == 0 && currentWrite == nil {
                        shouldClose = true
                    }
                }
                else{
                    shouldClose = true
                }
            }
        }
        else if flags.contains(.DisconnectAfterWrites) {
            if writeQueue.count == 0 && currentWrite == nil {
                shouldClose = true
            }
        }
        
        if shouldClose {
            close(withError: nil)
        }
    }

    
     /***********************************************************/
     // MARK: Diagnostics
     /***********************************************************/
     /**
     * Returns whether the socket is disconnected or connected.
     *
     * A disconnected socket may be recycled.
     * That is, it can used again for connecting or listening.
     *
     * If a socket is in the process of connecting, it may be neither disconnected nor connected.
     **/
    func isDisconnected() -> Bool {
        var result = false
        
        let block = {
            result = self.flags.contains(.SocketStarted)
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    func isConnected() -> Bool {
        var result = false
        
        let block = {
            result = self.flags.contains(.Connected)
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    
    /**
     * Returns the local or remote host and port to which this socket is connected, or nil and 0 if not connected.
     * The host will be an IP address.
     **/
    func connectedHost() -> String? {
        var result : String? = nil
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                result = self.connectedHostFromSocket4(self._socket4FD)
            }
            if self._socket6FD != SOCKET_NULL {
                result = self.connectedHostFromSocket6(self._socket6FD)
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue) {
                autoreleasepool {
                    block()
                }
            }
        }
        
        return result
    }
    func connectedPort() -> UInt16 {
        var result:UInt16 = 0
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                result = self.connectedPortFromSocket4(self._socket4FD)
            }
            if self._socket6FD != SOCKET_NULL {
                result = self.connectedPortFromSocket6(self._socket6FD)
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue) {
                autoreleasepool {
                    block()
                }
            }
        }
        
        return result
    }
    func connectedUrl() -> NSURL? {
        var result:NSURL? = nil
        
        let block = {
            if self.socketUN != SOCKET_NULL {
                result = self.connectedUrlFromSocketUN(self.socketUN)
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue) {
                autoreleasepool {
                    block()
                }
            }
        }
        
        return result
    }
    func localHost() -> String? {
        var result:String? = nil
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                result = self.localHostFromSocket4(self._socket4FD)
            }
            if self._socket6FD != SOCKET_NULL {
                result = self.localHostFromSocket6(self._socket6FD)
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue) {
                autoreleasepool {
                    block()
                }
            }
        }
        
        return result
    }
    func localPort() -> UInt16 {
        var result:UInt16 = 0
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                result = self.localPortFromSocket4(self._socket4FD)
            }
            if self._socket6FD != SOCKET_NULL {
                result = self.localPortFromSocket6(self._socket6FD)
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            // No need for autorelease pool
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    func connectedHost4() -> String? {
        guard _socket4FD != SOCKET_NULL else {
            return nil
        }
        return connectedHostFromSocket4(_socket4FD)
    }
    func connectedHost6() -> String? {
        guard _socket6FD != SOCKET_NULL else {
            return nil
        }
        return connectedHostFromSocket6(_socket6FD)

    }
    func connectedPort4() -> UInt16 {
        guard _socket4FD != SOCKET_NULL else {
            return 0
        }
        return connectedPortFromSocket4(_socket4FD)
    }
    func connectedPort6() -> UInt16 {
        guard _socket6FD != SOCKET_NULL else {
            return 0
        }
        return connectedPortFromSocket6(_socket6FD)
    }
    func localHost4() -> String? {
        guard _socket4FD != SOCKET_NULL else {
            return nil
        }
        return localHostFromSocket4(_socket4FD)
    }
    func localHost6() -> String? {
        guard _socket6FD != SOCKET_NULL else {
            return nil
        }
        return localHostFromSocket6(_socket6FD)
    }
    func localPort4() -> UInt16 {
        guard _socket4FD != SOCKET_NULL else {
            return 0
        }
        return localPortFromSocket4(_socket4FD)
    }
    func localPort6() -> UInt16 {
        guard _socket6FD != SOCKET_NULL else {
            return 0
        }
        return localPortFromSocket6(_socket6FD)
    }
    func connectedHostFromSocket4(socketFD : Int32) -> String? {

        var sockaddr4 = sockaddr_in()
        var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
        
        let getPeerNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                getpeername(socketFD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
            }
        }
        guard getPeerNameResult >= 0 else {
            return nil
        }
        
        return GCDAsyncSocket.hostFromSockaddr4(&sockaddr4)

    }
    func connectedHostFromSocket6(socketFD : Int32) -> String? {
        var sockaddr6 = sockaddr_in6()
        var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
        
        let getPeerNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                getpeername(socketFD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
            }
        }
        guard getPeerNameResult >= 0 else {
            return nil
        }
        
        return GCDAsyncSocket.hostFromSockaddr6(&sockaddr6)
    }
    func connectedPortFromSocket4(socketFD : Int32) -> UInt16 {
        var sockaddr4 = sockaddr_in()
        var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
        
        let getPeerNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                getpeername(socketFD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
            }
        }
        guard getPeerNameResult >= 0 else {
            return 0
        }
        
        return GCDAsyncSocket.portFromSockaddr4(&sockaddr4)
    }
    func connectedPortFromSocket6(socketFD : Int32) -> UInt16 {
        var sockaddr6 = sockaddr_in6()
        var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
        
        let getPeerNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                getpeername(socketFD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
            }
        }
        guard getPeerNameResult >= 0 else {
            return 0
        }
        
        return GCDAsyncSocket.portFromSockaddr6(&sockaddr6)
    }
    func connectedUrlFromSocketUN(socketFD : Int32) -> NSURL? {
        var sockaddr = sockaddr_un()
        var sockaddrlen = socklen_t(sizeofValue(sockaddr))
        
        let getPeerNameResult = withUnsafeMutablePointer(&sockaddr){ (sockaddrPtr) -> Int32 in
            withUnsafeMutablePointer(&sockaddrlen){ (sockaddrlenPtr) -> Int32 in
                getpeername(socketFD, UnsafeMutablePointer(sockaddrPtr), UnsafeMutablePointer(sockaddrlenPtr))
            }
        }
        guard getPeerNameResult >= 0 else {
            return nil
        }
        
        return GCDAsyncSocket.urlFromSockaddrUN(&sockaddr)
    }
    func localHostFromSocket4(socketFD : Int32) -> String? {
        var sockaddr4 = sockaddr_in()
        var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
        
        let getSockNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                getsockname(socketFD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
            }
        }
        guard getSockNameResult >= 0 else {
            return nil
        }
        
        return GCDAsyncSocket.hostFromSockaddr4(&sockaddr4)
    }
    func localHostFromSocket6(socketFD : Int32) -> String? {
        var sockaddr6 = sockaddr_in6()
        var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
        
        let getSockNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                getsockname(socketFD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
            }
        }
        guard getSockNameResult >= 0 else {
            return nil
        }
        
        return GCDAsyncSocket.hostFromSockaddr6(&sockaddr6)
    }
    func localPortFromSocket4(socketFD : Int32) -> UInt16 {
        var sockaddr4 = sockaddr_in()
        var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
        
        let getSockNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                getsockname(socketFD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
            }
        }
        guard getSockNameResult >= 0 else {
            return 0
        }
        
        return GCDAsyncSocket.portFromSockaddr4(&sockaddr4)
    }
    func localPortFromSocket6(socketFD : Int32) -> UInt16 {
        var sockaddr6 = sockaddr_in6()
        var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
        
        let getSockNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
            withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                getsockname(socketFD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
            }
        }
        guard getSockNameResult >= 0 else {
            return 0
        }
        
        return GCDAsyncSocket.portFromSockaddr6(&sockaddr6)
    }
    /**
     * Returns the local or remote address to which this socket is connected,
     * specified as a sockaddr structure wrapped in a NSData object.
     *
     * @seealso connectedHost
     * @seealso connectedPort
     * @seealso localHost
     * @seealso localPort
     **/
    func connectedAddress() -> NSData? {
        var result:NSData? = nil
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                var sockaddr4 = sockaddr_in()
                var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
                
                let getPeerNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
                    withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                        getpeername(self._socket4FD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
                    }
                }
                guard getPeerNameResult >= 0 else {
                    return
                }
                
                result = NSData.init(bytes: &sockaddr4, length: Int(sockaddr4len) )
            }
            if self._socket6FD != SOCKET_NULL {
                var sockaddr6 = sockaddr_in6()
                var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
                
                let getPeerNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
                    withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                        getpeername(self._socket6FD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
                    }
                }
                guard getPeerNameResult >= 0 else {
                    return
                }
                
                result = NSData.init(bytes: &sockaddr6, length: Int(sockaddr6len) )
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    func localAddress() -> NSData? {
        var result:NSData? = nil
        
        let block = {
            if self._socket4FD != SOCKET_NULL {
                var sockaddr4 = sockaddr_in()
                var sockaddr4len = socklen_t(sizeofValue(sockaddr4))
                
                let getSockNameResult = withUnsafeMutablePointer(&sockaddr4){ (sockaddr4Ptr) -> Int32 in
                    withUnsafeMutablePointer(&sockaddr4len){ (sockaddr4lenPtr) -> Int32 in
                        getsockname(self._socket4FD, UnsafeMutablePointer(sockaddr4Ptr), UnsafeMutablePointer(sockaddr4lenPtr))
                    }
                }
                guard getSockNameResult >= 0 else {
                    return
                }
                
                result = NSData.init(bytes: &sockaddr4, length: Int(sockaddr4len) )
            }
            if self._socket6FD != SOCKET_NULL {
                var sockaddr6 = sockaddr_in6()
                var sockaddr6len = socklen_t(sizeofValue(sockaddr6))
                
                let getSockNameResult = withUnsafeMutablePointer(&sockaddr6){ (sockaddr6Ptr) -> Int32 in
                    withUnsafeMutablePointer(&sockaddr6len){ (sockaddr6lenPtr) -> Int32 in
                        getsockname(self._socket6FD, UnsafeMutablePointer(sockaddr6Ptr), UnsafeMutablePointer(sockaddr6lenPtr))
                    }
                }
                guard getSockNameResult >= 0 else {
                    return
                }
                
                result = NSData.init(bytes: &sockaddr6, length: Int(sockaddr6len) )
            }
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    /**
     * Returns whether the socket is IPv4 or IPv6.
     * An accepting socket may be both.
     **/
    func isIPv4() -> Bool {
        var result = false
        
        let block = {
            result = self._socket4FD != SOCKET_NULL
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    func isIPv6() -> Bool {
        var result = false
        
        let block = {
            result = self._socket6FD != SOCKET_NULL
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
    }
    /**
     * Returns whether or not the socket has been secured via SSL/TLS.
     *
     * See also the startTLS method.
     **/
    func isSecure() -> Bool {
        var result = false
        
        let block = {
            result = self.flags.contains(.SocketSecure)
        }
        
        if dispatch_get_specific(GCDAsyncSocketQueueName) != nil {
            block()
        }
        else {
            dispatch_sync(socketQueue, block)
        }
        
        return result
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
        //!!! check that interfaceDescription has a characters.count
        
    }
    func getInterfaceAddressFromUrl(url:NSURL) -> NSMutableData? {
        return nil
    }
    func setupReadAndWriteSourcesForNewlyConnectedSocket(socketFD:Int32) {
        
    }
    func usingCFStreamForTLS() -> Bool {
        return false
    }
    func usingSecureTransportForTLS() -> Bool {
        return false
    }
    func suspendReadSource() {
        
    }
    func resumeReadSource() {
        
    }
    func suspendWriteSource() {
        
    }
    func resumeWriteSource() {
        
    }
    
     /***********************************************************/
     // MARK: Reading
     /***********************************************************/
     // The readData and writeData methods won't block (they are asynchronous).
     //
     // When a read is complete the socket:didReadData:withTag: delegate method is dispatched on the delegateQueue.
     // When a write is complete the socket:didWriteDataWithTag: delegate method is dispatched on the delegateQueue.
     //
     // You may optionally set a timeout for any read/write operation. (To not timeout, use a negative time interval.)
     // If a read/write opertion times out, the corresponding "socket:shouldTimeout..." delegate method
     // is called to optionally allow you to extend the timeout.
     // Upon a timeout, the "socket:didDisconnectWithError:" method is called
     //
     // The tag is for your convenience.
     // You can use it as an array index, step number, state id, pointer, etc.
     
     /**
     * Reads the first available bytes that become available on the socket.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     **/
    func readDataWithTimeout(timeout:NSTimeInterval, tag:Int) {
        
    }
    /**
     * Reads the first available bytes that become available on the socket.
     * The bytes will be appended to the given byte buffer starting at the given offset.
     * The given buffer will automatically be increased in size if needed.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     * If the buffer if nil, the socket will create a buffer for you.
     *
     * If the bufferOffset is greater than the length of the given buffer,
     * the method will do nothing, and the delegate will not be called.
     *
     * If you pass a buffer, you must not alter it in any way while the socket is using it.
     * After completion, the data returned in socket:didReadData:withTag: will be a subset of the given buffer.
     * That is, it will reference the bytes that were appended to the given buffer via
     * the method [NSData dataWithBytesNoCopy:length:freeWhenDone:NO].
     **/
    func readDataWithTimeout(timeout:NSTimeInterval, buffer:NSMutableData, bufferOffset:Int, tag:Int) {
        
    }
    /**
     * Reads the first available bytes that become available on the socket.
     * The bytes will be appended to the given byte buffer starting at the given offset.
     * The given buffer will automatically be increased in size if needed.
     * A maximum of length bytes will be read.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     * If the buffer if nil, a buffer will automatically be created for you.
     * If maxLength is zero, no length restriction is enforced.
     *
     * If the bufferOffset is greater than the length of the given buffer,
     * the method will do nothing, and the delegate will not be called.
     *
     * If you pass a buffer, you must not alter it in any way while the socket is using it.
     * After completion, the data returned in socket:didReadData:withTag: will be a subset of the given buffer.
     * That is, it will reference the bytes that were appended to the given buffer  via
     * the method [NSData dataWithBytesNoCopy:length:freeWhenDone:NO].
     **/
    func readDataWithTimeout(timeout:NSTimeInterval, buffer:NSMutableData, bufferOffset:UInt, maxLength:UInt, tag:Int) {
        
    }
    /**
     * Reads the given number of bytes.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     *
     * If the length is 0, this method does nothing and the delegate is not called.
     **/
    func readDataToLength(length:UInt, withTimeout timeout:NSTimeInterval, tag:Int) {
        
    }
    /**
     * Reads the given number of bytes.
     * The bytes will be appended to the given byte buffer starting at the given offset.
     * The given buffer will automatically be increased in size if needed.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     * If the buffer if nil, a buffer will automatically be created for you.
     *
     * If the length is 0, this method does nothing and the delegate is not called.
     * If the bufferOffset is greater than the length of the given buffer,
     * the method will do nothing, and the delegate will not be called.
     *
     * If you pass a buffer, you must not alter it in any way while AsyncSocket is using it.
     * After completion, the data returned in socket:didReadData:withTag: will be a subset of the given buffer.
     * That is, it will reference the bytes that were appended to the given buffer via
     * the method [NSData dataWithBytesNoCopy:length:freeWhenDone:NO].
     **/
    func readDataToLength(length:UInt, withTimeout timeout:NSTimeInterval, buffer:NSMutableData, bufferOffset:Int, tag:Int) {
        
    }
    /**
     * Reads bytes until (and including) the passed "data" parameter, which acts as a separator.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     *
     * If you pass nil or zero-length data as the "data" parameter,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     *
     * To read a line from the socket, use the line separator (e.g. CRLF for HTTP, see below) as the "data" parameter.
     * If you're developing your own custom protocol, be sure your separator can not occur naturally as
     * part of the data between separators.
     * For example, imagine you want to send several small documents over a socket.
     * Using CRLF as a separator is likely unwise, as a CRLF could easily exist within the documents.
     * In this particular example, it would be better to use a protocol similar to HTTP with
     * a header that includes the length of the document.
     * Also be careful that your separator cannot occur naturally as part of the encoding for a character.
     *
     * The given data (separator) parameter should be immutable.
     * For performance reasons, the socket will retain it, not copy it.
     * So if it is immutable, don't modify it while the socket is using it.
     **/
    func readDataToData(data:NSData?, withTimeout timeout:NSTimeInterval, tag:Int) {
        
    }
    /**
     * Reads bytes until (and including) the passed "data" parameter, which acts as a separator.
     * The bytes will be appended to the given byte buffer starting at the given offset.
     * The given buffer will automatically be increased in size if needed.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     * If the buffer if nil, a buffer will automatically be created for you.
     *
     * If the bufferOffset is greater than the length of the given buffer,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     *
     * If you pass a buffer, you must not alter it in any way while the socket is using it.
     * After completion, the data returned in socket:didReadData:withTag: will be a subset of the given buffer.
     * That is, it will reference the bytes that were appended to the given buffer via
     * the method [NSData dataWithBytesNoCopy:length:freeWhenDone:NO].
     *
     * To read a line from the socket, use the line separator (e.g. CRLF for HTTP, see below) as the "data" parameter.
     * If you're developing your own custom protocol, be sure your separator can not occur naturally as
     * part of the data between separators.
     * For example, imagine you want to send several small documents over a socket.
     * Using CRLF as a separator is likely unwise, as a CRLF could easily exist within the documents.
     * In this particular example, it would be better to use a protocol similar to HTTP with
     * a header that includes the length of the document.
     * Also be careful that your separator cannot occur naturally as part of the encoding for a character.
     *
     * The given data (separator) parameter should be immutable.
     * For performance reasons, the socket will retain it, not copy it.
     * So if it is immutable, don't modify it while the socket is using it.
     **/
    func readDataToData(data:NSData?, withTimeout timeout:NSTimeInterval, buffer:NSMutableData, bufferOffset:Int, tag:Int) {
        
    }
    /**
     * Reads bytes until (and including) the passed "data" parameter, which acts as a separator.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     *
     * If maxLength is zero, no length restriction is enforced.
     * Otherwise if maxLength bytes are read without completing the read,
     * it is treated similarly to a timeout - the socket is closed with a GCDAsyncSocketReadMaxedOutError.
     * The read will complete successfully if exactly maxLength bytes are read and the given data is found at the end.
     *
     * If you pass nil or zero-length data as the "data" parameter,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     * If you pass a maxLength parameter that is less than the length of the data parameter,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     *
     * To read a line from the socket, use the line separator (e.g. CRLF for HTTP, see below) as the "data" parameter.
     * If you're developing your own custom protocol, be sure your separator can not occur naturally as
     * part of the data between separators.
     * For example, imagine you want to send several small documents over a socket.
     * Using CRLF as a separator is likely unwise, as a CRLF could easily exist within the documents.
     * In this particular example, it would be better to use a protocol similar to HTTP with
     * a header that includes the length of the document.
     * Also be careful that your separator cannot occur naturally as part of the encoding for a character.
     *
     * The given data (separator) parameter should be immutable.
     * For performance reasons, the socket will retain it, not copy it.
     * So if it is immutable, don't modify it while the socket is using it.
     **/
    func readDataToData(data:NSData?, withTimeout timeout:NSTimeInterval, maxLength:UInt, tag:Int) {
        
    }
    /**
     * Reads bytes until (and including) the passed "data" parameter, which acts as a separator.
     * The bytes will be appended to the given byte buffer starting at the given offset.
     * The given buffer will automatically be increased in size if needed.
     *
     * If the timeout value is negative, the read operation will not use a timeout.
     * If the buffer if nil, a buffer will automatically be created for you.
     *
     * If maxLength is zero, no length restriction is enforced.
     * Otherwise if maxLength bytes are read without completing the read,
     * it is treated similarly to a timeout - the socket is closed with a GCDAsyncSocketReadMaxedOutError.
     * The read will complete successfully if exactly maxLength bytes are read and the given data is found at the end.
     *
     * If you pass a maxLength parameter that is less than the length of the data (separator) parameter,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     * If the bufferOffset is greater than the length of the given buffer,
     * the method will do nothing (except maybe print a warning), and the delegate will not be called.
     *
     * If you pass a buffer, you must not alter it in any way while the socket is using it.
     * After completion, the data returned in socket:didReadData:withTag: will be a subset of the given buffer.
     * That is, it will reference the bytes that were appended to the given buffer via
     * the method [NSData dataWithBytesNoCopy:length:freeWhenDone:NO].
     *
     * To read a line from the socket, use the line separator (e.g. CRLF for HTTP, see below) as the "data" parameter.
     * If you're developing your own custom protocol, be sure your separator can not occur naturally as
     * part of the data between separators.
     * For example, imagine you want to send several small documents over a socket.
     * Using CRLF as a separator is likely unwise, as a CRLF could easily exist within the documents.
     * In this particular example, it would be better to use a protocol similar to HTTP with
     * a header that includes the length of the document.
     * Also be careful that your separator cannot occur naturally as part of the encoding for a character.
     *
     * The given data (separator) parameter should be immutable.
     * For performance reasons, the socket will retain it, not copy it.
     * So if it is immutable, don't modify it while the socket is using it.
     **/
    func readDataToData(data:NSData?, withTimeout timeout:NSTimeInterval, buffer:NSMutableData, bufferOffset:Int, maxLength:UInt, tag:Int) {
        
    }
    /**
     * Returns progress of the current read, from 0.0 to 1.0, or NaN if no current read (use isnan() to check).
     * The parameters "tag", "done" and "total" will be filled in if they aren't NULL.
     **/
    func progressOfReadReturningTag(inout tagPtr:Int, inout bytesDone:UInt, inout total:UInt) -> Float {
        return 0.0
    }
    /**
    * This method starts a new read, if needed.
    *
    * It is called when:
    * - a user requests a read
    * - after a read request has finished (to handle the next request)
    * - immediately after the socket opens to handle any pending requests
    *
    * This method also handles auto-disconnect post read/write completion.
    **/
    func maybeDequeueRead() {
        
    }
    func flushSSLBuffers() {
        
    }
    func doReadData() {
        
    }
    func doReadEOF() {
        
    }
    func completeCurrentRead() {
        
    }
    func endCurrentRead() {
        
    }
    func setupReadTimerWithTimeout(timeout:NSTimeInterval) {
        
    }
    func doReadTimeout() {
        
    }
    func doReadTimeoutWithExtension(timeoutExtension:NSTimeInterval) {
        
    }
     
     /***********************************************************/
     // MARK: Writing
     /***********************************************************/
     /**
     * Writes data to the socket, and calls the delegate when finished.
     *
     * If you pass in nil or zero-length data, this method does nothing and the delegate will not be called.
     * If the timeout value is negative, the write operation will not use a timeout.
     *
     * Thread-Safety Note:
     * If the given data parameter is mutable (NSMutableData) then you MUST NOT alter the data while
     * the socket is writing it. In other words, it's not safe to alter the data until after the delegate method
     * socket:didWriteDataWithTag: is invoked signifying that this particular write operation has completed.
     * This is due to the fact that GCDAsyncSocket does NOT copy the data. It simply retains it.
     * This is for performance reasons. Often times, if NSMutableData is passed, it is because
     * a request/response was built up in memory. Copying this data adds an unwanted/unneeded overhead.
     * If you need to write data from an immutable buffer, and you need to alter the buffer before the socket
     * completes writing the bytes (which is NOT immediately after this method returns, but rather at a later time
     * when the delegate method notifies you), then you should first copy the bytes, and pass the copy to this method.
     **/
    func writeData(data:NSData?, withTimeout timeout:NSTimeInterval, tag:Int){
        
    }
    /**
     * Returns progress of the current write, from 0.0 to 1.0, or NaN if no current write (use isnan() to check).
     * The parameters "tag", "done" and "total" will be filled in if they aren't NULL.
     **/
    func progressOfWriteReturningFlag(inout tagPtr:Int, inout bytesDone donePtr:UInt, inout total:UInt) -> Float {
        return 0.0
    }
    /**
    * Conditionally starts a new write.
    *
    * It is called when:
    * - a user requests a write
    * - after a write request has finished (to handle the next request)
    * - immediately after the socket opens to handle any pending requests
    *
    * This method also handles auto-disconnect post read/write completion.
    **/
    func maybeDequeueWrite() {
        
    }
    func doWriteData() {
        
    }
    func completeCurrentWrite() {
        
    }
    func endCurrentWrite() {
        
    }
    func setupWriteTimerWithTimeout(timeout:NSTimeInterval) {
        
    }
    func doWriteTimeout() {
        
    }
    func doWriteTimeoutWithExtension(timeoutExtension:NSTimeInterval) {
        
    }
     
     /***********************************************************/
     // MARK: Security
     /***********************************************************/
     /**
     * Secures the connection using SSL/TLS.
     *
     * This method may be called at any time, and the TLS handshake will occur after all pending reads and writes
     * are finished. This allows one the option of sending a protocol dependent StartTLS message, and queuing
     * the upgrade to TLS at the same time, without having to wait for the write to finish.
     * Any reads or writes scheduled after this method is called will occur over the secured connection.
     *
     * ==== The available TOP-LEVEL KEYS are:
     *
     * - GCDAsyncSocketManuallyEvaluateTrust
     *     The value must be of type NSNumber, encapsulating a BOOL value.
     *     If you set this to YES, then the underlying SecureTransport system will not evaluate the SecTrustRef of the peer.
     *     Instead it will pause at the moment evaulation would typically occur,
     *     and allow us to handle the security evaluation however we see fit.
     *     So GCDAsyncSocket will invoke the delegate method socket:shouldTrustPeer: passing the SecTrustRef.
     *
     *     Note that if you set this option, then all other configuration keys are ignored.
     *     Evaluation will be completely up to you during the socket:didReceiveTrust:completionHandler: delegate method.
     *
     *     For more information on trust evaluation see:
     *     Apple's Technical Note TN2232 - HTTPS Server Trust Evaluation
     *     https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     *
     *     If unspecified, the default value is NO.
     *
     * - GCDAsyncSocketUseCFStreamForTLS (iOS only)
     *     The value must be of type NSNumber, encapsulating a BOOL value.
     *     By default GCDAsyncSocket will use the SecureTransport layer to perform encryption.
     *     This gives us more control over the security protocol (many more configuration options),
     *     plus it allows us to optimize things like sys calls and buffer allocation.
     *
     *     However, if you absolutely must, you can instruct GCDAsyncSocket to use the old-fashioned encryption
     *     technique by going through the CFStream instead. So instead of using SecureTransport, GCDAsyncSocket
     *     will instead setup a CFRead/CFWriteStream. And then set the kCFStreamPropertySSLSettings property
     *     (via CFReadStreamSetProperty / CFWriteStreamSetProperty) and will pass the given options to this method.
     *
     *     Thus all the other keys in the given dictionary will be ignored by GCDAsyncSocket,
     *     and will passed directly CFReadStreamSetProperty / CFWriteStreamSetProperty.
     *     For more infomation on these keys, please see the documentation for kCFStreamPropertySSLSettings.
     *
     *     If unspecified, the default value is NO.
     *
     * ==== The available CONFIGURATION KEYS are:
     *
     * - kCFStreamSSLPeerName
     *     The value must be of type NSString.
     *     It should match the name in the X.509 certificate given by the remote party.
     *     See Apple's documentation for SSLSetPeerDomainName.
     *
     * - kCFStreamSSLCertificates
     *     The value must be of type NSArray.
     *     See Apple's documentation for SSLSetCertificate.
     *
     * - kCFStreamSSLIsServer
     *     The value must be of type NSNumber, encapsulationg a BOOL value.
     *     See Apple's documentation for SSLCreateContext for iOS.
     *     This is optional for iOS. If not supplied, a NO value is the default.
     *     This is not needed for Mac OS X, and the value is ignored.
     *
     * - GCDAsyncSocketSSLPeerID
     *     The value must be of type NSData.
     *     You must set this value if you want to use TLS session resumption.
     *     See Apple's documentation for SSLSetPeerID.
     *
     * - GCDAsyncSocketSSLProtocolVersionMin
     * - GCDAsyncSocketSSLProtocolVersionMax
     *     The value(s) must be of type NSNumber, encapsulting a SSLProtocol value.
     *     See Apple's documentation for SSLSetProtocolVersionMin & SSLSetProtocolVersionMax.
     *     See also the SSLProtocol typedef.
     *
     * - GCDAsyncSocketSSLSessionOptionFalseStart
     *     The value must be of type NSNumber, encapsulating a BOOL value.
     *     See Apple's documentation for kSSLSessionOptionFalseStart.
     *
     * - GCDAsyncSocketSSLSessionOptionSendOneByteRecord
     *     The value must be of type NSNumber, encapsulating a BOOL value.
     *     See Apple's documentation for kSSLSessionOptionSendOneByteRecord.
     *
     * - GCDAsyncSocketSSLCipherSuites
     *     The values must be of type NSArray.
     *     Each item within the array must be a NSNumber, encapsulating
     *     See Apple's documentation for SSLSetEnabledCiphers.
     *     See also the SSLCipherSuite typedef.
     *
     * - GCDAsyncSocketSSLDiffieHellmanParameters (Mac OS X only)
     *     The value must be of type NSData.
     *     See Apple's documentation for SSLSetDiffieHellmanParams.
     *
     * ==== The following UNAVAILABLE KEYS are: (with throw an exception)
     *
     * - kCFStreamSSLAllowsAnyRoot (UNAVAILABLE)
     *     You MUST use manual trust evaluation instead (see GCDAsyncSocketManuallyEvaluateTrust).
     *     Corresponding deprecated method: SSLSetAllowsAnyRoot
     *
     * - kCFStreamSSLAllowsExpiredRoots (UNAVAILABLE)
     *     You MUST use manual trust evaluation instead (see GCDAsyncSocketManuallyEvaluateTrust).
     *     Corresponding deprecated method: SSLSetAllowsExpiredRoots
     *
     * - kCFStreamSSLAllowsExpiredCertificates (UNAVAILABLE)
     *     You MUST use manual trust evaluation instead (see GCDAsyncSocketManuallyEvaluateTrust).
     *     Corresponding deprecated method: SSLSetAllowsExpiredCerts
     *
     * - kCFStreamSSLValidatesCertificateChain (UNAVAILABLE)
     *     You MUST use manual trust evaluation instead (see GCDAsyncSocketManuallyEvaluateTrust).
     *     Corresponding deprecated method: SSLSetEnableCertVerify
     *
     * - kCFStreamSSLLevel (UNAVAILABLE)
     *     You MUST use GCDAsyncSocketSSLProtocolVersionMin & GCDAsyncSocketSSLProtocolVersionMin instead.
     *     Corresponding deprecated method: SSLSetProtocolVersionEnabled
     *
     *
     * Please refer to Apple's documentation for corresponding SSLFunctions.
     *
     * If you pass in nil or an empty dictionary, the default settings will be used.
     *
     * IMPORTANT SECURITY NOTE:
     * The default settings will check to make sure the remote party's certificate is signed by a
     * trusted 3rd party certificate agency (e.g. verisign) and that the certificate is not expired.
     * However it will not verify the name on the certificate unless you
     * give it a name to verify against via the kCFStreamSSLPeerName key.
     * The security implications of this are important to understand.
     * Imagine you are attempting to create a secure connection to MySecureServer.com,
     * but your socket gets directed to MaliciousServer.com because of a hacked DNS server.
     * If you simply use the default settings, and MaliciousServer.com has a valid certificate,
     * the default settings will not detect any problems since the certificate is valid.
     * To properly secure your connection in this particular scenario you
     * should set the kCFStreamSSLPeerName property to "MySecureServer.com".
     * 
     * You can also perform additional validation in socketDidSecure.
     **/
    func startTLS(tlsSettings:NSDictionary?){
        
    }
    func maybeStartTLS() {
        
    }
    
     /***********************************************************/
     // MARK: Security via SecureTransport
     /***********************************************************/
    func sslReadWithBuffer(buffer:UnsafeMutablePointer<CInt>, inout length bufferLength:size_t) -> OSStatus {
        return 0
    }
    func sslWriteWithBuffer(buffer:UnsafeMutablePointer<CInt>, inout length bufferLength:size_t) -> OSStatus {
        return 0
    }
    //static OSStatus SSLReadFunction(SSLConnectionRef connection, void *data, size_t *dataLength)
    //static OSStatus SSLWriteFunction(SSLConnectionRef connection, const void *data, size_t *dataLength)
    func ssl_startTLS() {
        
    }
    func ssl_continueSSLHandshake() {
        
    }
    func ssl_shouldTrustPeer(shouldTrust:Bool, aStateIndex:Int) {
        
    }
     /***********************************************************/
     // MARK: Security via CFStream
     /***********************************************************/
    #if iOS
    func cf_finishSSLHandshake() {
    
    }
    func cf_abortSSLHandshake() throws {
    
    }
    func cf_startTLS() {
    
    }
    #endif
    
     /***********************************************************/
     // MARK: CFStream
     /***********************************************************/
    #if iOS
    func ignore(sender:AnyObject?){
    
    }
    func startCFStreamThreadIfNeeded() {
    
    }
    func stopCFStreamThreadIfNeeded() {
    
    }
    func cfstreamThread() {
    
    }
    func scheduleCFStreams(asyncSocket:GCDAsyncSocket){
    
    }
    func unscheduleCFStreams(asyncSocket:GCDAsyncSocket){
    
    }
    static func CFReadStreamCallback(stream:CFReadStreamRef, type:CFStreamEventType, inout pInfo:UnsafeMutablePointer<CInt>) {
    
    }
    static func CFWriteStreamCallback(stream:CFReadStreamRef, type:CFStreamEventType, inout pInfo:UnsafeMutablePointer<CInt>) {
    
    }
    func createReadAndWriteStream() -> Bool {
        return false
    }
    func registerForStreamCallbacks(includeReadWrite:Bool) -> Bool {
        return false
    }
    func addStreamsToRunLoop() -> Bool {
        return false
    }
    func removeStreamsFromRunLoop() {
    
    }
    func openStreams() -> Bool {
        return false
    }
    #endif
     /***********************************************************/
     // MARK: Advanced
     /***********************************************************/
     /**
     * Traditionally sockets are not closed until the conversation is over.
     * However, it is technically possible for the remote enpoint to close its write stream.
     * Our socket would then be notified that there is no more data to be read,
     * but our socket would still be writeable and the remote endpoint could continue to receive our data.
     *
     * The argument for this confusing functionality stems from the idea that a client could shut down its
     * write stream after sending a request to the server, thus notifying the server there are to be no further requests.
     * In practice, however, this technique did little to help server developers.
     *
     * To make matters worse, from a TCP perspective there is no way to tell the difference from a read stream close
     * and a full socket close. They both result in the TCP stack receiving a FIN packet. The only way to tell
     * is by continuing to write to the socket. If it was only a read stream close, then writes will continue to work.
     * Otherwise an error will be occur shortly (when the remote end sends us a RST packet).
     *
     * In addition to the technical challenges and confusion, many high level socket/stream API's provide
     * no support for dealing with the problem. If the read stream is closed, the API immediately declares the
     * socket to be closed, and shuts down the write stream as well. In fact, this is what Apple's CFStream API does.
     * It might sound like poor design at first, but in fact it simplifies development.
     *
     * The vast majority of the time if the read stream is closed it's because the remote endpoint closed its socket.
     * Thus it actually makes sense to close the socket at this point.
     * And in fact this is what most networking developers want and expect to happen.
     * However, if you are writing a server that interacts with a plethora of clients,
     * you might encounter a client that uses the discouraged technique of shutting down its write stream.
     * If this is the case, you can set this property to NO,
     * and make use of the socketDidCloseReadStream delegate method.
     * 
     * The default value is YES.
     **/
    func autoDisconnectOnClosedReadStream() -> Bool {
        return false
    }
    func setAutoDisconnectOnClosedReadStream(flag:Bool) {
        
    }
    /**
     * GCDAsyncSocket maintains thread safety by using an internal serial dispatch_queue.
     * In most cases, the instance creates this queue itself.
     * However, to allow for maximum flexibility, the internal queue may be passed in the init method.
     * This allows for some advanced options such as controlling socket priority via target queues.
     * However, when one begins to use target queues like this, they open the door to some specific deadlock issues.
     *
     * For example, imagine there are 2 queues:
     * dispatch_queue_t socketQueue;
     * dispatch_queue_t socketTargetQueue;
     *
     * If you do this (pseudo-code):
     * socketQueue.targetQueue = socketTargetQueue;
     *
     * Then all socketQueue operations will actually get run on the given socketTargetQueue.
     * This is fine and works great in most situations.
     * But if you run code directly from within the socketTargetQueue that accesses the socket,
     * you could potentially get deadlock. Imagine the following code:
     *
     * - (BOOL)socketHasSomething
     * {
     *     __block BOOL result = NO;
     *     dispatch_block_t block = ^{
     *         result = [self someInternalMethodToBeRunOnlyOnSocketQueue];
     *     }
     *     if (is_executing_on_queue(socketQueue))
     *         block();
     *     else
     *         dispatch_sync(socketQueue, block);
     *
     *     return result;
     * }
     *
     * What happens if you call this method from the socketTargetQueue? The result is deadlock.
     * This is because the GCD API offers no mechanism to discover a queue's targetQueue.
     * Thus we have no idea if our socketQueue is configured with a targetQueue.
     * If we had this information, we could easily avoid deadlock.
     * But, since these API's are missing or unfeasible, you'll have to explicitly set it.
     *
     * IF you pass a socketQueue via the init method,
     * AND you've configured the passed socketQueue with a targetQueue,
     * THEN you should pass the end queue in the target hierarchy.
     *
     * For example, consider the following queue hierarchy:
     * socketQueue -> ipQueue -> moduleQueue
     *
     * This example demonstrates priority shaping within some server.
     * All incoming client connections from the same IP address are executed on the same target queue.
     * And all connections for a particular module are executed on the same target queue.
     * Thus, the priority of all networking for the entire module can be changed on the fly.
     * Additionally, networking traffic from a single IP cannot monopolize the module.
     *
     * Here's how you would accomplish something like that:
     * - (dispatch_queue_t)newSocketQueueForConnectionFromAddress:(NSData *)address onSocket:(GCDAsyncSocket *)sock
     * {
     *     dispatch_queue_t socketQueue = dispatch_queue_create("", NULL);
     *     dispatch_queue_t ipQueue = [self ipQueueForAddress:address];
     *
     *     dispatch_set_target_queue(socketQueue, ipQueue);
     *     dispatch_set_target_queue(iqQueue, moduleQueue);
     *
     *     return socketQueue;
     * }
     * - (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
     * {
     *     [clientConnections addObject:newSocket];
     *     [newSocket markSocketQueueTargetQueue:moduleQueue];
     * }
     * 
     * Note: This workaround is ONLY needed if you intend to execute code directly on the ipQueue or moduleQueue.
     * This is often NOT the case, as such queues are used solely for execution shaping.
     **/
    func markSocketQueueTargetQueue(socketNewTargetQueue:dispatch_queue_t) {
        
    }
    func unmarkSocketQueueTargetQueue(socketOldTargetQueue:dispatch_queue_t) {
        
    }
    /**
     * It's not thread-safe to access certain variables from outside the socket's internal queue.
     *
     * For example, the socket file descriptor.
     * File descriptors are simply integers which reference an index in the per-process file table.
     * However, when one requests a new file descriptor (by opening a file or socket),
     * the file descriptor returned is guaranteed to be the lowest numbered unused descriptor.
     * So if we're not careful, the following could be possible:
     *
     * - Thread A invokes a method which returns the socket's file descriptor.
     * - The socket is closed via the socket's internal queue on thread B.
     * - Thread C opens a file, and subsequently receives the file descriptor that was previously the socket's FD.
     * - Thread A is now accessing/altering the file instead of the socket.
     *
     * In addition to this, other variables are not actually objects,
     * and thus cannot be retained/released or even autoreleased.
     * An example is the sslContext, of type SSLContextRef, which is actually a malloc'd struct.
     *
     * Although there are internal variables that make it difficult to maintain thread-safety,
     * it is important to provide access to these variables
     * to ensure this class can be used in a wide array of environments.
     * This method helps to accomplish this by invoking the current block on the socket's internal queue.
     * The methods below can be invoked from within the block to access
     * those generally thread-unsafe internal variables in a thread-safe manner.
     * The given block will be invoked synchronously on the socket's internal queue.
     *
     * If you save references to any protected variables and use them outside the block, you do so at your own peril.
     **/
    func performBlock(block:dispatch_block_t) {
        
    }
    /**
     * These methods are only available from within the context of a performBlock: invocation.
     * See the documentation for the performBlock: method above.
     *
     * Provides access to the socket's file descriptor(s).
     * If the socket is a server socket (is accepting incoming connections),
     * it might actually have multiple internal socket file descriptors - one for IPv4 and one for IPv6.
     **/
    func socketFD() -> Int {
        return 0
    }
    func socket4FD() -> Int {
        return 0
    }
    func socket6FD() -> Int {
        return 0
    }
    #if TARGET_OS_IPHONE
    /**
    * These methods are only available from within the context of a performBlock: invocation.
    * See the documentation for the performBlock: method above.
    *
    * Provides access to the socket's internal CFReadStream/CFWriteStream.
    *
    * These streams are only used as workarounds for specific iOS shortcomings:
    *
    * - Apple has decided to keep the SecureTransport framework private is iOS.
    *   This means the only supplied way to do SSL/TLS is via CFStream or some other API layered on top of it.
    *   Thus, in order to provide SSL/TLS support on iOS we are forced to rely on CFStream,
    *   instead of the preferred and faster and more powerful SecureTransport.
    *
    * - If a socket doesn't have backgrounding enabled, and that socket is closed while the app is backgrounded,
    *   Apple only bothers to notify us via the CFStream API.
    *   The faster and more powerful GCD API isn't notified properly in this case.
    *
    * See also: (BOOL)enableBackgroundingOnSocket
    **/
    func readStream() -> CFReadStreamRef {
    
    }
    func writeStream() -> CFWriteStreamRef {
    
    }
    
    /**
    * This method is only available from within the context of a performBlock: invocation.
    * See the documentation for the performBlock: method above.
    *
    * Configures the socket to allow it to operate when the iOS application has been backgrounded.
    * In other words, this method creates a read & write stream, and invokes:
    *
    * CFReadStreamSetProperty(readStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    * CFWriteStreamSetProperty(writeStream, kCFStreamNetworkServiceType, kCFStreamNetworkServiceTypeVoIP);
    *
    * Returns YES if successful, NO otherwise.
    *
    * Note: Apple does not officially support backgrounding server sockets.
    * That is, if your socket is accepting incoming connections, Apple does not officially support
    * allowing iOS applications to accept incoming connections while an app is backgrounded.
    *
    * Example usage:
    *
    * - (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
    * {
    *     [asyncSocket performBlock:^{
    *         [asyncSocket enableBackgroundingOnSocket];
    *     }];
    * }
    **/
    func enableBackgroundingOnSocketWithCaveat(caveat:Bool) -> Bool {
    
    }
    func enableBackgroundingOnSocket() -> Bool {
    
    }
    #endif
    
    /**
     * This method is only available from within the context of a performBlock: invocation.
     * See the documentation for the performBlock: method above.
     *
     * Provides access to the socket's SSLContext, if SSL/TLS has been started on the socket.
     **/
    func sslContext() -> SSLContextRef? {
        if dispatch_get_specific(GCDAsyncSocketQueueName) == nil {
            print("sslContext is only available from within a block")
            return nil
        }
        return _sslContext
    }
     /***********************************************************/
     // MARK: Class Utilities
     /***********************************************************/
     /**
     * The address lookup utility used by the class.
     * This method is synchronous, so it's recommended you use it on a background thread/queue.
     *
     * The special strings "localhost" and "loopback" return the loopback address for IPv4 and IPv6.
     *
     * @returns
     *   A mutable array with all IPv4 and IPv6 addresses returned by getaddrinfo.
     *   The addresses are specifically for TCP connections.
     *   You can filter the addresses, if needed, using the other utility methods provided by the class.
     **/
    class func lookupHost(host:String, port:UInt16) throws -> [NSData] {
        return [NSData]()
    }
    
    /**
     * Extracting host and port information from raw address data.
     **/
    class func hostFromSockaddr4(inout sockaddr4:sockaddr_in) -> String {
        return ""
    }
    class func hostFromSockaddr6(inout sockaddr6:sockaddr_in6) -> String {
        return ""
    }
    class func portFromSockaddr4(inout sockaddr4:sockaddr_in) -> UInt16 {
        return 0
    }
    class func portFromSockaddr6(inout sockaddr6:sockaddr_in6) -> UInt16 {
        return 0
    }
    class func urlFromSockaddrUN(inout sockaddrUn:sockaddr_un) -> NSURL {
        return NSURL(string: "")!
    }
    class func hostFromAddress(address:NSData?) -> String {
        return ""
    }
    class func portFromAddress(address:NSData) -> UInt16 {
        return 0
    }
    class func isIPv4Address(address:NSData) -> Bool {
        return false
    }
    class func isIPv6Address(address:NSData) -> Bool {
        return false
    }
    class func getHost(inout host:String, inout port:UInt16, fromAddress address:NSData) -> Bool {
        return false
    }
    class func getHost(inout host:String, inout port:UInt16, inout family:sa_family_t, fromAddress address:NSData) -> Bool {
        return false
    }
//    class func CRLFData() -> NSData {
//    
//    }
}