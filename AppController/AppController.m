//
//  AppController.m
//  AppController
//
//  Created by Zichen Zheng on 12/2/13.
//  Copyright (c) 2013 Zichen Zheng. All rights reserved.
//

#import "AppController.h"

@implementation AppController

@synthesize frameOutputURL;
@synthesize endAppControlLoop;

- (BOOL) setupAVCapture {
    NSError *error = nil;
    
    captureSession = [AVCaptureSession new];
    [captureSession setSessionPreset:AVCaptureSessionPresetPhoto];
	
    // Select a video device, make an input
    for (AVCaptureDevice *device in [AVCaptureDevice devices]) {
        if ([device hasMediaType:AVMediaTypeVideo] || [device hasMediaType:AVMediaTypeMuxed]) {
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            if (error) {
                [captureSession release];
                NSLog(@"deviceInputWithDevice failed with error %@", [error localizedDescription]);
                return NO;
            }
            if ([captureSession canAddInput:input]) [captureSession addInput:input];
            break;
        }
    }
	
    // Make a still image output
    stillImageOutput = [AVCaptureStillImageOutput new];
    if ([captureSession canAddOutput:stillImageOutput])
        [captureSession addOutput:stillImageOutput];
	
    // Make a preview layer so we can see the visual output of an AVCaptureSession
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [previewLayer setFrame:[previewView bounds]];
    [[previewLayer connection] setAutomaticallyAdjustsVideoMirroring:NO];
    [[previewLayer connection] setVideoMirrored:YES];
    
    // add the preview layer to the hierarchy
    CALayer *rootLayer = [previewView layer];
    [rootLayer setBackgroundColor: CGColorGetConstantColor(kCGColorBlack)];
    [rootLayer addSublayer: previewLayer];
    // add a text field (or label) on top of the preview, showing the gesture status
    [gdStatusView setStringValue: @"Stopped"];
    [self setGestureStatusViewColor: STOPPED];
    [rootLayer addSublayer: [gdStatusView layer]];
    
    if (DEBUG == 0) [debugTextView setHidden: YES];
    [rootLayer addSublayer: [debugTextView layer]];
    [debugTextView setStringValue: [[NSBundle mainBundle] bundlePath]];
    
    // start the capture session running, note this is an async operation
    // status is provided via notifications such as AVCaptureSessionDidStartRunningNotification/AVCaptureSessionDidStopRunningNotification
    [captureSession startRunning];
	
    return YES;
}

- (void) saveImage {
    // initiate a still image capture, return immediately
    // the completionHandler is called when a sample buffer has been captured
    AVCaptureConnection *stillImageConnection = [stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    [stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *__strong error) {
        NSData* imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        NSImage* image = [[NSImage alloc] initWithData:imageData];
        imageData = [image TIFFRepresentation];
        NSBitmapImageRep* bitmap = [NSBitmapImageRep imageRepWithData: imageData];
        imageData = [bitmap representationUsingType: NSPNGFileType properties: nil];
        [imageData writeToFile: [frameOutputURL path] atomically:YES];
        [image autorelease];  // avoid potential leak
	}];
}

- (void) appControl {
    while (true) {
        if (self.endAppControlLoop) {
            [gdStatusView setStringValue: @"Stopped"];
            [self setGestureStatusViewColor: STOPPED];
            break;
        }
        // save frame as an image
        [self saveImage];
        
        // execute gesture detection routine
        NSTask* gdTask = [[NSTask alloc] init];  // task for gesture detection
        NSString* gdExecPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"GestureDetector/GestureDetector"];
        NSString* gdRootDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"GestureDetector/"];
        [gdTask setLaunchPath: gdExecPath];
        [gdTask setArguments: [NSArray arrayWithObjects: @"-m", @"5", @"-i", frameOutputURL, @"-r", gdRootDir, nil]];
        [gdTask launch];
        [gdTask waitUntilExit];
        
        if ([gdTask terminationStatus] != 0) {
            [gdTask release];
            continue;
        }
        
        // read detection result from text file
        NSURL* gdResultURL = [NSURL URLWithString: @"GestureDetector/predict.result" relativeToURL:[[NSBundle mainBundle] resourceURL]];;
        NSString* gdResultStr = [[NSString alloc] initWithContentsOfURL: gdResultURL encoding:NSUTF8StringEncoding error: nil];
        int gdCode = [gdResultStr intValue];
        NSLog(@"Gesture code: %d\n", gdCode);
        
        itunesApp = [SBApplication applicationWithBundleIdentifier: @"com.apple.iTunes"];
        
        if (gdCode == 0) {
            [gdStatusView setStringValue: @"No Gesture"];
            [self setGestureStatusViewColor: NO_GESTURE];
        }
        
        else if (gdCode == 1) {
            [gdStatusView setStringValue: @"Fist"];
            [self setGestureStatusViewColor: HAS_GESTURE];
            
            if (iTunesControlled) {
                if ([itunesApp isRunning]) {  // iTunes must be running
                    // pause iTunes if it is playing
                    if (iTunesEPlSPlaying == [itunesApp playerState]) {
                        [itunesApp playpause];
                    }
                }
            }
            else {
                // refresh page (command + R)
                NSAppleScript* scriptObject = [[NSAppleScript alloc] initWithSource: @"tell application \"System Events\" to key code 15 using command down"];
                [scriptObject executeAndReturnError: nil];
                [scriptObject release];
            }
        }
        
        else if (gdCode == 2) {
            [gdStatusView setStringValue: @"Palm"];
            [self setGestureStatusViewColor: HAS_GESTURE];
            
            if (iTunesControlled) {
                if ([itunesApp isRunning]) {  // iTunes must be running
                    // play next track
                    if (previousGDCode != gdCode) {
                        [itunesApp nextTrack];
                    }
                }
            }
            else {
                // press down key
                NSAppleScript* scriptObject = [[NSAppleScript alloc] initWithSource: @"tell application \"System Events\" to key code 125\n"];
                [scriptObject executeAndReturnError: nil];
                [scriptObject release];
            }
        }
        
        else if (gdCode == 3) {
            [gdStatusView setStringValue: @"Pointing"];
            [self setGestureStatusViewColor: HAS_GESTURE];
            
            if (iTunesControlled) {
                if ([itunesApp isRunning]) {  // iTunes must be running
                    // play iTunes if it is paused
                    if (iTunesEPlSPlaying != [itunesApp playerState]) {
                        [itunesApp playpause];
                    }
                }
            }
            else {
                // press up key
                NSAppleScript* scriptObject = [[NSAppleScript alloc] initWithSource: @"tell application \"System Events\" to key code 126\n"];
                [scriptObject executeAndReturnError: nil];
                [scriptObject release];
            }
        }
        
        previousGDCode = gdCode;
        
        [gdTask release];
        [gdResultStr release];
    }
}

- (IBAction) startStop: (id) sender {
    if (started) {
        // finish
        endAppControlLoop = YES;
        [appControlThread cancel];
        [appControlThread release];
        appControlThread = nil;
        [gdStatusView setStringValue: @"Stopped"];
        [self setGestureStatusViewColor: STOPPED];
        [sender setTitle:@"Start Controlling"];
    }
    else {
        // begin
        endAppControlLoop = NO;
        appControlThread = [[NSThread alloc] initWithTarget:self selector:@selector(appControl) object:nil];
        [appControlThread start];
        [gdStatusView setStringValue: @"No Gesture"];
        [self setGestureStatusViewColor: NO_GESTURE];
        [sender setTitle:@"Stop Controlling"];
    }
    started = !started;
}

- (void) close {
    [captureSession stopRunning];
    [previewLayer removeFromSuperlayer];
    [previewLayer setSession:nil];
    [previewLayer release];
    [stillImageOutput release];
    [captureSession release];
    [super close];
}

- (IBAction) togglePreviewMirrored: (id) sender {
    [[previewLayer connection] setVideoMirrored:[(NSButton *)sender state]];
}

- (IBAction) toggleiTunesControlled: (id) sender {
    iTunesControlled = ! iTunesControlled;
}

- (id) init {
    self = [super init];
    self.frameOutputURL = [NSURL URLWithString: @"frame.png" relativeToURL:[[NSBundle mainBundle] resourceURL]];
    [[NSFileManager defaultManager] removeItemAtURL:self.frameOutputURL error:nil];
    [self setDisplayName: @"AppController Monitor"];
    previousGDCode = -1;
    iTunesControlled = YES;
    
    return self;
}

- (NSString*) windowNibName {
    return @"AppControllerMonitor";
}

- (void) windowControllerDidLoadNib: (NSWindowController*) aController {
    [super windowControllerDidLoadNib:aController];
    [self setupAVCapture];
}

- (void) setGestureStatusViewColor: (GestureStatus) gs {
    switch (gs) {
        case STOPPED:
            [gdStatusView setTextColor: [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:1.0]];
            [gdStatusView setBackgroundColor: [NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.85 alpha:1.0]];
            break;
            
        case HAS_GESTURE:
            [gdStatusView setTextColor: [NSColor colorWithCalibratedRed:0.0/255.0 green:95.0/255.0 blue:0.0/255.0 alpha:1.0]];
            [gdStatusView setBackgroundColor: [NSColor colorWithCalibratedRed:215.0/255.0 green:255.0/255.0 blue:196.0/255.0 alpha:1.0]];
            break;
            
        default:
            [gdStatusView setTextColor: [NSColor colorWithCalibratedRed:13.0/255.0 green:56.0/255.0 blue:162.0/255.0 alpha:1.0]];
            [gdStatusView setBackgroundColor: [NSColor colorWithCalibratedRed:176.0/255.0 green:216.0/255.0 blue:255.0/255.0 alpha:1.0]];
            break;
    }
}

@end
