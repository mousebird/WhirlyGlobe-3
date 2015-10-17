/*
 *  LayoutManager.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 7/15/13.
 *  Copyright 2011-2015 mousebird consulting. All rights reserved.
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

#import "LayoutManager.h"
#import "SceneRendererES2.h"
#import "WhirlyGeometry.h"
#import "GlobeMath.h"
#import "MaplyLayerViewWatcher.h"

using namespace Eigen;

namespace WhirlyKit
{

// Default constructor for layout object
LayoutObject::LayoutObject()
    : ScreenSpaceObject(), importance(MAXFLOAT), clusterGroup(-1), acceptablePlacement(WhirlyKitLayoutPlacementLeft | WhirlyKitLayoutPlacementRight | WhirlyKitLayoutPlacementAbove | WhirlyKitLayoutPlacementBelow)
{
}
    
LayoutObject::LayoutObject(SimpleIdentity theId) : ScreenSpaceObject(theId),
     importance(MAXFLOAT), clusterGroup(-1), acceptablePlacement(WhirlyKitLayoutPlacementLeft | WhirlyKitLayoutPlacementRight | WhirlyKitLayoutPlacementAbove | WhirlyKitLayoutPlacementBelow)
{
}
    
void LayoutObject::setLayoutSize(const Point2d &layoutSize,const Point2d &offset)
{
    if (layoutSize.x() == 0.0 && layoutSize.y() == 0.0)
        return;
    
    layoutPts.push_back(Point2d(0,0)+offset);
    layoutPts.push_back(Point2d(layoutSize.x(),0.0)+offset);
    layoutPts.push_back(layoutSize+offset);
    layoutPts.push_back(Point2d(0.0,layoutSize.y())+offset);
}
    
void LayoutObject::setSelectSize(const Point2d &selectSize,const Point2d &offset)
{
    if (selectSize.x() == 0.0 && selectSize.y() == 0.0)
        return;
    
    selectPts.push_back(Point2d(0,0)+offset);
    selectPts.push_back(Point2d(selectSize.x(),0.0)+offset);
    selectPts.push_back(selectSize+offset);
    selectPts.push_back(Point2d(0.0,selectSize.y())+offset);
}
    
LayoutObjectEntry::LayoutObjectEntry(SimpleIdentity theId)
: Identifiable(theId)
{
    currentEnable = newEnable = false;
    currentCluster = newCluster = -1;
    offset = Point2d(MAXFLOAT,MAXFLOAT);
    changed = true;
}
    
LayoutManager::LayoutManager()
    : maxDisplayObjects(0), hasUpdates(false), clusterGen(NULL)
{
    pthread_mutex_init(&layoutLock, NULL);
}
    
LayoutManager::~LayoutManager()
{
    for (LayoutEntrySet::iterator it = layoutObjects.begin();
         it != layoutObjects.end(); ++it)
        delete *it;
    layoutObjects.clear();
    
    pthread_mutex_destroy(&layoutLock);
}
    
void LayoutManager::setMaxDisplayObjects(int numObjects)
{
    pthread_mutex_lock(&layoutLock);

    maxDisplayObjects = numObjects;

    pthread_mutex_unlock(&layoutLock);
}
    
void LayoutManager::addLayoutObjects(const std::vector<LayoutObject> &newObjects)
{
    pthread_mutex_lock(&layoutLock);

    for (unsigned int ii=0;ii<newObjects.size();ii++)
    {
        const LayoutObject &layoutObj = newObjects[ii];
        LayoutObjectEntry *entry = new LayoutObjectEntry(layoutObj.getId());
        entry->obj = newObjects[ii];
        layoutObjects.insert(entry);
    }
    hasUpdates = true;

    pthread_mutex_unlock(&layoutLock);
}

void LayoutManager::addLayoutObjects(const std::vector<LayoutObject *> &newObjects)
{
    pthread_mutex_lock(&layoutLock);
    
    for (unsigned int ii=0;ii<newObjects.size();ii++)
    {
        const LayoutObject *layoutObj = newObjects[ii];
        LayoutObjectEntry *entry = new LayoutObjectEntry(layoutObj->getId());
        entry->obj = *(newObjects[ii]);
        layoutObjects.insert(entry);
    }
    hasUpdates = true;
    
    pthread_mutex_unlock(&layoutLock);
}

/// Enable/disable layout objects
void LayoutManager::enableLayoutObjects(const SimpleIDSet &theObjects,bool enable)
{
    pthread_mutex_lock(&layoutLock);

    for (SimpleIDSet::const_iterator it = theObjects.begin();
         it != theObjects.end(); ++it)
    {
        LayoutObjectEntry entry(*it);
        LayoutEntrySet::iterator eit = layoutObjects.find(&entry);
        if (eit != layoutObjects.end())
            (*eit)->obj.enable = enable;
    }
    hasUpdates = true;    

    pthread_mutex_unlock(&layoutLock);
}
    
void LayoutManager::removeLayoutObjects(const SimpleIDSet &oldObjects)
{
    pthread_mutex_lock(&layoutLock);

    for (SimpleIDSet::const_iterator it = oldObjects.begin();
         it != oldObjects.end(); ++it)
    {
        LayoutObjectEntry entry(*it);
        LayoutEntrySet::iterator eit = layoutObjects.find(&entry);
        if (eit != layoutObjects.end())
        {
            delete *eit;
            layoutObjects.erase(eit);
        }
    }
    hasUpdates = true;

    pthread_mutex_unlock(&layoutLock);
}
    
bool LayoutManager::hasChanges()
{
    bool ret = false;
    
    pthread_mutex_lock(&layoutLock);
    
    ret = hasUpdates;
    
    pthread_mutex_unlock(&layoutLock);
    
    return ret;
}
    
// Sort more important things to the front
typedef struct
{
    bool operator () (const LayoutObjectEntry *a,const LayoutObjectEntry *b)
    {
        if (a->obj.importance == b->obj.importance)
            return a > b;
        return a->obj.importance > b->obj.importance;
    }
} LayoutEntrySorter;
typedef std::set<LayoutObjectEntry *,LayoutEntrySorter> LayoutSortingSet;

// Return the screen space objects in a form the selection manager can understand
void LayoutManager::getScreenSpaceObjects(const SelectionManager::PlacementInfo &pInfo,std::vector<ScreenSpaceObjectLocation> &screenSpaceObjs)
{
    pthread_mutex_lock(&layoutLock);
    
    // First the regular screen space objects
    for (LayoutEntrySet::iterator it = layoutObjects.begin();
         it != layoutObjects.end(); ++it)
    {
        LayoutObjectEntry *entry = *it;
        if (entry->currentEnable)
        {
            ScreenSpaceObjectLocation ssObj;
            ssObj.shapeIDs.push_back(entry->obj.getId());
            ssObj.dispLoc = entry->obj.worldLoc;
            ssObj.offset = entry->offset;
            ssObj.pts = entry->obj.selectPts;
            ssObj.mbr.addPoints(entry->obj.selectPts);

            screenSpaceObjs.push_back(ssObj);
        }
    }
    
    // Then the clusters
    for (auto &cluster : clusters)
    {
        ScreenSpaceObjectLocation ssObj;
        ssObj.shapeIDs = cluster.objectIDs;
        ssObj.dispLoc = cluster.layoutObj.worldLoc;
        ssObj.offset = cluster.layoutObj.offset;
        ssObj.pts = cluster.layoutObj.selectPts;
        ssObj.mbr.addPoints(cluster.layoutObj.selectPts);
        ssObj.isCluster = true;

        screenSpaceObjs.push_back(ssObj);
    }
    
    pthread_mutex_unlock(&layoutLock);
}
    
void LayoutManager::addClusterGenerator(ClusterGenerator *inClusterGen)
{
    pthread_mutex_lock(&layoutLock);

    clusterGen = inClusterGen;
    
    pthread_mutex_unlock(&layoutLock);
}

// Collection of objects we'll cluster together
class ClusteredObjects
{
public:
    ClusteredObjects() { }
    ClusteredObjects(int clusterID) : clusterID(clusterID) { }
    
    int clusterID;
    
    LayoutSortingSet layoutObjects;
};
    
struct ClusteredObjectsSorter
{
    // Comparison operator
    bool operator () (const ClusteredObjects *lhs,const ClusteredObjects *rhs) const
    {
        return lhs->clusterID < rhs->clusterID;
    }
};
    
typedef std::set<ClusteredObjects *,ClusteredObjectsSorter> ClusteredObjectsSet;

// Size of the overlap sampler
static const int OverlapSampleX = 10;
static const int OverlapSampleY = 60;

// Now much around the screen we'll take into account
static const float ScreenBuffer = 0.1;
    
bool LayoutManager::calcScreenPt(CGPoint &objPt,LayoutObjectEntry *layoutObj,WhirlyKitViewState *viewState,const Mbr &screenMbr,const Point2f &frameBufferSize)
{
    // Figure out where this will land
    bool isInside = false;
    for (unsigned int offi=0;offi<viewState.viewMatrices.size();offi++)
    {
        Eigen::Matrix4d modelTrans = viewState.fullMatrices[offi];
        CGPoint thisObjPt = [viewState pointOnScreenFromDisplay:layoutObj->obj.worldLoc transform:&modelTrans frameSize:frameBufferSize];
        if (screenMbr.inside(Point2f(thisObjPt.x,thisObjPt.y)))
        {
            isInside = true;
            objPt = thisObjPt;
        }
    }
    
    return isInside;
}
    
Matrix2d LayoutManager::calcScreenRot(float &screenRot,WhirlyKitViewState *viewState,WhirlyGlobeViewState *globeViewState,LayoutObjectEntry *layoutObj,const CGPoint &objPt,const Matrix4d &modelTrans,const Point2f &frameBufferSize)
{
    Point3d norm,right,up;
    Matrix2d screenRotMat;
    
    if (globeViewState)
    {
        Point3d simpleUp(0,0,1);
        norm = layoutObj->obj.worldLoc;
        norm.normalize();
        right = simpleUp.cross(norm);
        up = norm.cross(right);
        right.normalize();
        up.normalize();
    } else {
        right = Point3d(1,0,0);
        norm = Point3d(0,0,1);
        up = Point3d(0,1,0);
    }
    // Note: Check if the axes made any sense.  We might be at a pole.
    Point3d rightDir = right * sinf(layoutObj->obj.rotation);
    Point3d upDir = up * cosf(layoutObj->obj.rotation);
    
    Point3d outPt = rightDir * 1.0 + upDir * 1.0 + layoutObj->obj.worldLoc;
    CGPoint outScreenPt;
    outScreenPt = [viewState pointOnScreenFromDisplay:outPt transform:&modelTrans frameSize:frameBufferSize];
    screenRot = M_PI/2.0-atan2f(objPt.y-outScreenPt.y,outScreenPt.x-objPt.x);
    // Keep the labels upright
    if (layoutObj->obj.keepUpright)
        if (screenRot > M_PI/2 && screenRot < 3*M_PI/2)
            screenRot = screenRot + M_PI;
            screenRotMat = Eigen::Rotation2Dd(screenRot);
    
    return screenRotMat;
}
    
// Do the actual layout logic.  We'll modify the offset and on value in place.
bool LayoutManager::runLayoutRules(WhirlyKitViewState *viewState,std::vector<ClusterEntry> &clusterEntries,std::vector<ClusterGenerator::ClusterClassParams> &clusterParams)
{
    if (layoutObjects.empty())
        return false;
    
    bool hadChanges = false;
    
    ClusteredObjectsSet clusterObjs;
    LayoutSortingSet layoutObjs;
    
    // The globe has some special requirements
    WhirlyGlobeViewState *globeViewState = nil;
    MaplyViewState *mapViewState = nil;
    if ([viewState isKindOfClass:[WhirlyGlobeViewState class]])
        globeViewState = (WhirlyGlobeViewState *)viewState;
    else
        mapViewState = (MaplyViewState *)viewState;

    // View related matrix stuff
    Matrix4d modelTrans = viewState.fullMatrices[0];
    Matrix4f fullMatrix4f = Matrix4dToMatrix4f(viewState.fullMatrices[0]);
    Matrix4f fullNormalMatrix4f = Matrix4dToMatrix4f(viewState.fullNormalMatrices[0]);
    
    // Turn everything off and sort by importance
    for (LayoutEntrySet::iterator it = layoutObjects.begin();
         it != layoutObjects.end(); ++it)
    {
        LayoutObjectEntry *layoutObj = *it;
        if (layoutObj->obj.enable)
        {
            LayoutObjectEntry *obj = *it;
            bool use = false;
            if (globeViewState)
            {
                if (obj->obj.state.minVis == DrawVisibleInvalid || obj->obj.state.maxVis == DrawVisibleInvalid ||
                    (obj->obj.state.minVis < globeViewState.heightAboveGlobe && globeViewState.heightAboveGlobe < obj->obj.state.maxVis))
                    use = true;
            } else {
                if (obj->obj.state.minVis == DrawVisibleInvalid || obj->obj.state.maxVis == DrawVisibleInvalid ||
                    (obj->obj.state.minVis < mapViewState.heightAboveSurface && mapViewState.heightAboveSurface < obj->obj.state.maxVis))
                    use = true;
            }
            if (use) {
                // Make sure this one isn't behind the globe
                if (globeViewState)
                {
                    // Make sure this one is facing toward the viewer
                    use = CheckPointAndNormFacing(Vector3dToVector3f(layoutObj->obj.worldLoc),Vector3dToVector3f(layoutObj->obj.worldLoc.normalized()),fullMatrix4f,fullNormalMatrix4f) > 0.0;
                }

                if (use)
                {
                    obj->newCluster = -1;
                    if (obj->obj.clusterGroup > -1)
                    {
                        // Put the entry in the right cluster
                        ClusteredObjects findClusterObj(obj->obj.clusterGroup);
                        ClusteredObjects *thisClusterObj = NULL;
                        auto cit = clusterObjs.find(&findClusterObj);
                        if (cit == clusterObjs.end())
                        {
                            // Create a new cluster object
                            thisClusterObj = new ClusteredObjects(obj->obj.clusterGroup);
                            clusterObjs.insert(thisClusterObj);
                        } else
                            thisClusterObj = *cit;
                        
                        thisClusterObj->layoutObjects.insert(layoutObj);
                        
                        obj->newEnable = false;
                        obj->newCluster = -1;
                    } else {
                        // Not a cluster
                        layoutObjs.insert(layoutObj);
                    }
                }
            }
            // Note: Update this for clusters
            if ((use && !obj->currentEnable) || (!use && obj->currentEnable))
                hadChanges = true;
        }
    }
    
    // Extents for the layout helpers
    Point2f frameBufferSize;
    frameBufferSize.x() = renderer.framebufferWidth;
    frameBufferSize.y() = renderer.framebufferHeight;
    Mbr screenMbr(Point2f(-ScreenBuffer * frameBufferSize.x(),-ScreenBuffer * frameBufferSize.y()),frameBufferSize * (1.0 + ScreenBuffer));

    // Need to scale for retina displays
    float resScale = renderer.scale;

    if (clusterGen)
    {
        clusterGen->startLayoutObjects();
        
        // Lay out the clusters in order
        for (ClusteredObjectsSet::iterator it = clusterObjs.begin(); it != clusterObjs.end(); ++it)
        {
            ClusteredObjects *cluster = *it;
            clusterParams.resize(clusterParams.size()+1);
            ClusterGenerator::ClusterClassParams &params = clusterParams.back();
            clusterGen->paramsForClusterClass(cluster->clusterID,params);

            ClusterHelper clusterHelper(screenMbr,OverlapSampleX,OverlapSampleY,resScale,params.clusterSize);
            
            // Add all the various objects to the cluster and figure out overlaps
            for (LayoutSortingSet::iterator sit = cluster->layoutObjects.begin(); sit != cluster->layoutObjects.end(); ++sit)
            {
                LayoutObjectEntry *entry = *sit;
                
                // Project the point and figure out the rotation
                bool isActive = true;
                CGPoint objPt;
                bool isInside = calcScreenPt(objPt,entry,viewState,screenMbr,frameBufferSize);
                
                isActive &= isInside;
                
                if (isActive)
                {
                    // Deal with the rotation
                    float screenRot = 0.0;
                    Matrix2d screenRotMat;
                    if (entry->obj.rotation != 0.0)
                        screenRotMat = calcScreenRot(screenRot,viewState,globeViewState,entry,objPt,modelTrans,frameBufferSize);
                    
                    // Rotate the rectangle
                    std::vector<Point2d> objPts(4);
                    if (screenRot == 0.0)
                    {
                        for (unsigned int ii=0;ii<4;ii++)
                            objPts[ii] = Point2d(objPt.x,objPt.y) + entry->obj.layoutPts[ii] * resScale;
                    } else {
                        Point2d center(objPt.x,objPt.y);
                        for (unsigned int ii=0;ii<4;ii++)
                        {
                            Point2d &thisObjPt = objPts[ii];
                            thisObjPt = entry->obj.layoutPts[ii];
                            thisObjPt = screenRotMat * thisObjPt;
                            thisObjPt = Point2d(thisObjPt.x()*resScale,thisObjPt.y()*resScale)+center;
                        }
                    }

                    
                    clusterHelper.addObject(entry,objPts);
                }
            }
            
            // Deal with the clusters and their own overlaps
            clusterHelper.resolveClusters();

            // Toss the unaffected layout objects into the mix
            for (auto obj : clusterHelper.simpleObjects)
                if (obj.parentObject < 0)
                {
                    layoutObjs.insert(obj.objEntry);
                    obj.objEntry->newEnable = true;
                    obj.objEntry->newCluster = -1;
                }
            
            // Create new objects for the clusters
            for (auto clusterObj : clusterHelper.clusterObjects)
            {
                std::vector<LayoutObjectEntry *> objsForCluster;
                clusterHelper.objectsForCluster(clusterObj,objsForCluster);
                
                if (!objsForCluster.empty())
                {
                    int clusterEntryID = clusterEntries.size();
                    clusterEntries.resize(clusterEntryID+1);
                    ClusterEntry &clusterEntry = clusterEntries[clusterEntryID];

                    // Project the cluster back into a geolocation so we can place it.
                    Point3d dispPt;
                    bool dispPtValid = false;
                    if (globeViewState)
                    {
                        dispPtValid = [globeViewState pointOnSphereFromScreen:CGPointMake(clusterObj.center.x(),clusterObj.center.y()) transform:&modelTrans frameSize:frameBufferSize hit:&dispPt];
                    } else {
                        dispPtValid = [mapViewState pointOnPlaneFromScreen:CGPointMake(clusterObj.center.x(),clusterObj.center.y()) transform:&modelTrans frameSize:frameBufferSize hit:&dispPt clip:false];
                    }

                    // Note: What happens if the display point isn't valid?
                    if (dispPtValid)
                    {
                        clusterEntry.layoutObj.worldLoc = dispPt;
                        for (auto thisObj : objsForCluster)
                            clusterEntry.objectIDs.push_back(thisObj->obj.getId());
                        clusterGen->makeLayoutObject(cluster->clusterID, objsForCluster, clusterEntry.layoutObj);
                        if (!params.selectable)
                            clusterEntry.layoutObj.selectPts.clear();
                    }
                    clusterEntry.clusterParamID = clusterParams.size()-1;
                    
                    for (auto obj : objsForCluster)
                        obj->newCluster = clusterEntryID;
                }
            }
        }
        
        // Tear down the clusters
        // Note: Debugging
        for (ClusteredObjectsSet::iterator it = clusterObjs.begin(); it != clusterObjs.end(); ++it)
            delete *it;
        clusterObjs.clear();
        
        clusterGen->endLayoutObjects();
    }
    
//    NSLog(@"----Starting Layout----");
    
    // Set up the overlap sampler
    OverlapHelper overlapMan(screenMbr,OverlapSampleX,OverlapSampleY);
    
    // Lay out the various objects that are active
    int numSoFar = 0;
    for (LayoutSortingSet::iterator it = layoutObjs.begin();
         it != layoutObjs.end(); ++it)
    {
        LayoutObjectEntry *layoutObj = *it;
        bool isActive;
        Point2d objOffset(0.0,0.0);
        std::vector<Point2d> objPts(4);
        
        // Start with a max objects check
        isActive = true;
        if (maxDisplayObjects != 0 && (numSoFar >= maxDisplayObjects))
            isActive = false;
        
        // Figure out the rotation situation
        float screenRot = 0.0;
        Matrix2d screenRotMat;
        if (isActive)
        {
            CGPoint objPt;
            bool isInside = calcScreenPt(objPt,layoutObj,viewState,screenMbr,frameBufferSize);
            
            isActive &= isInside;
            
            // Deal with the rotation
            if (layoutObj->obj.rotation != 0.0)
                screenRotMat = calcScreenRot(screenRot,viewState,globeViewState,layoutObj,objPt,modelTrans,frameBufferSize);
            
            // Now for the overlap checks
            if (isActive)
            {
                // Try the four different orientations
                if (!layoutObj->obj.layoutPts.empty())
                {
                    bool validOrient = false;
                    for (unsigned int orient=0;orient<6;orient++)
                    {
                        // May only want to be placed certain ways.  Fair enough.
                        if (!(layoutObj->obj.acceptablePlacement & (1<<orient)))
                            continue;
                        const std::vector<Point2d> &layoutPts = layoutObj->obj.layoutPts;
                        Mbr layoutMbr;
                        for (unsigned int li=0;li<layoutPts.size();li++)
                            layoutMbr.addPoint(layoutPts[li]);
                        Point2f layoutSpan(layoutMbr.ur().x()-layoutMbr.ll().x(),layoutMbr.ur().y()-layoutMbr.ll().y());
                        Point2d layoutOrg(layoutMbr.ll().x(),layoutMbr.ll().y());
                        
                        // Set up the offset for this orientation
                        switch (orient)
                        {
                            // Don't move at all
                            case 0:
                                objOffset = Point2d(0,0);
                                break;
                            // Center
                            case 1:
                                objOffset = Point2d(-layoutSpan.x()/2.0,-layoutSpan.y()/2.0);
                                break;
                            // Right
                            case 2:
                                objOffset = Point2d(0.0,-layoutSpan.y()/2.0);
                                break;
                            // Left
                            case 3:
                                objOffset = Point2d(-(layoutSpan.x()),-layoutSpan.y()/2.0);
                                break;
                            // Above
                            case 4:
                                objOffset = Point2d(-layoutSpan.x()/2.0,0);
                                break;
                            // Below
                            case 5:
                                objOffset = Point2d(-layoutSpan.x()/2.0,-layoutSpan.y());
                                break;
                        }
                        
                        // Rotate the rectangle
                        if (screenRot == 0.0)
                        {
                            objPts[0] = Point2d(objPt.x,objPt.y) + (objOffset + layoutOrg)*resScale;
                            objPts[1] = objPts[0] + Point2d(layoutSpan.x()*resScale,0.0);
                            objPts[2] = objPts[0] + Point2d(layoutSpan.x()*resScale,layoutSpan.y()*resScale);
                            objPts[3] = objPts[0] + Point2d(0.0,layoutSpan.y()*resScale);
                        } else {
                            Point2d center(objPt.x,objPt.y);
                            objPts[0] = objOffset + layoutOrg;
                            objPts[1] = objOffset + layoutOrg + Point2d(layoutSpan.x(),0.0);
                            objPts[2] = objOffset + layoutOrg + Point2d(layoutSpan.x(),layoutSpan.y());
                            objPts[3] = objOffset + layoutOrg + Point2d(0.0,layoutSpan.y());
                            for (unsigned int oi=0;oi<4;oi++)
                            {
                                Point2d &thisObjPt = objPts[oi];
                                thisObjPt = screenRotMat * thisObjPt;
                                thisObjPt = Point2d(thisObjPt.x()*resScale,thisObjPt.y()*resScale)+center;
                            }
                        }
                        
                        // Now try it
                        if (overlapMan.addObject(objPts))
                        {
                            validOrient = true;
                            break;
                        }
                    }
                    
                    isActive = validOrient;
                }
            }

//            NSLog(@" Valid (%s): %@, pos = (%f,%f), size = (%f, %f), offset = (%f,%f)",(isActive ? "yes" : "no"),layoutObj->obj.hint,objPt.x,objPt.y,layoutObj->obj.size.x(),layoutObj->obj.size.y(),
//                  layoutObj->offset.x(),layoutObj->offset.y());
        }
        
        if (isActive)
            numSoFar++;
        
        // See if we've changed any of the state
        layoutObj->changed = (layoutObj->currentEnable != isActive);
        if (!layoutObj->changed && layoutObj->newEnable &&
            (layoutObj->offset.x() != objOffset.x() || layoutObj->offset.y() != objOffset.y()))
        {
            layoutObj->changed = true;
        }
        hadChanges |= layoutObj->changed;
        layoutObj->newEnable = isActive;
        layoutObj->newCluster = -1;
        layoutObj->offset = objOffset;
    }
    
//    NSLog(@"----Finished layout----");
    
    return hadChanges;
}

// Time we'll take to disappear objects
static float const DisappearFade = 0.1;

// Layout all the objects we're tracking
void LayoutManager::updateLayout(WhirlyKitViewState *viewState,ChangeSet &changes)
{
    CoordSystemDisplayAdapter *coordAdapter = scene->getCoordAdapter();
    
    pthread_mutex_lock(&layoutLock);

    NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
    
    std::vector<ClusterEntry> oldClusters = clusters;
    clusters.clear();
    std::vector<ClusterGenerator::ClusterClassParams> oldClusterParams = clusterParams;
    clusterParams.clear();
    
    // This will recalculate the offsets and enables
    // If there were any changes, we need to regenerate
    bool layoutChanges = runLayoutRules(viewState,clusters,clusterParams);
    
    if (hasUpdates || layoutChanges)
    {
        // Get rid of the last set of drawables
        for (SimpleIDSet::iterator it = drawIDs.begin(); it != drawIDs.end(); ++it)
            changes.push_back(new RemDrawableReq(*it));
        drawIDs.clear();

        // Generate the drawables
        ScreenSpaceBuilder ssBuild(coordAdapter,renderer.scale);
        for (LayoutEntrySet::iterator it = layoutObjects.begin();
             it != layoutObjects.end(); ++it)
        {
            LayoutObjectEntry *layoutObj = *it;

            layoutObj->obj.offset = Point2d(layoutObj->offset.x(),layoutObj->offset.y());
            if (!layoutObj->currentEnable)
            {
                layoutObj->obj.state.fadeDown = curTime;
                layoutObj->obj.state.fadeUp = curTime+DisappearFade;
            }
            
            // Just moved into a cluster
            if (layoutObj->currentEnable && !layoutObj->newEnable && layoutObj->currentCluster > -1)
            {
                ClusterEntry &cluster = clusters[layoutObj->newCluster];
            } else if (!layoutObj->currentEnable && layoutObj->newEnable && layoutObj->currentCluster > -1 && layoutObj->newCluster == -1)
            {
                // Just moved out of a cluster
                ClusterEntry *oldCluster = NULL;
                if (layoutObj->currentCluster < oldClusters.size())
                    oldCluster = &oldClusters[layoutObj->currentCluster];
                else {
                    NSLog(@"Cluster ID mismatch");
                    continue;
                }
                ClusterGenerator::ClusterClassParams &params = oldClusterParams[oldCluster->clusterParamID];
                
                // Animate from the old cluster position to the new real position
                ScreenSpaceObject animObj = layoutObj->obj;
                animObj.setMovingLoc(animObj.worldLoc, curTime, curTime+params.markerAnimationTime);
                animObj.worldLoc = oldCluster->layoutObj.worldLoc;
                animObj.setEnableTime(curTime, curTime+params.markerAnimationTime);
                animObj.state.progID = params.motionShaderID;
                for (auto &geom : animObj.geometry)
                    geom.progID = params.motionShaderID;
                ssBuild.addScreenObject(animObj);
                
                // And hold off on adding it
                ScreenSpaceObject shortObj = layoutObj->obj;
                shortObj.setEnableTime(curTime+params.markerAnimationTime, curTime+1e10);
                ssBuild.addScreenObject(shortObj);
            } else {
                // It's boring, just add it
                if (layoutObj->newEnable)
                    ssBuild.addScreenObject(layoutObj->obj);
            }

            layoutObj->currentEnable = layoutObj->newEnable;
            layoutObj->currentCluster = layoutObj->newCluster;
            
            layoutObj->changed = false;
        }
        
        
        // Add in the clusters
        for (auto &cluster : clusters)
        {
            // Note: Read from the cluster
//            double FadeTime = 0.2;
//            cluster.setFade(curTime+FadeTime, curTime);
            ssBuild.addScreenObject(cluster.layoutObj);
        }
        
        ssBuild.flushChanges(changes, drawIDs);
    }
    
    hasUpdates = false;
    
    pthread_mutex_unlock(&layoutLock);
}
    
}
