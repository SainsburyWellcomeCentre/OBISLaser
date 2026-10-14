classdef LaserApp < handle
% obis.gui.LaserApp is the control panel for an obis.Laser: start, stop, power and mode.
%
%   app = obis.gui.LaserApp()              owns a new obis.Laser (real laser); closing the
%                                          window turns emission off and disconnects it
%   app = obis.gui.LaserApp('Port', 'COM15', 'DllFolder', folder, ...)
%                                          owns an obis.Laser built with these options
%   app = obis.gui.LaserApp(laser)         attaches to an existing obis.Laser; closing the
%                                          panel never disconnects it
%   app = obis.gui.LaserApp(..., 'Parent', container)
%                                          builds the panel inside container (a figure,
%                                          uipanel, uitab or uigridlayout of another GUI)
%                                          instead of a window of its own
%   app = obis.gui.LaserApp(..., 'Visible', false, 'AutoRefresh', false, 'ShowLog', false)
%   app = obis.gui.LaserApp(..., 'ListDevices', fcn)   how ports are found (tests): fcn()
%                                          returns a table like obis.listDevices
%   app = obis.gui.LaserApp('ExpectedWavelengthNm', 488)   with several lasers, the one this
%                                          panel is for: Connect finds its port
%                                          (obis.findPort) and refuses any other laser
%   app = obis.gui.LaserApp(..., 'Identify', fcn)   how Connect asks a port's laser (tests)
%   app = obis.gui.LaserApp(..., 'SavePreferences', false)   a DLL folder chosen in the
%                                          panel is not kept for next time (tests)
%   app = obis.gui.LaserApp(..., 'Calibration', cal, 'CalibrationLabel', 'Out of objective')
%                                          also shows the power where cal was measured
%                                          (an obis.Calibration) for the setpoint, beside
%                                          the laser's own
%
%   Laid out like Coherent Connection's laser panel. The header shows the laser, its
%   output power, mode and state, with Start and Stop; its lamp is the laser's wavelength
%   colour, bright while emitting and dim while off. Connect finds the laser's port (Scan;
%   with a Wavelength set, the port whose laser reports it: obis.findPort) and connects.
%   The window's title names the laser connected, so two panels for two lasers are told
%   apart. Operating power (mW) is applied at once: typed (Enter), stepped with the down
%   and up arrows (by Step), or dragged on the slider, which spans 0 to Max power, your
%   limit; the mode (CW:Power, CW:Current, Digital, Analog, Mixed) when chosen. Details
%   (folded away at first) holds the connection: Wavelength (nm, 0 for any laser), port,
%   Scan (obis.listDevices, which reads Windows' device list and sends nothing), driver
%   (Coherent's DLL or MATLAB's serialport) and the folder holding Coherent's DLL (kept
%   with setpref for next time); a readback of what the laser reports (every RefreshS
%   while Auto refresh is ticked); and a log. Esc is Stop in a window of its own. See
%   docs/gui.md.
%
%   Pulse: with it ticked, Start switches emission on and off at Frequency (Hz) and Duty
%   (%) from MATLAB timers (obis.Pulser: a few ms of jitter, each phase at least 20 ms);
%   the line beside it gives the on and off times. Stop ends it. With a Calibration, a line
%   gives the power out of the light path (where the calibration was measured) for the
%   setpoint, and its average while pulsing; outside the calibrated setpoints it says so.
%
%   Auto refresh starts ticked for an owned laser and unticked for an attached one: a
%   protocol that sends commands from its own callbacks must not meet a readback in the
%   middle of one (obis:Laser:busy).
%
%   Properties (read-only)
%       Laser       the obis.Laser shown
%       OwnsLaser   true when the app created it
%       Figure      the figure holding the panel (its own uifigure, or the host's)
%       Root        the panel's outermost container (delete it to remove the panel)
%       Controls    struct of components (for scripting and tests)
%       LastError   text of the last error shown
%       LastStatus  struct from the last readback (obis.Laser.status), or []
%       LockReason  why the panel is view only (lock), or ''
%       Pulser      the obis.Pulser Start uses while Pulse is ticked
%       Calibration the obis.Calibration shown (setCalibration), or []
%
%   Methods
%       refresh()   redraw every control from the laser object (no traffic)
%       showDetails(tf)  unfold or fold away the connection, readback and log
%       readback()  ask the laser for its live values and show them
%       lock(reason)  view only: every control that would change the laser (Connect,
%                   Start, power, mode, connection) is disabled and the state says why;
%                   Stop (emission off, Esc) and readback stay. For a host whose own code
%                   drives the laser (a running session); any pulsing stops. unlock()
%                   gives the controls back
%       setCalibration(cal, label)  show the power where cal was measured ([] hides it)
%       close()     close the panel (stops any pulsing; disconnects only an owned laser)
%
% See also obis.app, obis.Laser

    properties (SetAccess = private)
        Laser                 % the obis.Laser shown
        OwnsLaser = false     % the app created it
        Figure = []           % figure holding the panel
        Root = []             % outermost container of the panel
        Controls = struct()   % components, for scripting and tests
        LastError = ''        % last error shown
        LastStatus = []       % last readback
        LockReason = ''       % why the panel is view only, or ''
        Pulser = []           % obis.Pulser for Pulse
        Calibration = []      % obis.Calibration shown beside the setpoint, or []
        CalibrationLabel = 'At sample'
    end

    properties
        RefreshS = 1          % readback period while Auto refresh is ticked, s
    end

    properties (Constant, Hidden)
        Danger = [0.80 0.10 0.10]
        Go = [0.15 0.55 0.25]
        OffColour = [0.55 0.55 0.55]  % the lamp while no laser (or wavelength) is known
        DimFactor = 0.35              % the lamp's brightness while emission is off
        Modes = {'CWP', 'CWC', 'Digital', 'Analog', 'Mixed'}
        ModeLabels = {'CW:Power', 'CW:Current', 'Digital', 'Analog', 'Mixed'}
    end

    properties (Access = private)
        FoldedHeight = []     % the window's height before Details unfolded
        Listeners = {}
        Timer = []
        Closing = false
        OwnsFigure = true
        Grid = []             % the panel's main grid; its last row holds the details
        LogLines = {}
        ListDevices = @obis.listDevices
        ScanMessage = ''
        PortChosen = false    % the port was picked by hand: Connect uses it as it is
        SavePreferences = true
        Identify = []         % fcn(port) -> the laser's wavelength, for obis.findPort (tests)
    end

    methods
        function obj = LaserApp(varargin)
            visible = true;
            autoRefresh = [];
            parent = [];
            showLog = [];
            if ~isempty(varargin) && isa(varargin{1}, 'obis.Laser')
                laser = varargin{1};
                varargin(1) = [];
                owns = false;
            else
                laser = [];
                owns = true;
            end
            rest = {};
            for k = 1:2:numel(varargin)
                switch lower(char(varargin{k}))
                    case 'visible'
                        visible = logical(varargin{k + 1});
                    case 'autorefresh'
                        autoRefresh = logical(varargin{k + 1});
                    case 'parent'
                        parent = varargin{k + 1};
                    case 'showlog'
                        showLog = logical(varargin{k + 1});
                    case 'listdevices'
                        obj.ListDevices = varargin{k + 1};
                    case 'identify'
                        obj.Identify = varargin{k + 1};
                    case 'savepreferences'
                        obj.SavePreferences = logical(varargin{k + 1});
                    case 'calibration'
                        obj.Calibration = varargin{k + 1};
                    case 'calibrationlabel'
                        obj.CalibrationLabel = char(varargin{k + 1});
                    otherwise
                        rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if owns
                laser = obis.Laser(rest{:});
            elseif ~isempty(rest)
                error('obis:LaserApp:invalidOption', ['Only ''Visible'', ''AutoRefresh'', ' ...
                    '''Parent'', ''ShowLog'', ''ListDevices'', ''Identify'', ' ...
                    '''SavePreferences'', ''Calibration'' and ''CalibrationLabel'' can be ' ...
                    'given when attaching to an existing laser.']);
            end
            if isempty(autoRefresh)
                autoRefresh = owns;
            end
            if isempty(showLog)
                showLog = isempty(parent);
            end
            obj.Laser = laser;
            obj.OwnsLaser = owns;
            obj.Pulser = obis.Pulser(laser);
            obj.build(parent, visible, autoRefresh, showLog);
            ref = matlab.lang.WeakReference(obj);
            names = {'StateChanged', 'CommandCompleted'};
            for k = 1:numel(names)
                obj.Listeners{end + 1} = addlistener(laser, names{k}, ...
                    @(~, ~) obis.gui.LaserApp.onLaserEvent(ref));
            end
            obj.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', obj.RefreshS, ...
                'BusyMode', 'drop', 'Name', 'obis.gui.LaserApp', ...
                'TimerFcn', @(~, ~) obis.gui.LaserApp.onTimer(ref));
            if autoRefresh
                start(obj.Timer);
            end
            obj.refresh();
        end

        function delete(obj)
            try
                obj.close();
            catch
                % delete never throws.
            end
        end

        function close(obj)
            % close() closes the panel; an owned laser is turned off and disconnected.
            if obj.Closing
                return
            end
            obj.Closing = true;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            if ~isempty(obj.Pulser) && isvalid(obj.Pulser) && obj.Pulser.Running
                obj.Pulser.stop();  % no pulsing left behind (it turns emission off)
            end
            if ~isempty(obj.Pulser) && isvalid(obj.Pulser)
                delete(obj.Pulser);
            end
            cellfun(@delete, obj.Listeners);
            obj.Listeners = {};
            if obj.OwnsLaser && isvalid(obj.Laser)
                obj.Laser.disconnect();
            end
            if obj.OwnsFigure
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            elseif ~isempty(obj.Root) && isvalid(obj.Root)
                delete(obj.Root);
            end
        end

        function setCalibration(obj, cal, label)
            % setCalibration(cal, label) shows the power where cal (an obis.Calibration) was
            % measured, for the setpoint; [] hides it.
            obj.Calibration = cal;
            if nargin > 2 && ~isempty(label)
                obj.CalibrationLabel = char(label);
            end
            obj.refresh();
        end

        function lock(obj, reason)
            % lock(reason) makes the panel view only (a host's own code drives the laser).
            if nargin < 2 || isempty(reason), reason = 'locked'; end
            if obj.Pulser.Running
                obj.Pulser.stop();  % the host takes the laser over: no pulsing under it
            end
            obj.LockReason = char(reason);
            obj.refresh();
        end

        function unlock(obj)
            % unlock() gives the controls back.
            obj.LockReason = '';
            obj.refresh();
        end

        function refresh(obj)
            % refresh() redraws every control from the laser object, with no traffic.
            if obj.Closing || isempty(obj.Root) || ~isvalid(obj.Root)
                return
            end
            laser = obj.Laser;
            c = obj.Controls;
            ready = strcmp(laser.State, 'Ready');
            disconnected = strcmp(laser.State, 'Disconnected');
            c.State.Text = laser.State;
            if strcmp(laser.State, 'Faulted')
                c.State.Text = sprintf('Faulted: %s', laser.FaultReason);
            end
            c.Connect.Text = ternary(disconnected, 'Connect', 'Disconnect');
            c.Port.Enable = disconnected;
            c.Scan.Enable = disconnected;
            c.Driver.Enable = disconnected && obj.OwnsLaser;
            c.Driver.Value = laser.Driver;
            c.Wavelength.Value = max([laser.ExpectedWavelengthNm, 0]);
            c.Wavelength.Enable = disconnected && obj.OwnsLaser;
            c.DllFolder.Value = laser.DllFolder;
            c.DllFolder.Enable = disconnected && obj.OwnsLaser;
            c.Browse.Enable = c.DllFolder.Enable;
            if obis.transport.CoherentTransport.isAvailable(laser.DllFolder)
                c.DllStatus.Text = 'DLL found';
                c.DllStatus.FontColor = [0.15 0.55 0.25];
            else
                c.DllStatus.Text = 'no DLL here';
                c.DllStatus.FontColor = obj.Danger;
            end
            if ready
                c.Name.Text = laserName(laser.Identity);
                c.Identity.Text = sprintf('S/N %s   %g nm   laser limits %g-%g mW   %s', ...
                    laser.Identity.SerialNumber, laser.Identity.WavelengthNm, ...
                    laser.DeviceMinPowermW, laser.DeviceMaxPowermW, ...
                    laser.Transport.Description);
            elseif ~isempty(laser.ExpectedWavelengthNm)
                c.Name.Text = sprintf('OBIS %g nm', laser.ExpectedWavelengthNm);
                c.Identity.Text = strtrim(['Not connected. ' obj.ScanMessage]);
            else
                c.Name.Text = 'OBIS laser';
                c.Identity.Text = strtrim(['Not connected. ' obj.ScanMessage]);
            end
            if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.Name = c.Name.Text;
            end
            for name = {'Start', 'Mode', 'MaxPower', 'Power', 'PowerDown', 'PowerUp', ...
                    'PowerSlider', 'Step', 'Readback'}
                c.(name{1}).Enable = ready;
            end
            pulsing = obj.Pulser.Running;
            c.Pulse.Enable = ~pulsing;  % settings fixed while it runs
            c.Frequency.Enable = ~pulsing;
            c.Duty.Enable = ~pulsing;
            if ~isempty(laser.MaxPowermW)
                top = max(laser.MaxPowermW, eps);
                c.MaxPower.Value = laser.MaxPowermW;
                c.Power.Limits = [0, top];
                c.PowerSlider.Limits = [0, top];
            end
            if ~isempty(laser.Mode)
                c.Mode.Value = char(laser.Mode);
            end
            if ~isempty(laser.CommandedPowermW)
                power = min(laser.CommandedPowermW, c.Power.Limits(2));
                c.Power.Value = power;
                c.PowerSlider.Value = power;
                c.Percent.Text = percentText(laser.CommandedPowermW, laser.DeviceMaxPowermW);
            end
            c.Connect.Enable = true;  % back after unlock
            if ~isempty(obj.LockReason)  % view only; Stop (emission off) stays, for safety
                for name = {'Connect', 'Start', 'Mode', 'MaxPower', 'Power', 'PowerDown', ...
                        'PowerUp', 'PowerSlider', 'Step', 'Port', 'Scan', 'Driver', ...
                        'Wavelength', 'DllFolder', 'Browse', 'Pulse', 'Frequency', 'Duty'}
                    c.(name{1}).Enable = false;
                end
                c.State.Text = sprintf('%s (view only: %s)', c.State.Text, obj.LockReason);
            end
            on = laser.IsEnabled && ready;
            c.EmissionLamp.Color = obj.lampColour(on);
            c.Start.Text = ternary(on, 'Emitting', 'Start');
            if obj.Pulser.Running
                c.Start.Text = 'Pulsing';
            end
            obj.showPulse();
            obj.showObjective();
            obj.showHeader();
            obj.showLog();
        end

        function showDetails(obj, tf)
            % showDetails(tf) unfolds (true) or folds away (false) the readback and the log.
            tf = logical(tf);
            c = obj.Controls;
            wasOpen = logical(c.DetailsArea.Visible);  % already as asked: the window stays
            c.Details.Value = tf;
            c.Details.Text = [char(ternary(tf, 9662, 9656)) '  Details'];
            c.DetailsArea.Visible = tf;
            extra = ternary(isempty(c.Log), 220, 380);  % px the details take
            obj.Grid.RowHeight{end} = ternary(tf, ternary(isempty(c.Log), 'fit', '1x'), 0);
            if obj.OwnsFigure && tf ~= wasOpen && ~isempty(obj.Figure) && isvalid(obj.Figure)
                position = obj.Figure.Position;
                top = position(2) + position(4);
                if tf
                    obj.FoldedHeight = position(4);  % to fold back to exactly this
                    height = position(4) + extra;
                elseif ~isempty(obj.FoldedHeight)
                    height = obj.FoldedHeight;
                else
                    height = position(4) - extra;
                end
                % grows downwards, keeping the title bar where it is, all on the screen
                obj.Figure.Position = onScreen([position(1), top - height, position(3), height]);
            end
        end

        function readback(obj)
            % readback() asks the laser for its live values and shows them.
            if ~strcmp(obj.Laser.State, 'Ready') || obj.Laser.IsBusy
                return
            end
            obj.guard(@() obj.doReadback());
        end
    end

    methods (Access = private)
        function build(obj, parent, visible, autoRefresh, showLog)
            % Lays out the panel, in a window of its own or inside parent.
            if isempty(parent)
                fig = uifigure('Name', 'OBIS laser', 'Position', onScreen([100 Inf 640 300]), ...
                    'Visible', matlab.lang.OnOffSwitchState(visible), ...
                    'CloseRequestFcn', @(~, ~) obj.close(), ...
                    'KeyPressFcn', @(~, evt) obj.onKey(evt));
                obj.Figure = fig;
                obj.OwnsFigure = true;
                root = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0]);
            else
                obj.Figure = ancestor(parent, 'figure');
                obj.OwnsFigure = false;
                root = uipanel(parent, 'Title', 'OBIS laser', 'FontWeight', 'bold');
                if ~isa(parent, 'matlab.ui.container.GridLayout')
                    root.Units = 'normalized';
                    root.Position = [0 0 1 1];
                end
            end
            obj.Root = root;
            % The last row holds the details (connection, readback, log), folded away until
            % Details opens
            rows = {'fit', 'fit', 'fit', 'fit', 0};
            grid = uigridlayout(root, [numel(rows) 1], 'RowHeight', rows, 'RowSpacing', 6);
            obj.Grid = grid;

            % Header: the laser, what it is doing, Start and Stop
            row = uigridlayout(grid, [1 6], 'ColumnWidth', {20, 'fit', '1x', 'fit', 75, 75}, ...
                'Padding', [0 0 0 0]);
            c.EmissionLamp = uilamp(row, 'Color', obj.OffColour);
            c.Name = uilabel(row, 'Text', 'OBIS laser', 'FontSize', 16, 'FontWeight', 'bold');
            c.Readout = uilabel(row, 'Text', '', 'HorizontalAlignment', 'center', ...
                'FontWeight', 'bold');
            c.State = uilabel(row, 'Text', 'Disconnected');
            c.Start = uibutton(row, 'Text', 'Start', 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'BackgroundColor', obj.Go, ...
                'ButtonPushedFcn', @(~, ~) obj.onStart());
            c.Stop = uibutton(row, 'Text', 'Stop', 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], 'BackgroundColor', obj.Danger, ...
                'Tooltip', 'Emission off, in any state (Esc)', ...
                'ButtonPushedFcn', @(~, ~) obj.onStop());

            % Connect (it finds the port first) and what is connected
            row = uigridlayout(grid, [1 2], 'ColumnWidth', {90, '1x'}, 'Padding', [0 0 0 0]);
            c.Connect = uibutton(row, 'Text', 'Connect', 'Tooltip', ['Find the laser''s ' ...
                'port and connect (the port can be chosen under Details)'], ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.Identity = uilabel(row, 'Text', 'Not connected', 'WordWrap', 'on', ...
                'FontColor', [0.45 0.45 0.45]);

            panel = uipanel(grid, 'Title', 'Operating power');
            inner = uigridlayout(panel, [6 6], 'ColumnWidth', {'fit', 34, 80, 34, 'fit', '1x'}, ...
                'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'});
            uilabel(inner, 'Text', 'Power (mW)');
            c.PowerDown = uibutton(inner, 'Text', char(9660), 'Tooltip', 'Down by Step', ...
                'ButtonPushedFcn', @(~, ~) obj.onStep(-1));
            c.Power = uieditfield(inner, 'numeric', 'Limits', [0 1], ...
                'ValueDisplayFormat', '%.2f', ...
                'ValueChangedFcn', @(src, ~) obj.applyPower(src.Value));
            c.PowerUp = uibutton(inner, 'Text', char(9650), 'Tooltip', 'Up by Step', ...
                'ButtonPushedFcn', @(~, ~) obj.onStep(1));
            uilabel(inner, 'Text', 'Step (mW)');
            c.Step = uieditfield(inner, 'numeric', 'Value', 1, 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off');
            c.Percent = uilabel(inner, 'Text', '');
            c.PowerSlider = uislider(inner, 'Limits', [0 1], ...
                'ValueChangedFcn', @(src, ~) obj.applyPower(src.Value));
            c.PowerSlider.Layout.Column = [2 6];
            uilabel(inner, 'Text', 'Max power (mW)');
            c.MaxPower = uieditfield(inner, 'numeric', 'Limits', [0 Inf], ...
                'Tooltip', 'Your limit: power above it is refused', ...
                'ValueChangedFcn', @(src, ~) obj.onMaxPower(src.Value));
            c.MaxPower.Layout.Column = [2 3];
            note = uilabel(inner, 'Text', 'your limit; the slider ends here', ...
                'FontColor', [0.45 0.45 0.45]);
            note.Layout.Column = [4 6];
            uilabel(inner, 'Text', 'Mode');
            c.Mode = uidropdown(inner, 'Items', obj.ModeLabels, 'ItemsData', obj.Modes, ...
                'ValueChangedFcn', @(src, ~) obj.onMode(src.Value));
            c.Mode.Layout.Column = [2 4];
            c.Pulse = uicheckbox(inner, 'Text', 'Pulse', 'Value', false, ...
                'Tooltip', ['Start switches emission on and off at this frequency and duty ' ...
                '(from MATLAB: a few ms of jitter)'], 'ValueChangedFcn', @(~, ~) obj.refresh());
            c.Pulse.Layout.Row = 5;
            c.Pulse.Layout.Column = 1;
            c.Frequency = uieditfield(inner, 'numeric', 'Value', obj.Pulser.FrequencyHz, ...
                'Limits', [0 obis.Pulser.MaxFrequencyHz], 'LowerLimitInclusive', 'off', ...
                'ValueDisplayFormat', '%g Hz', 'Tooltip', 'Pulses per second', ...
                'ValueChangedFcn', @(src, ~) obj.onPulseSetting('FrequencyHz', src));
            c.Frequency.Layout.Row = 5;
            c.Frequency.Layout.Column = [2 3];
            c.Duty = uieditfield(inner, 'numeric', 'Value', obj.Pulser.DutyPercent, ...
                'Limits', [0 100], 'ValueDisplayFormat', '%g %%', ...
                'Tooltip', 'Share of each period with emission on', ...
                'ValueChangedFcn', @(src, ~) obj.onPulseSetting('DutyPercent', src));
            c.Duty.Layout.Row = 5;
            c.Duty.Layout.Column = [4 5];
            c.PulseInfo = uilabel(inner, 'Text', '', 'FontColor', [0.45 0.45 0.45]);
            c.PulseInfo.Layout.Row = 5;
            c.PulseInfo.Layout.Column = 6;
            c.Objective = uilabel(inner, 'Text', '', 'FontWeight', 'bold', 'WordWrap', 'on');
            c.Objective.UserData = c.Objective.FontColor;  % the theme's, restored after a warning
            c.Objective.Layout.Row = 6;
            c.Objective.Layout.Column = [1 6];

            c.Details = uibutton(grid, 'state', 'Text', [char(9656) '  Details'], ...
                'Value', false, 'HorizontalAlignment', 'left', ...
                'Tooltip', 'Show or hide the connection, the readback and the log', ...
                'ValueChangedFcn', @(src, ~) obj.showDetails(src.Value));
            if showLog
                details = uigridlayout(grid, [3 1], 'RowHeight', {'fit', 'fit', '1x'}, ...
                    'Padding', [0 0 0 0], 'Visible', 'off');
            else
                details = uigridlayout(grid, [2 1], 'RowHeight', {'fit', 'fit'}, ...
                    'Padding', [0 0 0 0], 'Visible', 'off');
            end
            c.DetailsArea = details;

            panel = uipanel(details, 'Title', 'Connection');
            inner = uigridlayout(panel, [3 5], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', ...
                'fit'}, 'RowHeight', {'fit', 'fit', 'fit'});
            uilabel(inner, 'Text', 'Wavelength (nm)');
            c.Wavelength = uieditfield(inner, 'numeric', 'Limits', [0 Inf], 'Value', 0, ...
                'Tooltip', ['With several lasers, the one this panel is for (0: any). ' ...
                'Connect then finds its port.'], ...
                'ValueChangedFcn', @(src, ~) obj.onWavelength(src.Value));
            note = uilabel(inner, 'Text', '0: any laser', 'FontColor', [0.45 0.45 0.45]);
            note.Layout.Column = [3 5];
            uilabel(inner, 'Text', 'Port');
            c.Port = uidropdown(inner, 'Editable', 'on', 'Items', {''}, 'Value', '', ...
                'ValueChangedFcn', @(~, ~) obj.onPortChosen());
            c.Scan = uibutton(inner, 'Text', 'Scan', 'Tooltip', ['List the ports and select ' ...
                'the OBIS laser''s'], 'ButtonPushedFcn', @(~, ~) obj.onScan());
            uilabel(inner, 'Text', 'Driver');
            c.Driver = uidropdown(inner, 'Items', {'Coherent DLL', 'serialport'}, ...
                'ItemsData', {'coherent', 'serial'}, 'Value', obj.Laser.Driver, ...
                'ValueChangedFcn', @(src, ~) obj.onDriver(src.Value));
            uilabel(inner, 'Text', 'DLL folder');
            c.DllFolder = uieditfield(inner, 'text', 'Value', obj.Laser.DllFolder, ...
                'Tooltip', 'The folder holding CoherentConnectionLibrary.dll', ...
                'ValueChangedFcn', @(src, ~) obj.onDllFolder(src.Value));
            c.Browse = uibutton(inner, 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(~, ~) obj.onBrowse());
            c.DllStatus = uilabel(inner, 'Text', '');
            c.DllStatus.Layout.Column = [4 5];

            panel = uipanel(details, 'Title', 'Readback');
            inner = uigridlayout(panel, [1 3], 'ColumnWidth', {'1x', 'fit', 'fit'});
            c.ReadbackText = uilabel(inner, 'Text', '-', 'WordWrap', 'on');
            c.Readback = uibutton(inner, 'Text', 'Read now', ...
                'ButtonPushedFcn', @(~, ~) obj.readback());
            c.AutoRefresh = uicheckbox(inner, 'Text', 'Auto refresh', 'Value', autoRefresh, ...
                'ValueChangedFcn', @(src, ~) obj.onAutoRefresh(src.Value));

            if showLog
                c.Log = uitextarea(details, 'Editable', 'off', 'FontName', 'Consolas');
            else
                c.Log = [];
            end
            obj.Controls = c;
            obj.scanPorts(~isempty(obj.Laser.Port));
        end

        function onScan(obj)
            % Lists the ports again and selects the OBIS's.
            obj.PortChosen = false;
            obj.scanPorts(false);
            obj.refresh();
        end

        function findLaserPort(obj)
            % Selects the port whose laser is ExpectedWavelengthNm (obis.findPort).
            laser = obj.Laser;
            options = {'WavelengthNm', laser.ExpectedWavelengthNm, 'Driver', laser.Driver, ...
                'DllFolder', laser.DllFolder, 'ListDevices', obj.ListDevices};
            if ~isempty(obj.Identify)
                options = [options, {'Identify', obj.Identify}];
            end
            port = obis.findPort(options{:});
            obj.scanPorts(false);  % the list, and the note on what was found
            items = obj.Controls.Port.Items;
            if ~ismember(port, items)
                obj.Controls.Port.Items = [items, {port}];
            end
            obj.Controls.Port.Value = port;
            obj.ScanMessage = sprintf('Found the %g nm laser on %s.', ...
                laser.ExpectedWavelengthNm, port);
        end

        function onWavelength(obj, nm)
            % The laser this panel is for (0: any).
            if nm == 0
                nm = [];
            end
            obj.guard(@() setProperty(obj.Laser, 'ExpectedWavelengthNm', nm));
            obj.refresh();
        end

        function onPortChosen(obj)
            % A port picked by hand: Connect uses it without scanning.
            obj.PortChosen = true;
        end

        function onDllFolder(obj, folder)
            % Uses folder for the DLL; with the DLL there, the DLL driver too. Kept for
            % next time (setpref) unless SavePreferences is false.
            folder = strtrim(char(folder));
            if ~obj.guard(@() setProperty(obj.Laser, 'DllFolder', folder))
                obj.refresh();
                return
            end
            if obis.transport.CoherentTransport.isAvailable(folder)
                obj.guard(@() setProperty(obj.Laser, 'Driver', 'coherent'));
                if obj.SavePreferences
                    setpref('obis', 'DllFolder', folder);
                end
            end
            obj.refresh();
        end

        function onBrowse(obj)
            % Asks for the folder holding CoherentConnectionLibrary.dll.
            start = obj.Laser.DllFolder;
            if ~isfolder(start)
                start = pwd;
            end
            folder = uigetdir(start, 'Folder holding CoherentConnectionLibrary.dll');
            if ~isequal(folder, 0)
                obj.onDllFolder(folder);
            end
        end

        function scanPorts(obj, keepPort)
            % Lists the ports and selects the laser's own (keepPort), else the OBIS's found.
            try
                devices = obj.ListDevices();
            catch err
                devices = table({}, false(0, 1), false(0, 1), {}, {}, 'VariableNames', ...
                    {'Port', 'Available', 'IsObis', 'Description', 'Idn'});
                obj.ScanMessage = sprintf('Could not list the ports: %s', err.message);
            end
            items = cellstr(devices.Port(:)');
            found = devices(devices.IsObis, :);
            if keepPort
                port = obj.Laser.Port;
                obj.ScanMessage = '';
            elseif isempty(found)
                port = obj.Controls.Port.Value;
                if isempty(port) && ~isempty(items)
                    port = items{1};
                end
                if isempty(devices.Port)
                    obj.ScanMessage = 'No serial ports: is the laser plugged in and on?';
                else
                    obj.ScanMessage = ['No OBIS found among the ports (an OBIS Remote or a ' ...
                        'USB-serial adapter is not recognised): choose its port.'];
                end
            else
                allFound = found;
                free = found(found.Available, :);
                if ~isempty(free)
                    found = free;
                end
                port = found.Port{1};
                obj.ScanMessage = sprintf('Found %s.', describe(found.Port{1}, ...
                    found.Description{1}));
                if height(allFound) > 1
                    obj.ScanMessage = sprintf(['%s %d OBIS ports found (%s): check it is ' ...
                        'the right one.'], obj.ScanMessage, height(allFound), ...
                        strjoin(allFound.Port, ', '));
                end
                if ~found.Available(1)
                    obj.ScanMessage = [obj.ScanMessage ' It is in use by another program ' ...
                        '(close Coherent Connection).'];
                end
            end
            if ~isempty(port) && ~ismember(port, items)
                items{end + 1} = port;
            end
            if isempty(items)
                items = {''};
                port = '';
            end
            obj.Controls.Port.Items = items;
            obj.Controls.Port.Value = port;
        end

        function onDriver(obj, driver)
            % Chooses how the port is opened at the next Connect.
            obj.guard(@() setProperty(obj.Laser, 'Driver', driver));
            obj.refresh();
        end

        function onConnect(obj)
            % Finds the port (unless picked by hand) and connects; disconnects when connected.
            laser = obj.Laser;
            if strcmp(laser.State, 'Disconnected')
                if ~obj.PortChosen && ~isempty(laser.ExpectedWavelengthNm)
                    if ~obj.guard(@() obj.findLaserPort())
                        obj.refresh();
                        return
                    end
                elseif ~obj.PortChosen
                    obj.scanPorts(false);
                end
                obj.guard(@() connectTo(laser, obj.Controls.Port.Value, ...
                    isa(laser.Transport, 'obis.transport.SimulatedTransport')));
            else
                laser.disconnect();
            end
            obj.refresh();
            obj.readback();
        end

        function onStart(obj)
            % Emission on, or pulsing while Pulse is ticked.
            if obj.Controls.Pulse.Value
                obj.guard(@() obj.Pulser.start());
            else
                obj.guard(@() obj.Laser.setEnabled(true));
            end
            obj.refresh();
        end

        function onPulseSetting(obj, name, src)
            % A frequency or duty typed; a refusal puts the last one back.
            if ~obj.guard(@() setProperty(obj.Pulser, name, src.Value))
                src.Value = obj.Pulser.(name);
            end
            obj.refresh();
        end

        function showPulse(obj)
            % The on and off times, or why they cannot be.
            c = obj.Controls;
            p = obj.Pulser;
            try
                p.check();
                if p.DutyPercent == 0
                    c.PulseInfo.Text = 'off throughout';
                elseif p.DutyPercent == 100
                    c.PulseInfo.Text = 'on throughout';
                else
                    c.PulseInfo.Text = sprintf('on %.0f ms, off %.0f ms', 1000 * p.OnS, ...
                        1000 * p.OffS);
                end
                c.PulseInfo.FontColor = [0.45 0.45 0.45];
            catch
                c.PulseInfo.Text = sprintf('phases under %g ms', 1000 * p.MinPhaseS);
                c.PulseInfo.FontColor = obj.Danger;
            end
            if p.Running
                c.PulseInfo.Text = sprintf('%s; %d pulses', c.PulseInfo.Text, p.Cycles);
            end
        end

        function showObjective(obj)
            % The power where the calibration was measured, for the setpoint (and its average
            % while pulsing).
            c = obj.Controls;
            cal = obj.Calibration;
            setpoint = obj.Laser.CommandedPowermW;
            if isempty(cal)
                c.Objective.Text = '';
                return
            end
            if isempty(setpoint)
                c.Objective.Text = sprintf('%s: - (no setpoint yet)', obj.CalibrationLabel);
                return
            end
            try
                power = cal.powerFor(setpoint);
                text = sprintf('%s: %.3g mW   (laser setpoint %.1f mW)', obj.CalibrationLabel, ...
                    power, setpoint);
                duty = obj.Pulser.DutyPercent;
                if c.Pulse.Value && duty < 100
                    text = sprintf('%s;  average %.3g mW at %g %%', text, power * duty / 100, duty);
                end
                c.Objective.FontColor = c.Objective.UserData;
            catch
                text = sprintf(['%s: outside the calibration (laser setpoints %.1f to %.1f mW ' ...
                    'measured)'], obj.CalibrationLabel, cal.SetpointmW(1), cal.SetpointmW(end));
                c.Objective.FontColor = obj.Danger;
            end
            c.Objective.Text = text;
        end

        function onStop(obj)
            % Emission off, whatever else is happening.
            if obj.Pulser.Running
                obj.Pulser.stop();
            end
            if ~obj.Laser.stopAll() && ~strcmp(obj.Laser.State, 'Disconnected')
                obj.showError('Stop was not confirmed by the laser. Check it by eye.');
            end
            obj.refresh();
        end

        function onStep(obj, direction)
            % One Step down (-1) or up (+1) from the power shown.
            target = obj.Controls.Power.Value + direction * obj.Controls.Step.Value;
            obj.applyPower(min(max(target, 0), obj.Controls.Power.Limits(2)));
        end

        function applyPower(obj, mW)
            % Sends a power at once; a refusal puts the last accepted one back.
            obj.guard(@() obj.Laser.setPower(mW));
            obj.refresh();
        end

        function onMode(obj, mode)
            % Sends the chosen mode at once; a refusal puts the last one back.
            obj.guard(@() obj.Laser.setMode(mode));
            obj.refresh();
        end

        function onMaxPower(obj, value)
            % Changes your limit (no traffic).
            obj.guard(@() setProperty(obj.Laser, 'MaxPowermW', value));
            obj.refresh();
        end

        function onKey(obj, evt)
            % Esc is Stop.
            if strcmp(evt.Key, 'escape')
                obj.onStop();
            end
        end

        function onAutoRefresh(obj, tf)
            % Starts or stops the readback timer.
            if tf && strcmp(obj.Timer.Running, 'off')
                start(obj.Timer);
            elseif ~tf && strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
            end
        end

        function doReadback(obj)
            % One status() read, shown in the Readback panel and the header.
            s = obj.Laser.status();
            obj.LastStatus = s;
            obj.Controls.ReadbackText.Text = sprintf(['%s, %s   setpoint %.2f mW   output ' ...
                '%.2f mW   %.1f C   status %s   fault %s'], ternary(s.IsEnabled, 'on', ...
                'off'), char(s.Mode), s.SetpointmW, s.OutputmW, s.BaseplateC, s.StatusCode, ...
                s.FaultCode);
            obj.showHeader();
        end

        function colour = lampColour(obj, on)
            % The laser's wavelength colour: full while emitting, dimmed while off, grey
            % when no wavelength is known (nothing connected and none expected).
            laser = obj.Laser;
            nm = NaN;
            if strcmp(laser.State, 'Ready')
                nm = laser.Identity.WavelengthNm;
            elseif ~isempty(laser.ExpectedWavelengthNm)
                nm = laser.ExpectedWavelengthNm;
            end
            if isnan(nm)
                colour = obj.OffColour;
            elseif on
                colour = obis.gui.LaserApp.wavelengthColour(nm);
            else
                colour = obj.DimFactor * obis.gui.LaserApp.wavelengthColour(nm);
            end
        end

        function showHeader(obj)
            % The header's readout: output (last read, else the setpoint) and mode.
            laser = obj.Laser;
            c = obj.Controls;
            if ~strcmp(laser.State, 'Ready')
                c.Readout.Text = '';
                return
            end
            s = obj.LastStatus;
            if ~isempty(s)
                power = sprintf('%.1f mW', s.OutputmW);
            elseif ~isempty(laser.CommandedPowermW)
                power = sprintf('set %.1f mW', laser.CommandedPowermW);
            else
                power = '';
            end
            mode = '';
            if ~isempty(laser.Mode)
                mode = obj.ModeLabels{strcmp(obj.Modes, char(laser.Mode))};
            end
            c.Readout.Text = sprintf('%s   %s', power, mode);
        end

        function ok = guard(obj, action)
            % Runs a user action; an error is shown, not thrown.
            ok = false;
            try
                action();
                ok = true;
            catch err
                obj.showError(err.message);
            end
        end

        function showError(obj, message)
            % Shows an error in the log and, when the panel is visible, as an alert.
            obj.LastError = message;
            obj.LogLines{end + 1} = ['ERROR: ' message];
            obj.showLog();
            fig = obj.Figure;
            if ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible, 'on')
                try
                    uialert(fig, message, 'OBIS laser');
                catch
                    warndlg(message, 'OBIS laser');  % a host figure that takes no uialert
                end
            end
        end

        function showLog(obj)
            % The last commands from the laser's log, newest last, with errors shown here.
            if isempty(obj.Controls.Log)
                return
            end
            entries = obj.Laser.log();
            lines = {};
            first = max(1, height(entries) - 30);
            for k = first:height(entries)
                lines{end + 1} = sprintf('%8.2f  %-44s %s', entries.Time(k), ...
                    entries.Command{k}, entries.Reply{k}); %#ok<AGROW>
            end
            obj.Controls.Log.Value = [lines, obj.LogLines(max(1, end - 5):end)];
        end
    end

    methods (Static)
        function rgb = wavelengthColour(nm)
            % rgb = obis.gui.LaserApp.wavelengthColour(nm) is the colour of light of nm.
            %
            %   Visible light (380-780 nm) after Bruton's approximation, gamma 0.8, dimmed
            %   towards both ends where the eye sees less. Outside it, the nearest end's
            %   colour, so a UV or IR laser still gets a lamp that can be seen.
            nm = min(max(nm, 380), 780);
            if nm < 440
                rgb = [(440 - nm) / 60, 0, 1];
            elseif nm < 490
                rgb = [0, (nm - 440) / 50, 1];
            elseif nm < 510
                rgb = [0, 1, (510 - nm) / 20];
            elseif nm < 580
                rgb = [(nm - 510) / 70, 1, 0];
            elseif nm < 645
                rgb = [1, (645 - nm) / 65, 0];
            else
                rgb = [1, 0, 0];
            end
            if nm < 420
                factor = 0.3 + 0.7 * (nm - 380) / 40;
            elseif nm > 700
                factor = 0.3 + 0.7 * (780 - nm) / 80;
            else
                factor = 1;
            end
            % keeps a little light at the ends, so the lamp is never black
            rgb = max((factor * rgb) .^ 0.8, 0.1);
        end
    end

    methods (Static, Hidden)
        function onLaserEvent(ref)
            % A laser event redraws the panel, if it still exists.
            app = ref.Handle;
            if ~isempty(app) && isvalid(app)
                app.refresh();
            end
        end

        function onTimer(ref)
            % The readback timer; never throws into the timer.
            try
                app = ref.Handle;
                if ~isempty(app) && isvalid(app)
                    app.readback();
                end
            catch
                % A failed readback is in the laser's log; the next tick tries again.
            end
        end
    end
end


function connectTo(laser, port, simulated)
% Connects laser on port (a simulated laser keeps its own transport).
if ~simulated
    laser.Port = port;
end
laser.connect();
end


function text = describe(port, name)
% 'COM15 (Coherent OBIS Device)', or the port alone when Windows gives no name.
text = port;
name = strtrim(erase(name, ['(' port ')']));
if ~isempty(name)
    text = sprintf('%s (%s)', port, name);
end
end


function name = laserName(identity)
% The model, or 'OBIS 489 nm' behind an OBIS Remote, whose MODel? names the controller.
name = identity.Model;
if isempty(name) || contains(name, 'CONTROLLER', 'IgnoreCase', true)
    name = sprintf('OBIS %g nm', identity.WavelengthNm);
end
end


function setProperty(object, name, value)
% Sets a property, for guard.
object.(name) = value;
end


function text = percentText(mW, deviceMaxmW)
% The power as a share of the laser's own maximum.
text = '';
if ~isempty(deviceMaxmW) && deviceMaxmW > 0
    text = sprintf('%.1f%% of the laser''s max', 100 * mW / deviceMaxmW);
end
end


function value = ternary(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end


function position = onScreen(position)
% position [x y width height] moved, and shortened if need be, so that the whole window,
% title bar included, is on the screen (above the taskbar).
screen = get(groot, 'ScreenSize');
topMargin = 40;     % the title bar
bottomMargin = 50;  % the taskbar
position(4) = min(position(4), screen(4) - topMargin - bottomMargin);
position(2) = min(position(2), screen(4) - topMargin - position(4));
position(2) = max(position(2), bottomMargin);
end
