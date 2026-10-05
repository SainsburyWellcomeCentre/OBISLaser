classdef Laser < handle
% obis.Laser controls a Coherent OBIS laser: connection, mode, power, emission and safety.
%
%   laser = obis.Laser('Port', 'COM15')        real laser on a serial port
%   laser = obis.Laser('Transport', obis.transport.SimulatedTransport())
%   laser = obis.Laser(..., 'Name', value)     any settable property below
%
%   The constructor never touches the hardware; connect() does. connect() turns emission
%   off, so the laser is in a known state whatever the last program left it in, and leaves
%   the mode as it found it. Every command waits for the laser's answer (handshaking is
%   turned on at connect), so a call that returns has been accepted, and a refusal is an
%   error naming the laser's code. Nothing reads the light itself: what this object reports
%   as commanded is what the laser accepted, and powermW() is the laser's own reading.
%
%   Properties (read-only)
%       State             'Disconnected' | 'Ready' | 'Faulted'
%       FaultReason       why the object is Faulted, else ''
%       Transport         the obis.transport.Transport in use
%       Identity          struct: Idn, Model, SerialNumber, WavelengthNm (filled by connect)
%       DeviceMaxPowermW  the laser's own power limit (SOURce:POWer:LIMit:HIGH?)
%       DeviceMinPowermW  the laser's lowest setpoint (SOURce:POWer:LIMit:LOW?)
%       Mode              obis.Mode the laser reported or was last set to
%       CommandedPowermW  last setpoint the laser accepted (read back at connect)
%       IsEnabled         emission state the laser last accepted
%       IsBusy            true while a command waits for its answer
%
%   Properties (settable)
%       Port         serial port, e.g. 'COM15' (when no Transport is given; default from
%                    obis.config, i.e. setpref('obis', 'Port', ...))
%       BaudRate     default 115200
%       MaxPowermW   your limit: setPower refuses anything above it. Empty until connect,
%                    which sets it to DeviceMaxPowermW unless you set a lower one. Cannot be
%                    set above DeviceMaxPowermW, nor below the setpoint already commanded.
%       TimeoutS     how long a command waits for the laser's answer (default 2)
%       Verbose      print each command and reply (default false)
%       LogCapacity  entries kept by log() (default 1000)
%
%   Methods
%       connect()                  open, handshake on, read identity and limits, emission off
%       disconnect()               emission off, close. Idempotent, never throws
%       setMode(mode)              obis.Mode or its name ('Digital', 'CWP', ...)
%       setPower(mW)               setpoint in mW; refused above MaxPowermW or below 0
%       setEnabled(tf)             emission on or off
%       ok = stopAll()             emission off; tried in every state, never throws
%       mW = powermW()             output power the laser measures now
%       mW = setpointmW()          setpoint the laser holds now
%       s = status()               one read of every value above plus temperature and codes
%       reply = query(line)        send any query, return its value (expert use)
%       command(line)              send any command (expert use; power commands refused: use
%                                  setPower, which applies MaxPowermW)
%       s = record()               plain struct for data files
%       t = log()                  table of recent commands, replies and latencies
%
%   Events: StateChanged, CommandCompleted (listeners read the properties).
%
%   Errors
%       obis:Laser:notReady        a command needs State Ready
%       obis:Laser:noPort          connect with neither Port nor Transport
%       obis:Laser:timeout         no answer within TimeoutS (the object becomes Faulted)
%       obis:Laser:deviceError     the laser answered ERR-<code>
%       obis:Laser:aboveLimit      a power above MaxPowermW
%       obis:Laser:badValue        a power that is negative, not finite or not a scalar
%       obis:Laser:limitAboveDevice  MaxPowermW above DeviceMaxPowermW
%       obis:Laser:limitBelowCommanded  MaxPowermW below CommandedPowermW
%       obis:Laser:useSetPower     command() given a power command
%       obis:Laser:busy            a command issued while another waits for its answer
%       obis:Laser:portLocked      Port or BaudRate changed while connected
%       Transport errors from open (e.g. obis:SerialTransport:openFailed) pass through.
%
%   Example
%       laser = obis.Laser('Transport', obis.transport.SimulatedTransport());
%       laser.connect();
%       laser.MaxPowermW = 50;
%       laser.setMode('Digital');
%       laser.setPower(20);
%       laser.setEnabled(true);
%       laser.disconnect();
%
%   See also obis.Mode, obis.Calibration, obis.app, obis.listDevices, obis.config

    properties (SetAccess = private)
        State = 'Disconnected'   % 'Disconnected' | 'Ready' | 'Faulted'
        FaultReason = ''         % why the object is Faulted
        Transport = []           % obis.transport.Transport in use
        Identity = obis.Laser.emptyIdentity()  % Idn, Model, SerialNumber, WavelengthNm
        DeviceMaxPowermW = []    % laser's own power limit, mW
        DeviceMinPowermW = []    % laser's lowest setpoint, mW
        Mode = obis.Mode.empty   % mode the laser reported or was last set to
        CommandedPowermW = []    % last setpoint the laser accepted, mW
        IsEnabled = false        % emission state the laser last accepted
        IsBusy = false           % a command waits for its answer
    end

    properties (Dependent)
        Port        % serial port, e.g. 'COM15'
        BaudRate    % bits per second
        MaxPowermW  % your power limit, mW
    end

    properties
        TimeoutS = 2         % wait for each answer, s
        Verbose = false      % print commands and replies
        LogCapacity = 1000   % entries kept by log()
    end

    events
        StateChanged
        CommandCompleted
    end

    properties (Access = private)
        PortValue = ''
        BaudRateValue = 115200
        MaxPowerValue = []
        OwnsTransport = false
        LogEntries
        ClockStart
        ClockEpoch
    end

    methods
        function obj = Laser(varargin)
            obj.LogEntries = obis.Laser.emptyLog();
            obj.ClockStart = tic;
            obj.ClockEpoch = datetime('now');
            if mod(numel(varargin), 2) ~= 0
                error('obis:Laser:invalidOption', 'Options must be name-value pairs.');
            end
            cfg = obis.config();
            obj.PortValue = cfg.Port;
            obj.BaudRateValue = cfg.BaudRate;
            for k = 1:2:numel(varargin)
                name = char(varargin{k});
                value = varargin{k + 1};
                switch lower(name)
                    case 'transport'
                        if ~isa(value, 'obis.transport.Transport')
                            error('obis:Laser:invalidOption', ...
                                'Transport must be an obis.transport.Transport.');
                        end
                        obj.Transport = value;
                    case {'port', 'baudrate', 'maxpowermw', 'timeouts', 'verbose', ...
                            'logcapacity'}
                        props = {'Port', 'BaudRate', 'MaxPowermW', 'TimeoutS', 'Verbose', ...
                            'LogCapacity'};
                        obj.(props{strcmpi(props, name)}) = value;
                    otherwise
                        error('obis:Laser:invalidOption', ['Unknown option "%s". Valid: ' ...
                            'Transport, Port, BaudRate, MaxPowermW, TimeoutS, Verbose, ' ...
                            'LogCapacity.'], name);
                end
            end
        end

        function delete(obj)
            obj.disconnect();
        end

        %% Connection -------------------------------------------------------------------------

        function connect(obj)
            % connect() opens the port, reads identity and limits, and turns emission off.
            %
            %   Handshaking is turned on first, so every later command is answered. The
            %   mode and setpoint are read back, not changed. Errors close the port and
            %   leave the object Disconnected (Faulted, with FaultReason, on a timeout).
            if strcmp(obj.State, 'Ready')
                return
            end
            if isempty(obj.Transport) || obj.OwnsTransport
                if isempty(obj.PortValue)
                    error('obis:Laser:noPort', ['No port: give ''Port'' (see ' ...
                        'obis.listDevices) or set a default with setpref(''obis'', ' ...
                        '''Port'', ''COM15'').']);
                end
                obj.Transport = obis.transport.SerialTransport(obj.PortValue, ...
                    'BaudRate', obj.BaudRateValue);
                obj.OwnsTransport = true;
            end
            obj.FaultReason = '';
            try
                obj.Transport.open();
                obj.Transport.flush();
                % Short form: the rig's OBIS Remote (v2.0.2) refuses the long one (scpi.md).
                obj.exchange('SYST:COMM:HAND ON', false);
                identity = obis.Laser.emptyIdentity();
                identity.Idn = obj.exchange('*IDN?', true);
                identity.Model = obj.exchange('SYSTem:INFormation:MODel?', true);
                identity.SerialNumber = obj.exchange('SYSTem:INFormation:SNUMber?', true);
                identity.WavelengthNm = str2double(obj.exchange( ...
                    'SYSTem:INFormation:WAVelength?', true));
                obj.Identity = identity;
                obj.DeviceMaxPowermW = obis.Laser.wattsToMilliwatts(obj.exchange( ...
                    'SOURce:POWer:LIMit:HIGH?', true));
                obj.DeviceMinPowermW = obis.Laser.wattsToMilliwatts(obj.exchange( ...
                    'SOURce:POWer:LIMit:LOW?', true));
                obj.exchange('SOURce:AM:STATe OFF', false);
                obj.IsEnabled = false;
                obj.Mode = obis.Mode.fromText(obj.exchange('SOURce:AM:SOURce?', true));
                obj.CommandedPowermW = obis.Laser.wattsToMilliwatts(obj.exchange( ...
                    'SOURce:POWer:LEVel:IMMediate:AMPLitude?', true));
                if isempty(obj.MaxPowerValue)
                    obj.MaxPowerValue = obj.DeviceMaxPowermW;
                elseif obj.MaxPowerValue > obj.DeviceMaxPowermW
                    error('obis:Laser:limitAboveDevice', ['MaxPowermW (%g mW) is above ' ...
                        'this laser''s limit (%g mW).'], obj.MaxPowerValue, ...
                        obj.DeviceMaxPowermW);
                end
            catch err
                obj.Transport.close();
                rethrow(err);
            end
            obj.setState('Ready');
        end

        function disconnect(obj)
            % disconnect() turns emission off and closes the port. Never throws.
            if isempty(obj.Transport)
                return
            end
            wasConnected = ~strcmp(obj.State, 'Disconnected');
            if wasConnected
                obj.stopAll();
            end
            try
                obj.Transport.close();
            catch
                % Nothing more can be done for a port that will not close.
            end
            obj.IsBusy = false;
            if wasConnected
                obj.setState('Disconnected');
            end
        end

        %% Commands ---------------------------------------------------------------------------

        function setMode(obj, mode)
            % setMode(mode) selects where output power comes from (obis.Mode or its name).
            %
            %   The laser decides whether it accepts a change with emission on; a refusal
            %   is an obis:Laser:deviceError (docs/rig-checks.md lists this as unchecked).
            mode = obis.Mode.fromText(mode);
            obj.requireReady();
            obj.exchange(mode.Command, false);
            obj.Mode = mode;
            notify(obj, 'CommandCompleted');
        end

        function setPower(obj, mW)
            % setPower(mW) sets the output power setpoint, in mW.
            %
            %   Refused, never reduced, above MaxPowermW. In an external mode the setpoint is
            %   the power while the input is high (Digital) or at full scale (Analog).
            if ~isnumeric(mW) || ~isscalar(mW) || ~isfinite(mW) || mW < 0
                error('obis:Laser:badValue', 'Power must be one finite number >= 0 (mW).');
            end
            obj.requireReady();
            if mW > obj.MaxPowerValue
                error('obis:Laser:aboveLimit', ['%g mW refused: above MaxPowermW (%g mW). ' ...
                    'Raise MaxPowermW first if this is intended.'], mW, obj.MaxPowerValue);
            end
            obj.exchange(sprintf('SOURce:POWer:LEVel:IMMediate:AMPLitude %.6f', mW / 1000), ...
                false);
            obj.CommandedPowermW = mW;
            notify(obj, 'CommandCompleted');
        end

        function setEnabled(obj, tf)
            % setEnabled(tf) turns emission on (true) or off (false).
            obj.requireReady();
            if tf
                obj.exchange('SOURce:AM:STATe ON', false);
            else
                obj.exchange('SOURce:AM:STATe OFF', false);
            end
            obj.IsEnabled = logical(tf);
            notify(obj, 'CommandCompleted');
        end

        function ok = stopAll(obj)
            % ok = stopAll() turns emission off in any state where the port is open.
            %
            %   Never throws; ok is false when the laser did not confirm. Use it from cleanup
            %   paths and emergency buttons.
            ok = false;
            try
                if isempty(obj.Transport) || ~obj.Transport.isOpen()
                    return
                end
                obj.IsBusy = false;
                obj.exchange('SOURce:AM:STATe OFF', false);
                obj.IsEnabled = false;
                ok = true;
                notify(obj, 'CommandCompleted');
            catch
                % The caller is told by ok; throwing here would stop a cleanup halfway.
            end
        end

        function mW = powermW(obj)
            % mW = powermW() is the output power the laser measures now.
            obj.requireReady();
            mW = obis.Laser.wattsToMilliwatts(obj.exchange('SOURce:POWer:LEVel?', true));
        end

        function mW = setpointmW(obj)
            % mW = setpointmW() is the setpoint the laser holds now, read back.
            obj.requireReady();
            mW = obis.Laser.wattsToMilliwatts(obj.exchange( ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude?', true));
        end

        function s = status(obj)
            % s = status() reads every live value once.
            %
            %   Returns a struct: IsEnabled, Mode (obis.Mode), SetpointmW, OutputmW,
            %   BaseplateC, StatusCode and FaultCode (the laser's hex words, docs/scpi.md).
            obj.requireReady();
            s = struct();
            s.IsEnabled = strcmpi(obj.exchange('SOURce:AM:STATe?', true), 'ON');
            s.Mode = obis.Mode.fromText(obj.exchange('SOURce:AM:SOURce?', true));
            s.SetpointmW = obis.Laser.wattsToMilliwatts(obj.exchange( ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude?', true));
            s.OutputmW = obis.Laser.wattsToMilliwatts(obj.exchange('SOURce:POWer:LEVel?', ...
                true));
            s.BaseplateC = str2double(erase(obj.exchange('SOURce:TEMPerature:BASeplate?', ...
                true), 'C'));
            s.StatusCode = obj.exchange('SYSTem:STATus?', true);
            s.FaultCode = obj.exchange('SYSTem:FAULt?', true);
        end

        function reply = query(obj, line)
            % reply = query(line) sends any query and returns the laser's value.
            obj.requireReady();
            reply = obj.exchange(char(line), true);
        end

        function command(obj, line)
            % command(line) sends any command and waits for the laser to accept it.
            %
            %   Power commands are refused (obis:Laser:useSetPower) so that MaxPowermW
            %   always applies. The object's commanded state is not updated: read it back
            %   with status() after changing mode or emission this way.
            line = char(line);
            if contains(upper(line), 'AMPL') && ~endsWith(strtrim(line), '?')
                error('obis:Laser:useSetPower', ['Use setPower to change the power, so ' ...
                    'that MaxPowermW applies.']);
            end
            obj.requireReady();
            obj.exchange(line, false);
            notify(obj, 'CommandCompleted');
        end

        %% Records ----------------------------------------------------------------------------

        function s = record(obj)
            % s = record() is a plain struct describing the laser and the session's commands.
            s = struct();
            s.Package = 'obis';
            s.Version = obis.version();
            s.RecordedAt = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));
            s.State = obj.State;
            s.FaultReason = obj.FaultReason;
            s.Transport = class(obj.Transport);
            s.Connection = '';
            if ~isempty(obj.Transport)
                s.Connection = obj.Transport.Description;
            end
            s.Identity = obj.Identity;
            s.DeviceMaxPowermW = obj.DeviceMaxPowermW;
            s.DeviceMinPowermW = obj.DeviceMinPowermW;
            s.MaxPowermW = obj.MaxPowerValue;
            s.Mode = '';
            if ~isempty(obj.Mode)
                s.Mode = char(obj.Mode);
            end
            s.CommandedPowermW = obj.CommandedPowermW;
            s.IsEnabled = obj.IsEnabled;
            entries = obj.LogEntries;
            times = obj.ClockEpoch + seconds([entries.Time]);
            times.Format = 'yyyy-MM-dd''T''HH:mm:ss.SSS';
            timeText = cellstr(char(times));
            for k = 1:numel(entries)
                entries(k).Time = timeText{k};
            end
            s.Log = entries;
        end

        function t = log(obj)
            % t = log() is a table of recent commands: Time (s), Command, Reply, Ok, LatencyMs.
            t = struct2table(obj.LogEntries, 'AsArray', true);
        end

        %% Property access --------------------------------------------------------------------

        function value = get.Port(obj)
            value = obj.PortValue;
        end

        function set.Port(obj, value)
            obj.requireUnlocked('Port');
            obj.PortValue = char(value);
        end

        function value = get.BaudRate(obj)
            value = obj.BaudRateValue;
        end

        function set.BaudRate(obj, value)
            obj.requireUnlocked('BaudRate');
            obj.BaudRateValue = value;
        end

        function value = get.MaxPowermW(obj)
            value = obj.MaxPowerValue;
        end

        function set.MaxPowermW(obj, value)
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value < 0
                error('obis:Laser:badValue', 'MaxPowermW must be one finite number >= 0.');
            end
            if ~isempty(obj.DeviceMaxPowermW) && value > obj.DeviceMaxPowermW
                error('obis:Laser:limitAboveDevice', ['MaxPowermW %g mW is above this ' ...
                    'laser''s limit (%g mW).'], value, obj.DeviceMaxPowermW);
            end
            if strcmp(obj.State, 'Ready') && ~isempty(obj.CommandedPowermW) ...
                    && value < obj.CommandedPowermW
                error('obis:Laser:limitBelowCommanded', ['MaxPowermW %g mW is below the ' ...
                    'setpoint already commanded (%g mW); lower the power first.'], value, ...
                    obj.CommandedPowermW);
            end
            obj.MaxPowerValue = value;
        end
    end

    methods (Access = private)
        function value = exchange(obj, line, isQuery)
            % Sends one line and reads to its OK; returns the value line of a query.
            if obj.IsBusy
                error('obis:Laser:busy', ['"%s" sent while another command waits for its ' ...
                    'answer.'], line);
            end
            obj.IsBusy = true;
            busy = onCleanup(@() obj.clearBusy());  % frees the object on any exit
            started = tic;
            value = '';
            reply = '';
            ok = false;
            try
                obj.Transport.writeLine(line);
                while true
                    received = obj.Transport.readLine(max(obj.TimeoutS - toc(started), 0.01));
                    if isempty(received)
                        reason = sprintf('no answer to "%s" within %g s', line, obj.TimeoutS);
                        obj.addLog(line, reply, false, toc(started));
                        obj.fault(reason);
                        error('obis:Laser:timeout', 'The laser gave %s.', reason);
                    end
                    received = char(received);
                    if startsWith(received, 'ERR', 'IgnoreCase', true)
                        reply = received;
                        break
                    elseif strcmpi(received, 'OK')
                        ok = true;
                        break
                    elseif isQuery && isempty(value)
                        value = received;
                        reply = received;
                    end
                end
            catch err
                if ~strcmp(err.identifier, 'obis:Laser:timeout')
                    obj.addLog(line, err.message, false, toc(started));
                end
                rethrow(err);
            end
            obj.addLog(line, reply, ok, toc(started));
            if ~ok
                error('obis:Laser:deviceError', ...
                    'The laser refused "%s" with %s (docs/scpi.md).', line, reply);
            end
        end

        function clearBusy(obj)
            % Marks the object free for the next command.
            if isvalid(obj)
                obj.IsBusy = false;
            end
        end

        function addLog(obj, command, reply, ok, elapsedS)
            % Appends one command to the log, keeping at most LogCapacity entries.
            entry = struct('Time', toc(obj.ClockStart) - elapsedS, 'Command', command, ...
                'Reply', reply, 'Ok', ok, 'LatencyMs', 1000 * elapsedS);
            obj.LogEntries(end + 1) = entry;
            if numel(obj.LogEntries) > obj.LogCapacity
                obj.LogEntries(1:end - obj.LogCapacity) = [];
            end
            if obj.Verbose
                fprintf('[obis] %s -> %s (%.1f ms)\n', command, reply, 1000 * elapsedS);
            end
        end

        function requireReady(obj)
            % Errors unless the laser is connected and not faulted.
            if ~strcmp(obj.State, 'Ready')
                detail = '';
                if strcmp(obj.State, 'Faulted')
                    detail = sprintf(' (%s; disconnect and connect again)', obj.FaultReason);
                end
                error('obis:Laser:notReady', 'The laser is %s%s; connect() first.', ...
                    obj.State, detail);
            end
        end

        function requireUnlocked(obj, name)
            % Errors while connected: the port cannot change under an open connection.
            if ~strcmp(obj.State, 'Disconnected')
                error('obis:Laser:portLocked', '%s cannot change while connected.', name);
            end
        end

        function fault(obj, reason)
            % Marks the object Faulted: the laser state is unknown until reconnected.
            obj.FaultReason = reason;
            obj.setState('Faulted');
        end

        function setState(obj, state)
            % Changes State and tells listeners.
            if ~strcmp(obj.State, state)
                obj.State = state;
                notify(obj, 'StateChanged');
            end
        end
    end

    methods (Static, Hidden)
        function s = emptyIdentity()
            % Identity before connect.
            s = struct('Idn', '', 'Model', '', 'SerialNumber', '', 'WavelengthNm', NaN);
        end

        function s = emptyLog()
            % A log with no entries.
            s = struct('Time', {}, 'Command', {}, 'Reply', {}, 'Ok', {}, 'LatencyMs', {});
        end

        function mW = wattsToMilliwatts(text)
            % The laser's power replies are in W.
            mW = 1000 * str2double(text);
        end
    end
end
