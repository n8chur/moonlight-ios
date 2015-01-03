//
//  DiscoveryManager.m
//  Limelight
//
//  Created by Diego Waxemberg on 1/1/15.
//  Copyright (c) 2015 Limelight Stream. All rights reserved.
//

#import "DiscoveryManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"
#import "DataManager.h"
#import "DiscoveryWorker.h"

@implementation DiscoveryManager {
    NSMutableArray* _hostQueue;
    NSMutableArray* _discoveredHosts;
    id<DiscoveryCallback> _callback;
    MDNSManager* _mdnsMan;
    NSOperationQueue* _opQueue;
    NSString* _uniqueId;
    NSData* _cert;
    BOOL shouldDiscover;
}

- (id)initWithHosts:(NSArray *)hosts andCallback:(id<DiscoveryCallback>)callback {
    self = [super init];
    _hostQueue = [NSMutableArray arrayWithArray:hosts];
    _callback = callback;
    _opQueue = [[NSOperationQueue alloc] init];
    _mdnsMan = [[MDNSManager alloc] initWithCallback:self];
    [CryptoManager generateKeyPairUsingSSl];
    _uniqueId = [CryptoManager getUniqueID];
    _cert = [CryptoManager readCertFromFile];
    shouldDiscover = NO;
    return self;
}

- (void) discoverHost:(NSString *)hostAddress withCallback:(void (^)(Host *))callback {
    HttpManager* hMan = [[HttpManager alloc] initWithHost:hostAddress uniqueId:_uniqueId deviceName:deviceName cert:_cert];
    NSData* serverInfoData = [hMan executeRequestSynchronously:[hMan newServerInfoRequest]];
    
    Host* host = nil;
    if ([[HttpManager getStatusStringFromXML:serverInfoData] isEqualToString:@"OK"]) {
        DataManager* dataMan = [[DataManager alloc] init];
        host = [dataMan createHost];
        host.address = hostAddress;
        [DiscoveryWorker updateHost:host withServerInfo:serverInfoData];
        if (![self addHostToDiscovery:host]) {
            [dataMan removeHost:host];
        }
    }
    callback(host);
}

- (void) startDiscovery {
    NSLog(@"Starting discovery");
    shouldDiscover = YES;
    [_mdnsMan searchForHosts];
    for (Host* host in _hostQueue) {
        [_opQueue addOperation:[self createWorkerForHost:host]];
    }
}

- (void) stopDiscovery {
    NSLog(@"Stopping discovery");
    shouldDiscover = NO;
    [_mdnsMan stopSearching];
    [_opQueue cancelAllOperations];
}
    shouldDiscover = NO;
    [_mdnsMan stopSearching];
}

- (BOOL) addHostToDiscovery:(Host *)host {
    if (![self isHostInDiscovery:host]) {
        [_hostQueue addObject:host];
        if (shouldDiscover) {
            [_opQueue addOperation:[self createWorkerForHost:host]];
        }
        return YES;
    }
    return NO;
}

- (void) removeHostFromDiscovery:(Host *)host {
    for (DiscoveryWorker* worker in [_opQueue operations]) {
        if ([worker getHost] == host) {
            [worker cancel];
        }
    }
    [_hostQueue removeObject:host];
}

- (void)updateHosts:(NSArray *)hosts {
    for (Host* host in hosts) {
        if ([self addHostToDiscovery:host]) {
            [_callback updateAllHosts:_hostQueue];
        }
    }
}

- (BOOL) isHostInDiscovery:(Host*)host {
    for (int i = 0; i < _hostQueue.count; i++) {
        Host* discoveredHost = [_hostQueue objectAtIndex:i];
        if ([discoveredHost.uuid isEqualToString:host.uuid]) {
            return YES;
        }
    }
    return NO;
}

- (NSOperation*) createWorkerForHost:(Host*)host {
    DiscoveryWorker* worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:_uniqueId cert:_cert];
    return worker;
}

@end