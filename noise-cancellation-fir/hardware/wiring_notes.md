# Complete Hardware Connection & Wiring Guide

## 1. System Overview Architecture

```
                                                           +------------------+
                                                           |   INMP441 Mic    |
                                                           |  (I2S Digital)   |
                                                           +--------+---------+
                                                                    |
                                                                    | I2S (SCK, WS, SD)
                                                                    v
                                                           +--------+---------+
                                                           |   ESP32 Master   |
                                                           | (LMS ALE Filter) |
                                                           +--------+---------+
                                                                    |
                                                                    | WiFi UDP
                                                                    | (Cleaned Audio Stream)
                                                                    v
                                                           +--------+---------+
                                                           |     Laptop       |
                                                           | (MATLAB Player)  |
                                                           +--------+---------+
                                                                    |
                                                           Laptop's 3.5mm Jack
                                                                    |
                                                               🎧 Earphones
```

**Signal path:** Mic → ESP32 (noise cancellation) → WiFi → Laptop → Laptop's headphone jack → Earphones

---

## 2. Bill of Materials

| # | Component | Qty | Purpose |
|---|-----------|-----|---------|
| 1 | ESP32 DevKit V1 | 1 | Main processor (I2S input, LMS filter, WiFi audio stream) |
| 2 | INMP441 I2S MEMS Microphone | 1 | Captures ambient audio digitally via I2S |
| 3 | 1kΩ Resistor | 1 | Series with INMP441 VDD — power supply noise filter |
| 4 | 0.1µF (100nF) Ceramic Capacitor | 1 | INMP441 VDD decoupling capacitor |

> **Note:** No separate headphone jack, amplifier, or DAC output circuit needed.
> The cleaned audio is streamed over WiFi to the laptop, which plays it through
> its own built-in 3.5mm headphone jack.

---

## 3. Pin-to-Pin Connection Tables

### A. Digital I2S Microphone (INMP441) -> ESP32

| INMP441 Pin | ESP32 Pin | Description |
|:---|:---|:---|
| **VDD** | **3.3V** (through 1kΩ) | Power Supply (3.3V only, filtered) |
| **GND** | **GND** | Ground |
| **SD**  | **GPIO 33** | Serial Data (I2S Data In) |
| **WS**  | **GPIO 25** | Word Select (Left/Right clock) |
| **SCK** | **GPIO 32** | Serial Clock (Bit Clock) |
| **L/R** | **GND** | Left/Right Channel (GND = Left) |

---

### B. INMP441 Power Supply Filtering

The 1kΩ resistor and 0.1µF capacitor form a low-pass RC filter on the mic's power rail
to reduce high-frequency noise and ensure clean, stable power.

```
ESP32 3.3V ─────[ 1 kΩ Resistor ]─────┬──────> INMP441 VDD
                                       │
                                 [ 0.1 µF Cap ]
                                       │
                                      GND ──────> INMP441 GND
```

| Component | Connection From | Connection To |
|:---|:---|:---|
| **1 kΩ Resistor** | ESP32 3.3V | INMP441 VDD (filtered) |
| **0.1 µF (100 nF) Capacitor** | INMP441 VDD | GND (decoupling) |

---

## 4. Audio Output Path (Laptop)

No hardware output circuit on the ESP32 side. The cleaned audio flows like this:

1. ESP32 processes audio with the LMS adaptive noise cancellation filter
2. ESP32 sends cleaned audio samples over **WiFi UDP** to the laptop
3. MATLAB on the laptop receives the stream and plays it via `audioDeviceWriter`
4. Audio comes out of the **laptop's built-in 3.5mm headphone jack**
5. Plug your earphones into the laptop

---

## 5. Important Notes

- **Common ground:** Ensure ESP32 GND and INMP441 GND are tied together.
- **Power:** ESP32 powered via USB from the laptop. The INMP441 draws ~1.4mA from the filtered 3.3V rail.
- **WiFi:** ESP32 and laptop must be on the **same WiFi network**.
- **Latency:** WiFi streaming adds ~20-50ms latency. Acceptable for noise cancellation demo.
- **Firewall:** Make sure UDP port 5005 is open on the laptop (Windows Firewall may block it).
