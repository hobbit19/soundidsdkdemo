#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>

@interface Audio : NSObject

- (id)initWithSampleRate:(Float64)sampleRate
             andChannels:(UInt32)channels
             andCallback:(void (^)(void*, UInt32))initCallback;

- (void)start;
- (void)stop;
- (void)getSamples:(AudioBufferList*)ioData;

@end
