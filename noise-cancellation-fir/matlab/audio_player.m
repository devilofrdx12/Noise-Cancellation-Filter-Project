% audio_player.m
% Receives cleaned audio from ESP32 over WiFi UDP and plays it in real-time
% through the laptop's default audio output (3.5mm headphone jack).

AUDIO_PORT = 5005;           % must match UDP_AUDIO_PORT in config.h
SAMPLE_RATE = 8000;          % must match SAMPLE_RATE in config.h

% --- Clean up old sockets just in case ---
% This attempts to close any lingering Instrument Control UDP objects
objs = instrfind;
if ~isempty(objs)
    fclose(objs);
    delete(objs);
end

% --- Setup Java UDP Socket (No toolbox required, no bind errors) ---
try
    socket = java.net.DatagramSocket(AUDIO_PORT);
    socket.setSoTimeout(100); % 100ms timeout so Ctrl+C still works smoothly
catch ME
    error('Could not bind to port %d. Restart MATLAB if it keeps failing.', AUDIO_PORT);
end

packetBuffer = zeros(1, 4096, 'int8');
packet = java.net.DatagramPacket(packetBuffer, length(packetBuffer));

% --- Setup Java Audio Output (No toolbox required) ---
% 8000 Hz, 16-bit, Mono, Signed, Little-Endian
af = javax.sound.sampled.AudioFormat(SAMPLE_RATE, 16, 1, true, false);
player = javax.sound.sampled.AudioSystem.getSourceDataLine(af);
player.open(af, 4096);
player.start();

fprintf('=== ESP32 Noise Cancellation Audio Player ===\n');
fprintf('Listening on UDP port %d for cleaned audio...\n', AUDIO_PORT);
fprintf('Audio will play through your laptop speakers/headphone jack.\n');
fprintf('Plug your earphones into the LAPTOP.\n');
fprintf('Press Ctrl+C to stop.\n\n');

% --- Main receive-and-play loop ---
try
    while true
        try
            socket.receive(packet);
            len = packet.getLength();
            data = packet.getData();
            
            % Convert signed int8 from Java to unsigned uint8
            bytes = typecast(data(1:len), 'uint8');
            
            % Process in multiples of 4 bytes (float32 size)
            numFloats = floor(length(bytes) / 4);
            if numFloats > 0
                validBytes = bytes(1 : numFloats*4);
                
                % Convert bytes to float32
                samples = typecast(validBytes, 'single');
                
                % Clip and scale to 16-bit integer for playback
                samples(samples > 1.0) = 1.0;
                samples(samples < -1.0) = -1.0;
                samples_int16 = int16(samples * 32767);
                
                % Convert to byte array for Java
                java_bytes = typecast(samples_int16, 'int8');
                
                % Play through laptop audio output using Java
                player.write(java_bytes, 0, length(java_bytes));
            end
        catch
            % Timeout (no packet received in 100ms), just continue loop
        end
    end
catch ME
    % Ctrl+C or any error — clean up gracefully
    fprintf('\nStopping audio player...\n');
    if exist('player', 'var')
        player.stop();
        player.close();
    end
    if exist('socket', 'var')
        socket.close();
    end
    fprintf('Done.\n');
    if ~strcmp(ME.identifier, 'MATLAB:interrupt')
        rethrow(ME);
    end
end
