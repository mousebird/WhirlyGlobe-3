/*
 *  MaplyTileFetcher.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 6/15/18.
 *  Copyright 2011-2018 Saildrone Inc
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "MaplyTileFetcher_private.h"
#import "MaplyRenderController_private.h"

namespace WhirlyKit
{

// A single tile that we're aware of
class TileInfo
{
public:
    TileInfo() : state(), isLocal(false), importance(0.0), tileSource(NULL) , request(nil), task(nil) { }

    /// Comparison based on importance, tile source, then x,y,level
    bool operator < (const TileInfo &that) const
    {
        if (this->isLocal == that.isLocal) {
            if (this->priority == that.priority) {
                if (this->importance == that.importance) {
                    if (tileSource == that.tileSource) {
                        return request < that.request;
                    }
                    return tileSource < that.tileSource;
                }
                return this->importance < that.importance;
            }
            return this->priority > that.priority;
        }
        return this->isLocal < that.isLocal;
    }

    // We're either loading it or going to load it eventually
    typedef enum {ToLoad,Loading} State;
    State state;
    
    // Set if we know the tile is cached
    bool isLocal;

    // Used to uniquely identify a group of requests
    id tileSource;
    
    // Priority before importance
    int priority;
    
    // Importance of this tile request as passed in by the fetch request
    double importance;
    
    // The request as it came from outside the tile fetcher
    MaplyTileFetchRequest *request;
    
    // If we're loading it, this is the data task associated with it
    NSURLSessionDataTask *task;
};


typedef std::shared_ptr<TileInfo> TileInfoRef;
typedef struct {
    bool operator () (const TileInfoRef a,const TileInfoRef b) const {
        return *a < *b;
    }
} TileInfoSorter;
typedef std::set<TileInfoRef,TileInfoSorter> TileInfoSet;
typedef std::map<MaplyTileFetchRequest *,TileInfoRef> TileFetchMap;

}

using namespace WhirlyKit;

@implementation MaplyTileFetchRequest

-(instancetype)init
{
    self = [super init];
    _tileSource = nil;
    _importance = 0.0;
    
    _success = nil;
    _failure = nil;
    
    return self;
}

@end

@implementation MaplyTileFetcherStats

-(instancetype)initWithFetcher:(MaplyTileFetcher *)fetcher
{
    self = [super init];
    _fetcher = fetcher;
    _startDate = [[NSDate alloc] init];
    _totalRequests = 0;
    _totalCancels = 0;
    _totalFails = 0;
    _remoteData = 0;
    _localData = 0;
    
    return self;
}

- (void)addStats:(MaplyTileFetcherStats * __nonnull)stats
{
    _totalRequests += stats.totalRequests;
    _totalCancels += stats.totalCancels;
    _totalFails += stats.totalFails;
    _remoteData += stats.remoteData;
    _localData += stats.localData;
}

- (void)dump
{
    NSLog(@"---MaplyTileFetcher %@ Stats---",_fetcher.name);
    NSLog(@"   Total Requests = %d",_totalRequests);
    NSLog(@"   Canceled Requests = %d",_totalCancels);
    NSLog(@"   Failed Requests = %d",_totalFails);
    NSLog(@"   Data Transferred = %.2fMB",_remoteData / (1024.0*1024.0));
    NSLog(@"   Cached Data = %.2fMB",_localData / (1024.0*1024.0));
}

@end

@implementation MaplyTileFetcher
{
    bool active;
    NSURLSession *session;
    dispatch_queue_t queue;
    
    TileInfoSet loading;  // Tiles that are currently loading
    TileFetchMap tilesByFetchRequest;  // Tiles sorted by fetch request
    TileInfoSet toLoad;  // Tiles sorted by importance
    
    // Keeps track of stats
    MaplyTileFetcherStats *allStats;
    MaplyTileFetcherStats *recentStats;
}

- (instancetype)initWithName:(NSString *)name connections:(int)numConnections
{
    self = [super init];
    _name = name;
    active = true;
    _numConnections = numConnections;
    // All the internal work is done on a single queue.  Nothing significant, really.
    queue = dispatch_queue_create("MaplyTileFetcher", nil);
    session = [NSURLSession sharedSession];
    allStats = [[MaplyTileFetcherStats alloc] init];
    recentStats = [[MaplyTileFetcherStats alloc] init];
    
    return self;
}

/// Return the fetching stats since the beginning or since the last reset
- (MaplyTileFetcherStats * __nullable)getStats:(bool)allTime
{
    if (allTime)
        return allStats;
    else
        return recentStats;
}

- (void)resetStats
{
    recentStats = [[MaplyTileFetcherStats alloc] initWithFetcher:self];
}

- (dispatch_queue_t)getQueue
{
    return queue;
}

- (id)startTileFetch:(MaplyTileFetchRequest *)request
{
    if (!active)
        return nil;
    
    dispatch_async(queue,
    ^{
        [self startTileFetchLocal:request];
    });
    
    return request;
}

- (void)cancelTileFetch:(MaplyTileFetchRequest *)request
{
    if (!active)
        return;

    dispatch_async(queue,
    ^{
        [self cancelTileFetchLocal:request];
    });
}

// Run on the dispatch queue
- (void)startTileFetchLocal:(MaplyTileFetchRequest *)request
{
    allStats.totalRequests = allStats.totalRequests + 1;
    recentStats.totalRequests = recentStats.totalRequests + 1;
    
    // Set up new request
    TileInfoRef tile(new TileInfo());
    tile->tileSource = request.tileSource;
    tile->importance = request.importance;
    tile->priority = request.priority;
    tile->state = TileInfo::ToLoad;
    tile->request = request;
    tilesByFetchRequest[request] = tile;

    // If it's already cached, just short circuit this
    if (request.cacheFile && [self isTileLocal:tile fileName:request.cacheFile])
        tile->isLocal = true;

    // Just run the normal load
    toLoad.insert(tile);
    
    [self updateLoading];
}

/// Update an active request with a new priority and importance
- (id)updateTileFetch:(id)request priority:(int)priority importance:(double)importance
{
    if (!active)
        return nil;
    
    dispatch_async(queue,
    ^{
       [self updateTileFetchLocal:request priority:priority importance:importance];
    });
    
    return request;
}

// Run on the dispatch queue
- (void)updateTileFetchLocal:(MaplyTileFetchRequest *)request priority:(int)priority importance:(double)importance
{
    auto it = tilesByFetchRequest.find(request);
    if (it == tilesByFetchRequest.end())
        return;
    
    TileInfoRef tile = it->second;
    // Don't mess with a tile that's actually loading
    if (tile->state == TileInfo::ToLoad) {
        // Change the priority/importance and put it back
        toLoad.erase(tile);
        tile->priority = priority;
        tile->importance = importance;
        toLoad.insert(tile);
    }
}

// Run on the dispatch queue
- (void)cancelTileFetchLocal:(MaplyTileFetchRequest *)request
{
    allStats.totalCancels = allStats.totalCancels + 1;
    recentStats.totalCancels = recentStats.totalCancels + 1;

    auto it = tilesByFetchRequest.find(request);
    if (it == tilesByFetchRequest.end()) {
        // Wasn't there.  Ignore.
        return;
    }
    TileInfoRef tile = it->second;
    switch (tile->state) {
        case TileInfo::Loading:
            [tile->task cancel];
            loading.erase(tile);
            break;
        case TileInfo::ToLoad:
            toLoad.erase(tile);
            break;
    }
    tile->task = nil;
    tilesByFetchRequest.erase(it);
    
    [self updateLoading];
}

- (bool)isTileLocal:(TileInfoRef)tile fileName:(NSString *)fileName
{
    if (!fileName)
        return false;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:fileName])
    {
        return true;
        // Note: Consider moving this logic over here
        // If the file is out of date, treat it as if it were not local, as it will have to be fetched.
//        if (self.cachedFileLifetime != 0)
//        {
//            NSDate *fileTimestamp = [MaplyRemoteTileInfo dateForFile:fileName];
//            int ageOfFile = (int) [[NSDate date] timeIntervalSinceDate:fileTimestamp];
//            if (ageOfFile <= self.cachedFileLifetime)
//            {
//                return true;
//            }
//            //            else
//            //            {
//            //                NSLog(@"TileIsLocal returned false due to tile age: %d: (%d,%d)",tileID.level,tileID.x,tileID.y);
//            //            }
//        }
//        else // no lifetime set for cached files
//        {
//            return true;
//        }
    }
    
    return false;
}

- (void)writeToCache:(TileInfoRef)tileInfo tileData:(NSData *)tileData
{
    if (tileInfo->request.cacheFile) {
        NSString *dir = [tileInfo->request.cacheFile stringByDeletingLastPathComponent];
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
        [tileData writeToFile:tileInfo->request.cacheFile atomically:NO];
    }
}

- (NSData *)readFromCache:(TileInfoRef)tileInfo
{
    if (!tileInfo->request.cacheFile)
        return nil;
    return [NSData dataWithContentsOfFile:tileInfo->request.cacheFile];
}

// Run on the dispatch queue
- (void)updateLoading
{
    // Ask for a few more to load
    while (loading.size() < _numConnections) {
        auto nextLoad = toLoad.rbegin();
        if (nextLoad == toLoad.rend())
            break;
        
        // Move it into loading
        TileInfoRef tile = *nextLoad;
        toLoad.erase(std::next(nextLoad).base());
        tile->state = TileInfo::Loading;
        loading.insert(tile);
        
        NSURLRequest *urlReq = tile->request.urlReq;
        
        // Set up the fetch task so we can use it in a couple places
        tile->task = [session dataTaskWithRequest:urlReq completionHandler:
                      ^(NSData * _Nullable data, NSURLResponse * _Nullable inResponse, NSError * _Nullable error) {
                          NSHTTPURLResponse *response = (NSHTTPURLResponse *)inResponse;
                          dispatch_async(self->queue,
                                         ^{
                              if (error || response.statusCode != 200) {
                                  // Cancels don't count as errors
                                  if (!error || error.code != NSURLErrorCancelled) {
                                      self->allStats.totalFails = self->allStats.totalFails + 1;
                                      self->recentStats.totalFails = self->recentStats.totalFails + 1;
                                      [self finishedLoading:tile data:nil error:error];
                                  }
                              } else {
                                  int length = [data length];
                                  self->allStats.remoteData = self->allStats.remoteData + length;
                                  self->recentStats.remoteData = self->recentStats.remoteData + length;
                                  [self finishedLoading:tile data:data error:error];
                                  [self writeToCache:tile tileData:data];
                              }
                        });
                      }];
        
        // Look for it cached
        if ([self isTileLocal:tile fileName:tile->request.cacheFile]) {
            // Do the reading somewhere else
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [self readFromCache:tile];
                if (!data) {
                    // It failed (which happens) so we need to fetch it after all
                    [tile->task resume];
                } else {
                    // It worked, but run the finished loading back on our queue
                    dispatch_async(self->queue,^{
                        int length = [data length];
                        self->allStats.localData = self->allStats.localData + length;
                        self->recentStats.localData = self->recentStats.localData + length;
                        [self finishedLoading:tile data:data error:nil];
                    });
                }
            });
        } else {
            [tile->task resume];
        }
    }
}

// Called on our queue
- (void)finishTile:(TileInfoRef)tile
{
    auto it = tilesByFetchRequest.find(tile->request);
    if (it != tilesByFetchRequest.end())
        tilesByFetchRequest.erase(it);
    loading.erase(tile);
    toLoad.erase(tile);
}

// Called on our queue
- (void)finishedLoading:(TileInfoRef)tile data:(NSData *)data error:(NSError *)error
{
    auto it = tilesByFetchRequest.find(tile->request);
    if (it == tilesByFetchRequest.end())
        // No idea what it is.  Toss it.
        return;
    
    MaplyTileFetcher * __weak weakSelf = self;
    
    // Do the callback on a background queue
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    ^{
        // We assume the parsing is going to take some time
        if (data) {
           tile->request.success(tile->request,data);
        } else {
           tile->request.failure(tile->request, error);
        }

        dispatch_queue_t theQueue = [weakSelf getQueue];
        if (theQueue)
            dispatch_async(theQueue,
            ^{
                [weakSelf finishTile:tile];

                [weakSelf updateLoading];
            });
    });
}

- (void)shutdown
{
    active = false;
    
    // Execute an empty task and wait for it to return
    // This drains the queue
    dispatch_sync(queue, ^{});
    
    toLoad.clear();
    loading.clear();
    tilesByFetchRequest.clear();
}

@end
