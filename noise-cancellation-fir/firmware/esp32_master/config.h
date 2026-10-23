#pragma once

// ---------------- Audio config ----------------
#define SAMPLE_RATE          8000        // 8kHz is plenty for speech, keeps latency low
#define I2S_WS_PIN           25
#define I2S_SD_PIN           33
#define I2S_SCK_PIN          32
#define I2S_PORT             I2S_NUM_0

// ---------------- LMS adaptive filter config ----------------
#define FILTER_ORDER         32          // taps - start small, raise only if needed
#define LMS_MU               0.0008f     // step size - tune this in MATLAB offline sim first
#define REF_DELAY            5           // samples of decorrelation delay (Adaptive Line Enhancer)

// ---------------- Audio streaming config ----------------
#define AUDIO_CHUNK_SIZE     64          // samples per UDP packet (64 samples = 8ms at 8kHz)

// ---------------- Telemetry (MATLAB) config ----------------
#define WIFI_SSID             "vivo T5x 5G"
#define WIFI_PASS             "demon 2345"
#define MATLAB_PC_IP          "10.12.112.158"   // set to your laptop's IP
#define UDP_AUDIO_PORT        5005              // cleaned audio stream to MATLAB player
#define UDP_TELEMETRY_PORT    5006              // raw+filtered telemetry for live plot
#define TELEMETRY_DOWNSAMPLE  4                 // send every Nth sample pair to telemetry plot
