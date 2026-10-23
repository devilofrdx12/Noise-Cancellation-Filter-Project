% fir_design_reference.m
% If you also want a FIXED reference FIR (e.g. a band-pass keeping just
% the speech band 300Hz-3400Hz) to compare against your adaptive filter,
% design it here with fir1 / fdesign.

Fs = 8000;
Nfilt = 64;
Wn = [300 3400] / (Fs/2);   % normalized band edges

b = fir1(Nfilt, Wn, 'bandpass');

fvtool(b, 1, 'Fs', Fs);   % view frequency response

% Export coefficients to paste into a C array if you want a fixed
% band-pass stage in addition to the adaptive LMS stage:
fprintf('const float fir_coeffs[%d] = {\n', length(b));
fprintf('%.8ff,\n', b);
fprintf('};\n');
