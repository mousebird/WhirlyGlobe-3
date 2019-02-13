/*
 *  SceneRendererES2.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 10/23/12.
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

#import "SceneRendererES.h"
#import "Lighting.h"
#import "WhirlyTypes.h"
#import "glwrapper.h"

namespace WhirlyKit
{
/** Scene Renderer for OpenGL ES2.
     This implements the actual rendering.  In theory it's
     somewhat composable, but in reality not all that much.
     Just set this up as in the examples and let it run.
 */
class SceneRendererES2 : public SceneRendererES
{
public:
    EIGEN_MAKE_ALIGNED_OPERATOR_NEW;

    SceneRendererES2();
    virtual ~SceneRendererES2();
    
    /// Add a light to the existing set
    void addLight(const DirectionalLight &light);
    
    /// Replace all the lights at once. nil turns off lighting
    void replaceLights(const std::vector<DirectionalLight> &lights);
    
    /// Set the default material
    void setDefaultMaterial(const Material &mat);
    
    /// The next time through we'll redo the render setup.
    /// We might need this if the view has switched away and then back.
    void forceRenderSetup();
    
    virtual void setScene(Scene *inScene);
    
    void setClearColor(const RGBAColor &color);
        
    void processScene();

    void render(TimeInterval duration);
    
    bool hasChanges();
    
protected:
    TimeInterval lightsLastUpdated;
    Material defaultMat;
    
    bool extraFrameDrawn;
    std::vector<DirectionalLight> lights;
};

typedef std::shared_ptr<SceneRendererES2> SceneRendererES2Ref;
    
}
