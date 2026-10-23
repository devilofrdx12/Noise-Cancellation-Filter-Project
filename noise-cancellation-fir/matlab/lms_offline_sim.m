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
