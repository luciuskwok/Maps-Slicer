//
//  AppDelegate.h
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

/*	
 About this code:
	This Slicer app is the desktop companion to the Transit Maps iPhone app by Felt Tip Inc and available in the App Store. This app will take a bitmap or PDF image file and slice it into tiles for use with the iPhone app. It will create 512 pixel square tiles and save them as PNG files. It will also create the MapInfo.plist file, which is made using NSKeyedArchiver. 
 
 Networking:
 The networking code, including references to MapClient, is currently not working, and the version of Transit Maps in the App Store does not include the required server code to function with this app anyway.
 
	-Lucius Kwok
 */


#import <Cocoa/Cocoa.h>
@class MapClient;

@interface AppDelegate : NSObject {
	IBOutlet NSWindow *window;
	IBOutlet NSTextField *dimensionsLabel;
	IBOutlet NSTextField *zoomedDimensionsLabel;
	IBOutlet NSProgressIndicator *progressIndicator;
	IBOutlet NSProgressIndicator *netActivityIndicator;
	IBOutlet NSTableView *tableView;
	
	double userZoom;
	NSString *inputFilePath;
	NSString *mapName;
	
	NSNetServiceBrowser *netServiceBrowser;
	NSNetService *netService;
	
	MapClient *mapClient;
	NSArray *maps;
}
@property (nonatomic, retain) NSWindow *window;
@property (nonatomic, retain) NSTextField *dimensionsLabel;
@property (nonatomic, retain) NSTextField *zoomedDimensionsLabel;
@property (nonatomic, retain) NSProgressIndicator *progressIndicator;
@property (nonatomic, retain) NSProgressIndicator *netActivityIndicator;
@property (nonatomic, retain) NSTableView *tableView;

@property (nonatomic, assign) double userZoom;
@property (nonatomic, retain) NSString *inputFilePath;
@property (nonatomic, retain) NSString *mapName;
@property (nonatomic, retain) MapClient *mapClient;
@property (nonatomic, retain) NSArray *maps;

- (IBAction)openDocument:(id)sender;
- (IBAction)slice:(id)sender;
- (IBAction)showSlicerWindow:(id)sender;

- (void)sliceImage:(NSString*)inputFile withOutputPath:(NSString*)outputPath zoom:(float)zoom;
- (NSBitmapImageRep*) bitmapWithSourceImage:(NSImage*)sourceImage sourceRect:(NSRect)sourceRect destinationSize:(CGSize)destinationSize;
- (void)writeImage:(CGImageRef)image toFile:(NSString*)file;
- (BOOL) writePropertiesToPath:(NSString*)path withMapSize:(CGSize)mapSize previewScale:(float)previewScale;
- (CGSize)optimalPreviewSizeForImageSize:(CGSize)imageSize;
- (BOOL)isCancelled;

- (IBAction)ping:(id)sender;
- (void)stopNetService;

@end
