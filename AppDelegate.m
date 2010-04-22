//
//  AppDelegate.m
//  Slicer
//
//  Created by Lucius Kwok on 5/6/09.

/*
 Copyright (c) 2010, Felt Tip Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:  
 1.  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 2.  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 3.  Neither the name of the copyright holder(s) nor the names of any contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



#import "AppDelegate.h"
#import "MapClient.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>

#define kTileWidth 512
#define kTileHeight 512
#define kPreviewSize 960
#define kSliceFilename @"slice"
#define kPreviewFilename @"preview.png"
#define kBonjourServiceType @"_felttip-transit-map._tcp."
#define kBonjourServiceDomain @"local"


@implementation AppDelegate
@synthesize window, dimensionsLabel, zoomedDimensionsLabel, progressIndicator, netActivityIndicator, tableView, userZoom, inputFilePath, mapName, mapClient, maps;

- (void)awakeFromNib {
	self.userZoom = 1.0;
	self.mapName = @"Untitled Map";
	[self.window registerForDraggedTypes: [NSArray arrayWithObject:NSFilenamesPboardType]];
	
	netServiceBrowser = [[NSNetServiceBrowser alloc] init];
	netServiceBrowser.delegate = self;
}

- (void)dealloc {
	[dimensionsLabel release];
	[zoomedDimensionsLabel release];
	[progressIndicator release];
	[tableView release];
	[inputFilePath release];
	[mapClient release];
	[mapName release];
	[netServiceBrowser release];
	[maps release];
	[super dealloc];
}

#pragma mark -

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
	NSPasteboard *pboard = [sender draggingPasteboard];
	if ([[pboard types] containsObject:NSFilenamesPboardType])
		return NSDragOperationLink;
	return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
	NSPasteboard *pboard = [sender draggingPasteboard];
	BOOL success = NO;
	//NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
	if ([[pboard types] containsObject:NSFilenamesPboardType]) {
		NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		if (files.count > 0)	 {
			self.inputFilePath = [files objectAtIndex:0];
			success = YES;
		}
	}
	return success;
}

- (BOOL)wantsPeriodicDraggingUpdates {
	return NO;
}

- (IBAction)openDocument:(id)sender {
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = NO;
	panel.canChooseDirectories = NO;
	panel.canChooseFiles = YES;
	NSInteger result = [panel runModalForDirectory:nil file:nil types:nil];
	if (result == NSOKButton) {
		if (panel.filenames.count > 0)
			self.inputFilePath = [panel.filenames objectAtIndex:0];
	}
}

- (NSString*) createMapDirectoryWithName:(NSString*)name {
	NSString *basePath = name;
	int n = 1;
	// Find a unique name
	while ([self.mapClient fileExistsAtPath: name]) {
		n++;
		name = [basePath stringByAppendingFormat:@"-%d", n];
	}
	[self.mapClient createDirectoryAtPath:name];
	return name;
}

- (IBAction)slice:(id)sender {
	[self.window makeFirstResponder:sender];
	
	if (self.mapClient) { // Network version
		NSString *mapFilename = [[self.inputFilePath lastPathComponent] stringByDeletingPathExtension];
		mapFilename = [self createMapDirectoryWithName:mapFilename];
		
		// Update Maps.plist
		NSMutableDictionary *mapEntry = [NSMutableDictionary dictionary];
		[mapEntry setObject:self.mapName forKey:@"name"];
		[mapEntry setObject:mapFilename forKey:@"directory"];
		[mapEntry setObject:[NSNumber numberWithInt:1] forKey:@"userMap"];
		
		NSMutableArray *newMaps = [NSMutableArray arrayWithArray:self.maps];
		[newMaps addObject:mapEntry];
		self.maps = newMaps;
		
		// Send updated Maps.plist
		NSData *mapsPlist = [NSKeyedArchiver archivedDataWithRootObject:self.maps];
		[self.mapClient putData:mapsPlist atPath:@"Maps.plist"];
		
		// Slice and send
		[self sliceImage:self.inputFilePath withOutputPath:mapFilename zoom:self.userZoom];

		// Refresh maps list on device
		[self.mapClient refreshRemoteDevice];
		
	} else { // Save to same directory as original file
		NSString *currentDirectory = [self.inputFilePath stringByDeletingLastPathComponent];
		[self sliceImage:self.inputFilePath withOutputPath:currentDirectory zoom:self.userZoom];
	}
}

- (IBAction)showSlicerWindow:(id)sender {
	[window makeKeyAndOrderFront:sender];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
	self.inputFilePath = filename;
	return YES;
}

#pragma mark -

- (CGSize)pixelDimensionsOfImage:(NSImage*)image {
	float width = [image size].width;
	float height = [image size].height;
	
	// Try to get bitmap representations
	NSArray* reps = [image representations];
	for (NSImageRep *rep in reps) {
		if ([rep isKindOfClass: [NSBitmapImageRep class]]) {
			NSBitmapImageRep *bitmapRep = (NSBitmapImageRep*) rep;
			width = bitmapRep.pixelsWide;
			height = bitmapRep.pixelsHigh;
			break;
		}
	}
	return CGSizeMake (width, height);
}

- (void)setInputFilePath:(NSString*)newPath {
	[inputFilePath release];
	inputFilePath = [newPath copy];

	NSImage *image = [[NSImage alloc] initWithContentsOfFile:newPath];
	CGSize size = [self pixelDimensionsOfImage: image];
	
	[image release];
	[dimensionsLabel setStringValue: [NSString stringWithFormat:@"%1.0f x %1.0f", size.width, size.height]];
	
}

- (void)sliceImage:(NSString*)inputFile withOutputPath:(NSString*)outputPath zoom:(float)zoom {
	NSImage *sourceImage = nil;
	CGSize sourceImageSize;

	[progressIndicator setDoubleValue: 0.0];
	if ([self isCancelled]) return;
	
	sourceImage = [[NSImage alloc] initWithContentsOfFile:inputFile];
	sourceImageSize = CGSizeMake ([sourceImage size].width, [sourceImage size].height);
	CGSize sourcePixelSize = [self pixelDimensionsOfImage:sourceImage];
	// Adjust zoom for difference between image size and pixel size
	zoom = zoom * sourcePixelSize.width / sourceImageSize.width;

	// Progress 
	double numberOfTiles = ceil (sourceImageSize.height * zoom / kTileHeight) * ceil (sourceImageSize.width * zoom / kTileWidth) ;
	double tilesCompleted = 0.0;
	[progressIndicator setMinValue: 0.0];
	[progressIndicator setMaxValue: numberOfTiles];

	//CGRect tileBounds = CGRectMake (0.0f, 0.0f, kTileWidth, kTileHeight);
	int tileX, tileY, tileWidth, tileHeight, fileX, fileY;
	int outputWidth = floor (sourceImageSize.width * zoom);
	int outputHeight = floor (sourceImageSize.height * zoom);
	NSString *filename;
	//NSLog (@"output image size: %d %d", outputWidth, outputHeight);
	
	// Create preview image
	float previewScale = 0.0;
	NSRect sourceRect = NSMakeRect(0, 0, sourceImageSize.width, sourceImageSize.height);
	CGSize previewSize = [self optimalPreviewSizeForImageSize: CGSizeMake (sourceImageSize.width * zoom, sourceImageSize.height * zoom)];
	NSBitmapImageRep *bitmap = nil;
	if (previewSize.width > 0.0f) {
		float previewZoom = previewSize.width / sourceImageSize.width;
		previewScale = zoom / previewZoom;
		bitmap = [self bitmapWithSourceImage:sourceImage sourceRect:sourceRect destinationSize:previewSize];
		[self writeImage:[bitmap CGImage] toFile:[outputPath stringByAppendingPathComponent:kPreviewFilename]];
	}
	
	// Write map info
	[self writePropertiesToPath:outputPath withMapSize:CGSizeMake(outputWidth, outputHeight) previewScale:previewScale];
	
	// Create slices
	fileY = 0;
	for (tileY = 0.0f; tileY < outputHeight; tileY += kTileHeight) {
		fileX = 0;
		for (tileX = 0.0f; tileX < outputWidth; tileX += kTileWidth) {
			tileWidth = ((outputWidth - tileX) < kTileWidth)? (outputWidth - tileX) : kTileWidth;
			tileHeight = ((outputHeight - tileY) < kTileHeight)? (outputHeight - tileY) : kTileHeight;
			
			sourceRect.origin.x = tileX / zoom;
			sourceRect.origin.y = tileY / zoom;
			sourceRect.size.width = tileWidth / zoom;
			sourceRect.size.height = tileHeight / zoom;
			
			//NSLog (@"%@: %d %d %d %d", outputFilePath, tileX, tileY, tileWidth, tileHeight);
			bitmap = [self bitmapWithSourceImage:sourceImage sourceRect:sourceRect destinationSize:CGSizeMake (tileWidth, tileHeight)];
			filename = [NSString stringWithFormat:@"%@-%d%c.png", kSliceFilename, fileY, 'a'+fileX];
			[self writeImage:[bitmap CGImage] toFile:[outputPath stringByAppendingPathComponent:filename]];
			
			// Clean up
			fileX++;
			tilesCompleted++;
			
			// Update progress
			[progressIndicator setDoubleValue: tilesCompleted];
			if ([self isCancelled]) {
				tileY = outputHeight;
				break;
			}
		}
		fileY++;
	}
	[sourceImage release];
}

- (NSBitmapImageRep*) bitmapWithSourceImage:(NSImage*)sourceImage sourceRect:(NSRect)sourceRect destinationSize:(CGSize)destinationSize {
	NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:destinationSize.width pixelsHigh:destinationSize.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:32] autorelease];
	
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
	
	NSRect destinationRect = NSMakeRect (0, 0, destinationSize.width, destinationSize.height);
	[[NSColor whiteColor] set];
	NSRectFill(destinationRect);
	[sourceImage drawInRect:destinationRect fromRect:sourceRect operation:NSCompositeSourceOver fraction:1.0];
	
	[NSGraphicsContext restoreGraphicsState];
	
	return bitmap;
}

- (void)writeImage:(CGImageRef)image toFile:(NSString*)file {
	//NSURL *url = [NSURL fileURLWithPath:file];
	//CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL ((CFURLRef)url, kUTTypePNG, 1, nil);
	
	NSMutableData *data = [NSMutableData data];
	CGDataConsumerRef dataConsumer = CGDataConsumerCreateWithCFData((CFMutableDataRef) data);
	CGImageDestinationRef imageDestination = CGImageDestinationCreateWithDataConsumer (dataConsumer, kUTTypePNG, 1, nil);
	if (imageDestination == nil) { 
		NSLog (@"image destination is nil."); 
	} else {
		CGImageDestinationAddImage (imageDestination, image, nil);
		CGImageDestinationFinalize (imageDestination);
		CFRelease (imageDestination);
	}
	CFRelease (dataConsumer);
	
	if (self.mapClient) {
		[self.mapClient putData:data atPath:file];
	} else {
		NSError *error = nil;
		[data writeToFile:file options:0 error:&error];
		if (error) NSLog (@"Error writing to file. %@", error);
	}
}

- (BOOL) writePropertiesToPath:(NSString*)path withMapSize:(CGSize)mapSize previewScale:(float)previewScale {
	NSMutableDictionary *properties = [NSMutableDictionary dictionary];
	
	[properties setObject:[NSNumber numberWithInt:mapSize.width] forKey:@"mapWidth"];
	[properties setObject:[NSNumber numberWithInt:mapSize.height] forKey:@"mapHeight"];
	[properties setObject:[NSNumber numberWithInt:kTileWidth] forKey:@"tileWidth"];
	[properties setObject:[NSNumber numberWithInt:kTileHeight] forKey:@"tileHeight"];
	[properties setObject:[NSNumber numberWithFloat:previewScale] forKey:@"previewScale"];
	
	BOOL success = NO;
	if (self.mapClient) {
		NSData *plistData = [NSKeyedArchiver archivedDataWithRootObject:properties];
		if (plistData)
			[self.mapClient putData:plistData atPath:[path stringByAppendingPathComponent:@"MapInfo.plist"]];
		else
			NSLog (@"MapInfo.plist data is nil.");
	} else {
		[NSKeyedArchiver archiveRootObject:properties toFile:[path stringByAppendingPathComponent:@"MapInfo.plist"]];
	}
	return success;
}

- (CGSize)optimalPreviewSizeForImageSize:(CGSize)imageSize {
	if ((imageSize.width <= kPreviewSize) && (imageSize.height <= kPreviewSize)) return CGSizeZero;
	
	float ratio = imageSize.width / imageSize.height;
	if (ratio > 1.0f) {
		imageSize.width = kPreviewSize;
		imageSize.height = imageSize.width / ratio;
	} else {
		imageSize.height = kPreviewSize;
		imageSize.width = imageSize.height * ratio;
	}
	return imageSize;
}

- (BOOL)isCancelled {
	BOOL result = NO;
	NSEvent *event = [NSApp nextEventMatchingMask: NSKeyDownMask | NSLeftMouseDownMask untilDate:[NSDate distantPast] inMode:NSModalPanelRunLoopMode dequeue:YES];
	switch ([event type]) {
		case NSKeyDown:
			if ([event keyCode]==53) // escape key
				result = YES;
			break;
		case NSLeftMouseDown:
			//[cancelButton mouseDown: event];
			break;
		default:
			break;
	}
	return result;
}

#pragma mark -

- (IBAction)ping:(id)sender {
	NSLog (@"Looking for services.");
	// Clear table
	self.maps = nil;
	[tableView reloadData];
	[netServiceBrowser searchForServicesOfType:kBonjourServiceType inDomain:kBonjourServiceDomain];
	[netActivityIndicator startAnimation:nil];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindDomain:(NSString *)domainName moreComing:(BOOL)moreDomainsComing {
	NSLog (@"Found domain: %@, more = %d", domainName, moreDomainsComing);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreServicesComing {
	NSLog (@"Found service: %@, more = %d", service, moreServicesComing);
	
	// Cancel any pending services
	if (netService) {
		[self stopNetService];
	}
	
	// Attempt to resolve service
	[service setDelegate:self];
	[service resolveWithTimeout:60.0];
	netService = [service retain];
	
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
	if (service != netService) return;
	
	NSLog (@"Net service did not resolve: %@", errorDict);
	[self stopNetService];
	[netActivityIndicator stopAnimation:nil];
}

- (void)parseMapsData:(NSData*)data {
	NSArray *deviceMaps = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	if (deviceMaps == nil) {NSLog (@"Maps data was nil."); return;}
	self.maps = deviceMaps;
	[self.tableView reloadData];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
	if (service != netService) return;
	
	[netActivityIndicator stopAnimation:nil];

	NSInputStream *inputStream = NULL;
	NSOutputStream *outputStream = NULL;
	BOOL success = [netService getInputStream:&inputStream outputStream:&outputStream];
	if (!success) { NSLog (@"Could not get streams from net service."); return; }

	MapClient *client = [[MapClient alloc] initWithInputStream:inputStream outputStream:outputStream];
	if (client == nil) return;
	self.mapClient = client;
	
	NSData *fileData = [client getFile:@"Maps.plist"];
	if (fileData != nil) 
		[self parseMapsData:fileData];
	
	[client release];
	
}

- (void)stopNetService {
	[netService stop];
	[netService release];
	netService = nil;
}

#pragma mark -

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	return self.maps.count;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	if (self.maps == nil) return nil;
	if (rowIndex >= self.maps.count) return nil;
	
	NSDictionary *entry = [self.maps objectAtIndex:rowIndex];
	return [entry objectForKey:@"name"];
}


@end
