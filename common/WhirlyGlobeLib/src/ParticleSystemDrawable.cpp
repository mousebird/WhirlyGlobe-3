/*
 *  ParticleSystemDrawable.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 4/28/15.
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

#import "ParticleSystemDrawable.h"
#import "GLUtils.h"
#import "BasicDrawable.h"
#import "GlobeScene.h"
#import "SceneRendererES.h"
#import "TextureAtlas.h"
#import "WhirlyKitLog.h"


namespace WhirlyKit
{

ParticleSystemDrawable::ParticleSystemDrawable(const std::string &name,
                                               const std::vector<SingleVertexAttributeInfo> &inVertAttrs,
                                               const std::vector<SingleVertexAttributeInfo> &inVaryAttrs,
                                               int numTotalPoints,int batchSize,bool useRectangles,bool useInstancing)
    : Drawable(name), enable(true), numTotalPoints(numTotalPoints), batchSize(batchSize), vertexSize(0), calculateProgramId(0), renderProgramId(0), drawPriority(0), pointBuffer(0), rectBuffer(0), requestZBuffer(false), writeZBuffer(false), minVis(0.0), maxVis(10000.0), useRectangles(useRectangles), useInstancing(useInstancing), baseTime(0.0), startb(0), endb(0), chunksDirty(true), usingContinuousRender(true), renderTargetID(EmptyIdentity), lastUpdateTime(0.0), activeVaryBuffer(0)
{
    for (auto attr : inVertAttrs)
    {
        vertexSize += attr.size();
        vertAttrs.push_back(attr);
    }
    varyAttrs = inVaryAttrs;
}
    
ParticleSystemDrawable::~ParticleSystemDrawable()
{
}
    
bool ParticleSystemDrawable::isOn(RendererFrameInfo *frameInfo) const
{
    if (!enable)
        return false;
    
    return true;
}

void ParticleSystemDrawable::setupGL(WhirlyKitGLSetupInfo *setupInfo,OpenGLMemManager *memManager)
{
    if (pointBuffer != 0)
        return;

    int totalBytes = vertexSize*numTotalPoints;
    pointBuffer = memManager->getBufferID(totalBytes,GL_DYNAMIC_DRAW);
    
    // Set up rectangles
    if (useRectangles)
    {
        // Build up the coordinates for two rectangles
        if (useInstancing)
        {
            Point2f verts[2*6];
            verts[0] = Point2f(-1,-1);
            verts[1] = Point2f(0,0);
            verts[2] = Point2f(1,-1);
            verts[3] = Point2f(1.0,0);
            verts[4] = Point2f(1,1);
            verts[5] = Point2f(1.0,1.0);
            verts[6] = Point2f(-1,-1);
            verts[7] = Point2f(0,0);
            verts[8] = Point2f(1,1);
            verts[9] = Point2f(1.0,1.0);
            verts[10] = Point2f(-1,1);
            verts[11] = Point2f(0,1.0);
            
            int rectSize = 2*sizeof(float)*6*2;
            rectBuffer = memManager->getBufferID(0,GL_STATIC_DRAW);
            
            glBindBuffer(GL_ARRAY_BUFFER, rectBuffer);
            glBufferData(GL_ARRAY_BUFFER, rectSize, (const GLvoid *)&verts[0], GL_STATIC_DRAW);
            glBindBuffer(GL_ARRAY_BUFFER, 0);
        } else {
            wkLogLevel(Error,"ParticleSystemDrawable: Can only do instanced rectangles at present.  This system can't handle instancing.");
        }
    }
    
    // If we have varyings we need buffers to hold them
    for (auto varyAttr : varyAttrs) {
        GLuint totalSize = varyAttr.size()*numTotalPoints;
        
        VaryBufferPair bufferPair;
        for (unsigned int ii=0;ii<2;ii++) {
            bufferPair.buffers[ii] = memManager->getBufferID(totalSize,GL_DYNAMIC_DRAW);

            // Zero out the new buffers
            // That's how we signal that they're new
            glBindBuffer(GL_ARRAY_BUFFER, bufferPair.buffers[ii]);
            void *glMem = NULL;
            if (setupInfo->glesVersion < 3)
                glMem = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
            else
                glMem = glMapBufferRange(GL_ARRAY_BUFFER, 0, totalSize, GL_MAP_WRITE_BIT);
            memset(glMem, 0, totalSize);
            if (setupInfo->glesVersion < 3)
                glUnmapBufferOES(GL_ARRAY_BUFFER);
            else
                glUnmapBuffer(GL_ARRAY_BUFFER);
            glBindBuffer(GL_ARRAY_BUFFER, 0);

        }
        varyBuffers.push_back(bufferPair);
    }
    
    // Set up the batches
    int numBatches = numTotalPoints / batchSize;
    int batchBufLen = batchSize * vertexSize;
    batches.resize(numBatches);
    unsigned int bufOffset = 0;
    for (unsigned int ii=0;ii<numBatches;ii++)
    {
        Batch &batch = batches[ii];
        batch.active = false;
        batch.batchID = ii;
        batch.offset = bufOffset;
        batch.len = batchBufLen;
        bufOffset += batchBufLen;
    }
    chunks.clear();
    chunksDirty = true;
    
    // Zero it out to avoid warnings
//    glBindBuffer(GL_ARRAY_BUFFER, pointBuffer);
//    void *glMem = NULL;
//    EAGLContext *context = [EAGLContext currentContext];
//    if (context.API < kEAGLRenderingAPIOpenGLES3)
//        glMem = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
//    else
//        glMem = glMapBufferRange(GL_ARRAY_BUFFER, 0, totalBytes, GL_MAP_WRITE_BIT);
//    memset(glMem, 0, totalBytes);
//    if (context.API < kEAGLRenderingAPIOpenGLES3)
//        glUnmapBufferOES(GL_ARRAY_BUFFER);
//    else
//        glUnmapBuffer(GL_ARRAY_BUFFER);
//    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void ParticleSystemDrawable::teardownGL(OpenGLMemManager *memManager)
{
    if (pointBuffer)
        memManager->removeBufferID(pointBuffer);
    pointBuffer = 0;
    if (rectBuffer)
        memManager->removeBufferID(rectBuffer);
    for (auto bufferPair : varyBuffers)
        for (unsigned int ii=0;ii<2;ii++)
            memManager->removeBufferID(bufferPair.buffers[ii]);
    varyBuffers.clear();
    rectBuffer = 0;
    batches.clear();
    chunks.clear();
}
    
void ParticleSystemDrawable::updateRenderer(SceneRendererES *renderer)
{
    if (usingContinuousRender)
        renderer->addContinuousRenderRequest(getId());
}
    
void ParticleSystemDrawable::addAttributeData(WhirlyKitGLSetupInfo *setupInfo,const std::vector<AttributeData> &attrData,const Batch &batch)
{
    if (attrData.size() != vertAttrs.size())
        return;

    // Note: Android.  Needs hasMapBufferSupport check
    // When the particles initialize themselves we don't have vertex data
    if (vertexSize > 0) {
        glBindBuffer(GL_ARRAY_BUFFER, pointBuffer);
        unsigned char *glMem = NULL;
        int glMemOffset = 0;
        if (setupInfo->glesVersion < 3)
        {
            glMem = (unsigned char *)glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
            glMemOffset = batch.batchID*vertexSize*batchSize;
        } else {
            glMem = (unsigned char *)glMapBufferRange(GL_ARRAY_BUFFER, batch.batchID*vertexSize*batchSize, vertexSize*batchSize, GL_MAP_WRITE_BIT);
        }
        
        // Work through the attribute blocks
        int attrOffset = 0;
        for (unsigned int ai=0;ai<vertAttrs.size();ai++)
        {
            const AttributeData &thisAttrData = attrData[ai];
            SingleVertexAttributeInfo &attrInfo = vertAttrs[ai];
            int attrSize = attrInfo.size();
            unsigned char *rawAttrData = (unsigned char *)thisAttrData.data;
            unsigned char *ptr = glMem + attrOffset + glMemOffset;
            // Copy into each vertex
            for (unsigned int ii=0;ii<batchSize;ii++)
            {
                memcpy(ptr, rawAttrData, attrSize);
                ptr += vertexSize;
                rawAttrData += attrSize;
            }
            
            attrOffset += attrSize;
        }
        
        if (setupInfo->glesVersion < 3)
            glUnmapBufferOES(GL_ARRAY_BUFFER);
        else
            glUnmapBuffer(GL_ARRAY_BUFFER);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    
    {
        std::lock_guard<std::mutex> guardLock(batchLock);
        batches[batch.batchID] = batch;
        batches[batch.batchID].active = true;
        chunksDirty = true;
    }
}
    
void ParticleSystemDrawable::updateBatches(TimeInterval now)
{
    {
        std::lock_guard<std::mutex> guardLock(batchLock);
        // Check the batches to see if any have gone off
        for (int bi=startb;bi<endb;)
        {
            Batch &batch = batches[bi % batches.size()];
            if (batch.active)
            {
                if (batch.startTime + lifetime < now)
                {
                    batch.active = false;
                    chunksDirty = true;
                    startb++;
                }
            } else
                break;
            
            bi++;
        }
    }
    
    updateChunks();
}
    
void ParticleSystemDrawable::updateChunks()
{
    if (!chunksDirty)
        return;
    
    std::lock_guard<std::mutex> guardLock(batchLock);

    chunksDirty = false;
    chunks.clear();
    if (startb != endb)
    {
        int start = 0;
        do {
            // Skip empty batches at the beginning
            for (;start < batches.size() && !batches[start].active;start++);

            int end = start;
            if (start < batches.size())
            {
                for (;end < batches.size() && batches[end].active;end++);
                if (start != end)
                {
                    BufferChunk chunk;
                    chunk.bufferStart = (start % batches.size()) * batchSize * vertexSize;
                    chunk.vertexStart = (start % batches.size()) * batchSize;
                    chunk.numVertices = (end-start) * batchSize;
                    chunks.push_back(chunk);
                }
            }
            
            start = end;
        } while (start < batches.size());
    }
}
    
bool ParticleSystemDrawable::findEmptyBatch(Batch &retBatch)
{
    bool ret = false;
    
    std::lock_guard<std::mutex> guardLock(batchLock);
    if (!batches[endb % batches.size()].active)
    {
        ret = true;
        retBatch = batches[endb % batches.size()];
        endb++;
    }
    
    return ret;
}
    
void ParticleSystemDrawable::drawSetupTextures(RendererFrameInfo *frameInfo,Scene *scene,OpenGLES2Program *prog,bool hasTexture[],int &progTexBound)
{
    // GL Texture IDs
    bool anyTextures = false;
    std::vector<GLuint> glTexIDs;
    for (SimpleIdentity texID : texIDs)
    {
        GLuint glTexID = scene->getGLTexture(texID);
        anyTextures = true;
        glTexIDs.push_back(glTexID);
    }
    
    // The program itself may have some textures to bind
    progTexBound = prog->bindTextures();
    for (unsigned int ii=0;ii<progTexBound;ii++)
        hasTexture[ii] = true;
    
    // Zero or more textures in the drawable
    for (unsigned int ii=0;ii<WhirlyKitMaxTextures-progTexBound;ii++)
    {
        GLuint glTexID = ii < glTexIDs.size() ? glTexIDs[ii] : 0;
        auto baseMapNameID = baseMapNameIDs[ii];
        auto hasBaseMapNameID = hasBaseMapNameIDs[ii];
        const OpenGLESUniform *texUni = prog->findUniform(baseMapNameID);
        hasTexture[ii+progTexBound] = glTexID != 0 && texUni;
        if (hasTexture[ii+progTexBound])
        {
            glActiveTexture(GL_TEXTURE0+ii+progTexBound);
            glBindTexture(GL_TEXTURE_2D, glTexID);
            CheckGLError("BasicDrawable::drawVBO2() glBindTexture");
            prog->setUniform(baseMapNameID, (int)ii+progTexBound);
            CheckGLError("BasicDrawable::drawVBO2() glUniform1i");
            prog->setUniform(hasBaseMapNameID, 1);
        } else {
            prog->setUniform(hasBaseMapNameID, 0);
        }
    }
}
    
void ParticleSystemDrawable::drawTeardownTextures(RendererFrameInfo *frameInfo,Scene *scene,OpenGLES2Program *prog,bool hasTexture[],int progTexBound)
{
    // Unbind any textures
    for (unsigned int ii=0;ii<WhirlyKitMaxTextures;ii++)
        if (hasTexture[ii])
        {
            glActiveTexture(GL_TEXTURE0+ii);
            glBindTexture(GL_TEXTURE_2D, 0);
        }
}
    
void ParticleSystemDrawable::drawSetupUniforms(RendererFrameInfo *frameInfo,Scene *scene,OpenGLES2Program *prog)
{
    // Model/View/Projection matrix
    prog->setUniform(mvpMatrixNameID, frameInfo->mvpMat);
    prog->setUniform(mvpInvMatrixNameID, frameInfo->mvpInvMat);
    prog->setUniform(mvMatrixNameID, frameInfo->viewAndModelMat);
    prog->setUniform(mvNormalMatrixNameID, frameInfo->viewModelNormalMat);
    prog->setUniform(mvpNormalMatrixNameID, frameInfo->mvpNormalMat);
    prog->setUniform(u_pMatrixNameID, frameInfo->projMat);
    prog->setUniform(u_ScaleNameID, Point2f(2.f/(float)frameInfo->sceneRenderer->framebufferWidth,2.f/(float)frameInfo->sceneRenderer->framebufferHeight));
    
    // Size of a single pixel
    Point2f pixDispSize(frameInfo->screenSizeInDisplayCoords.x()/frameInfo->sceneRenderer->framebufferWidth,frameInfo->screenSizeInDisplayCoords.y()/frameInfo->sceneRenderer->framebufferHeight);
    
    // If this is present, the drawable wants to do something based where the viewer is looking
    prog->setUniform(u_EyeVecNameID, frameInfo->fullEyeVec);
    prog->setUniform(u_EyePosNameID, Vector3dToVector3f(frameInfo->eyePos));

    prog->setUniform(u_SizeNameID, pointSize);
    prog->setUniform(u_TimeNameID, (float)(frameInfo->currentTime-baseTime));
    prog->setUniform(u_lifetimeNameID, (float)lifetime);
    prog->setUniform(u_pixDispSizeNameID, pixDispSize);
    prog->setUniform(u_frameLenID, (float)frameInfo->frameLen);
}
    
void ParticleSystemDrawable::drawBindAttrs(RendererFrameInfo *frameInfo,Scene *scene,OpenGLES2Program *prog,const BufferChunk &chunk,int vertexOffset,bool useInstancingHere)
{
    glBindBuffer(GL_ARRAY_BUFFER,pointBuffer);
    
    // Bind the various attributes to their offsets
    int attrOffset = 0;
    for (SingleVertexAttributeInfo &attrInfo : vertAttrs)
    {
        int attrSize = attrInfo.size();
        
        const OpenGLESAttribute *thisAttr = prog->findAttribute(attrInfo.nameID);
        if (thisAttr)
        {
            glVertexAttribPointer(thisAttr->index, attrInfo.glEntryComponents(), attrInfo.glType(), attrInfo.glNormalize(), vertexSize, (const GLvoid *)(long)(attrOffset+chunk.bufferStart));
            
            if (useInstancingHere) {
                int divisor = 0;
                if (useInstancing)
                    divisor = 1;
                if (frameInfo->glesVersion < 3)
                    glVertexAttribDivisorEXT(thisAttr->index, divisor);
                else
                    glVertexAttribDivisor(thisAttr->index, divisor);
            }
            glEnableVertexAttribArray(thisAttr->index);
        }
        
        attrOffset += attrSize;
    }
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    // Link the varying output to attribute array input
    int varyWhich = 0;
    for (SingleVertexAttributeInfo &varyInfo : varyAttrs) {
        glBindBuffer(GL_ARRAY_BUFFER, varyBuffers[varyWhich].buffers[activeVaryBuffer]);
        
        const OpenGLESAttribute *thisAttr = prog->findAttribute(varyInfo.nameID);
        if (thisAttr)
        {
            GLuint size = varyInfo.size();
            glVertexAttribPointer(thisAttr->index, varyInfo.glEntryComponents(), varyInfo.glType(), varyInfo.glNormalize(), varyInfo.size(), (const GLvoid *)(long)(size*vertexOffset));
            
            if (useInstancingHere) {
                int divisor = 0;
                if (useInstancing)
                    divisor = 1;
                if (frameInfo->glesVersion < 3)
                    glVertexAttribDivisorEXT(thisAttr->index, divisor);
                else
                    glVertexAttribDivisor(thisAttr->index, divisor);
            }
            glEnableVertexAttribArray(thisAttr->index);
        }
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
//        {
//            GLint attrSize = varyInfo.size();
//            glBindBuffer(GL_ARRAY_BUFFER, varyBuffers[varyWhich].buffers[activeVaryBuffer]);
//            void *glMem = NULL;
//            glMem = glMapBufferRange(GL_ARRAY_BUFFER, chunk.vertexStart*attrSize, chunk.numVertices*attrSize, GL_MAP_READ_BIT);
//            float *floatData = (float *)glMem;
//            Point3f *vecData = (Point3f *)vecData;
//            int numBad = 0;
//            for (int ix=0;ix<chunk.numVertices*(attrSize/4);ix++)
//                if (isnan(floatData[ix]))
//                    numBad++;
//            if (numBad > 1)
//                NSLog(@"bindAttrs(): Got junk data for %s, vertexStart = %d, numVertex = %d, bad = %d", StringIndexer::getString(varyInfo.nameID).c_str(),chunk.vertexStart,chunk.numVertices,numBad);
//            //            else
//            //                NSLog(@"calculate(): Got good data for %s, vertexStart = %d", StringIndexer::getString(varyInfo.nameID).c_str(),chunk.vertexStart);
//            glUnmapBuffer(GL_ARRAY_BUFFER);
//            glBindBuffer(GL_ARRAY_BUFFER, 0);
//        }

        varyWhich++;
    }
}
    
void ParticleSystemDrawable::drawUnbindAttrs(OpenGLES2Program *prog)
{
    // Tear down the state
    for (SingleVertexAttributeInfo &attrInfo : vertAttrs)
    {
        const OpenGLESAttribute *thisAttr = prog->findAttribute(attrInfo.nameID);
        if (thisAttr) {
            glDisableVertexAttribArray(thisAttr->index);
            glVertexAttribDivisor(thisAttr->index, 0);
        }
    }
    for (SingleVertexAttributeInfo &varyInfo : varyAttrs)
    {
        const OpenGLESAttribute *thisAttr = prog->findAttribute(varyInfo.nameID);
        if (thisAttr) {
            glDisableVertexAttribArray(thisAttr->index);
            glVertexAttribDivisor(thisAttr->index, 0);
        }
    }
}
    
void ParticleSystemDrawable::calculate(RendererFrameInfo *frameInfo,Scene *scene)
{
    CheckGLError("BasicDrawable::calculate() glBeginTransformFeedback");

    updateBatches(frameInfo->currentTime);
    updateChunks();
    lastUpdateTime = frameInfo->currentTime;
    
    if (chunks.empty())
        return;
    
    OpenGLES2Program *prog = frameInfo->program;
    
    if (!prog)
        return;
    
    // Setup the textures for use and set the uniforms
    bool hasTexture[WhirlyKitMaxTextures];
    int progTexBound = 0;
    drawSetupTextures(frameInfo, scene, prog, hasTexture, progTexBound);
    drawSetupUniforms(frameInfo, scene, prog);
    
    // Work through the batches to assign vertex arrays
    for (const BufferChunk &chunk : chunks)
    {
//        NSLog(@"Calculating chunk vertexStart = %d, numVertex = %d",chunk.vertexStart,chunk.numVertices);

        drawBindAttrs(frameInfo,scene,prog,chunk,chunk.vertexStart,false);
        
        // Now bind the varying outputs to their buffers
        int varyIdx = 0;
        int outputVaryBuffer = (activeVaryBuffer == 0) ? 1 : 0;
        for (SingleVertexAttributeInfo &varyInfo : varyAttrs) {
            GLint attrSize = varyInfo.size();
            glBindBufferRange(GL_TRANSFORM_FEEDBACK_BUFFER, varyIdx, varyBuffers[varyIdx].buffers[outputVaryBuffer], chunk.vertexStart*attrSize, chunk.numVertices*attrSize);
            varyIdx++;
        }
        
        glBeginTransformFeedback(GL_POINTS);
        CheckGLError("BasicDrawable::calculate() glBeginTransformFeedback");

        glDrawArrays(GL_POINTS, 0, chunk.numVertices);
        CheckGLError("BasicDrawable::calculate() glDrawArrays");

        glEndTransformFeedback();
        CheckGLError("BasicDrawable::calculate() glEndTransformFeedback");
        
        for (int varyIdx = 0; varyIdx < varyAttrs.size(); varyIdx++) {
            glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, varyIdx, 0);
        }

        // Check the buffer for debugging
//        varyIdx = 0;
//        for (SingleVertexAttributeInfo &varyInfo : varyAttrs) {
//            GLint attrSize = varyInfo.size();
//            glBindBuffer(GL_ARRAY_BUFFER, varyBuffers[varyIdx].buffers[outputVaryBuffer]);
//            void *glMem = NULL;
//            glMem = glMapBufferRange(GL_ARRAY_BUFFER, chunk.vertexStart*attrSize, chunk.numVertices*attrSize, GL_MAP_READ_BIT);
//            float *floatData = (float *)glMem;
//            Point3f *vecData = (Point3f *)vecData;
//            int numBad = 0;
//            for (int ix=0;ix<chunk.numVertices*(attrSize/4);ix++)
//                if (isnan(floatData[ix]))
//                    numBad++;
//            if (numBad > 1)
//                NSLog(@"calculate(): Got junk data for %s, vertexStart = %d, numVertex = %d, bad = %d", StringIndexer::getString(varyInfo.nameID).c_str(),chunk.vertexStart,chunk.numVertices,numBad);
////            else
////                NSLog(@"calculate(): Got good data for %s, vertexStart = %d", StringIndexer::getString(varyInfo.nameID).c_str(),chunk.vertexStart);
//            glUnmapBuffer(GL_ARRAY_BUFFER);
//            glBindBuffer(GL_ARRAY_BUFFER, 0);
//            varyIdx++;
//        }
        
        drawUnbindAttrs(prog);
    }

    // Tear down textures we may have set up
    drawTeardownTextures(frameInfo, scene, prog, hasTexture, progTexBound);
    
    // Switch the active vary buffers (if we're using them)
    activeVaryBuffer = (activeVaryBuffer == 0) ? 1 : 0;
}

void ParticleSystemDrawable::draw(RendererFrameInfo *frameInfo,Scene *scene)
{
    if (lastUpdateTime < frameInfo->currentTime) {
        updateBatches(frameInfo->currentTime);
        updateChunks();
        lastUpdateTime = frameInfo->currentTime;
    }
    
    if (chunks.empty())
        return;
    
    OpenGLES2Program *prog = frameInfo->program;
    
    // Sometimes the program is deleted before the drawable (oops)
    if (!prog)
        return;
    
    bool hasTexture[WhirlyKitMaxTextures];
    int progTexBound = 0;

    // Setup the textures for use and set the uniforms
    drawSetupTextures(frameInfo, scene, prog, hasTexture, progTexBound);
    drawSetupUniforms(frameInfo, scene, prog);

    // Work through the batches
    for (const BufferChunk &chunk : chunks)
    {
//        NSLog(@"Drawing chunk vertexStart = %d, numVertex = %d",chunk.vertexStart,chunk.numVertices);
        
        // Use the rectangle buffer for instancing
        if (rectBuffer)
        {
            glBindBuffer(GL_ARRAY_BUFFER,rectBuffer);
            const OpenGLESAttribute *thisAttr = prog->findAttribute(a_offsetNameID);
            if (thisAttr)
            {
                glVertexAttribPointer(thisAttr->index, 2, GL_FLOAT, GL_FALSE, 4*sizeof(GLfloat), (const GLvoid *)(long)0);
                CheckGLError("ParticleSystemDrawable::setupVAO glVertexAttribPointer");
                if (frameInfo->glesVersion < 3)
                    glVertexAttribDivisorEXT(thisAttr->index, 0);
                else
                    glVertexAttribDivisor(thisAttr->index, 0);
                glEnableVertexAttribArray(thisAttr->index);
                CheckGLError("ParticleSystemDrawable::setupVAO glEnableVertexAttribArray");
            }
            thisAttr = prog->findAttribute(a_texCoordNameID);
            if (thisAttr)
            {
                glVertexAttribPointer(thisAttr->index, 2, GL_FLOAT, GL_FALSE, 4*sizeof(GLfloat), (const GLvoid *)(long)(2*sizeof(GLfloat)));
                CheckGLError("ParticleSystemDrawable::setupVAO glVertexAttribPointer");
                if (frameInfo->glesVersion < 3)
                    glVertexAttribDivisorEXT(thisAttr->index, 0);
                else
                    glVertexAttribDivisor(thisAttr->index, 0);
                glEnableVertexAttribArray(thisAttr->index);
                CheckGLError("ParticleSystemDrawable::setupVAO glEnableVertexAttribArray");
            }
            glBindBuffer(GL_ARRAY_BUFFER, 0);
        }

        drawBindAttrs(frameInfo,scene,prog,chunk,chunk.vertexStart,true);

        if (rectBuffer)
        {
            if (frameInfo->glesVersion < 3)
                glDrawArraysInstancedEXT(GL_TRIANGLES, 0, 6, chunk.numVertices);
            else
                glDrawArraysInstanced(GL_TRIANGLES, 0, 6, chunk.numVertices);
            CheckGLError("BasicDrawable::drawVBO2() glDrawArraysInstanced");
        } else {
            glDrawArrays(GL_POINTS, 0, chunk.numVertices);
            CheckGLError("BasicDrawable::drawVBO2() glDrawArrays");
        }
    
        if (rectBuffer)
        {
            const OpenGLESAttribute *thisAttr = prog->findAttribute(a_offsetNameID);
            if (thisAttr)
            {
                glDisableVertexAttribArray(thisAttr->index);
                CheckGLError("ParticleSystemDrawable glDisableVertexAttribArray");
            }
            thisAttr = prog->findAttribute(a_texCoordNameID);
            if (thisAttr)
            {
                glDisableVertexAttribArray(thisAttr->index);
                CheckGLError("ParticleSystemDrawable glDisableVertexAttribArray");
            }
        }

        drawUnbindAttrs(prog);
    }
    
    // Tear down any textures we set up
    drawTeardownTextures(frameInfo, scene, prog, hasTexture, progTexBound);
}
    
static const char *vertexShaderTri = R"(
precision highp float;

uniform mat4  u_mvpMatrix;
uniform mat4  u_mvMatrix;
uniform mat4  u_mvNormalMatrix;
uniform float u_size;
uniform float u_time;

attribute vec3 a_position;
attribute vec4 a_color;
attribute vec3 a_dir;
attribute float a_startTime;

varying vec4 v_color;

void main()
{
   v_color = a_color;
   vec3 thePos = normalize(a_position + (u_time-a_startTime)*a_dir);
   // Convert from model space into display space
   vec4 pt = u_mvMatrix * vec4(thePos,1.0);
   pt /= pt.w;
   // Make sure the object is facing the user
   vec4 testNorm = u_mvNormalMatrix * vec4(thePos,0.0);
   float dot_res = dot(-pt.xyz,testNorm.xyz);
   // Set the point size
   gl_PointSize = u_size;
   // Project the point into 3-space
   gl_Position = (dot_res > 0.0) ? u_mvpMatrix * vec4(thePos,1.0) : vec4(1000.0,1000.0,1000.0,0.0);
}
)";

static const char *fragmentShaderTri = R"(
precision highp float;

varying vec4      v_color;

void main()
{
    gl_FragColor = v_color;
}
)";
    
OpenGLES2Program *BuildParticleSystemProgram()
{
    OpenGLES2Program *shader = new OpenGLES2Program(kParticleSystemShaderName,vertexShaderTri,fragmentShaderTri);
    if (!shader->isValid())
    {
        delete shader;
        shader = NULL;
    }
    
    if (shader)
        glUseProgram(shader->getProgram());
    
    return shader;
}
    
}