<#
    setup_noise_cancellation_project.ps1
    ------------------------------------
    Scaffolds the full "Real-Time Audio Noise Cancellation using FIR Filtering"
    project: ESP32 firmware (ALE/LMS active noise cancellation), MATLAB scripts,
    hardware notes and docs.

    Output: 3.5mm headphone jack via ESP32 DAC + RC filter.
    Components: ESP32, INMP441 mic, 1kΩ resistor, 0.1µF capacitor, 3.5mm jack.

    Run it from wherever you want the project folder created:
        powershell -ExecutionPolicy Bypass -File setup_noise_cancellation_project.ps1

    It only creates folders/files - it does NOT install any toolchain.
    You still need: Arduino IDE (+ ESP32 board package), MATLAB.
#>

$root = "noise-cancellation-fir"

$dirs = @(
    "$root\firmware\esp32_master",
    "$root\matlab",
    "$root\hardware",
    "$root\docs"
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Write-File {
    param([string]$Path, [string]$Content)
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Host "Created: $Path"
}

# ============================================================
# firmware/esp32_master/config.h
# ============================================================
Write-File "$root\firmware\esp32_master\config.h" @'
#pragma once

// ---------------- Audio config ----------------
#define SAMPLE_RATE          8000        // 8kHz is plenty for speech, keeps latency low
#define I2S_WS_PIN           25
#define I2S_SD_PIN           33
#define I2S_SCK_PIN          32
#define I2S_PORT             I2S_NUM_0

#define AUDIO_OUT_PIN        26          // DAC2 pin (GPIO26) -> 1kΩ + 0.1µF RC -> 3.5mm headphone jack

// ---------------- LMS adaptive filter config ----------------
#define FILTER_ORDER         32          // taps - start small, raise only if needed
#define LMS_MU               0.0008f     // step size - tune this in MATLAB offline sim first
#define REF_DELAY            5           // samples of decorrelation delay (Adaptive Line Enhancer)

// ---------------- Telemetry (MATLAB) config ----------------
#define WIFI_SSID             "YOUR_WIFI_SSID"
#define WIFI_PASS             "YOUR_WIFI_PASSWORD"
#define MATLAB_PC_IP          "192.168.1.100"   // set to your laptop's IP
#define UDP_TELEMETRY_PORT    5005
#define TELEMETRY_DOWNSAMPLE  4           // send every Nth sample pair to MATLAB
'@

# ============================================================
# firmware/esp32_master/i2s_audio.h
# ============================================================
Write-File "$root\firmware\esp32_master\i2s_audio.h" @'
#pragma once
#include <Arduino.h>

void i2sAudioInit();
float i2sReadSample();          // returns normalized -1.0 .. 1.0
void i2sWriteSample(float s);   // writes normalized -1.0 .. 1.0 to DAC -> headphone jack
'@

# ============================================================
# firmware/esp32_master/i2s_audio.cpp
# ============================================================
Write-File "$root\firmware\esp32_master\i2s_audio.cpp" @'
#include "i2s_audio.h"
#include "config.h"
#include <driver/i2s.h>
#include <driver/dac.h>

void i2sAudioInit() {
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
        .sample_rate = SAMPLE_RATE,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,   // INMP441 outputs 32-bit frames
        .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 2,         // ultra low latency (2 buffers)
        .dma_buf_len = 32,          // 32 samples per DMA interrupt
        .use_apll = false
    };

    i2s_pin_config_t pin_config = {
        .bck_io_num = I2S_SCK_PIN,
        .ws_io_num = I2S_WS_PIN,
        .data_out_num = I2S_PIN_NO_CHANGE,
        .data_in_num = I2S_SD_PIN
    };

    i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
    i2s_set_pin(I2S_PORT, &pin_config);

    // Output side: use the built-in DAC (GPIO26) -> 1kΩ + 0.1µF RC filter -> 3.5mm headphone jack.
    dac_output_enable(DAC_CHANNEL_2); // GPIO26
}

float i2sReadSample() {
    int32_t raw = 0;
    size_t bytesRead = 0;
    i2s_read(I2S_PORT, &raw, sizeof(raw), &bytesRead, portMAX_DELAY);

    // INMP441 gives 24-bit data left-justified in a 32-bit frame
    int32_t sample24 = raw >> 8;
    return (float)sample24 / 8388608.0f; // normalize to -1..1 (2^23)
}

void i2sWriteSample(float s) {
    // clamp
    if (s > 1.0f) s = 1.0f;
    if (s < -1.0f) s = -1.0f;
    uint8_t dacVal = (uint8_t)((s + 1.0f) * 127.5f); // map -1..1 -> 0..255
    dac_output_voltage(DAC_CHANNEL_2, dacVal);
}
'@

# ============================================================
# firmware/esp32_master/lms_filter.h
# ============================================================
Write-File "$root\firmware\esp32_master\lms_filter.h" @'
#pragma once

void lmsInit();
float lmsProcess(float x);   // feed one noisy sample in, get one cleaned sample out
'@

# ============================================================
# firmware/esp32_master/lms_filter.cpp
# ============================================================
Write-File "$root\firmware\esp32_master\lms_filter.cpp" @'
#include "lms_filter.h"
#include "config.h"
#include <string.h>

/*
  Adaptive Line Enhancer (ALE) structure - the right approach for a SINGLE mic.

  Why: with one mic you can't do destructive-interference ANC (that needs a
  reference mic + speaker). What you CAN do is exploit the fact that periodic /
  narrowband noise (hum, motor whine, fan noise) is predictable from a delayed
  copy of itself, while broadband speech is not (beyond a very short lag).

  So: predict the "predictable" (periodic) part from a delayed version of the
  input, subtract it from the current sample -> what's left is your enhanced
  speech with the periodic noise suppressed.
*/

static float weights[FILTER_ORDER];
static float delayLine[FILTER_ORDER];
static float inputHistory[256];
static int histIndex = 0;

void lmsInit() {
    memset(weights, 0, sizeof(weights));
    memset(delayLine, 0, sizeof(delayLine));
    memset(inputHistory, 0, sizeof(inputHistory));
    histIndex = 0;
}

float lmsProcess(float x) {
    // store input history so we can pull out a delayed reference sample
    inputHistory[histIndex] = x;
    int refIdx = (histIndex - REF_DELAY + 256) % 256;
    float ref = inputHistory[refIdx];

    // shift delay line, push new reference sample in
    for (int i = FILTER_ORDER - 1; i > 0; i--) {
        delayLine[i] = delayLine[i - 1];
    }
    delayLine[0] = ref;

    // predict the periodic/noise component from the delayed reference
    float y = 0.0f;
    for (int i = 0; i < FILTER_ORDER; i++) {
        y += weights[i] * delayLine[i];
    }

    // error = current sample minus predicted noise = your cleaned output
    float e = x - y;

    // LMS weight update (gradient descent on the squared error)
    for (int i = 0; i < FILTER_ORDER; i++) {
        weights[i] += LMS_MU * e * delayLine[i];
    }

    histIndex = (histIndex + 1) % 256;
    return e;
}
'@

# ============================================================
# firmware/esp32_master/telemetry_udp.h
# ============================================================
Write-File "$root\firmware\esp32_master\telemetry_udp.h" @'
#pragma once

void telemetryInit();
void telemetrySend(float raw, float filtered);
'@

# ============================================================
# firmware/esp32_master/telemetry_udp.cpp
# ============================================================
Write-File "$root\firmware\esp32_master\telemetry_udp.cpp" @'
#include "telemetry_udp.h"
#include "config.h"
#include <WiFi.h>
#include <WiFiUdp.h>

static WiFiUDP udp;
static int sampleCounter = 0;

void telemetryInit() {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 10000) {
        delay(200);
    }
    udp.begin(UDP_TELEMETRY_PORT);
}

void telemetrySend(float raw, float filtered) {
    // downsample so we don't flood the WiFi link / stall the audio core
    sampleCounter++;
    if (sampleCounter < TELEMETRY_DOWNSAMPLE) return;
    sampleCounter = 0;

    if (WiFi.status() != WL_CONNECTED) return;

    // simple 8-byte packet: [float raw][float filtered]
    uint8_t packet[8];
    memcpy(packet, &raw, 4);
    memcpy(packet + 4, &filtered, 4);

    udp.beginPacket(MATLAB_PC_IP, UDP_TELEMETRY_PORT);
    udp.write(packet, 8);
    udp.endPacket();
}
'@

# ============================================================
# firmware/esp32_master/esp32_master.ino
# ============================================================
Write-File "$root\firmware\esp32_master\esp32_master.ino" @'
#include "config.h"
#include "i2s_audio.h"
#include "lms_filter.h"
#include "telemetry_udp.h"

TaskHandle_t audioTaskHandle;

// Core 0: HIGH PRIORITY AUDIO DSP THREAD.
// This is strictly isolated from WiFi and background Arduino ticks.
void audioTask(void *pvParameters) {
    for (;;) {
        float raw = i2sReadSample();
        float clean = lmsProcess(raw);
        i2sWriteSample(clean);
        
        // Push telemetry to lock-free queue (doesn't block audio)
        telemetryQueue(raw, clean);
    }
}

void setup() {
    Serial.begin(115200);
    
    // Force maximum CPU frequency (240 MHz) for absolute minimum algorithm latency
    setCpuFrequencyMhz(240);

    i2sAudioInit();
    lmsInit();
    telemetryInit(); // also creates the FreeRTOS telemetry queue

    // Run DSP on Core 0 at MAXIMUM priority (configMAX_PRIORITIES - 1)
    // Core 0 is normally used for WiFi, but since we use a pure FreeRTOS task,
    // setting it to max priority guarantees audio pre-empts everything else.
    xTaskCreatePinnedToCore(
        audioTask, "audioTask", 8192, NULL, configMAX_PRIORITIES - 1, &audioTaskHandle, 0
    );
}

void loop() {
    // Core 1 (Default Arduino loop): LOW PRIORITY BACKGROUND TASKS
    telemetryTick(); // Dequeues and sends UDP packets over WiFi safely
    vTaskDelay(1);
}
'@

# ============================================================
# matlab/live_plot_main.m
# ============================================================
Write-File "$root\matlab\live_plot_main.m" @'
% live_plot_main.m
% Receives UDP telemetry (raw, filtered float pairs) from the ESP32 and
% plots them live: waveform overlay + a rolling FFT comparison.
%
% Requires R2019b+ for udpport(). Set your PC's IP into MATLAB_PC_IP in
% firmware/esp32_master/config.h to match.

clear; clc; close all;

PORT = 5005;
BUFFER_LEN = 500;      % samples shown on screen at once

u = udpport("datagram", "LocalPort", PORT);

rawBuf = zeros(1, BUFFER_LEN);
filtBuf = zeros(1, BUFFER_LEN);

fig = figure('Name', 'Real-Time Noise Cancellation Monitor');

subplot(2,1,1);
hRaw = animatedline('Color', [0.85 0.2 0.2]);
hFilt = animatedline('Color', [0.1 0.6 0.9]);
legend('Raw (noisy)', 'Filtered (clean)');
title('Live Waveform: Raw vs Filtered');
xlabel('Sample #'); ylabel('Amplitude');
axis([0 BUFFER_LEN -1 1]);

subplot(2,1,2);
hFFT = plot(nan, nan);
title('FFT: Noise Floor Before vs After (updates periodically)');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');

n = 0;
disp('Listening for ESP32 telemetry... start talking into the mic.');

while ishandle(fig)
    if u.NumDatagramsAvailable > 0
        d = read(u, 1, "uint8");
        bytes = d.Data;
        if numel(bytes) == 8
            raw = typecast(uint8(bytes(1:4)), 'single');
            filtered = typecast(uint8(bytes(5:8)), 'single');

            n = n + 1;
            idx = mod(n, BUFFER_LEN) + 1;
            rawBuf(idx) = raw;
            filtBuf(idx) = filtered;

            addpoints(hRaw, idx, raw);
            addpoints(hFilt, idx, filtered);

            if mod(n, 50) == 0
                drawnow limitrate;
            end
            if mod(n, 200) == 0
                updateFFT(rawBuf, filtBuf);
            end
        end
    end
end

function updateFFT(rawBuf, filtBuf)
    Fs = 8000;
    Nfft = 256;
    Fraw = abs(fft(rawBuf(1:min(Nfft,end)), Nfft));
    Ffilt = abs(fft(filtBuf(1:min(Nfft,end)), Nfft));
    f = (0:Nfft/2-1) * (Fs/Nfft);
    subplot(2,1,2);
    plot(f, 20*log10(Fraw(1:Nfft/2)+eps), 'r', ...
         f, 20*log10(Ffilt(1:Nfft/2)+eps), 'b');
    legend('Raw', 'Filtered');
    title('FFT: Noise Floor Before vs After');
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
end
'@

# ============================================================
# matlab/fft_spectrum_compare.m
# ============================================================
Write-File "$root\matlab\fft_spectrum_compare.m" @'
% fft_spectrum_compare.m
% Offline helper: load a recorded raw vs filtered WAV pair and compare
% their spectra. Useful for your report screenshots.

[rawSig, Fs] = audioread('raw_sample.wav');
[filtSig, ~] = audioread('filtered_sample.wav');

N = min(length(rawSig), length(filtSig));
rawSig = rawSig(1:N);
filtSig = filtSig(1:N);

Nfft = 2^nextpow2(N);
Fraw = abs(fft(rawSig, Nfft));
Ffilt = abs(fft(filtSig, Nfft));
f = (0:Nfft/2-1) * (Fs/Nfft);

figure;
subplot(2,1,1);
plot((1:N)/Fs, rawSig, 'r'); hold on;
plot((1:N)/Fs, filtSig, 'b');
legend('Raw', 'Filtered'); title('Time Domain'); xlabel('Time (s)');

subplot(2,1,2);
plot(f, 20*log10(Fraw(1:Nfft/2)+eps), 'r'); hold on;
plot(f, 20*log10(Ffilt(1:Nfft/2)+eps), 'b');
legend('Raw', 'Filtered'); title('Frequency Domain');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
'@

# ============================================================
# matlab/lms_offline_sim.m
# ============================================================
Write-File "$root\matlab\lms_offline_sim.m" @'
% lms_offline_sim.m
% Simulate the SAME Adaptive Line Enhancer algorithm the ESP32 runs,
% but in MATLAB on a recorded WAV file. Use this to tune FILTER_ORDER
% and LMS_MU BEFORE porting the numbers into config.h - much faster
% than iterating on hardware.

[x, Fs] = audioread('noisy_recording.wav');
x = x(:,1); % mono

order = 32;
mu = 0.0008;
refDelay = 5;

N = length(x);
w = zeros(order, 1);
delayLine = zeros(order, 1);
histBuf = zeros(256, 1);
histIdx = 1;
y = zeros(N, 1);

for n = 1:N
    histBuf(histIdx) = x(n);
    refIdx = mod(histIdx - refDelay - 1, 256) + 1;
    ref = histBuf(refIdx);

    delayLine = [ref; delayLine(1:end-1)];

    pred = w' * delayLine;
    e = x(n) - pred;
    w = w + mu * e * delayLine;

    y(n) = e;
    histIdx = mod(histIdx, 256) + 1;
end

audiowrite('filtered_sample.wav', y, Fs);
audiowrite('raw_sample.wav', x, Fs);

figure;
subplot(2,1,1); plot(x); title('Raw');
subplot(2,1,2); plot(y); title('Filtered (ALE output)');

fprintf('Try sweeping mu between 0.0002 and 0.005 and order between 16 and 64.\n');
'@

# ============================================================
# matlab/fir_design_reference.m
# ============================================================
Write-File "$root\matlab\fir_design_reference.m" @'
% fir_design_reference.m
% If you also want a FIXED reference FIR (e.g. a band-pass keeping just
% the speech band 300Hz-3400Hz) to compare against your adaptive filter,
% design it here with fir1 / fdesign.

Fs = 8000;
Nfilt = 64;
Wn = [300 3400] / (Fs/2);   % normalized band edges

b = fir1(Nfilt, Wn, 'bandpass');

fvtool(b, 1, 'Fs', Fs);   % view frequency response

% Export coefficients to paste into a C array if you want a fixed
% band-pass stage in addition to the adaptive LMS stage:
fprintf('const float fir_coeffs[%d] = {\n', length(b));
fprintf('%.8ff,\n', b);
fprintf('};\n');
'@

# ============================================================
# hardware/wiring_notes.md
# ============================================================
Write-File "$root\hardware\wiring_notes.md" @'
# Complete Hardware Connection & Wiring Guide

## 1. System Overview Architecture

```
                 +--------------------------------------------------+
                 |                    WiFi UDP                      |
                 |          (Telemetry: Waveform & FFT)             |
                 v                                                  |
       +-------------------+                               +------------------+
       |   MATLAB Laptop   |                               |   INMP441 Mic    |
       +-------------------+                               |  (I2S Digital)   |
                                                           +--------+---------+
                                                                    |
                                                                    | I2S (SCK, WS, SD)
                                                                    v
                                                           +--------+---------+
                                                           |   ESP32 Master   |
                                                           | (LMS ALE Filter) |
                                                           +--------+---------+
                                                                    |
                                                       Audio (GPIO26) | DAC Output
                                                                    v
                                                         [ 1kΩ + 0.1µF RC Filter ]
                                                                    |
                                                                    | Clean Audio
                                                                    v
                                                          +-------------------+
                                                          |  3.5mm Headphone  |
                                                          |       Jack        |
                                                          +-------------------+
                                                                    |
                                                               Earphones
```

---

## 2. Bill of Materials

| # | Component | Qty | Purpose |
|---|-----------|-----|---------|
| 1 | ESP32 DevKit V1 | 1 | Main processor (I2S input, LMS filter, DAC output) |
| 2 | INMP441 I2S MEMS Microphone | 1 | Captures ambient audio digitally via I2S |
| 3 | 1kΩ Resistor | 1 | Part of RC low-pass filter on DAC output |
| 4 | 0.1µF (100nF) Ceramic Capacitor | 1 | RC filter + DC blocking for headphone jack |
| 5 | 3.5mm TRS Headphone Jack (Female) | 1 | Audio output connector for earphones |

---

## 3. Pin-to-Pin Connection Tables

### A. Digital I2S Microphone (INMP441) -> ESP32
| INMP441 Pin | ESP32 Pin | Description |
|:---|:---|:---|
| **VDD** | **3.3V** | Power Supply (3.3V only) |
| **GND** | **GND** | Ground |
| **SD**  | **GPIO 33** | Serial Data (I2S Data In) |
| **WS**  | **GPIO 25** | Word Select (Left/Right clock) |
| **SCK** | **GPIO 32** | Serial Clock (Bit Clock) |
| **L/R** | **GND** | Left/Right Channel (GND = Left) |

---

### B. ESP32 DAC Output -> RC Low-Pass Filter -> 3.5mm Headphone Jack
The ESP32 DAC (GPIO 26) generates an 8-bit analog step voltage. The RC filter smooths out quantization steps and blocks DC bias from reaching the headphones.

```
ESP32 GPIO 26 -----[ 1 kΩ Resistor ]-----+------> TIP   (Left Audio)
                                         |          +---> RING  (Right Audio, mono, same signal)
                                   [ 0.1 µF Cap ]
                                         |
                                        GND ------> SLEEVE (Ground)
```

**RC Filter Cutoff:** f = 1 / (2pi x R x C) = 1 / (2pi x 1000 x 0.0000001) = ~1.6 kHz
This smooths the DAC staircase output. Adequate for speech frequencies (300-3400 Hz).

| Component | Connection From | Connection To |
|:---|:---|:---|
| **1 kΩ Resistor** | ESP32 GPIO 26 | Filter Output Node |
| **0.1 µF (100 nF) Capacitor** | Filter Output Node | ESP32 GND |
| **Filter Output Node** | --- | 3.5mm Jack TIP + RING (mono to both ears) |
| **GND** | ESP32 GND | 3.5mm Jack SLEEVE |

---

### C. 3.5mm TRS Jack Pinout
| Jack Terminal | Signal | Wired To |
|:---|:---|:---|
| **TIP** | Left Audio | RC Filter Output |
| **RING** | Right Audio | RC Filter Output (bridged to TIP for mono) |
| **SLEEVE** | Ground | ESP32 GND |

---

## 4. Important Notes

- **No amplifier needed:** Standard earphones/headphones (16-32 ohm) can be driven directly by the ESP32 DAC through the RC filter. Volume will be modest but audible.
- **DC blocking:** The 0.1uF capacitor also acts as a DC-blocking cap, preventing the DAC's DC bias (~1.65V midpoint) from reaching the headphone drivers.
- **Common ground:** Ensure all GND connections (ESP32, INMP441, 3.5mm jack sleeve) are tied together.
- **Power:** ESP32 can be powered via USB. The INMP441 draws minimal current from the 3.3V rail.
'@

# ============================================================
# docs/test_results.md
# ============================================================
Write-File "$root\docs\test_results.md" @'
# Test Results (fill this in as you go)

## Latency
- Measured input-to-output latency: ___ ms
  (method: play a click track into the mic, capture output on a scope /
  second phone recording, measure the time delta)

## Noise Reduction
- SNR before filtering: ___ dB
- SNR after filtering: ___ dB
- Noise types tested: fan / hum / traffic / etc.

## Headphone Output Quality
- Audible volume level: ___ (quiet / adequate / loud)
- Any DAC noise or hiss: ___ (yes / no)
- Audio clarity through headphones: ___ (muffled / acceptable / clear)
- Headphone impedance tested: ___ ohm
'@

# ============================================================
# README.md
# ============================================================
Write-File "$root\README.md" @'
# Real-Time Audio Noise Cancellation using FIR Filtering

Single-mic active noise cancellation (Adaptive Line Enhancer / LMS) running
on an ESP32, with 3.5mm headphone jack output and live MATLAB visualization.

## Components
- ESP32 DevKit
- INMP441 I2S MEMS Microphone
- 1k ohm Resistor + 0.1uF Capacitor (RC filter on DAC output)
- 3.5mm TRS Headphone Jack

## Build order (do it in this sequence)
1. `matlab/lms_offline_sim.m` - tune filter order & mu on a recorded clip.
2. Flash `firmware/esp32_master/esp32_master.ino` - get mic -> filter ->
   headphone jack working standalone first, no WiFi/MATLAB yet.
3. Bring up `matlab/live_plot_main.m` telemetry once step 2 sounds right.

## Folder map
- `firmware/esp32_master/` - main real-time DSP firmware (ESP32).
- `matlab/` - offline tuning + live telemetry plotting.
- `hardware/` - wiring notes and connection guide.
- `docs/` - test results template for your report.

## Config you MUST edit before flashing
In `firmware/esp32_master/config.h`:
- `WIFI_SSID` / `WIFI_PASS`
- `MATLAB_PC_IP` (your laptop's IP on the same WiFi network)
'@

Write-Host ""
Write-Host "Done. Project scaffolded at .\$root" -ForegroundColor Green
Write-Host "Open it in Arduino IDE (firmware/) and MATLAB (matlab/) and start with the README." -ForegroundColor Green
