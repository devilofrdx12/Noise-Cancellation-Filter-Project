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
