% test_connection.m
% Run this to verify that MATLAB is successfully receiving data from the ESP32.

clc; clear;
PORT = 5005; % Audio stream port

% Clean up old sockets just in case
objs = instrfind;
if ~isempty(objs)
    fclose(objs);
    delete(objs);
end

try
    socket = java.net.DatagramSocket(PORT);
    socket.setSoTimeout(1000); % 1 second timeout
    fprintf('=== ESP32 Connection Tester ===\n');
    fprintf('Listening for ESP32 packets on port %d...\n', PORT);
    fprintf('Make sure your ESP32 is powered on and connected to WiFi.\n\n');
catch
    error('Port %d is busy. Restart MATLAB.', PORT);
end

packetBuffer = zeros(1, 4096, 'int8');
packet = java.net.DatagramPacket(packetBuffer, length(packetBuffer));

packetsReceived = 0;
try
    while packetsReceived < 10
        try
            socket.receive(packet);
            packetsReceived = packetsReceived + 1;
            fprintf('✅ SUCCESS! Received packet %d from ESP32 (Size: %d bytes)\n', packetsReceived, packet.getLength());
            
            if packetsReceived == 10
                fprintf('\n🎉 COMMUNICATION IS WORKING PERFECTLY! 🎉\n');
                fprintf('You can now run audio_player.m or live_plot_main.m\n');
                break;
            end
        catch
            fprintf('⏳ Waiting for ESP32... (Check Serial Monitor if this continues)\n');
        end
    end
catch ME
    disp('Test stopped.');
end

if exist('socket', 'var')
    socket.close();
end
