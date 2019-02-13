/*
 *  MaplyLineAndPointShaders.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 8/21/18.
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

#import "MaplyLineAndPointShaders_private.h"

namespace WhirlyKit
{

static const char *vertexShaderLine = R"(
precision highp float;
    
uniform mat4  u_mvpMatrix;
uniform mat4  u_mvMatrix;
uniform mat4  u_mvNormalMatrix;
uniform float u_fade;

attribute vec3 a_position;
attribute vec4 a_color;
attribute vec3 a_normal;

varying vec4      v_color;
varying float      v_dot;

void main()
{
   vec4 pt = u_mvMatrix * vec4(a_position,1.0);
   pt /= pt.w;
   vec4 testNorm = u_mvNormalMatrix * vec4(a_normal,0.0);
   v_dot = dot(-pt.xyz,testNorm.xyz);
   v_color = a_color * u_fade;
   gl_Position = u_mvpMatrix * vec4(a_position,1.0);
}
)";

static const char *fragmentShaderLine = R"(
precision highp float;

varying vec4      v_color;
varying float      v_dot;

void main()
{
  gl_FragColor = (v_dot > 0.0 ? v_color : vec4(0.0,0.0,0.0,0.0));
}
)";

WhirlyKit::OpenGLES2Program *BuildDefautLineShaderCulling(const std::string &name)
{
    OpenGLES2Program *shader = new OpenGLES2Program(name,vertexShaderLine,fragmentShaderLine);
    if (!shader->isValid())
    {
        delete shader;
        shader = NULL;
    }
    
    return shader;
}

static const char *vertexShaderLineNoBack = R"(
precision highp float;
    
uniform mat4  u_mvpMatrix;
uniform mat4  u_mvMatrix;
uniform mat4  u_mvNormalMatrix;
uniform float u_fade;

attribute vec3 a_position;
attribute vec4 a_color;
attribute vec3 a_normal;

varying vec4      v_color;

void main()
{
   v_color = a_color * u_fade;
   gl_Position = u_mvpMatrix * vec4(a_position,1.0);
}
)";

static const char *fragmentShaderLineNoBack = R"(
precision highp float;

varying vec4      v_color;

void main()
{
  gl_FragColor = v_color;
}
)";

WhirlyKit::OpenGLES2Program *BuildDefaultLineShaderNoCulling(const std::string &name)
{
    OpenGLES2Program *shader = new OpenGLES2Program(name,vertexShaderLineNoBack,fragmentShaderLineNoBack);
    if (!shader->isValid())
    {
        delete shader;
        shader = NULL;
    }
    
    return shader;
}
    
}