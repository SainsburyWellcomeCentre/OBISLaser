classdef SimulatedTransport < obis.transport.Transport
% obis.transport.SimulatedTransport is an OBIS laser without hardware: answers, records, fails.
%
%   t = obis.transport.SimulatedTransport()
%   t = obis.transport.SimulatedTransport('MaxPowermW', 100, 'WavelengthNm', 488)
%   laser = obis.Laser('Transport', t);
%
%   Answers the SCPI commands obis.Laser sends the way docs/scpi.md describes the real laser:
%   OK after every command while handshaking is on, the value then OK for a query, ERR-<code>
%   for an unknown command or a value out of range. It keeps the state those commands change
%   (emission, modulation source, setpoint) so a test can check what the laser would be doing.
%   Commands are matched in the long form obis.Laser writes, in any letter case; the short
%   SCPI forms (SOUR:AM:STAT) are not recognised and get ERR-100. Handshaking is the
%   exception: as on the rig's OBIS Remote, only SYST:COMM:HAND is known. Error codes are the
%   simulator's own: the real laser's numbers are in docs/scpi.md.
%
%   Properties
%       MaxPowermW, MinPowermW  the power limits the laser reports (default 165 and 0)
%       WavelengthNm            reported wavelength (default 561)
%       Model, SerialNumber     reported identity
%       ModulationInput         level 0..1 on the external input, for the simulated output
%                               power in Digital, Analog and Mixed modes (default 0)
%       BaseplateC              reported baseplate temperature (default 25)
%   Read-only state
%       Calls                   struct array Time (s), Line: every line received
%       Handshake, Enabled, Mode ('CWP', 'CWC', 'DIGITAL', 'ANALOG', 'MIXED'), SetpointW
%
%   Fault injection
%       failNext(prefix, reply)  the next line starting with prefix gets reply ('ERR-100' by
%                                default) and changes nothing
%       hangNext(prefix)         the next line starting with prefix gets no reply at all
%       unplug()                 every later write errors, as a pulled USB cable does
%       clearCalls()             empty Calls
%       lines = callsOf(prefix)  the received lines that start with prefix (any case)
%
%   See also obis.transport.Transport, obis.Laser

    properties
        MaxPowermW = 165            % reported SOURce:POWer:LIMit:HIGH, mW
        MinPowermW = 0              % reported SOURce:POWer:LIMit:LOW, mW
        WavelengthNm = 561          % reported wavelength, nm
        Model = 'OBIS 561nm LS 165mW'  % reported model
        SerialNumber = 'SIM0001'    % reported serial number
        ModulationInput = 0         % external input level 0..1
        BaseplateC = 25             % reported baseplate temperature, C
    end

    properties (SetAccess = protected)
        Description = 'simulated OBIS'  % for records
    end

    properties (SetAccess = private)
        Calls = struct('Time', {}, 'Line', {})  % every line received
        Handshake = true   % OK after each command
        Enabled = false    % SOURce:AM:STATe
        Mode = 'CWP'       % SOURce:AM:SOURce reply
        SetpointW = 0      % SOURce:POWer:LEVel:IMMediate:AMPLitude, W
    end

    properties (Access = private)
        Opened = false
        Unplugged = false
        Outbox = {}
        Failures = struct('Prefix', {}, 'Reply', {})
        Hangs = {}
        ClockStart
    end

    methods
        function obj = SimulatedTransport(varargin)
            obj.ClockStart = tic;
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k + 1};
            end
        end

        function open(obj)
            obj.Opened = true;
            obj.Outbox = {};
        end

        function close(obj)
            obj.Opened = false;
            obj.Outbox = {};
        end

        function tf = isOpen(obj)
            tf = obj.Opened;
        end

        function writeLine(obj, text)
            if obj.Unplugged
                error('obis:SimulatedTransport:unplugged', 'The simulated laser was unplugged.');
            end
            if ~obj.Opened
                error('obis:SimulatedTransport:notOpen', 'The simulated port is not open.');
            end
            text = strtrim(char(text));
            obj.Calls(end + 1) = struct('Time', toc(obj.ClockStart), 'Line', text);
            for k = 1:numel(obj.Hangs)
                if startsWith(upper(text), upper(obj.Hangs{k}))
                    obj.Hangs(k) = [];
                    return
                end
            end
            for k = 1:numel(obj.Failures)
                if startsWith(upper(text), upper(obj.Failures(k).Prefix))
                    reply = obj.Failures(k).Reply;
                    obj.Failures(k) = [];
                    obj.Outbox{end + 1} = reply;
                    return
                end
            end
            obj.answer(text);
        end

        function line = readLine(obj, ~)
            if isempty(obj.Outbox)
                line = [];
                return
            end
            line = obj.Outbox{1};
            obj.Outbox(1) = [];
        end

        function flush(obj)
            obj.Outbox = {};
        end

        function failNext(obj, prefix, reply)
            % failNext(prefix, reply) makes the next line starting with prefix get reply.
            if nargin < 3
                reply = 'ERR-100';
            end
            obj.Failures(end + 1) = struct('Prefix', char(prefix), 'Reply', char(reply));
        end

        function hangNext(obj, prefix)
            % hangNext(prefix) makes the next line starting with prefix get no reply.
            obj.Hangs{end + 1} = char(prefix);
        end

        function unplug(obj)
            % unplug() makes every later write error, as a pulled USB cable does.
            obj.Unplugged = true;
        end

        function clearCalls(obj)
            % clearCalls() empties Calls.
            obj.Calls = struct('Time', {}, 'Line', {});
        end

        function lines = callsOf(obj, prefix)
            % lines = callsOf(prefix) is the received lines that start with prefix, any case.
            lines = {obj.Calls.Line};
            lines = lines(startsWith(upper(lines), upper(char(prefix))));
        end
    end

    methods (Access = private)
        function answer(obj, text)
            % Applies one received line to the simulated state and queues the reply.
            [head, argument] = strtok(text, ' ');
            head = upper(head);
            argument = upper(strtrim(argument));
            value = '';
            ok = true;
            switch head
                case '*IDN?'
                    value = sprintf('Coherent, Inc - %s Laser - %s - V1.0.0 - simulated', ...
                        obj.Model, obj.SerialNumber);
                case 'SYSTEM:INFORMATION:MODEL?'
                    value = obj.Model;
                case 'SYSTEM:INFORMATION:SNUMBER?'
                    value = obj.SerialNumber;
                case 'SYSTEM:INFORMATION:WAVELENGTH?'
                    value = sprintf('%g', obj.WavelengthNm);
                case 'SYST:COMM:HAND'
                    ok = any(strcmp(argument, {'ON', 'OFF'}));
                    if ok
                        obj.Handshake = strcmp(argument, 'ON');
                    end
                case 'SYST:COMM:HAND?'
                    value = onOff(obj.Handshake);
                case 'SOURCE:POWER:LIMIT:HIGH?'
                    value = sprintf('%.5f', obj.MaxPowermW / 1000);
                case 'SOURCE:POWER:LIMIT:LOW?'
                    value = sprintf('%.5f', obj.MinPowermW / 1000);
                case 'SOURCE:POWER:NOMINAL?'
                    value = sprintf('%.5f', obj.MaxPowermW / 1000);
                case 'SOURCE:POWER:LEVEL:IMMEDIATE:AMPLITUDE'
                    watts = str2double(argument);
                    ok = isfinite(watts) && watts >= obj.MinPowermW / 1000 ...
                        && watts <= obj.MaxPowermW / 1000;
                    if ok
                        obj.SetpointW = watts;
                    else
                        obj.Outbox{end + 1} = 'ERR-102';
                        return
                    end
                case 'SOURCE:POWER:LEVEL:IMMEDIATE:AMPLITUDE?'
                    value = sprintf('%.5f', obj.SetpointW);
                case 'SOURCE:POWER:LEVEL?'
                    value = sprintf('%.5f', obj.outputW());
                case 'SOURCE:AM:STATE'
                    ok = any(strcmp(argument, {'ON', 'OFF'}));
                    if ok
                        obj.Enabled = strcmp(argument, 'ON');
                    end
                case 'SOURCE:AM:STATE?'
                    value = onOff(obj.Enabled);
                case 'SOURCE:AM:INTERNAL'
                    ok = any(strcmp(argument, {'CWP', 'CWC'}));
                    if ok
                        obj.Mode = argument;
                    end
                case 'SOURCE:AM:EXTERNAL'
                    names = struct('DIGITAL', 'DIGITAL', 'DIG', 'DIGITAL', 'ANALOG', 'ANALOG', ...
                        'ANAL', 'ANALOG', 'MIXED', 'MIXED', 'MIX', 'MIXED');
                    ok = isvarname(argument) && isfield(names, argument);
                    if ok
                        obj.Mode = names.(argument);
                    end
                case 'SOURCE:AM:SOURCE?'
                    value = obj.Mode;
                case 'SOURCE:TEMPERATURE:BASEPLATE?'
                    value = sprintf('%.1fC', obj.BaseplateC);
                case {'SYSTEM:STATUS?', 'SYSTEM:FAULT?'}
                    value = '00000000';
                otherwise
                    obj.Outbox{end + 1} = 'ERR-100';
                    return
            end
            if ~ok
                obj.Outbox{end + 1} = 'ERR-102';
                return
            end
            if ~isempty(value)
                obj.Outbox{end + 1} = value;
            end
            if obj.Handshake
                obj.Outbox{end + 1} = 'OK';
            end
        end

        function watts = outputW(obj)
            % The power the simulated laser emits now, W.
            if ~obj.Enabled
                watts = 0;
            elseif any(strcmp(obj.Mode, {'CWP', 'CWC'}))
                watts = obj.SetpointW;
            else
                watts = obj.SetpointW * obj.ModulationInput;
            end
        end
    end
end


function text = onOff(tf)
% 'ON' or 'OFF'.
if tf
    text = 'ON';
else
    text = 'OFF';
end
end
