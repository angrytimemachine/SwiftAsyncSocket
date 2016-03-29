//
//  SwiftTests.swift
//  CocoaAsyncSocket
//
//  Created by Chris Ballinger on 2/17/16.
//
//


import XCTest
@testable import SwiftAsyncSocket

class SwiftTests: XCTestCase, GCDAsyncSocketDelegate {
    
    let kTestPort: UInt16 = 30301
    
    var clientSocket: GCDAsyncSocket?
    var serverSocket: GCDAsyncSocket?
    var acceptedServerSocket: GCDAsyncSocket?
    var expectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        clientSocket = GCDAsyncSocket(withDelegate: self, withDelegateQueue: dispatch_get_main_queue())
        serverSocket = GCDAsyncSocket(withDelegate: self, withDelegateQueue: dispatch_get_main_queue())
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        clientSocket?.disconnect()
        serverSocket?.disconnect()
        acceptedServerSocket?.disconnect()
        clientSocket = nil
        serverSocket = nil
        acceptedServerSocket = nil
    }
    
    func testFullConnection() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        do {
            try serverSocket?.acceptOnPort(kTestPort)
        } catch {
            XCTFail("\(error)")
        }
        do {
            try clientSocket?.connectToHost("127.0.0.1", onPort: kTestPort)
        } catch {
            XCTFail("\(error)")
        }
        expectation = expectation(withDescription: "Test Full Connection")
        waitForExpectations(withTimeout:30) { (error: NSError?) -> Void in
            if error != nil {
                XCTFail("\(error)")
            }
        }
    }
    
    
    //MARK:- GCDAsyncSocketDelegate
    func socket(sock:GCDAsyncSocket, didAcceptNewSocket newSocket:GCDAsyncSocket) {
        print("didAcceptNewSocket \(sock) \(newSocket)")
        acceptedServerSocket = newSocket
    }
    
    func socket(sock:GCDAsyncSocket, didConnectToHost host:String, port:UInt16) {
        print("didConnectToHost \(sock) \(host) \(port)");
        expectation?.fulfill()
    }
    
    func newSocketQueueForConnection(fromAddress address:NSData, onSocket:GCDAsyncSocket) -> dispatch_queue_t! {
        return dispatch_queue_create(GCDAsyncSocketQueueName, nil)
    }
    func socket(sock:GCDAsyncSocket, didConnectToUrl:NSURL) {
        
    }
    func socket(sock:GCDAsyncSocket, didReadData data:NSData, withTag tag:Int) {
        
    }
    func socket(sock:GCDAsyncSocket, didReadPartialDataOfLength partialLength:Int, tag:Int) {
        
    }
    func socket(sock:GCDAsyncSocket, didWritePartialDataOfLength partialLength:Int, tag:Int) {
        
    }
    func socket(sock:GCDAsyncSocket, didWriteDataWithTag tag:Int) {
        
    }
    func socket(sock:GCDAsyncSocket, shouldTimeoutReadWithTag tag:Int, elapsed:NSTimeInterval, bytesDone length:Int) -> NSTimeInterval {
        return 0
    }
    func socket(sock:GCDAsyncSocket, shouldTimeoutWriteWithTag tag:Int, elapsed:NSTimeInterval, bytesDone length:Int) -> NSTimeInterval {
        return 0
    }
    func socketDidCloseReadStream(sock:GCDAsyncSocket) {
        
    }
    func socketDidDisconnect(sock:GCDAsyncSocket?, withError:ErrorProtocol?) {
        
    }
    func socketDidSecure(sock:GCDAsyncSocket) {
        
    }
    func socket(sock:GCDAsyncSocket, didReceiveTrust trust:SecTrust, completionHandler:(shouldTrust:Bool)->Void) {
        
    }
    
}

