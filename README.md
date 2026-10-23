# Real-Time Audio Noise Cancellation using FIR Filtering

Single-mic active noise cancellation (Adaptive Line Enhancer / LMS) running
on an ESP32. Cleaned audio streams over WiFi to your laptop and plays through
the laptop's 3.5mm headphone jack. Live MATLAB visualization included.

## Components
- ESP32 DevKit
- INMP441 I2S MEMS Microphone
- 1kΩ Resistor + 0.1µF Capacitor (mic power supply filtering)

## How it works
```
INMP441 mic → ESP32 (LMS noise cancellation) → WiFi UDP → Laptop → Laptop's 3.5mm jack → 🎧
```

## Build order (do it in this sequence)
1. `matlab/lms_offline_sim.m` — tune filter order & mu on a recorded clip.
2. Flash `firmware/esp32_master/esp32_master.ino` to the ESP32.
3. Run `matlab/audio_player.m` — hear cleaned audio through your laptop's headphone jack.
4. Run `matlab/live_plot_main.m` — see raw vs filtered waveform + FFT live.

## Folder map
- `firmware/esp32_master/` — main real-time DSP firmware (ESP32).
- `matlab/` — audio player, live plotting, and offline tuning.
- `hardware/` — wiring notes and connection guide.
- `docs/` — test results template for your report.

## Config you MUST edit before flashing
In `firmware/esp32_master/config.h`:
- `WIFI_SSID` / `WIFI_PASS`
- `MATLAB_PC_IP` (your laptop's IP on the same WiFi network)
- 
