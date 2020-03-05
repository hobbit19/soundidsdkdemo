package com.sonarworks.sample;

import android.app.Activity;
import android.content.res.AssetFileDescriptor;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.Switch;

import com.sonarworks.Processor;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class MainActivity extends Activity {
    private static final String TAG = "sample";

    private static final int sizeOfFloat = 4;
    private static final int sampleRate = 44100;
    private static final int channels = 2;
    private static final int bufferSize = 65536 * sizeOfFloat;
    private static final int bufferSizePerChannel = bufferSize / channels;
    private static final int bufferSizeFrames = bufferSizePerChannel / sizeOfFloat;
    private static final int blockSize = 256;
    private static final int blockSizePerChannel = blockSize / channels;
    private static final int blockSizeFrames = blockSizePerChannel / sizeOfFloat;

    private Button playButton;
    private Button pauseButton;
    private Switch enableSwitch;

    private AudioTrack audioTrack = new AudioTrack(AudioManager.STREAM_MUSIC,
            sampleRate,
            AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_FLOAT,
            bufferSize,
            AudioTrack.MODE_STREAM);

    private Processor processor = new Processor(sampleRate, AudioFormat.ENCODING_PCM_FLOAT, 2, blockSize);

    private MediaExtractor extractor = new MediaExtractor();
    private MediaCodec decoder;
    private MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();

    private ByteBuffer audioDataByteBuffer;
    private byte[] audioBytes = new byte[blockSize];
    private ByteBuffer audioByteBuffer = ByteBuffer.allocate(blockSize);

    private ByteBuffer getAudioData()
    {
        audioByteBuffer.clear();

        int remaining = blockSize;

        while (remaining > 0) {
            if (audioDataByteBuffer != null &&
                    audioDataByteBuffer.remaining() >= remaining) {

                audioDataByteBuffer.get(audioBytes, 0, remaining);
                audioByteBuffer.put(audioBytes, 0, remaining);
                remaining = 0;
            } else {
                if (audioDataByteBuffer != null &&
                        audioDataByteBuffer.remaining() > 0) {
                    int size = audioDataByteBuffer.remaining();
                    audioDataByteBuffer.get(audioBytes, 0, size);
                    audioByteBuffer.put(audioBytes, 0, size);
                    remaining -= size;
                }

                int inputBufferIndex = decoder.dequeueInputBuffer(10000);
                if (inputBufferIndex >= 0) {
                    ByteBuffer inputBuffer = decoder.getInputBuffer(inputBufferIndex);
                    int sampleSize = extractor.readSampleData(inputBuffer, 0);
                    if (sampleSize < 0) {
                        Log.d("DecodeActivity", "InputBuffer BUFFER_FLAG_END_OF_STREAM");
                        decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                    } else {
                        decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.getSampleTime(), 0);
                        extractor.advance();
                    }
                }

                int outputBufferIndex = decoder.dequeueOutputBuffer(info, 10000);

                if (outputBufferIndex >= 0)
                {
                    ByteBuffer outputBuffer = decoder.getOutputBuffer(outputBufferIndex);

                    if (audioDataByteBuffer == null ||
                            audioDataByteBuffer.capacity() < outputBuffer.limit() * 2)
                    {
                        audioDataByteBuffer = ByteBuffer.allocateDirect(outputBuffer.limit() * 2);
                        audioDataByteBuffer.order(ByteOrder.nativeOrder());
                    }

                    audioDataByteBuffer.clear();

                    while (outputBuffer.remaining() >= 2)
                        audioDataByteBuffer.putFloat(outputBuffer.getShort() / 32768.0f);

                    audioDataByteBuffer.flip();

                    outputBuffer.clear();
                    decoder.releaseOutputBuffer(outputBufferIndex, false);
                }
                else switch (outputBufferIndex)
                {
                    case MediaCodec.INFO_OUTPUT_FORMAT_CHANGED:
                        Log.d("DecodeActivity", "New format " + decoder.getOutputFormat());
                        break;
                    case MediaCodec.INFO_TRY_AGAIN_LATER:
                        Log.d("DecodeActivity", "dequeueOutputBuffer timed out!");
                        break;
                }

                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    Log.d("DecodeActivity", "OutputBuffer BUFFER_FLAG_END_OF_STREAM");

                    extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
                    decoder.flush();
                }
            }
        }

        audioByteBuffer.flip();

        processor.process(audioByteBuffer);

        return audioByteBuffer;
    }
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        try {
            InputStream stream = getAssets().open("profile.eqb");
            byte[] array = new byte[stream.available()];
            stream.read(array);
            processor.setProfile(ByteBuffer.wrap(array));

            Log.v(TAG, "Profile set");
        }
        catch (IOException exception)
        {
            Log.v(TAG, exception.getMessage());
        }

        try {
            AssetFileDescriptor fd = getAssets().openFd("Tropical House - Yuriy Bespalov.mp3");
            extractor.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());

            if (extractor.getTrackCount() == 1) {
                MediaFormat format = extractor.getTrackFormat(0);

                String mime = format.getString(MediaFormat.KEY_MIME);

                if (mime.startsWith("audio/")) {
                    extractor.selectTrack(0);

                    MediaFormat targetFormat = new MediaFormat();
                    targetFormat.setInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate);
                    targetFormat.setString(MediaFormat.KEY_MIME, mime);
                    targetFormat.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
                    targetFormat.setInteger(MediaFormat.KEY_CHANNEL_COUNT, 2);

                    decoder = MediaCodec.createDecoderByType(mime);
                    decoder.configure(targetFormat, null, null, 0);

                    decoder.start();
                }
            }

            Log.v(TAG, "Audio loaded");
        }
        catch (IOException exception)
        {
            Log.e(TAG, "Failed to load music");
            Log.e(TAG, exception.getMessage());
        }

        audioTrack.setPlaybackPositionUpdateListener(new AudioTrack.OnPlaybackPositionUpdateListener() {
            @Override
            public void onMarkerReached(AudioTrack audioTrack) {

            }

            @Override
            public void onPeriodicNotification(AudioTrack audioTrack) {
                int remainingFrames = bufferSizeFrames / 2;
                while (remainingFrames > 0) {
                    audioTrack.write(getAudioData(), blockSize, AudioTrack.WRITE_NON_BLOCKING);
                    remainingFrames -= blockSizeFrames;
                }
            }
        });

        audioTrack.setPositionNotificationPeriod(bufferSizeFrames / 2);

        playButton = findViewById(R.id.playButton);
        pauseButton = findViewById(R.id.pauseButton);
        enableSwitch = findViewById(R.id.enableSwitch);

        playButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                int remainingFrames = bufferSizeFrames;
                while (remainingFrames > 0) {
                    audioTrack.write(getAudioData(), blockSize, AudioTrack.WRITE_NON_BLOCKING);
                    remainingFrames -= blockSizeFrames;
                }

                audioTrack.play();
                Log.v(TAG, "play");
            }
        });

        pauseButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                audioTrack.pause();
                Log.v(TAG, "pause");
            }
        });

        enableSwitch.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton compoundButton, boolean b) {
                processor.setBypass(!b);
                Log.v(TAG, "toggle " + b);
            }
        });

        int minBuffer = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_FLOAT);

        Log.v(TAG, "Min buffer " + minBuffer);
    }
}
