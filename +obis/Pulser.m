classdef Pulser < handle
% obis.Pulser switches an OBIS laser's emission on and off at a frequency and duty cycle.
%
%   p = obis.Pulser(laser)                              10 Hz, 50 %
%   p = obis.Pulser(laser, 'FrequencyHz', 5, 'DutyPercent', 20)
%   p.start()     emission on now, then off and on again every period
%   p.stop()      stops the pulsing; emission off
%
%   The laser has no pulse generator of its own: this sends emission on and off over its
%   port (SOURce:AM:STATe) from two MATLAB timers, one starting each period and one ending
%   its on phase. Timing is MATLAB's, so each edge can be late by a few ms (more while
%   MATLAB is busy): good for a steady, visible pulse train, not for precise stimulation,
%   which needs Digital mode and an external TTL. Each phase (on and off) must last at least
%   MinPhaseS, so the frequency is at most MaxFrequencyHz and the duty is kept away from
%   0 and 100 % at high frequencies. A command that fails (the laser busy with another
%   command, for example) is counted in Missed, not thrown; stop() always turns emission off.
%
%   Properties
%       FrequencyHz   pulses per second (settable while stopped)
%       DutyPercent   share of each period the emission is on, 0 to 100 (settable while
%                     stopped)
%       OnS, OffS     each phase's length, s (read only)
%       Running       true between start and stop (read only)
%       Cycles        periods started since start (read only)
%       Missed        commands that failed since start (read only)
%
%   Errors: obis:Pulser:badValue (a frequency or duty out of range, or phases shorter than
%   MinPhaseS), obis:Pulser:notReady (the laser is not connected).
%
% See also obis.Laser, obis.gui.LaserApp

    properties
        FrequencyHz = 10      % pulses per second
        DutyPercent = 50      % share of each period on, %
    end

    properties (SetAccess = private)
        Laser                 % the obis.Laser pulsed
        Running = false
        Cycles = 0
        Missed = 0
    end

    properties (Dependent)
        OnS                   % on phase, s
        OffS                  % off phase, s
    end

    properties (Constant)
        MinPhaseS = 0.02      % each on or off phase lasts at least this long
        MaxFrequencyHz = 25
    end

    properties (Access = private)
        PeriodTimer = []
        OffTimer = []
    end

    methods
        function obj = Pulser(laser, varargin)
            if ~isa(laser, 'obis.Laser')
                error('obis:Pulser:badValue', 'Give the obis.Laser to pulse.');
            end
            obj.Laser = laser;
            for k = 1:2:numel(varargin)
                obj.(char(varargin{k})) = varargin{k + 1};
            end
        end

        function delete(obj)
            try
                if obj.Running
                    obj.stop();  % no pulsing left behind; idle, the laser is left as it is
                end
            catch
                % delete never throws.
            end
        end

        function set.FrequencyHz(obj, value)
            if obj.Running %#ok<MCSUP> it guards the timers, which have no setter
                error('obis:Pulser:badValue', 'Stop the pulsing before changing its frequency.');
            end
            top = obis.Pulser.MaxFrequencyHz;
            if ~(isnumeric(value) && isscalar(value) && value > 0 && value <= top)
                error('obis:Pulser:badValue', ...
                    'The frequency must be above 0 and at most %g Hz.', top);
            end
            obj.FrequencyHz = double(value);
        end

        function set.DutyPercent(obj, value)
            if obj.Running %#ok<MCSUP> it guards the timers, which have no setter
                error('obis:Pulser:badValue', 'Stop the pulsing before changing its duty cycle.');
            end
            if ~(isnumeric(value) && isscalar(value) && value >= 0 && value <= 100)
                error('obis:Pulser:badValue', 'The duty cycle must be 0 to 100 %%.');
            end
            obj.DutyPercent = double(value);
        end

        function s = get.OnS(obj)
            s = obj.DutyPercent / 100 / obj.FrequencyHz;
        end

        function s = get.OffS(obj)
            s = (1 - obj.DutyPercent / 100) / obj.FrequencyHz;
        end

        function check(obj)
            % check() errors (obis:Pulser:badValue) unless both phases are long enough.
            % A duty of 0 or 100 % is allowed: emission simply stays off or on.
            on = obj.OnS;
            off = obj.OffS;
            if (on > 0 && on < obj.MinPhaseS) || (off > 0 && off < obj.MinPhaseS)
                error('obis:Pulser:badValue', ['At %g Hz and %g %% the on phase lasts %.1f ms ' ...
                    'and the off phase %.1f ms; each must be 0 or at least %g ms (switching ' ...
                    'over the port takes a few ms).'], obj.FrequencyHz, obj.DutyPercent, ...
                    1000 * on, 1000 * off, 1000 * obj.MinPhaseS);
            end
        end

        function start(obj)
            % start() turns emission on now and keeps pulsing until stop().
            if obj.Running
                return
            end
            if ~strcmp(obj.Laser.State, 'Ready')
                error('obis:Pulser:notReady', 'Connect the laser before pulsing it.');
            end
            obj.check();
            obj.Cycles = 0;
            obj.Missed = 0;
            obj.Running = true;
            if obj.DutyPercent == 0
                obj.send(false);
                return
            end
            if obj.DutyPercent == 100
                obj.send(true);
                return
            end
            ref = matlab.lang.WeakReference(obj);
            obj.OffTimer = timer('ExecutionMode', 'singleShot', ...
                'StartDelay', round(obj.OnS, 3), 'Name', 'obis.Pulser off', ...
                'TimerFcn', @(~, ~) obis.Pulser.onOff(ref));
            obj.PeriodTimer = timer('ExecutionMode', 'fixedRate', ...
                'Period', round(1 / obj.FrequencyHz, 3), 'BusyMode', 'drop', ...
                'Name', 'obis.Pulser', 'TimerFcn', @(~, ~) obis.Pulser.onPeriod(ref));
            start(obj.PeriodTimer);
        end

        function stop(obj)
            % stop() stops the pulsing and turns emission off; never throws.
            obj.Running = false;
            for t = {obj.PeriodTimer, obj.OffTimer}
                try
                    if ~isempty(t{1}) && isvalid(t{1})
                        stop(t{1});
                        delete(t{1});
                    end
                catch
                end
            end
            obj.PeriodTimer = [];
            obj.OffTimer = [];
            try
                if isvalid(obj.Laser)
                    obj.Laser.stopAll();
                end
            catch
            end
        end
    end

    methods (Access = private)
        function send(obj, on)
            % Emission on or off; a failure is counted, not thrown.
            try
                obj.Laser.setEnabled(on);
            catch
                obj.Missed = obj.Missed + 1;
            end
        end

        function period(obj)
            % A period starts: emission on, and the off edge after OnS.
            if ~obj.Running, return; end
            obj.Cycles = obj.Cycles + 1;
            obj.send(true);
            try
                if strcmp(obj.OffTimer.Running, 'off')
                    start(obj.OffTimer);
                end
            catch
            end
        end
    end

    methods (Static, Access = private)
        function onPeriod(ref)
            obj = ref.Handle;
            if ~isempty(obj) && isvalid(obj)
                obj.period();
            end
        end

        function onOff(ref)
            obj = ref.Handle;
            if ~isempty(obj) && isvalid(obj) && obj.Running
                obj.send(false);
            end
        end
    end
end
