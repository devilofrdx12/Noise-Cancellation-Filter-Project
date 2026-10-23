#include "telemetry_udp.h"
#include "config.h"
#include <WiFi.h>
#include <WiFiUdp.h>

static WiFiUDP udpAudio;       // cleaned audio stream for laptop playback
static WiFiUDP udpTelemetry;   // raw+filtered pairs for MATLAB live plot

static int telemetrySampleCounter = 0;

// Audio chunk buffer — we batch samples into chunks before sending
// to reduce UDP packet overhead (header per packet is 28 bytes).
static float audioChunk[AUDIO_CHUNK_SIZE];
static int audioChunkIdx = 0;

void telemetryInit() {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    Serial.print("Connecting to WiFi");
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 10000) {
        delay(200);
        Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\nWiFi connected! IP: " + WiFi.localIP().toString());
    } else {
        Serial.println("\nWiFi FAILED - audio streaming won't work.");
    }

    udpAudio.begin(UDP_AUDIO_PORT);
    udpTelemetry.begin(UDP_TELEMETRY_PORT);
}

void audioStreamSend(float filtered) {
    // Buffer samples into chunks for efficient UDP transmission
    audioChunk[audioChunkIdx++] = filtered;

    if (audioChunkIdx >= AUDIO_CHUNK_SIZE) {
        audioChunkIdx = 0;

        if (WiFi.status() != WL_CONNECTED) return;

        // Send chunk as raw float array (AUDIO_CHUNK_SIZE * 4 bytes)
        udpAudio.beginPacket(MATLAB_PC_IP, UDP_AUDIO_PORT);
        udpAudio.write((uint8_t*)audioChunk, sizeof(audioChunk));
        udpAudio.endPacket();
    }
}

void telemetrySend(float raw, float filtered) {
    // Downsample for the visualization plot (doesn't need every sample)
    telemetrySampleCounter++;
    if (telemetrySampleCounter < TELEMETRY_DOWNSAMPLE) return;
    telemetrySampleCounter = 0;

    if (WiFi.status() != WL_CONNECTED) return;

    // simple 8-byte packet: [float raw][float filtered]
    uint8_t packet[8];
    memcpy(packet, &raw, 4);
    memcpy(packet + 4, &filtered, 4);

    udpTelemetry.beginPacket(MATLAB_PC_IP, UDP_TELEMETRY_PORT);
    udpTelemetry.write(packet, 8);
    udpTelemetry.endPacket();
}
