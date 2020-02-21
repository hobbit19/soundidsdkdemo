#import "ViewController.h"
#import "Audio.h"
#import "Sonarworks/SWProcessor.h"

@implementation ViewController
{
    Audio* audio;
    SWProcessor* processor;
    NSData* data;
    long totalFrames;
    long offset;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString* path = [[NSBundle mainBundle] pathForResource:@"Tropical House - Yuriy Bespalov" ofType:@"raw"];
    data = [NSData dataWithContentsOfFile:path];

    totalFrames = [data length] / (sizeof(float) * 2);

    audio = [[Audio alloc] initWithSampleRate:44100 andChannels:2 andCallback:^(void* samples, UInt32 frames) {
        UInt32 remaining = frames;
        const float* data = (const float*)[self->data bytes];

        while (remaining)
        {
            if (remaining > self->totalFrames - self->offset)
            {
                memcpy(samples, data + self->offset,
                       (self->totalFrames - self->offset) * sizeof(float) * 2);
                remaining -= self->totalFrames - self->offset;
                self->offset = 0;
            }
            else
            {
                memcpy(samples, data + self->offset,
                       remaining * sizeof(float) * 2);
                self->offset += remaining * 2;
                remaining = 0;
            }
        }
    }];

    processor = [[SWProcessor alloc] initWithSampleRate:44100 andSampleFormat:SWFloatingPoint andSampleSize:4 andChannelCount:2];

    NSString* profilePath = [[NSBundle mainBundle] pathForResource:@"profile"
                                                            ofType:@"eqb"];
    NSData* profile = [NSData dataWithContentsOfFile:profilePath];

    [processor setProfile:profile];
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

-(IBAction)handlePlay:(id)sender
{
    [audio start];
}

-(IBAction)handlePause:(id)sender
{
    [audio stop];
}

-(IBAction)handleBypassChange:(id)sender
{
    [processor setBypass:_bypassSwitch.state == NSControlStateValueOn];
}

@end
