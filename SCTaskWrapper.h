//
//  SCTaskWrapper.h
//  PhotoCapture360
//	
//	Based on AMShellWrapper by Andreas Mayer
//
//  Created by vincent on 8/25/10.
//  Copyright 2010 Ortery Technologies, Inc. All rights reserved.
//

//
//  AMShellWrapper.m
//  CommX
//
//  Created by Andreas on 2002-04-24.
//  Based on TaskWrapper from Apple
//
//  2002-06-17 Andreas Mayer
//  - used defines for keys in AMShellWrapperProcessFinishedNotification userInfo dictionary
//  2002-08-30 Andreas Mayer
//  - removed bug in getData that sent all output to appendError:
//  - added setInputStringEncoding: and setOutputStringEncoding:
//  - reactivated code to clear output pipes when the task is finished
//  2004-06-15 Andreas Mayer
//  - renamed stopProcess to cleanup since that is what it does; stopProcess
//    is meant to just terminate the task so it's issuing a [task terminate] only now
//  - appendOutput: and appendError: do some error handling now
//  2004-08-11 Andreas Mayer
//  - removed AMShellWrapperProcessFinishedNotification notification since
//	it prevented the task from getting deallocated
//  - don't retain stdin/out/errHandle
//
//  I had some trouble to decide when the task had really stopped. The Apple example
//  did only examine the output pipe and exited when it was empty - which I found unreliable.
//
//  This, finally, seems to work: Wait until the output pipe is empty *and* we received
//  the NSTaskDidTerminateNotification. Seems obvious now ...  :)

#import <Foundation/Foundation.h>
#import "SCTaskErrors.h"

extern NSString *const SCTaskWrapperProcessFinishedNotification;
extern NSString *const SCTaskWrapperProcessFinishedNotificationTaskKey;
extern NSString *const SCTaskWrapperProcessFinishedNotificationTerminationStatusKey;
extern NSString *const SCTaskWrapperErrorDomain;

// implement this protocol to control your SCTaskWrapper object:
@protocol SCTaskWrapperController


/*!
    @method     
    @abstract   output from stdout
    @discussion Your controller's implementation of this method will be called 
				when output arrives from the NSTask.
				Output will come from stdout, per the SCTaskWrapper implementation.
*/
- (void)appendOutput:(NSString *)output;


/*!
    @method     
    @abstract   output from stderr
	@discussion Your controller's implementation of this method will be called 
				when output arrives from the NSTask. 
				Output will come from stderr, per the SCTaskWrapper implementation.
*/
- (void)appendError:(NSString *)error;


// This method is a callback which your controller can use to do other initialization
// when a process is launched.
- (void)processStarted:(id)sender;


// This method is a callback which your controller can use to do other cleanup
// when a process is halted.
- (void)processFinished:(id)sender withTerminationStatus:(int)resultCode;


// AMShellWrapper posts a SCTaskWrapperProcessFinishedNotification when a process finished.
// The userInfo of the notification contains the corresponding NSTask ((NSTask *), key @"task")
// and the result code ((NSNumber *), key @"resultCode")
// ! notification removed since it prevented the task from getting deallocated

@end



@interface SCTaskWrapper : NSObject {
	NSTask *task_;
	id <SCTaskWrapperController> controller_;
	NSString			*workingDirectory_;
	NSString			*taskLaunchPath_;
	NSDictionary		*environment_;
	NSArray				*arguments_;
	NSFileHandle		*stdinHandle_;
	NSFileHandle		*stdoutHandle_;
	NSFileHandle		*stderrHandle_;
	NSStringEncoding	inputStringEncoding_;
	NSStringEncoding	outputStringEncoding_;
	id stdinPipe_;
	id stdoutPipe_;
	id stderrPipe_;
	BOOL stdoutEmpty_;
	BOOL stderrEmpty_;
	BOOL taskDidTerminate_;
}

/*!
    @method     
    @abstract   This is the designated initializer
    @discussion Pass in your controller and any task arguments.
				Allowed for stdin/stdout and stderr are
				- values of type NSFileHandle or
				- NSPipe or
				- nil, in which case this wrapper class automatically 
				connects to the callbacks and 
				appendInput: method and provides asynchronous feedback notifications.
				The environment argument may be nil in which case the environment 
				is inherited from the calling process.
	@param controller	object which calls the task
	@param inputPipe	stdin pipe (NSFileHandle or NSPipe or nil)
	@param outputPipe	stdout pipe (NSFileHandle or NSPipe or nil)
	@param errorPipe	stderr pipe (NSFileHandle or NSPipe or nil)
	@param environment	The environment argument may be nil in which case the environment 
						is inherited from the calling process.
	@param workingDirectory	The current working path
	@param taskLaunchPath The path to the executable to launch with the NSTask.
	@param arguments a NSArray contains arguments for the executable
*/
- (id)initWithController:(id <SCTaskWrapperController>)controller 
			   inputPipe:(id)input 
			  outputPipe:(id)output 
			   errorPipe:(id)error 
			 environment:(NSDictionary *)env 
		workingDirectory:(NSString *)directoryPath 
		  taskLaunchPath:(NSString *)taskPath arguments:(NSArray *)args;

- (BOOL)startProcess:(NSError **)error;
// This method launches the process, setting up asynchronous feedback notifications.

- (void)stopProcess;
// This method stops the process, stoping asynchronous feedback notifications.

- (void)appendInput:(NSString *)input;
// input to stdin

- (void)setInputStringEncoding:(NSStringEncoding)newInputStringEncoding;
// If you need something else than UTF8, set the encoding type of the task's input here

- (void)setOutputStringEncoding:(NSStringEncoding)newOutputStringEncoding;
// If you need something else than UTF8, tell the task what encoding to use for output here

@end
