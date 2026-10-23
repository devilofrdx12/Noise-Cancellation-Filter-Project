function live_plot_main()
    % live_plot_main.m
    % Receives UDP telemetry (raw, filtered float pairs) from the ESP32 and
    % plots them live: waveform overlay + a rolling FFT comparison.
    % Uses Java UDP sockets for ultimate compatibility across all MATLAB versions.

    PORT = 5006;     % telemetry port (audio playback uses 5005)
    BUFFER_LEN = 500;      % samples shown on screen at once

    % Clean up old instrument control objects just in case
    objs = instrfind;
    if ~isempty(objs)
        fclose(objs);
        delete(objs);
    end

    % Setup Java UDP Socket (No toolbox required)
    try
        socket = java.net.DatagramSocket(PORT);
        socket.setSoTimeout(50); % 50ms timeout
    catch ME
        error('Could not bind to port %d. Restart MATLAB if it keeps failing.', PORT);
    end

    packetBuffer = zeros(1, 4096, 'int8');
    packet = java.net.DatagramPacket(packetBuffer, length(packetBuffer));

    rawBuf = zeros(1, BUFFER_LEN);
    filtBuf = zeros(1, BUFFER_LEN);

    fig = figure('Name', 'Real-Time Noise Cancellation Monitor', 'DeleteFcn', @(o,e) cleanup(socket));

    subplot(2,1,1);
    hRaw = animatedline('Color', [0.85 0.2 0.2]);
    hFilt = animatedline('Color', [0.1 0.6 0.9]);
    legend('Raw (noisy)', 'Filtered (clean)');
    title('Live Waveform: Raw vs Filtered');
    xlabel('Sample #'); ylabel('Amplitude');
    axis([0 BUFFER_LEN -1 1]);

    subplot(2,1,2);
    hFFT = plot(nan, nan);
    title('FFT: Noise Floor Before vs After (updates periodically)');
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');

    n = 0;
    disp('Listening for ESP32 telemetry... start talking into the mic.');

    try
        while ishandle(fig)
            try
                socket.receive(packet);
                len = packet.getLength();
                data = packet.getData();
                
                bytes = typecast(data(1:len), 'uint8');
                bytesToRead = floor(length(bytes) / 8) * 8;
                
                for k = 1:8:bytesToRead
                    raw = typecast(bytes(k:k+3), 'single');
                    filtered = typecast(bytes(k+4:k+7), 'single');

                    n = n + 1;
                    idx = mod(n, BUFFER_LEN) + 1;
                    rawBuf(idx) = raw;
                    filtBuf(idx) = filtered;

                    addpoints(hRaw, idx, raw);
                    addpoints(hFilt, idx, filtered);
                end

                if mod(n, 50) == 0
                    drawnow limitrate;
                end
                if mod(n, 200) == 0
                    updateFFT(rawBuf, filtBuf);
                end
            catch
                % Timeout or error on receive, drawnow to keep UI responsive
                drawnow limitrate;
            end
        end
    catch ME
        cleanup(socket);
    end
end

function updateFFT(rawBuf, filtBuf)
    Fs = 8000;
    Nfft = 256;
    Fraw = abs(fft(rawBuf(1:min(Nfft,end)), Nfft));
    Ffilt = abs(fft(filtBuf(1:min(Nfft,end)), Nfft));
    f = (0:Nfft/2-1) * (Fs/Nfft);
    subplot(2,1,2);
    plot(f, 20*log10(Fraw(1:Nfft/2)+eps), 'r', ...
         f, 20*log10(Ffilt(1:Nfft/2)+eps), 'b');
    legend('Raw', 'Filtered');
    title('FFT: Noise Floor Before vs After');
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
end

function cleanup(socket)
    if exist('socket', 'var')
        socket.close();
    end
end
