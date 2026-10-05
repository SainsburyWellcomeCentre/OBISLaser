% example_basic walks through every obis.Laser command on the simulated laser.
%
%   Runs as it is with no hardware. Set useHardware = true and port to drive a real OBIS:
%   then check that nothing is in the beam path that should not be, and wear the eyewear
%   the laser's class requires.
%
% See also obis.Laser, obis.Mode, example_bpod_softcode, example_calibration

useHardware = false;
port = 'COM15';

if useHardware
    laser = obis.Laser('Port', port); %#ok<UNRCH> % reached once useHardware is set
else
    laser = obis.Laser('Transport', obis.transport.SimulatedTransport());
end
cleanup = onCleanup(@() laser.disconnect());   % emission off however the script ends

laser.connect();                               % emission is off after connect
disp(laser.Identity)
fprintf('Laser limits: %g to %g mW\n', laser.DeviceMinPowermW, laser.DeviceMaxPowermW);

laser.MaxPowermW = 20;                         % refuse anything above 20 mW from here on
laser.setMode('CWP');                          % constant power, internal
laser.setPower(5);
laser.setEnabled(true);
pause(0.5);
fprintf('Output now %.2f mW (setpoint %.2f mW)\n', laser.powermW(), laser.setpointmW());

try
    laser.setPower(50);                        % above MaxPowermW: refused, nothing sent
catch err
    fprintf('Refused as expected: %s\n', err.message);
end

laser.setEnabled(false);
laser.setMode('Digital');                      % from now on a TTL on the input gates output
laser.setPower(10);
laser.setEnabled(true);                        % emits only while the TTL is high
disp(laser.status())

session = laser.record();                      % save this with your data
laser.disconnect();
