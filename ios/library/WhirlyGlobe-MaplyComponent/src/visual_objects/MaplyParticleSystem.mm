/*
 *  MaplyParticleSystem.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 4/26/15.
 *  Copyright 2011-2019 mousebird consulting
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

#import "MaplyParticleSystem_private.h"
#import "MaplyRenderTarget_private.h"
#import "MaplySharedAttributes.h"
#import "MaplyRenderController_private.h"

namespace WhirlyKit
{
    
int ParticleSystemAttribute::dataSize()
{
    switch (type)
    {
        case MaplyShaderAttrTypeInt:
            return 4;
            break;
        case MaplyShaderAttrTypeFloat:
            return 4;
            break;
        case MaplyShaderAttrTypeFloat2:
            return 4*2;
            break;
        case MaplyShaderAttrTypeFloat3:
            return 4*3;
            break;
        case MaplyShaderAttrTypeFloat4:
            return 4*4;
            break;
        default:
            return 0;
            break;
    }
}
    
}

using namespace WhirlyKit;

@interface MaplyParticleSystem()
@property (nonatomic,assign) int numRegAttrs;
@end

@implementation MaplyParticleSystem

- (instancetype)initWithName:(NSString *)name viewC:(NSObject<MaplyRenderControllerProtocol> *)viewC
{
    self = [super init];
    if (!self)
        return nil;

    _ident = WhirlyKit::EmptyIdentity;
    _name = name;
    _type = MaplyParticleSystemTypePoint;
    _lifetime = 5.0;
    _batchSize = 2000;
    _totalParticles = 100000;
    _viewC = viewC;
    MaplyRenderController *renderControl = [_viewC getRenderControl];
    _baseTime = renderControl->scene->getCurrentTime();
    _renderTargetID = EmptyIdentity;
    _numRegAttrs = 0;
    _vertexSize = 0;
    
    return self;
}

- (void)addAttribute:(NSString *)attrName type:(MaplyShaderAttrType)type
{
    WhirlyKit::ParticleSystemAttribute attr;
    attr.name = attrName;
    attr.type = type;
    
    self.attrs.insert(attr);
    _numRegAttrs++;
}

- (void)addVarying:(NSString *)varyAttrName inputName:(NSString *)inputName type:(MaplyShaderAttrType)type
{
    WhirlyKit::ParticleSystemAttribute attr;
    attr.name = inputName;
    attr.varyName = varyAttrName;
    attr.type = type;
    
    self.attrs.insert(attr);
}

- (void)addTexture:(id)image
{
    _images.push_back(image);
}

- (void)setRenderTarget:(MaplyRenderTarget *)renderTarget
{
    _renderTargetID = renderTarget.renderTargetID;
}

@end

@implementation MaplyParticleBatch

- (id) initWithParticleSystem:(MaplyParticleSystem *)partSys
{
    self = [super init];
    if (!self)
        return nil;
    _partSys = partSys;
    MaplyRenderController *renderControl = [partSys.viewC getRenderControl];
    _time = renderControl->scene->getCurrentTime();
    
    return self;
}

- (bool) addAttribute:(NSString *)attrName values:(NSData *)data
{
    // Look for the name
    for (auto attr : _partSys.attrs)
    {
        if ([attrName isEqualToString:attr.name])
        {
            // Found it.  Now make sure the size matches
            WhirlyKit::ParticleSystemAttrVals attrVals;
            attrVals.attrID = attr.getId();
            attrVals.data = data;
            if ([data length] != attr.dataSize() * _partSys.batchSize)
                return false;
            self.attrVals.push_back(attrVals);
            
            return true;
        }
    }
    
    return false;
}

- (void) addData:(NSData *)data
{
    self.data = data;
}

- (bool) isValid
{
    return _partSys.numRegAttrs == self.attrVals.size();
}

@end
