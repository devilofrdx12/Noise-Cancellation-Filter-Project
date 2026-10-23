#pragma once
#include <Arduino.h>

void i2sAudioInit();
float i2sReadSample();          // returns normalized -1.0 .. 1.0
