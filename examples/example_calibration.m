% example_calibration converts between a power at the sample and the setpoint that gives it.
%
%   A calibration is a table of setpoints and the power a meter read at the sample for each;
%   obis.Calibration interpolates it both ways and refuses anything outside it. Runs with no
%   hardware.
%
% See also obis.Calibration, example_basic

setpointmW = [0 5 10 20 40 80 165]';
measuredmW = [0 1.7 3.4 6.8 13.5 27.1 53.2]';  % what the meter read at the sample
cal = obis.Calibration(setpointmW, measuredmW);  % or obis.Calibration.fromCsv(file)

fprintf('Calibrated from %.2f to %.2f mW at the sample\n', cal.Range);
fprintf('For 10 mW at the sample, set %.1f mW\n', cal.setpointFor(10));
fprintf('A 100 mW setpoint gives %.2f mW at the sample\n', cal.powerFor(100));

% The same table as irradiance over a 2.2 x 1.65 mm field (mW/mm2).
irradiance = cal.scaled(1 / (2.2 * 1.65));
fprintf('For 2 mW/mm2, set %.1f mW\n', irradiance.setpointFor(2));

try
    cal.setpointFor(80);                         % beyond the table: refused
catch err
    fprintf('Refused as expected: %s\n', err.message);
end
