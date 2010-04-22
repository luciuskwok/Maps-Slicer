//
//  MapClient.m
//  Slicer
//
//  Created by Lucius Kwok on 5/12/09.

/*
 Copyright (c) 2010, Felt Tip Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:  
 1.  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 2.  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 3.  Neither the name of the copyright holder(s) nor the names of any contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



#import "MapClient.h"


@implementation MapClient

- (id)initWithInputStream:(NSInputStream*)is outputStream:(NSOutputStream*)os {
	if (self = [super init]) {
		if ((is == nil) || (os == nil)) { NSLog (@"Streams are nil."); [self release]; return nil; }
		
		netDebugging = YES;
		inputStream = [is retain];
		outputStream = [os retain];

		if (!CFReadStreamOpen ((CFReadStreamRef) inputStream)) { 
			NSLog (@"Could not open read stream."); [self release]; return nil; 
		}
		
		if (!CFWriteStreamOpen ((CFWriteStreamRef) outputStream)) {
			NSLog (@"Could not open write stream."); [self release]; return nil;
		}
	}
	return self;
}

- (void)dealloc {
	if (inputStream) CFReadStreamClose ((CFReadStreamRef) inputStream);
	if (outputStream) CFWriteStreamClose ((CFWriteStreamRef) outputStream);
	[inputStream release];
	[outputStream release];
	[super dealloc];
}

- (void)sendCommand:(NSString*)command path:(NSString*)path {
	NSString *toSend = nil;
	if (path == nil)
		toSend = [NSString stringWithFormat:@"%@\n", command];
	else
		toSend = [NSString stringWithFormat:@"%@ %@\n", command, path];
	NSData *data = [toSend dataUsingEncoding:NSUTF8StringEncoding];
	CFWriteStreamWrite((CFWriteStreamRef) outputStream, [data bytes], [data length]);
	if (netDebugging) NSLog (@"Sent command %@", toSend);
}

- (void) refreshRemoteDevice {
	[self sendCommand:@"REF" path:nil];
}

- (NSData*)receiveFile {
	SInt32 fileLength = 0;
	int bytesRead = CFReadStreamRead ((CFReadStreamRef) inputStream, (UInt8*) &fileLength, sizeof(fileLength));
	if (bytesRead != sizeof(fileLength)) {NSLog (@"Incorrect number of bytes read."); return nil;}
	if (fileLength < 0) {NSLog (@"Remote file not found."); return nil;}
	
	NSMutableData *fileData = [NSMutableData dataWithLength:fileLength];
	bytesRead = CFReadStreamRead ((CFReadStreamRef) inputStream, [fileData mutableBytes], [fileData length]);
	if (bytesRead != fileLength) {NSLog (@"Incorrect number of bytes read.");}
	
	return fileData;
}

- (NSData*) getFile:(NSString*)path {
	[self sendCommand:@"GET" path:path];
	return [self receiveFile];
}

- (BOOL) fileExistsAtPath:(NSString*)path {
	[self sendCommand:@"XST" path:path];
	char exists = 0;
	CFReadStreamRead ((CFReadStreamRef) inputStream, (UInt8*) &exists, sizeof(char));
	return (exists != 0);
}

- (BOOL) createDirectoryAtPath:(NSString*)path {
	[self sendCommand:@"MKD" path:path];
	char success = 0;
	CFReadStreamRead ((CFReadStreamRef) inputStream, (UInt8*) &success, sizeof(char));
	return (success != 0);
}

- (void) putData:(NSData*)data atPath:(NSString*)path {
	[self sendCommand:@"PUT" path:path];
	SInt32 fileLength = [data length];
	int bytesWritten;
	bytesWritten = CFWriteStreamWrite((CFWriteStreamRef) outputStream, (UInt8*) &fileLength, sizeof(fileLength));
	if (bytesWritten != sizeof(fileLength)) NSLog (@"Bytes written %d doesn't match length %d", bytesWritten, sizeof(fileLength));
	
	int remain = [data length];
	int offset = 0;
	const unsigned char *dataPtr = [data bytes];
	while (remain > 0) {
		bytesWritten = CFWriteStreamWrite((CFWriteStreamRef) outputStream, &dataPtr[offset], remain);
		remain -= bytesWritten;
		offset += bytesWritten;
	}
	
	if (netDebugging) NSLog (@"Sent %d bytes of data.", offset);
}


@end
