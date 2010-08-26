//
//  SCTaskWrapper.m
//  SCTaskWrapper
//
//  Created by vincent on 8/25/10.
//  Copyright 2010 Ortery Technologies, Inc. All rights reserved.
//

#import "SCTaskWrapper.h"

NSString *const SCTaskWrapperProcessFinishedNotification = @"SCTaskWrapperProcessFinishedNotification";
NSString *const SCTaskWrapperProcessFinishedNotificationTaskKey = @"SCTaskWrapperProcessFinishedNotificationTaskKey";
NSString *const SCTaskWrapperProcessFinishedNotificationTerminationStatusKey = @"SCTaskWrapperProcessFinishedNotificationTerminationStatusKey";

NSString *const SCTaskWrapperErrorDomain = @"com.smokyonion.SCTaskWrapper.ErrorDomain";

@interface SCTaskWrapper (Private)

- (BOOL)setupTask:(NSError **)error;
- (void)cleanup;
- (void)getData:(NSNotification *)notification;
- (void)taskStopped:(NSNotification *)notification;
- (void)appendOutput:(NSData *)data;
- (void)appendError:(NSData *)data;
- (NSFileHandle *)stdoutHandle;
- (NSFileHandle *)stderrHandle;
- (void)setStdoutHandle:(NSFileHandle *)handle;
- (void)setStderrHandle:(NSFileHandle *)handle;

@end

@implementation SCTaskWrapper

- (id)initWithController:(id <SCTaskWrapperController>)controller 
			   inputPipe:(id)input 
			  outputPipe:(id)output 
			   errorPipe:(id)error 
			 environment:(NSDictionary *)env 
		workingDirectory:(NSString *)directoryPath 
		  taskLaunchPath:(NSString *)taskPath
			   arguments:(NSArray *)args
{
	if ([super init]) {
		controller_ = controller;
		stdinPipe_ = [input retain];
		stdoutPipe_ = [output retain];
		stderrPipe_ = [error retain];
		environment_ = [env retain];
		workingDirectory_ = [directoryPath retain];
		taskLaunchPath_ = [taskPath retain];
		arguments_ = [args retain];
		inputStringEncoding_ = NSUTF8StringEncoding;
		outputStringEncoding_ = NSUTF8StringEncoding;
		task_ = [[NSTask alloc] init];
	}
	
	return self;
}

- (void)dealloc
{
	[stderrPipe_ release];
	[stdoutPipe_ release];
	[stdinPipe_ release];
	[environment_ release];
	[workingDirectory_ release];
	[arguments_ release];
	[task_ release];
	[super dealloc];
}

- (BOOL)startProcess:(NSError **)error
{
	BOOL result = YES;
	
	// We first let the controller know that we are starting 
	[controller_ processStarted:self];
	result = [self setupTask:error];
	
	if (result == YES) {
		// Here we register as an observer of the NSFileHandleReadCompletionNotification,
		// which lets us know when there is data waiting for us to grab it in the task's file
		// handle (the pipe to which we connected stdout and stderr above).
		// -getData: will be called when there is data waiting. The reason we need to do this
		// is because if the file handle gets filled up, the task will block waiting to send
		// data and we'll never get anywhere. So we have to keep reading data from the file
		// handle as we go.
		if (stdoutPipe_ == nil) // we have to handle this ourselves:
			[[NSNotificationCenter defaultCenter] addObserver:self 
													 selector:@selector(getData:) 
														 name:NSFileHandleReadCompletionNotification 
													   object:stdoutHandle_];
		
		if (stderrPipe_ == nil) // we have to handle this ourselves:
			[[NSNotificationCenter defaultCenter] addObserver:self 
													 selector:@selector(getData:) 
														 name:NSFileHandleReadCompletionNotification 
													   object:stderrHandle_];
		
		// We tell the file handle to go ahead and read in the background asynchronously,
		// and notify us via the callback registered above when we signed up as an observer.
		// The file handle will send a NSFileHandleReadCompletionNotification when it has
		// data that is available.
		[stdoutHandle_ readInBackgroundAndNotify];
		[stderrHandle_ readInBackgroundAndNotify];
		
		// since waiting for the output pipes to run dry seems unreliable in terms of
		// deciding wether the task has died, we go the 'clean' route and wait for a notification
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(taskStopped:) 
													 name:NSTaskDidTerminateNotification 
												   object:task_];
		
		// we will wait for data in stdout; there may be nothing to receive from stderr
		stdoutEmpty_ = NO;
		stderrEmpty_ = YES;
		
		// launch the task asynchronously
		[task_ launch];
		
		// since the notification center does not retain the observer, make sure
		// we don't get deallocated early
		[self retain];
	}
	else {
		[self retain];
		[self performSelector:@selector(cleanup) withObject:nil afterDelay:0];
	}
	
	return result;
}

- (void)stopProcess
{
	[task_ terminate];
}

// If you need something else than UTF8, set the code type of the task's input here
- (void)setInputStringEncoding:(NSStringEncoding)newInputStringEncoding
{
	inputStringEncoding_ = newInputStringEncoding;
}

// If you need something else than UTF8, tell the task what coding to use for output here
- (void)setOutputStringEncoding:(NSStringEncoding)newOutputStringEncoding
{
	outputStringEncoding_ = newOutputStringEncoding;
}

// input to stdin
- (void)appendInput:(NSString *)input
{
	[stdinHandle_ writeData:[input dataUsingEncoding:inputStringEncoding_]];
}

@end

@implementation SCTaskWrapper (Private)

- (BOOL)setupTask:(NSError **)error
{
	BOOL result = YES;
	NSInteger errorCode = kSCTaskErrorNone;
	
	// The output of stdout and stderr is sent to a pipe so that we can catch it later
	// and send it along to the controller; we redirect stdin too, so that it accepts
	// input from us instead of the console
	if (stdinPipe_ == nil) {
		NSPipe *newPipe = [[NSPipe alloc] init];
		if (newPipe) {
			[task_ setStandardInput:newPipe];
			stdinHandle_ = [[task_ standardInput] fileHandleForWriting];
			// we do NOT retain stdinHandle here since it is retained (and released)
			// by the task standardInput pipe (or so I hope ...)
			[newPipe release];
		} else {
			perror("SCTaskWrapper - failed to create pipe for stdIn");
			errorCode = kSCTaskErrorFailedToCreatePipeForStdin;
			result = NO;
		}
	} else {
		[task_ setStandardInput:stdinPipe_];
		if ([stdinPipe_ isKindOfClass:[NSPipe class]])
			stdinHandle_ = [stdinPipe_ fileHandleForWriting];
		else
			stdinHandle_ = stdinPipe_;
	}
	
	if (stdoutPipe_ == nil) {
		NSPipe *newPipe = [[NSPipe alloc] init];
		if (newPipe) {
			[task_ setStandardOutput:newPipe];
			stdoutHandle_ = [[task_ standardOutput] fileHandleForReading];
			[newPipe release];
		} else {
			perror("SCTaskWrapper - failed to create pipe for stdOut");
			errorCode = kSCTaskErrorFailedToCreatePipeForStdout;
			result = NO;
		}
	} else {
		[task_ setStandardOutput:stdoutPipe_];
		stdoutHandle_ = stdoutPipe_;
	}
	
	if (stderrPipe_ == nil) {
		NSPipe *newPipe = [[NSPipe alloc] init];
		if (newPipe) {
			[task_ setStandardError:newPipe];
			stderrHandle_ = [[task_ standardError] fileHandleForReading];
			[newPipe release];
		} else {
			perror("SCTaskWrapper - failed to create pipe for stdErr");
			errorCode = kSCTaskErrorFailedToCreatePipeForStderr;
			result = NO;
		}
	} else {
		[task_ setStandardError:stderrPipe_];
		stderrHandle_ = stderrPipe_;
	}
	
	// setting the current working directory
	if (workingDirectory_ != nil)
		[task_ setCurrentDirectoryPath:workingDirectory_];
	
	// Setting the environment if available
	if (environment_ != nil)
		[task_ setEnvironment:environment_];
	
	// The path to the binary
	if (taskLaunchPath_ != nil)
		[task_ setLaunchPath:taskLaunchPath_];
	
	// The task arguments are just grabbed from the array
	[task_ setArguments:arguments_];
	
	if (error) {
		*error = [NSError errorWithDomain:SCTaskWrapperErrorDomain 
									 code:errorCode userInfo:nil];
	}
	
	return result;
}

// If the task ends, there is no more data coming through the file handle even when
// the notification is sent, or the process object is released, then this method is called.
- (void)cleanup
{
	NSData *data;
	int terminationStatus = -1;
	
	if (taskDidTerminate_) {
		// It is important to clean up after ourselves so that we don't leave potentially
		// deallocated objects as observers in the notification center; this can lead to
		// crashes.
		[[NSNotificationCenter defaultCenter] removeObserver:self];
		
		// Make sure the task has actually stopped!
		//[task terminate];
		
		// NSFileHandle availableData is a blocking read - what were they thinking? :-/
		// Umm - OK. It comes back when the file is closed. So here we go ...
		
		// clear stdout
		while ((data = [stdoutHandle_ availableData]) && [data length]) {
			[self appendOutput:data];
		}
		
		// clear stderr
		while ((data = [stderrHandle_ availableData]) && [data length]) {
			[self appendError:data];
		}
		terminationStatus = [task_ terminationStatus];
	}
	
	// we tell the controller that we finished, via the callback, and then blow away
	// our connection to the controller.  NSTasks are one-shot (not for reuse), so we
	// might as well be too.
	[controller_ processFinished:self withTerminationStatus:terminationStatus];
	
	/*
	 NSDictionary *userInfo = nil;
	 // task has to go so we can't put it in a dictionary ...
	 if (task) {
	 userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[[task retain] autorelease], AMShellWrapperProcessFinishedNotificationTaskKey, [NSNumber numberWithInt:terminationStatus], AMShellWrapperProcessFinishedNotificationTerminationStatusKey, nil];
	 } else {
	 userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], AMShellWrapperProcessFinishedNotificationTaskKey, [NSNumber numberWithInt:terminationStatus], AMShellWrapperProcessFinishedNotificationTerminationStatusKey, nil];
	 }
	 
	 [[NSNotificationCenter defaultCenter] postNotificationName:AMShellWrapperProcessFinishedNotification object:self userInfo:userInfo];
	 */
	
	controller_ = nil;
	
	// we are done; go ahead and kill us if you like ...
	[self release];
}

// This method is called asynchronously when data is available from the task's file handle.
// We just pass the data along to the controller as an NSString.
- (void)getData:(NSNotification *)notification
{
	NSData *data;
	id notificationObject;
	
	notificationObject = [notification object];
	data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
	
	// If the length of the data is zero, then the task is basically over - there is nothing
	// more to get from the handle so we may as well shut down.
	if ([data length]) {
		// Send the data on to the controller; we can't just use +stringWithUTF8String: here
		// because -[data bytes] is not necessarily a properly terminated string.
		// -initWithData:encoding: on the other hand checks -[data length]
		if ([notificationObject isEqualTo:stdoutHandle_]) {
			[self appendOutput:data];
			stdoutEmpty_ = NO;
		} else if ([notificationObject isEqualTo:stderrHandle_]) {
			[self appendError:data];
			stderrEmpty_ = NO;
		} else {
			// this should really not happen ...
		}
		
		// we need to schedule the file handle go read more data in the background again.
		[notificationObject readInBackgroundAndNotify];
	} else {
		if ([notificationObject isEqualTo:stdoutHandle_]) {
			stdoutEmpty_ = YES;
		} else if ([notificationObject isEqualTo:stderrHandle_]) {
			stderrEmpty_ = YES;
		} else {
			// this should really not happen ...
		}
		// if there is no more data in the pipe AND the task did terminate, we are done
		if (stdoutEmpty_ && stderrEmpty_ && taskDidTerminate_) {
			[self cleanup];
		}
	}
	
	// we need to schedule the file handle go read more data in the background again.
	//[notificationObject readInBackgroundAndNotify];  
}

- (void)taskStopped:(NSNotification *)notification
{
	if (!taskDidTerminate_) {
		taskDidTerminate_ = YES;
		// did we receive all data?
		if (stdoutEmpty_ && stderrEmpty_) {
			// no data left - do the clean up
			[self cleanup];
		}
	}
}

- (void)appendOutput:(NSData *)data
{
	NSString *outputString = [[[NSString alloc] initWithData:data encoding:outputStringEncoding_] autorelease];
	if (outputString) {
		[controller_ appendOutput:outputString];
	} else {
		NSLog(@"SCTaskWrapper - not able to encode output. Specified encoding: %i", outputStringEncoding_);
	}
}

- (void)appendError:(NSData *)data
{
	NSString *errorString = [[[NSString alloc] initWithData:data encoding:outputStringEncoding_] autorelease];
	if (errorString) {
		[controller_ appendError:errorString];
	} else {
		NSLog(@"SCTaskWrapper - not able to encode output. Specified encoding: %i", outputStringEncoding_);
	}
}

- (NSFileHandle *)stdoutHandle 
{
    return [[stdoutHandle_ retain] autorelease];
}

- (void)setStdoutHandle:(NSFileHandle *)handle 
{
    if (stdoutHandle_ != handle) {
        [stdoutHandle_ release];
        stdoutHandle_ = [handle copy];
    }
}

- (NSFileHandle *)stderrHandle 
{
    return [[stderrHandle_ retain] autorelease];
}

- (void)setStderrHandle:(NSFileHandle *)handle 
{
    if (stderrHandle_ != handle) {
        [stderrHandle_ release];
        stderrHandle_ = [handle copy];
    }
}

@end

