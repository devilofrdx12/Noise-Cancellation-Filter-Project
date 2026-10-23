#include "i2s_audio.h"
#include "config.h"
#include <driver/i2s.h>

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

    // No DAC output — cleaned audio is streamed to laptop via WiFi UDP
}

float i2sReadSample() {
    int32_t raw = 0;
    size_t bytesRead = 0;
    i2s_read(I2S_PORT, &raw, sizeof(raw), &bytesRead, portMAX_DELAY);

    // INMP441 gives 24-bit data left-justified in a 32-bit frame
    int32_t sample24 = raw >> 8;
    return (float)sample24 / 8388608.0f; // normalize to -1..1 (2^23)
}
