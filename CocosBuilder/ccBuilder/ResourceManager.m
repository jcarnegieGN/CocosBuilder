//
//  ResourceManager.m
//  CocosBuilder
//
//  Created by Viktor Lidholt on 3/5/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ResourceManager.h"
#import "CCBSpriteSheetParser.h"

#pragma mark RMSpriteFrame

@implementation RMSpriteFrame

@synthesize spriteFrameName, spriteSheetFile;

- (void) dealloc
{
    self.spriteFrameName = NULL;
    self.spriteSheetFile = NULL;
    [super dealloc];
}

@end


#pragma mark RMResource

@implementation RMResource

@synthesize type, modifiedTime, touched, data, filePath;

- (void) loadData
{
    if (type == kCCBResTypeSpriteSheet)
    {
        NSArray* spriteFrameNames = [CCBSpriteSheetParser listFramesInSheet:filePath];
        NSMutableArray* spriteFrames = [NSMutableArray arrayWithCapacity:[spriteFrameNames count]];
        for (NSString* frameName in spriteFrameNames)
        {
            RMSpriteFrame* frame = [[[RMSpriteFrame alloc] init] autorelease];
            frame.spriteFrameName = frameName;
            frame.spriteSheetFile = self.filePath;
            
            [spriteFrames addObject:frame];
        }
        self.data = spriteFrames;
    }
    else if (type == kCCBResTypeDirectory)
    {
        // Ignore changed directories
    }
    else
    {
        self.data = NULL;
    }
}

- (void) dealloc
{
    self.data = NULL;
    self.modifiedTime = NULL;
    self.filePath = NULL;
    [super dealloc];
}

@end


#pragma mark RMDirectory

@implementation RMDirectory

@synthesize count,dirPath, resources, images;

- (id) init
{
    self = [super init];
    if (!self) return NULL;
    
    resources = [[NSMutableDictionary alloc] init];
    images = [[NSMutableArray alloc] init];
    
    return self;
}

- (NSArray*)resourcesForType:(int)type
{
    if (type == kCCBResTypeImage) return images;
    return NULL;
}

- (void) dealloc
{
    [resources dealloc];
    [images dealloc];
    self.dirPath = NULL;
    [super dealloc];
}

- (NSComparisonResult) compare:(RMDirectory*)dir
{
    return [dirPath compare:dir.dirPath];
}

@end


#pragma mark ResourceManager

@implementation ResourceManager

@synthesize directories, activeDirectories;

+ (ResourceManager*) sharedManager
{
    static ResourceManager* rm = NULL;
    if (!rm) rm = [[ResourceManager alloc] init];
    return rm;
}

- (id) init
{
    self = [super init];
    if (!self) return NULL;
    
    directories = [[NSMutableDictionary alloc] init];
    activeDirectories = [[NSMutableArray alloc] init];
    pathWatcher = [[SCEvents alloc] init];
    pathWatcher.ignoreEventsFromSubDirs = YES;
    pathWatcher.delegate = self;
    resourceObserver = [[NSMutableArray alloc] init];
    
    return self;
}

- (void) dealloc
{
    [pathWatcher release];
    [directories release];
    [activeDirectories release];
    [resourceObserver release];
    self.activeDirectories = NULL;
    [super dealloc];
}

- (NSArray*) getAddedDirs
{
    NSMutableArray* arr = [NSMutableArray arrayWithCapacity:[directories count]];
    for (NSString* dirPath in directories)
    {        
        [arr addObject:dirPath];
    }
    return arr;
}



- (void) updatedWatchedPaths
{
    if (pathWatcher.isWatchingPaths)
    {
        [pathWatcher stopWatchingPaths];
    }
    [pathWatcher startWatchingPaths:[self getAddedDirs]];
}

- (void) notifyResourceObserversResourceListUpdated
{
    for (id observer in resourceObserver)
    {
        if ([observer respondsToSelector:@selector(resourceListUpdated)])
        {
            [observer performSelector:@selector(resourceListUpdated)];
        }
    }
}

- (int) getResourceTypeForFile:(NSString*) file
{
    NSString* ext = [[file pathExtension] lowercaseString];
    NSFileManager* fm = [NSFileManager defaultManager];
    
    BOOL isDirectory;
    [fm fileExistsAtPath:file isDirectory:&isDirectory];
    
    if (isDirectory)
    {
        return kCCBResTypeDirectory;
    }
    else if ([[file stringByDeletingPathExtension] hasSuffix:@"-hd"]
             || [[file stringByDeletingPathExtension] hasSuffix:@"@2x"])
    {
        // Ignore -hd files
        return kCCBResTypeNone;
    }
    else if ([ext isEqualToString:@"png"]
        || [ext isEqualToString:@"jpg"]
        || [ext isEqualToString:@"jpeg"])
    {
        return kCCBResTypeImage;
    }
    else if ([ext isEqualToString:@"fnt"])
    {
        return kCCBResTypeBMFont;
    }
    else if ([ext isEqualToString:@"plist"]
             && [CCBSpriteSheetParser isSpriteSheetFile:file])
    {
        return kCCBResTypeSpriteSheet;
    }
    
    return kCCBResTypeNone;
}

- (void) clearTouchedForResInDir:(RMDirectory*)dir
{
    NSDictionary* resources = dir.resources;
    for (NSString* file in resources)
    {
        RMResource* res = [resources objectForKey:file];
        res.touched = NO;
    }
}

- (void) updateResourcesForPath:(NSString*) path
{
    NSFileManager* fm = [NSFileManager defaultManager];
    RMDirectory* dir = [directories objectForKey:path];
    NSArray* files = [fm contentsOfDirectoryAtPath:path error:NULL];
    NSMutableDictionary* resources = dir.resources;
    
    BOOL needsUpdate = NO; // Assets needs to be reloaded in editor
    BOOL resourcesChanged = NO;  // A resource file was modified, added or removed
    
    [self clearTouchedForResInDir:dir];
    
    for (NSString* fileShort in files)
    {
        NSString* file = [path stringByAppendingPathComponent:fileShort];
        
        RMResource* res = [resources objectForKey:file];
        NSDictionary* attr = [fm attributesOfItemAtPath:file error:NULL];
        NSDate* modifiedTime = [attr fileModificationDate];
        
        if (res)
        {
            if ([res.modifiedTime compare:modifiedTime] == NSOrderedSame)
            {
                // Skip files that are not modified
                res.touched = YES;
                continue;
            }
            else
            {
                // A resource has been modified, we need to reload assets
                res.modifiedTime = modifiedTime;
                res.type = [self getResourceTypeForFile:file];
                
                // Reload its data
                [res loadData];
                
                needsUpdate = YES;
                resourcesChanged = YES;
            }
        }
        else
        {
            // This is a new resource, add it!
            res = [[RMResource alloc] init];
            res.modifiedTime = modifiedTime;
            res.type = [self getResourceTypeForFile:file];
            res.filePath = file;
            
            // Load basic resource data if neccessary
            [res loadData];
            
            // Check if it is a directory
            if (res.type == kCCBResTypeDirectory)
            {
                [self addDirectory:file];
                res.data = [directories objectForKey:file];
            }
            
            [resources setObject:res forKey:file];
            
            if (res.type != kCCBResTypeNone) resourcesChanged = YES;
        }
        res.touched = YES;
    }
    
    // Check for deleted files
    NSMutableArray* removedFiles = [NSMutableArray array];
    
    for (NSString* file in resources)
    {
        RMResource* res = [resources objectForKey:file];
        if (!res.touched)
        {
            [removedFiles addObject:file];
            needsUpdate = YES;
            if (res.type != kCCBResTypeNone) resourcesChanged = YES;
        }
    }
    
    // Remove references to files marked for deletion
    for (NSString* file in removedFiles)
    {
        [resources removeObjectForKey:file];
    }
    
    // Update arrays for different resources
    if (resChanged)
    {
        [dir.images removeAllObjects];
        for (NSString* file in resources)
        {
            RMResource* res = [resources objectForKey:file];
            if (res.type == kCCBResTypeImage
                || res.type == kCCBResTypeSpriteSheet
                || res.type == kCCBResTypeDirectory)
            {
                [dir.images addObject:res];
            }
        }
    }
    
    if (resourcesChanged) [self notifyResourceObserversResourceListUpdated];
}

- (void) addDirectory:(NSString *)dirPath
{
    NSLog(@"Add directory: %@", dirPath);
    
    // Check if directory is already added (then add to its count)
    RMDirectory* dir = [directories objectForKey:dirPath];
    if (dir)
    {
        dir.count++;
    }
    else
    {
        dir = [[[RMDirectory alloc] init] autorelease];
        dir.count = 1;
        dir.dirPath = dirPath;
        [directories setObject:dir forKey:dirPath];
        
        [self updatedWatchedPaths];
    }
    
    [self updateResourcesForPath:dirPath];
}

- (void) removeDirectory:(NSString *)dirPath
{
    NSLog(@"Remove directory: %@", dirPath);
    
    RMDirectory* dir = [directories objectForKey:dirPath];
    if (dir)
    {
        // Remove sub directories
        NSDictionary* resources = dir.resources;
        for (NSString* file in resources)
        {
            RMResource* res = [resources objectForKey:file];
            if (res.type == kCCBResTypeDirectory)
            {
                [self removeDirectory:file];
            }
        }
        
        dir.count--;
        if (!dir.count)
        {
            [directories removeObjectForKey:dirPath];
            [self updatedWatchedPaths];
        }
    }
}

- (void) setActiveDirectories:(NSArray *)ad
{
    NSLog(@"setActiveDirectories: %@", ad);
    [activeDirectories removeAllObjects];
    
    for (NSString* dirPath in ad)
    {
        RMDirectory* dir = [directories objectForKey:dirPath];
        if (dir)
        {
            NSLog(@"Adding directory: %@", dirPath);
            [activeDirectories addObject:dir];
        }
    }
    
    [self notifyResourceObserversResourceListUpdated];
}

- (void) setActiveDirectory:(NSString *)dir
{
    [self setActiveDirectories:[NSArray arrayWithObject:dir]];
}

- (void) addResourceObserver:(id)observer
{
    [resourceObserver addObject:observer];
}

- (void) removeResourceObserver:(id)observer
{
    [resourceObserver removeObject:observer];
}

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event
{
    [self updateResourcesForPath:event.eventPath];
}

@end
