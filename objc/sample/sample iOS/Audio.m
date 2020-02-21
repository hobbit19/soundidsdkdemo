#import <AVFoundation/AVFoundation.h>
#import "Audio.h"

static OSStatus outputCallback(void* inRefCon,
                               AudioUnitRenderActionFlags* ioActionFlags,
                               const AudioTimeStamp* inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList* __nullable ioData)
{
    Audio* audio = (__bridge Audio*)inRefCon;
    [audio getSamples:ioData];

    return noErr;
}

@interface RouteChangeDelegate: NSObject

@end

@implementation RouteChangeDelegate
{
    Audio* audio;
}

- (id)initWithAudio:(Audio*)initAudio
{
    if (self = [super init])
        audio = initAudio;

    return self;
}

- (void)handleRouteChanged:(NSNotification*)notification
{
    switch ([[[notification userInfo] objectForKey:AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue])
    {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            // TODO: implement
            break;

        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // TODO: implement
            break;
    }
}

@end

@implementation Audio
{
    AudioComponent audioComponent;
    AudioUnit audioUnit;
    RouteChangeDelegate* routeChangeDelegate;
    UInt32 channels;
    void (^callback)(void*, UInt32);
}

- (id)initWithSampleRate:(Float64)sampleRate
             andChannels:(UInt32)initChannels
             andCallback:(void (^)(void*, UInt32))initCallback
{
    if (self = [super init])
    {
        channels = initChannels;
        callback = initCallback;

        OSStatus result;

        AVAudioSession* audioSession = [AVAudioSession sharedInstance];
        if (![audioSession setCategory:AVAudioSessionCategoryAmbient error:nil])
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set audio session category" userInfo:nil];

        routeChangeDelegate = [[RouteChangeDelegate alloc] initWithAudio:self];

        [[NSNotificationCenter defaultCenter] addObserver:routeChangeDelegate
                                                 selector:@selector(handleRouteChanged:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:nil];

        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_RemoteIO;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;

        audioComponent = AudioComponentFindNext(NULL, &desc);

        if (!audioComponent)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to find requested CoreAudio component" userInfo:nil];

        if ((result = AudioComponentInstanceNew(audioComponent, &audioUnit)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to create CoreAudio component instance" userInfo:nil];

        const AudioUnitElement bus = 0;

        AudioStreamBasicDescription streamDescription;
        streamDescription.mSampleRate = sampleRate;
        streamDescription.mFormatID = kAudioFormatLinearPCM;
        streamDescription.mFormatFlags = kLinearPCMFormatFlagIsFloat;
        streamDescription.mChannelsPerFrame = channels;
        streamDescription.mFramesPerPacket = 1;
        streamDescription.mBitsPerChannel = sizeof(float) * 8;
        streamDescription.mBytesPerFrame = streamDescription.mBitsPerChannel * streamDescription.mChannelsPerFrame / 8;
        streamDescription.mBytesPerPacket = streamDescription.mBytesPerFrame * streamDescription.mFramesPerPacket;
        streamDescription.mReserved = 0;

        if ((result = AudioUnitSetProperty(audioUnit,
                                           kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Input, bus, &streamDescription, sizeof(streamDescription))) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set CoreAudio unit stream format to float" userInfo:nil];

        AURenderCallbackStruct callback;
        callback.inputProc = outputCallback;
        callback.inputProcRefCon = (__bridge void*)self;
        if ((result = AudioUnitSetProperty(audioUnit,
                                           kAudioUnitProperty_SetRenderCallback,
                                           kAudioUnitScope_Input, bus, &callback, sizeof(callback))) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set CoreAudio unit output callback" userInfo:nil];

        if ((result = AudioUnitInitialize(audioUnit)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to initialize CoreAudio unit" userInfo:nil];
    }

    return self;
}

- (void)start
{
    OSStatus result;
    if ((result = AudioOutputUnitStart(audioUnit)) != noErr)
        @throw [NSException exceptionWithName:@"" reason:@"Failed to start CoreAudio output unit" userInfo:nil];
}

- (void)stop
{
    OSStatus result;
    if ((result = AudioOutputUnitStop(audioUnit)) != noErr)
        @throw [NSException exceptionWithName:@"" reason:@"Failed to stop CoreAudio output unit" userInfo:nil];
}

- (void)getSamples:(AudioBufferList*)ioData
{
    for (UInt32 i = 0; i < ioData->mNumberBuffers; ++i)
    {
        AudioBuffer* buffer = &ioData->mBuffers[i];
        callback(buffer->mData, buffer->mDataByteSize / (sizeof(float) * channels));
    }
}

@end
