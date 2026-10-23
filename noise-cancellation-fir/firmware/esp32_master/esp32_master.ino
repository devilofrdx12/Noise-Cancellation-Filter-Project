#include "config.h"
#include "i2s_audio.h"
#include "lms_filter.h"
#include "telemetry_udp.h"

// This runs on an ESP32 with an INMP441 mic.
// It captures audio, applies LMS adaptive noise cancellation,
// and streams the cleaned audio over WiFi UDP to the laptop.
// The laptop plays it through its own 3.5mm headphone jack.

void setup() {
    Serial.begin(115200);

    // Force maximum CPU frequency (240 MHz) for minimum algorithm latency
    setCpuFrequencyMhz(240);

    i2sAudioInit();
    lmsInit();
    telemetryInit();

    Serial.println("Noise cancellation running. Streaming to laptop...");
}

void loop() {
    // Read one sample from INMP441 mic
    float raw = i2sReadSample();

    // Run ALE/LMS adaptive noise cancellation
    float clean = lmsProcess(raw);

    // Stream cleaned audio to laptop for playback (full rate, chunked UDP)
    audioStreamSend(clean);

    // Send raw+filtered pair to MATLAB for live visualization (downsampled)
    telemetrySend(raw, clean);
}
