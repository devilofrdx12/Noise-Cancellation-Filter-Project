#pragma once

void telemetryInit();

// Stream cleaned audio to laptop for playback (every sample, UDP_AUDIO_PORT)
void audioStreamSend(float filtered);

// Send raw+filtered pair to MATLAB for plotting (downsampled, UDP_TELEMETRY_PORT)
void telemetrySend(float raw, float filtered);
