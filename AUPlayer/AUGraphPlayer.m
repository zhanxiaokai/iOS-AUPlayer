//
//  AUGraphPlayer.m
//  AUPlayer
//
//  Created by apple on 2017/2/9.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import "AUGraphPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "ELAudioSession.h"

@implementation AUGraphPlayer
{
    AUGraph                                     mPlayerGraph;
    AUNode                                      mPlayerNode;
    AUNode                                      mSplitterNode;
    AudioUnit                                   mSplitterUnit;
    AUNode                                      mAccMixerNode;
    AudioUnit                                   mAccMixerUnit;
    AUNode                                      mVocalMixerNode;
    AudioUnit                                   mVocalMixerUnit;
    AudioUnit                                   mPlayerUnit;
    AUNode                                      mPlayerIONode;
    AudioUnit                                   mPlayerIOUnit;
    NSURL*                                      _playPath;
}

- (id) initWithFilePath:(NSString*) path
{
    self = [super init];
    if(self) {
        [[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord];
        [[ELAudioSession sharedInstance] setPreferredSampleRate:44100];
        [[ELAudioSession sharedInstance] setActive:YES];
        [[ELAudioSession sharedInstance] addRouteChangeListener];
        [self addAudioSessionInterruptedObserver];
        _playPath = [NSURL URLWithString:path];
        [self initializePlayGraph];
    }
    return self;
}


- (BOOL)play
{
    OSStatus status = AUGraphStart(mPlayerGraph);
    CheckStatus(status, @"Could not start AUGraph", YES);
    
    return YES;
}

- (void)stop
{
    
    Boolean isRunning = false;
    OSStatus status = AUGraphIsRunning(mPlayerGraph, &isRunning);
    if (isRunning)
    {
        status = AUGraphStop(mPlayerGraph);
        CheckStatus(status, @"Could not stop AUGraph", YES);
    }
}

- (void) initializePlayGraph;
{
    OSStatus status = noErr;
    //1:构造AUGraph
    status = NewAUGraph(&mPlayerGraph);
    CheckStatus(status, @"Could not create a new AUGraph", YES);
    //2-1:添加IONode
    AudioComponentDescription ioDescription;
    bzero(&ioDescription, sizeof(ioDescription));
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    status = AUGraphAddNode(mPlayerGraph, &ioDescription, &mPlayerIONode);
    CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
    //2-2:添加PlayerNode
    AudioComponentDescription playerDescription;
    bzero(&playerDescription, sizeof(playerDescription));
    playerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    playerDescription.componentType = kAudioUnitType_Generator;
    playerDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer;
    status = AUGraphAddNode(mPlayerGraph, &playerDescription, &mPlayerNode);
    CheckStatus(status, @"Could not add Player node to AUGraph", YES);
    //2-3:添加Splitter
    AudioComponentDescription splitterDescription;
    bzero(&splitterDescription, sizeof(splitterDescription));
    splitterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    splitterDescription.componentType = kAudioUnitType_FormatConverter;
    splitterDescription.componentSubType = kAudioUnitSubType_Splitter;
    status = AUGraphAddNode(mPlayerGraph, &splitterDescription, &mSplitterNode);
    CheckStatus(status, @"Could not add Splitter node to AUGraph", YES);
    //2-4:添加两个Mixer
    AudioComponentDescription mixerDescription;
    bzero(&mixerDescription, sizeof(mixerDescription));
    mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    mixerDescription.componentType = kAudioUnitType_Mixer;
    mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    status = AUGraphAddNode(mPlayerGraph, &mixerDescription, &mVocalMixerNode);
    CheckStatus(status, @"Could not add VocalMixer node to AUGraph", YES);
    status = AUGraphAddNode(mPlayerGraph, &mixerDescription, &mAccMixerNode);
    CheckStatus(status, @"Could not add AccMixer node to AUGraph", YES);
    
    //3:打开Graph, 只有真正的打开了Graph才会实例化每一个Node
    status = AUGraphOpen(mPlayerGraph);
    CheckStatus(status, @"Could not open AUGraph", YES);
    //4-1:获取出IONode的AudioUnit
    status = AUGraphNodeInfo(mPlayerGraph, mPlayerIONode, NULL, &mPlayerIOUnit);
    CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
    //4-2:获取出PlayerNode的AudioUnit
    status = AUGraphNodeInfo(mPlayerGraph, mPlayerNode, NULL, &mPlayerUnit);
    CheckStatus(status, @"Could not retrieve node info for Player node", YES);
    //4-3:获取出PlayerNode的AudioUnit
    status = AUGraphNodeInfo(mPlayerGraph, mSplitterNode, NULL, &mSplitterUnit);
    CheckStatus(status, @"Could not retrieve node info for Splitter node", YES);
    //4-4:获取出VocalMixer的AudioUnit
    status = AUGraphNodeInfo(mPlayerGraph, mVocalMixerNode, NULL, &mVocalMixerUnit);
    CheckStatus(status, @"Could not retrieve node info for VocalMixer node", YES);
    //4-5:获取出AccMixer的AudioUnit
    status = AUGraphNodeInfo(mPlayerGraph, mAccMixerNode, NULL, &mAccMixerUnit);
    CheckStatus(status, @"Could not retrieve node info for AccMixer node", YES);
    
    //5:给AudioUnit设置参数
    AudioStreamBasicDescription stereoStreamFormat;
    UInt32 bytesPerSample = sizeof(Float32);
    bzero(&stereoStreamFormat, sizeof(stereoStreamFormat));
    stereoStreamFormat.mFormatID          = kAudioFormatLinearPCM;
    stereoStreamFormat.mFormatFlags       = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    stereoStreamFormat.mBytesPerPacket    = bytesPerSample;
    stereoStreamFormat.mFramesPerPacket   = 1;
    stereoStreamFormat.mBytesPerFrame     = bytesPerSample;
    stereoStreamFormat.mChannelsPerFrame  = 2;                    // 2 indicates stereo
    stereoStreamFormat.mBitsPerChannel    = 8 * bytesPerSample;
    stereoStreamFormat.mSampleRate        = 48000.0;
    status = AudioUnitSetProperty(mPlayerIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"set remote IO output element stream format ", YES);
    status = AudioUnitSetProperty(
                                  mPlayerUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &stereoStreamFormat,
                                  sizeof (stereoStreamFormat)
                                  );
    CheckStatus(status, @"Could not Set StreamFormat for Player Unit", YES);
    
    //5-2配置Splitter的属性
    status = AudioUnitSetProperty(mSplitterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for Splitter Unit", YES);
    status = AudioUnitSetProperty(mSplitterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for Splitter Unit", YES);
    //5-3 配置VocalMixerUnit的属性
    status = AudioUnitSetProperty(mVocalMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for VocalMixer Unit", YES);
    status = AudioUnitSetProperty(mVocalMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for VocalMixer Unit", YES);
    int mixerElementCount = 1;
    status = AudioUnitSetProperty(mVocalMixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
                                  &mixerElementCount, sizeof(mixerElementCount));
    //5-4 配置AccMixerUnit的属性
    status = AudioUnitSetProperty(mAccMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for AccMixer Unit", YES);
    status = AudioUnitSetProperty(mAccMixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                  0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not Set StreamFormat for AccMixer Unit", YES);
    mixerElementCount = 2;
    status = AudioUnitSetProperty(mAccMixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
                                  &mixerElementCount, sizeof(mixerElementCount));
    
    [self setInputSource:NO];
    //6:连接起Node来
    AUGraphConnectNodeInput(mPlayerGraph, mPlayerNode, 0, mSplitterNode, 0);
    CheckStatus(status, @"Player Node Connect To IONode", YES);
    AUGraphConnectNodeInput(mPlayerGraph, mSplitterNode, 0, mVocalMixerNode, 0);
    CheckStatus(status, @"Player Node Connect To IONode", YES);
    AUGraphConnectNodeInput(mPlayerGraph, mSplitterNode, 1, mAccMixerNode, 0);
    CheckStatus(status, @"Player Node Connect To IONode", YES);
    AUGraphConnectNodeInput(mPlayerGraph, mVocalMixerNode, 0, mAccMixerNode, 1);
    CheckStatus(status, @"Player Node Connect To IONode", YES);
    AUGraphConnectNodeInput(mPlayerGraph, mAccMixerNode, 0, mPlayerIONode, 0);
    CheckStatus(status, @"Player Node Connect To IONode", YES);
    //7:初始化Graph
    status = AUGraphInitialize(mPlayerGraph);
    CheckStatus(status, @"Couldn't Initialize the graph", YES);
    //8:显示Graph结构
    CAShow(mPlayerGraph);
    //9:只有对Graph进行Initialize之后才可以设置AudioPlayer的参数
    [self setUpFilePlayer];
}

- (void) setInputSource:(BOOL) isAcc
{
    OSStatus status;
    AudioUnitParameterValue value;
    status = AudioUnitGetParameter(mVocalMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, &value);
    CheckStatus(status, @"get parameter fail", YES);
    NSLog(@"Vocal Mixer %lf", value);
    status = AudioUnitGetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, &value);
    CheckStatus(status, @"get parameter fail", YES);
    NSLog(@"Acc Mixer 0 %lf", value);
    status = AudioUnitGetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, &value);
    CheckStatus(status, @"get parameter fail", YES);
    NSLog(@"Acc Mixer 1 %lf", value);
    
//    status = AudioUnitSetParameter(mVocalMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, 1.0, 0);
//    CheckStatus(status, @"set parameter fail", YES);
    if(isAcc) {
        status = AudioUnitSetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, 0.1, 0);
        CheckStatus(status, @"set parameter fail", YES);
        status = AudioUnitSetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, 1, 0);
        CheckStatus(status, @"set parameter fail", YES);
    } else {
        status = AudioUnitSetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, 1, 0);
        CheckStatus(status, @"set parameter fail", YES);
        status = AudioUnitSetParameter(mAccMixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 1, 0.1, 0);
        CheckStatus(status, @"set parameter fail", YES);
    }
}

- (void) setUpFilePlayer;
{
    OSStatus status = noErr;
    AudioFileID musicFile;
    CFURLRef songURL = (__bridge  CFURLRef) _playPath;
    // open the input audio file
    status = AudioFileOpenURL(songURL, kAudioFileReadPermission, 0, &musicFile);
    CheckStatus(status, @"Open AudioFile... ", YES);
    
    
    // tell the file player unit to load the file we want to play
    status = AudioUnitSetProperty(mPlayerUnit, kAudioUnitProperty_ScheduledFileIDs,
                                  kAudioUnitScope_Global, 0, &musicFile, sizeof(musicFile));
    CheckStatus(status, @"Tell AudioFile Player Unit Load Which File... ", YES);
    
    
    
    AudioStreamBasicDescription fileASBD;
    // get the audio data format from the file
    UInt32 propSize = sizeof(fileASBD);
    status = AudioFileGetProperty(musicFile, kAudioFilePropertyDataFormat,
                                  &propSize, &fileASBD);
    CheckStatus(status, @"get the audio data format from the file... ", YES);
    UInt64 nPackets;
    UInt32 propsize = sizeof(nPackets);
    AudioFileGetProperty(musicFile, kAudioFilePropertyAudioDataPacketCount,
                         &propsize, &nPackets);
    // tell the file player AU to play the entire file
    ScheduledAudioFileRegion rgn;
    memset (&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
    rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    rgn.mTimeStamp.mSampleTime = 0;
    rgn.mCompletionProc = NULL;
    rgn.mCompletionProcUserData = NULL;
    rgn.mAudioFile = musicFile;
    rgn.mLoopCount = 0;
    rgn.mStartFrame = 0;
    rgn.mFramesToPlay = (UInt32)nPackets * fileASBD.mFramesPerPacket;
    status = AudioUnitSetProperty(mPlayerUnit, kAudioUnitProperty_ScheduledFileRegion,
                                  kAudioUnitScope_Global, 0,&rgn, sizeof(rgn));
    CheckStatus(status, @"Set Region... ", YES);
    
    
    // prime the file player AU with default values
    UInt32 defaultVal = 0;
    status = AudioUnitSetProperty(mPlayerUnit, kAudioUnitProperty_ScheduledFilePrime,
                                  kAudioUnitScope_Global, 0, &defaultVal, sizeof(defaultVal));
    CheckStatus(status, @"Prime Player Unit With Default Value... ", YES);
    
    
    // tell the file player AU when to start playing (-1 sample time means next render cycle)
    AudioTimeStamp startTime;
    memset (&startTime, 0, sizeof(startTime));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    status = AudioUnitSetProperty(mPlayerUnit, kAudioUnitProperty_ScheduleStartTimeStamp,
                                  kAudioUnitScope_Global, 0, &startTime, sizeof(startTime));
    CheckStatus(status, @"set Player Unit Start Time... ", YES);
}

// AudioSession 被打断的通知
- (void)addAudioSessionInterruptedObserver
{
    [self removeAudioSessionInterruptedObserver];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNotificationAudioInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
}

- (void)removeAudioSessionInterruptedObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
}

- (void)onNotificationAudioInterrupted:(NSNotification *)sender {
    AVAudioSessionInterruptionType interruptionType = [[[sender userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    switch (interruptionType) {
        case AVAudioSessionInterruptionTypeBegan:
            [self stop];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            [self play];
            break;
        default:
            break;
    }
}

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
    if(status != noErr)
    {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
            NSLog(@"%@: %s", message, fourCC);
        else
            NSLog(@"%@: %d", message, (int)status);
        
        if(fatal)
            exit(-1);
    }
}

@end
