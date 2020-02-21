#import <CoreAudio/CoreAudio.h>
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

static OSStatus deviceListChanged(AudioObjectID inObjectID,
                                  UInt32 inNumberAddresses,
                                  const AudioObjectPropertyAddress* inAddresses,
                                  void* __nullable inClientData)
{
    // TODO: implement
    return 0;
}

static OSStatus deviceUnplugged(AudioObjectID inObjectID,
                                UInt32 inNumberAddresses,
                                const AudioObjectPropertyAddress* inAddresses,
                                void* __nullable inClientData)
{
    // TODO: implement
    return noErr;
}

@implementation Audio
{
    AudioDeviceID deviceId;
    AudioComponent audioComponent;
    AudioUnit audioUnit;
    UInt32 channels;
    void (^callback)(void*, UInt32);
}

- (id)initWithSampleRate:(Float64)sampleRate
             andChannels:(UInt32)initCannels
             andCallback:(void (^)(void*, UInt32))initCallback
{
    if (self = [super init])
    {
        channels = initCannels;
        callback = initCallback;

        OSStatus result;

        const AudioObjectPropertyAddress deviceListAddress = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMaster
        };

        if ((result = AudioObjectAddPropertyListener(kAudioObjectSystemObject,
                                                     &deviceListAddress,
                                                     deviceListChanged,
                                                     (__bridge_retained void*)self)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to add CoreAudio property listener" userInfo:nil];

        const AudioObjectPropertyAddress defaultDeviceAddress = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMaster
        };

        UInt32 size = sizeof(AudioDeviceID);
        if ((result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &defaultDeviceAddress,
                                                 0, NULL, &size, &deviceId)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to get CoreAudio output device" userInfo:nil];

        const AudioObjectPropertyAddress aliveAddress = {
            kAudioDevicePropertyDeviceIsAlive,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMaster
        };

        UInt32 alive = 0;
        size = sizeof(alive);
        if ((result = AudioObjectGetPropertyData(deviceId, &aliveAddress, 0, NULL, &size, &alive)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to get CoreAudio device status" userInfo:nil];

        if (!alive)
            @throw [NSException exceptionWithName:@"" reason:@"Requested CoreAudio device is not alive" userInfo:nil];

        const AudioObjectPropertyAddress hogModeAddress = {
            kAudioDevicePropertyHogMode,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMaster
        };

        pid_t pid = 0;
        size = sizeof(pid);
        if ((result = AudioObjectGetPropertyData(deviceId, &hogModeAddress, 0, NULL, &size, &pid)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to check if CoreAudio device is in hog mode" userInfo:nil];

        if (pid != -1)
            @throw [NSException exceptionWithName:@"" reason:@"Requested CoreAudio device is being hogged" userInfo:nil];

        const AudioObjectPropertyAddress nameAddress = {
            kAudioObjectPropertyName,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMaster
        };

        CFStringRef tempStringRef = NULL;
        size = sizeof(CFStringRef);

        if ((result = AudioObjectGetPropertyData(deviceId, &nameAddress,
                                                 0, NULL, &size, &tempStringRef)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to get CoreAudio device name" userInfo:nil];

        NSLog(@"Using %@ for audio", tempStringRef);

        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_DefaultOutput;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;

        audioComponent = AudioComponentFindNext(NULL, &desc);

        if (!audioComponent)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to find requested CoreAudio component" userInfo:nil];

        if ((result = AudioObjectAddPropertyListener(deviceId, &aliveAddress, deviceUnplugged,
                                                     (__bridge_retained void*)self)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to add CoreAudio property listener" userInfo:nil];

        if ((result = AudioComponentInstanceNew(audioComponent, &audioUnit)) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to create CoreAudio component instance" userInfo:nil];

        if ((result = AudioUnitSetProperty(audioUnit,
                                           kAudioOutputUnitProperty_CurrentDevice,
                                           kAudioUnitScope_Global, 0,
                                           &deviceId,
                                           sizeof(AudioDeviceID))) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set CoreAudio unit property" userInfo:nil];

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
        callback.inputProcRefCon = (__bridge_retained void*)self;
        if ((result = AudioUnitSetProperty(audioUnit,
                                           kAudioUnitProperty_SetRenderCallback,
                                           kAudioUnitScope_Input, bus, &callback, sizeof(callback))) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set CoreAudio unit output callback" userInfo:nil];

        const UInt32 inIOBufferFrameSize = 512;
        if ((result = AudioUnitSetProperty(audioUnit,
                                           kAudioDevicePropertyBufferFrameSize,
                                           kAudioUnitScope_Global,
                                           0,
                                           &inIOBufferFrameSize, sizeof(UInt32))) != noErr)
            @throw [NSException exceptionWithName:@"" reason:@"Failed to set CoreAudio buffer size" userInfo:nil];

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
