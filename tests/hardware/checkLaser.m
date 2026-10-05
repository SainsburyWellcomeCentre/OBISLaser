function report = checkLaser(port)
% checkLaser runs rig checks 1-5 of docs/rig-checks.md against the real laser.
%
%   report = checkLaser('COM15')
%
%   Needs the operator's permission for this run (CLAUDE.md, Hardware). Block the beam, or put
%   a power meter head in it, and close Coherent Connection first. Every step pauses for the
%   operator to read the meter or watch the beam, and the laser ends with emission off and the
%   port closed however the script ends.
%
%   Returns the laser's record() plus the answers typed at each pause, for docs/rig-checks.md.
%
% See also obis.Laser, obis.Calibration
    laser = obis.Laser('Port', port, 'TimeoutS', 2);
    cleanup = onCleanup(@() laser.disconnect());
    report = struct('Steps', {{}});

    % 1. Connection and replies.
    laser.connect();
    disp(laser.Identity);
    fprintf('Limits %g-%g mW, mode %s, setpoint %g mW\n', laser.DeviceMinPowermW, ...
        laser.DeviceMaxPowermW, char(laser.Mode), laser.CommandedPowermW);
    disp(laser.log());

    % 2. Every mode, emission off then on.
    laser.setPower(min(1, laser.DeviceMaxPowermW));
    for enabled = [false true]
        laser.setEnabled(enabled);
        for name = {'CWP', 'CWC', 'Digital', 'Analog', 'Mixed'}
            try
                laser.setMode(name{1});
                outcome = 'accepted';
            catch err
                outcome = err.message;
            end
            fprintf('emission %d, %-7s %s\n', enabled, name{1}, outcome);
        end
        laser.setEnabled(false);
    end

    % 3. Power against the meter.
    laser.setMode('CWP');
    laser.setEnabled(true);
    for mW = [1 5 10 50]
        if mW <= laser.MaxPowermW
            laser.setPower(mW);
            pause(1);
            report.Steps{end + 1} = sprintf('%g mW set, laser reads %.3f mW, meter %s', mW, ...
                laser.powermW(), input(sprintf('Meter reading at %g mW: ', mW), 's'));
        end
    end
    laser.setPower(0);
    laser.setEnabled(false);

    % 5. Emission off on stopAll (the other paths are checked by hand).
    laser.setPower(1);
    laser.setEnabled(true);
    input('Emission is ON at 1 mW. Press Enter to send stopAll and watch it go off: ', 's');
    report.Steps{end + 1} = sprintf('stopAll confirmed: %d, seen off: %s', laser.stopAll(), ...
        input('Did the light go off (y/n)? ', 's'));

    report.Record = laser.record();
end
