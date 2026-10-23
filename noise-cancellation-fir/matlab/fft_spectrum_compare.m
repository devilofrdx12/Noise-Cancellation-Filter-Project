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
