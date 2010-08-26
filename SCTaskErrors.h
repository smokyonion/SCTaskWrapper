//
//  SCTaskError.h
//  SCTaskWrapper
//
//  Created by vincent on 8/26/10.
//  Copyright 2010 Ortery Technologies, Inc. All rights reserved.
//


typedef enum SCTaskErrors
{
	kSCTaskErrorNone						= 0xF0000,
	kSCTaskErrorFailedToCreatePipeForStdin	= 0xF0001,
	kSCTaskErrorFailedToCreatePipeForStdout = 0xF0002,
	kSCTaskErrorFailedToCreatePipeForStderr = 0xF0003,
} SCTaskErrors;