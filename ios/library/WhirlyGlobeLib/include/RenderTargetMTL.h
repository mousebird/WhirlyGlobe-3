/*
 *  RenderTargetMTL.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 5/16/19.
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

#import "RenderTarget.h"
#import "WrapperMTL.h"
#import "SceneRendererMTL.h"
#import "TextureMTL.h"

namespace WhirlyKit
{
    class SceneRenderer;
    
/** What and where we're rendering.  This can be a regular framebuffer
 to the screen or to a texture.
 */
class RenderTargetMTL : public RenderTarget
{
public:
    RenderTargetMTL();
    RenderTargetMTL(SimpleIdentity newID);
    virtual ~RenderTargetMTL();
    
    // Set up the render target
    bool init(SceneRenderer *renderer,Scene *scene,SimpleIdentity targetTexID);
    
    // Pull in framebuffer info from the current OpenGL State
    /// Set up the target texture
    virtual bool setTargetTexture(SceneRenderer *renderer,Scene *scene,SimpleIdentity newTargetTexID);
    
    // Clear up resources from the render target
    void clear();
    
    /// Copy the data out of the destination texture and return it
    virtual RawDataRef snapshot();

    /// Copy just a subset of data out of the destination texture
    virtual RawDataRef snapshot(int startX,int startY,int snapWidth,int snapHeight);

    /// Set the GL texture directly
    void setTargetTexture(TextureBaseMTL *tex);
    
public:
    MTLRenderPassDescriptor *renderPassDesc;
};
typedef std::shared_ptr<RenderTargetMTL> RenderTargetMTLRef;
    
}
