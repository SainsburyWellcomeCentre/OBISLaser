function session = example_bpod_softcode(useHardware, port)
% example_bpod_softcode sets an OBIS power per trial from a Bpod soft code.
%
%   session = example_bpod_softcode()             simulated laser, simulated trials
%   session = example_bpod_softcode(true, 'COM15') the real laser
%
%   The pattern a protocol follows (docs/bpod-integration.md): connect once in setup, in
%   Digital mode so the state machine's TTL gates the light; queue each trial's power when
%   the trial is prepared; set it from the soft code the trial's first state sends, before
%   any TTL; save record() with the session; disconnect in cleanup. Here a loop stands in
%   for Bpod: onSoftCode is what BpodSystem.SoftCodeHandlerFunction would call.
%
%   Returns the laser's record() taken at the end of the session.
%
% See also obis.Laser, example_basic
    if nargin < 1
        useHardware = false;
    end
    if useHardware
        laser = obis.Laser('Port', port);
    else
        laser = obis.Laser('Transport', obis.transport.SimulatedTransport());
    end
    cleanup = onCleanup(@() laser.disconnect());

    % Setup, once.
    laser.connect();
    laser.MaxPowermW = 60;
    laser.setMode('Digital');
    laser.setPower(0);
    laser.setEnabled(true);

    % Trials. The queue holds each prepared trial's power until its soft code arrives.
    powers = [10 20 40 20 10];
    queue = [];
    for trial = 1:numel(powers)
        queue(end + 1) = powers(trial); %#ok<AGROW> % prepared with the trial
        queue = onSoftCode(laser, queue);         % the trial's first state sends it
    end

    session = laser.record();
    laser.disconnect();
end


function queue = onSoftCode(laser, queue)
% Sets the next queued power. A soft-code handler must not throw: Bpod would stop.
try
    laser.setPower(queue(1));
    queue(1) = [];
catch err
    warning('example_bpod_softcode:laser', 'Power not set: %s', err.message);
end
end
