/*
 *  MaplyQuadImageFrameLoader.mm
 *
 *  Created by Steve Gifford on 9/13/18.
 *  Copyright 2012-2018 mousebird consulting inc
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

#import "MaplyQuadImageFrameLoader.h"
#import "MaplyBaseViewController_private.h"
#import "MaplyShader_private.h"
#import "MaplyRenderTarget_private.h"
#import "MaplyScreenLabel.h"
#import "MaplyQuadImageLoader_private.h"
#import "MaplyQuadLoader_private.h"
#import "MaplyImageTile_private.h"

using namespace WhirlyKit;

@implementation MaplyImageLoaderReturn

- (void)addImageTile:(MaplyImageTile *)image
{
    loadReturn->images.push_back(image->imageTile);
}

- (void)addImage:(UIImage *)image
{
    ImageTile_iOSRef imageTile = ImageTile_iOSRef(new ImageTile_iOS());
    imageTile->type = MaplyImgTypeImage;
    imageTile->components = 4;
    imageTile->width = -1;
    imageTile->height = -1;
    imageTile->borderSize = 0;
    imageTile->imageStuff = image;
    
    loadReturn->images.push_back(imageTile);
}

- (NSArray<MaplyImageTile *> *)getImages
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto imageTile : loadReturn->images) {
        ImageTile_iOSRef imageTileiOS = std::dynamic_pointer_cast<ImageTile_iOS>(imageTile);
        MaplyImageTile *imgTileObj = [[MaplyImageTile alloc] init];
        imgTileObj->imageTile = imageTileiOS;
        [ret addObject:imgTileObj];
    }
    
    return ret;
}

- (void)addCompObjs:(NSArray<MaplyComponentObject *> *)compObjs
{
    for (MaplyComponentObject *compObj in compObjs)
        loadReturn->compObjs.push_back(compObj->contents);
}

- (NSArray<MaplyComponentObject *> *)getCompObjs
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto compObj : loadReturn->compObjs) {
        MaplyComponentObject *compObjWrap = [[MaplyComponentObject alloc] init];
        compObjWrap->contents = compObj;
        [ret addObject:compObjWrap];
    }
    
    return ret;
}

- (void)addOvlCompObjs:(NSArray<MaplyComponentObject *> *)compObjs
{
    for (MaplyComponentObject *compObj in compObjs)
        loadReturn->ovlCompObjs.push_back(compObj->contents);
}

- (NSArray<MaplyComponentObject *> *)getOvlCompObjs
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto compObj : loadReturn->ovlCompObjs) {
        MaplyComponentObject *compObjWrap = [[MaplyComponentObject alloc] init];
        compObjWrap->contents = compObj;
        [ret addObject:compObjWrap];
    }
    
    return ret;
}

@end

@implementation MaplyImageLoaderInterpreter

- (void)dataForTile:(MaplyImageLoaderReturn * __nonnull)loadReturn
{
    NSArray *tileDatas = [loadReturn getTileData];
    
    for (NSData *tileData in tileDatas) {
        MaplyImageTile *imageTile = [[MaplyImageTile alloc] initWithPNGorJPEGData:tileData];
        [loadReturn addImageTile:imageTile];
    }
}

@end

@implementation MaplyOvlDebugImageLoaderInterpreter
{
    MaplyBaseViewController * __weak viewC;
    MaplyQuadLoaderBase * __weak loader;
    UIFont *font;
}

- (id)initWithLoader:(MaplyQuadLoaderBase *)inLoader viewC:(MaplyBaseViewController *)inViewC
{
    self = [super init];
    loader = inLoader;
    viewC = inViewC;
    font = [UIFont systemFontOfSize:12.0];
    
    return self;
}

- (void)dataForTile:(MaplyImageLoaderReturn * __nonnull)loadReturn
{
    [super dataForTile:loadReturn];
    
    MaplyBoundingBox bbox = [loader geoBoundsForTile:loadReturn.tileID];
    MaplyScreenLabel *label = [[MaplyScreenLabel alloc] init];
    MaplyCoordinate center;
    center.x = (bbox.ll.x+bbox.ur.x)/2.0;  center.y = (bbox.ll.y+bbox.ur.y)/2.0;
    label.loc = center;
    label.text = [NSString stringWithFormat:@"%d: (%d,%d)",loadReturn.tileID.level,loadReturn.tileID.x,loadReturn.tileID.y];
    label.layoutImportance = MAXFLOAT;
    
    MaplyComponentObject *labelObj = [viewC addScreenLabels:@[label] desc:
                                      @{kMaplyFont: font,
                                        kMaplyTextColor: UIColor.blackColor,
                                        kMaplyTextOutlineColor: UIColor.whiteColor,
                                        kMaplyTextOutlineSize: @(2.0)
                                        }
                                                       mode:MaplyThreadCurrent];
    
    MaplyCoordinate coords[5];
    coords[0] = bbox.ll;  coords[1] = MaplyCoordinateMake(bbox.ur.x, bbox.ll.y);
    coords[2] = bbox.ur;  coords[3] = MaplyCoordinateMake(bbox.ll.x, bbox.ur.y);
    coords[4] = coords[0];
    MaplyVectorObject *vecObj = [[MaplyVectorObject alloc] initWithLineString:coords numCoords:5 attributes:nil];
    [vecObj subdivideToGlobe:0.001];
    MaplyComponentObject *outlineObj = [viewC addVectors:@[vecObj] desc:nil mode:MaplyThreadCurrent];
    
    [loadReturn addCompObjs:@[labelObj,outlineObj]];
}

@end

@implementation MaplyDebugImageLoaderInterpreter
{
    MaplyBaseViewController * __weak viewC;
}

- (instancetype)initWithLoader:(MaplyQuadLoaderBase *)inLoader viewC:(MaplyBaseViewController *)inViewC
{
    self = [super init];
    
    viewC = inViewC;
    
    return self;
}

static const int MaxDebugColors = 10;
static const int debugColors[MaxDebugColors] = {0x86812D, 0x5EB9C9, 0x2A7E3E, 0x4F256F, 0xD89CDE, 0x773B28, 0x333D99, 0x862D52, 0xC2C653, 0xB8583D};

- (void)dataForTile:(MaplyImageLoaderReturn *)loadReturn
{
    MaplyTileID tileID = loadReturn.tileID;
    
    CGSize size;  size = CGSizeMake(256,256);
    UIGraphicsBeginImageContext(size);
    
    // Draw into the image context
    int hexColor = debugColors[loadReturn.tileID.level % MaxDebugColors];
    float red = (((hexColor) >> 16) & 0xFF)/255.0;
    float green = (((hexColor) >> 8) & 0xFF)/255.0;
    float blue = (((hexColor) >> 0) & 0xFF)/255.0;
    UIColor *backColor = nil;
    UIColor *fillColor = [UIColor whiteColor];
    backColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.7];
    fillColor = [UIColor colorWithRed:red green:green blue:blue alpha:0.7];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // Draw a rectangle around the edges for testing
    [backColor setFill];
    CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
    [fillColor setStroke];
    CGContextStrokeRect(ctx, CGRectMake(0, 0, size.width-1, size.height-1));
    
    [fillColor setStroke];
    [fillColor setFill];
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    NSString *textStr = nil;
    if (loadReturn.frame == -1) {
        textStr = [NSString stringWithFormat:@"%d: (%d,%d)",tileID.level,tileID.x,tileID.y];
    }
    else
        textStr = [NSString stringWithFormat:@"%d: (%d,%d); %d",tileID.level,tileID.x,tileID.y,loadReturn.frame];
    [[UIColor whiteColor] setStroke];
    [[UIColor whiteColor] setFill];
    [textStr drawInRect:CGRectMake(0,0,size.width,size.height) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:24.0]}];
    
    // Grab the image and shut things down
    UIImage *retImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [loadReturn addImage:retImage];
}

@end

NSString * const MaplyQuadImageLoaderFetcherName = @"QuadImageLoader";

@implementation MaplyQuadImageFrameAnimator
{
    MaplyBaseViewController * __weak viewC;
    MaplyQuadImageFrameLoader * __weak loader;
    TimeInterval startTime;
    int numFrames;
}

- (instancetype)initWithFrameLoader:(MaplyQuadImageFrameLoader *)inLoader viewC:(MaplyBaseViewController * __nonnull)inViewC
{
    self = [super init];
    loader = inLoader;
    viewC = inViewC;
    startTime = TimeGetCurrent();
    _period = 10.0;
    _pauseLength = 0.0;
    numFrames = [loader getNumFrames];

    [viewC addActiveObject:self];

    return self;
}

- (void)shutdown
{
    [viewC removeActiveObject:self];
    loader = nil;
    viewC = nil;
}

// MARK: ActiveObject methods

// Have to do the position update in the setCurrentImage so we're not messing with the rendering loop
- (bool)hasUpdate
{
    if (!viewC || !loader)
        return false;

    TimeInterval now = TimeGetCurrent();
    TimeInterval totalPeriod = _period + _pauseLength;
    double when = fmod(now-startTime,totalPeriod);
    if (when >= _period)
        // Snap it to the end for a while
        [loader setCurrentImage:numFrames-1];
    else {
        double where = when/_period * (numFrames-1);
        [loader setCurrentImage:where];
    }

    return false;
}

- (void)updateForFrame:(void *)frameInfo
{
}

- (void)teardown
{
    loader = nil;
}

@end

@interface MaplyQuadImageFrameLoader()<QuadImageFrameLoaderLayer>
@end

@implementation MaplyQuadImageFrameLoader

- (nullable instancetype)initWithParams:(MaplySamplingParams *__nonnull)inParams tileInfos:(NSArray<NSObject<MaplyTileInfoNew> *> *__nonnull)frameInfos viewC:(MaplyBaseViewController * __nonnull)inViewC
{
    if (!inParams.singleLevel) {
        NSLog(@"MaplyQuadImageFrameLoader only supports samplers with singleLevel set to true");
        return nil;
    }
    self = [super init];

    self->viewC = inViewC;
    params = inParams;

    // Loader does all the work.  The Obj-C version is just a wrapper
    self->loader = QuadImageFrameLoader_iosRef(new QuadImageFrameLoader_ios(params->params,frameInfos));
    
    self.baseDrawPriority = kMaplyImageLayerDrawPriorityDefault;
    self.drawPriorityPerLevel = 100;
    
    self.flipY = true;
    self.debugMode = false;
    self->minLevel = 10000;
    self->maxLevel = -1;
    for (MaplyRemoteTileInfoNew *frameInfo in frameInfos) {
        self->minLevel = std::min(self->minLevel,frameInfo.minZoom);
        self->maxLevel = std::max(self->maxLevel,frameInfo.maxZoom);
    }
    self->valid = true;
    
    return self;
}

- (bool)delayedInit
{
    if (!loadInterp) {
        loadInterp = [[MaplyImageLoaderInterpreter alloc] init];
    }
    loader->layer = self;

    // Hook into the active updater to organize geometry for rendering
    viewC->renderControl->scene->addActiveModel(loader);

    if (![super delayedInit])
        return false;

    return true;
}

- (void)setCurrentImage:(double)where
{
    double curFrame = std::min(std::max(where,0.0),(double)([loader->frameInfos count]-1));
    loader->setCurFrame(curFrame);
}

- (int)getNumFrames
{
    return [loader->frameInfos count];
}

// Called on a random dispatch queue
- (void)fetchRequestSuccess:(MaplyTileFetchRequest *)request tileID:(MaplyTileID)tileID frame:(int)frame data:(NSData *)data;
{
    if (loader->getDebugMode())
        NSLog(@"MaplyQuadImageLoader: Got fetch back for tile %d: (%d,%d) frame %d",tileID.level,tileID.x,tileID.y,frame);
    
    // Ask the interpreter to parse it
    MaplyImageLoaderReturn *loadData = [[MaplyImageLoaderReturn alloc] init];
    loadData.tileID = tileID;
    loadData.frame = frame;
    [loadData addTileData:data];
    
    [self performSelector:@selector(mergeFetchRequest:) onThread:self->samplingLayer.layerThread withObject:loadData waitUntilDone:NO];
}

// Called on SamplingLayer.layerThread
- (void)fetchRequestFail:(MaplyTileFetchRequest *)request tileID:(MaplyTileID)tileID frame:(int)frame error:(NSError *)error
{
 // Note: Need to do something more here for single frame cases
 
 NSLog(@"MaplyQuadImageLoader: Failed to fetch tile %d: (%d,%d) frame %d because:\n%@",tileID.level,tileID.x,tileID.y,frame,[error localizedDescription]);
}

// Called on the SamplingLayer.LayerThread
- (void)mergeFetchRequest:(MaplyLoaderReturn *)loadReturn
{
    if (!loader)
        return;

    // Don't actually want this one
    if (!loader->isFrameLoading(loadReturn->loadReturn->ident,loadReturn->loadReturn->frame))
        return;

    // Do the parsing on another thread since it can be slow
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self->loadInterp dataForTile:loadReturn];
     
        [self performSelector:@selector(mergeLoadedTile:) onThread:self->samplingLayer.layerThread withObject:loadReturn waitUntilDone:NO];
    });
}

// Called on the SamplingLayer.LayerThread
- (void)mergeLoadedTile:(MaplyLoaderReturn *)loadReturn
{
    if (!loader)
        return;
    
    ChangeSet changes;
    loader->mergeLoadedTile(loadReturn->loadReturn.get(),changes);

    [samplingLayer.layerThread addChangeRequests:changes];
}

- (void)cleanup
{
    ChangeSet changes;

    loader->cleanup(changes);
    [samplingLayer.layerThread addChangeRequests:changes];

    loader = nil;
}

- (void)shutdown
{
    ChangeSet changes;
    
    valid = false;
    
    self->samplingLayer.layerThread.scene->removeActiveModel(loader);
    
    if (self->samplingLayer && self->samplingLayer.layerThread)
        [self performSelector:@selector(cleanup) onThread:self->samplingLayer.layerThread withObject:nil waitUntilDone:NO];
    
    [viewC releaseSamplingLayer:samplingLayer forUser:loader];
}

@end
