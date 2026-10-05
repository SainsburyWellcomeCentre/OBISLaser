classdef LaserApp < handle
% obis.gui.LaserApp is the control window for an obis.Laser (programmatic uifigure).
%
%   app = obis.gui.LaserApp()              owns a new obis.Laser (real laser); closing the
%                                          window turns emission off and disconnects it
%   app = obis.gui.LaserApp('Port', 'COM15', 'Transport', t, ...)
%                                          owns an obis.Laser built with these options
%   app = obis.gui.LaserApp(laser)         attaches to an existing obis.Laser; closing the
%                                          window never disconnects it
%   app = obis.gui.LaserApp(..., 'Visible', false, 'AutoRefresh', false)
%
%   The window: port and Scan, Connect, the laser's identity and limits, Mode with Set mode,
%   Max power (your limit), Power with Set power, the Emission switch, a readback of what
%   the laser reports (every RefreshS while Auto refresh is ticked), a log, and EMISSION OFF
%   (also the Esc key). Editing Mode or Power sends nothing until its Set button; the
%   Emission switch and EMISSION OFF act at once. See docs/gui.md.
%
%   Auto refresh starts ticked for an owned laser and unticked for an attached one: a
%   protocol that sends commands from its own callbacks must not meet a readback in the
%   middle of one (obis:Laser:busy).
%
%   Properties (read-only)
%       Laser       the obis.Laser shown
%       OwnsLaser   true when the app created it
%       Figure      the uifigure
%       Controls    struct of components (for scripting and tests)
%       LastError   text of the last error shown
%       LastStatus  struct from the last readback (obis.Laser.status), or []
%
%   Methods
%       refresh()   redraw every control from the laser object (no traffic)
%       readback()  ask the laser for its live values and show them
%       close()     close the window (disconnects only an owned laser)
%
% See also obis.app, obis.Laser

    properties (SetAccess = private)
        Laser                 % the obis.Laser shown
        OwnsLaser = false     % the app created it
        Figure = []           % the uifigure
        Controls = struct()   % components, for scripting and tests
        LastError = ''        % last error shown
        LastStatus = []       % last readback
    end

    properties
        RefreshS = 1          % readback period while Auto refresh is ticked, s
    end

    properties (Constant, Hidden)
        Danger = [0.80 0.10 0.10]
        OnColour = [0.95 0.55 0.10]
        OffColour = [0.55 0.55 0.55]
    end

    properties (Access = private)
        Listeners = {}
        Timer = []
        Closing = false
        LogLines = {}
    end

    methods
        function obj = LaserApp(varargin)
            visible = true;
            autoRefresh = [];
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
                    otherwise
                        rest = [rest, varargin(k:min(k + 1, end))]; %#ok<AGROW>
                end
            end
            if owns
                laser = obis.Laser(rest{:});
            elseif ~isempty(rest)
                error('obis:LaserApp:invalidOption', ['Only ''Visible'' and ' ...
                    '''AutoRefresh'' can be given when attaching to an existing laser.']);
            end
            if isempty(autoRefresh)
                autoRefresh = owns;
            end
            obj.Laser = laser;
            obj.OwnsLaser = owns;
            obj.build(visible, autoRefresh);
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
            % close() closes the window; an owned laser is turned off and disconnected.
            if obj.Closing
                return
            end
            obj.Closing = true;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            cellfun(@delete, obj.Listeners);
            obj.Listeners = {};
            if obj.OwnsLaser && isvalid(obj.Laser)
                obj.Laser.disconnect();
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function refresh(obj)
            % refresh() redraws every control from the laser object, with no traffic.
            if obj.Closing || isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            laser = obj.Laser;
            c = obj.Controls;
            ready = strcmp(laser.State, 'Ready');
            c.State.Text = laser.State;
            if strcmp(laser.State, 'Faulted')
                c.State.Text = sprintf('Faulted: %s', laser.FaultReason);
            end
            c.Connect.Text = ternary(strcmp(laser.State, 'Disconnected'), 'Connect', ...
                'Disconnect');
            c.Port.Enable = strcmp(laser.State, 'Disconnected');
            c.Scan.Enable = c.Port.Enable;
            if ready
                c.Identity.Text = sprintf('%s   S/N %s   %g nm   limits %g-%g mW', ...
                    laser.Identity.Model, laser.Identity.SerialNumber, ...
                    laser.Identity.WavelengthNm, laser.DeviceMinPowermW, laser.DeviceMaxPowermW);
            else
                c.Identity.Text = 'Not connected';
            end
            for name = {'Mode', 'SetMode', 'MaxPower', 'Power', 'SetPower', 'Emission', ...
                    'Readback'}
                c.(name{1}).Enable = ready;
            end
            if ~isempty(laser.MaxPowermW)
                c.MaxPower.Value = laser.MaxPowermW;
                c.Power.Limits = [0, max(laser.MaxPowermW, eps)];
            end
            if ~isempty(laser.Mode) && ~c.SetMode.UserData
                c.Mode.Value = char(laser.Mode);
            end
            if ~isempty(laser.CommandedPowermW) && ~c.SetPower.UserData
                c.Power.Value = min(laser.CommandedPowermW, c.Power.Limits(2));
            end
            c.Emission.Value = ternary(laser.IsEnabled, 'On', 'Off');
            c.EmissionLamp.Color = ternary(laser.IsEnabled, obj.OnColour, obj.OffColour);
            obj.showLog();
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
        function build(obj, visible, autoRefresh)
            % Lays out the window.
            fig = uifigure('Name', 'OBIS laser', 'Position', [100 100 560 600], ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'CloseRequestFcn', @(~, ~) obj.close(), ...
                'KeyPressFcn', @(~, evt) obj.onKey(evt));
            obj.Figure = fig;
            grid = uigridlayout(fig, [6 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x', 50});

            row = uigridlayout(grid, [1 5], 'ColumnWidth', {'fit', '1x', 'fit', 'fit', '2x'}, ...
                'Padding', [0 0 0 0]);
            uilabel(row, 'Text', 'Port');
            c.Port = uidropdown(row, 'Editable', 'on', 'Items', obj.portItems(), ...
                'Value', obj.initialPort());
            c.Scan = uibutton(row, 'Text', 'Scan', 'ButtonPushedFcn', @(~, ~) obj.onScan());
            c.Connect = uibutton(row, 'Text', 'Connect', ...
                'ButtonPushedFcn', @(~, ~) obj.onConnect());
            c.State = uilabel(row, 'Text', 'Disconnected');

            c.Identity = uilabel(grid, 'Text', 'Not connected', 'WordWrap', 'on');

            panel = uipanel(grid, 'Title', 'Settings');
            inner = uigridlayout(panel, [4 4], 'ColumnWidth', {'fit', '1x', 'fit', 'fit'});
            uilabel(inner, 'Text', 'Mode');
            c.Mode = uidropdown(inner, 'Items', {'CWP', 'CWC', 'Digital', 'Analog', 'Mixed'}, ...
                'ValueChangedFcn', @(~, ~) obj.markPending('SetMode'));
            c.SetMode = uibutton(inner, 'Text', 'Set mode', 'UserData', false, ...
                'ButtonPushedFcn', @(~, ~) obj.onSetMode());
            uilabel(inner, 'Text', '');
            uilabel(inner, 'Text', 'Max power (mW)');
            c.MaxPower = uieditfield(inner, 'numeric', 'Limits', [0 Inf], ...
                'ValueChangedFcn', @(src, ~) obj.onMaxPower(src.Value));
            uilabel(inner, 'Text', 'your limit');
            uilabel(inner, 'Text', '');
            uilabel(inner, 'Text', 'Power (mW)');
            c.Power = uispinner(inner, 'Limits', [0 1], 'Step', 1, ...
                'ValueChangedFcn', @(~, ~) obj.markPending('SetPower'));
            c.SetPower = uibutton(inner, 'Text', 'Set power', 'UserData', false, ...
                'ButtonPushedFcn', @(~, ~) obj.onSetPower());
            uilabel(inner, 'Text', '');
            uilabel(inner, 'Text', 'Emission');
            c.Emission = uiswitch(inner, 'Items', {'Off', 'On'}, 'Value', 'Off', ...
                'ValueChangedFcn', @(src, ~) obj.onEmission(strcmp(src.Value, 'On')));
            c.EmissionLamp = uilamp(inner, 'Color', obj.OffColour);
            uilabel(inner, 'Text', '');

            panel = uipanel(grid, 'Title', 'Readback');
            inner = uigridlayout(panel, [1 3], 'ColumnWidth', {'1x', 'fit', 'fit'});
            c.ReadbackText = uilabel(inner, 'Text', '-');
            c.Readback = uibutton(inner, 'Text', 'Read now', ...
                'ButtonPushedFcn', @(~, ~) obj.readback());
            c.AutoRefresh = uicheckbox(inner, 'Text', 'Auto refresh', 'Value', autoRefresh, ...
                'ValueChangedFcn', @(src, ~) obj.onAutoRefresh(src.Value));

            c.Log = uitextarea(grid, 'Editable', 'off', 'FontName', 'Consolas');

            c.StopAll = uibutton(grid, 'Text', 'EMISSION OFF  (Esc)', 'FontSize', 16, ...
                'FontWeight', 'bold', 'FontColor', [1 1 1], 'BackgroundColor', obj.Danger, ...
                'ButtonPushedFcn', @(~, ~) obj.onStopAll());
            obj.Controls = c;
        end

        function items = portItems(~)
            % The serial ports Windows offers now.
            try
                items = cellstr(serialportlist("all"));
            catch
                items = {};
            end
            if isempty(items)
                items = {''};
            end
        end

        function port = initialPort(obj)
            % The laser's port, else the first one listed.
            port = obj.Laser.Port;
            if isempty(port)
                items = obj.portItems();
                port = items{1};
            end
        end

        function onScan(obj)
            % Lists the ports again.
            obj.Controls.Port.Items = obj.portItems();
        end

        function onConnect(obj)
            % Connects, or disconnects when connected.
            laser = obj.Laser;
            if strcmp(laser.State, 'Disconnected')
                obj.guard(@() connectTo(laser, obj.Controls.Port.Value, ...
                    isa(laser.Transport, 'obis.transport.SimulatedTransport')));
            else
                laser.disconnect();
            end
            obj.refresh();
            obj.readback();
        end

        function onSetMode(obj)
            % Sends the chosen mode.
            if obj.guard(@() obj.Laser.setMode(obj.Controls.Mode.Value))
                obj.clearPending('SetMode');
            end
        end

        function onMaxPower(obj, value)
            % Changes your limit (no traffic).
            obj.guard(@() setMaxPower(obj.Laser, value));
            obj.refresh();
        end

        function onSetPower(obj)
            % Sends the chosen power.
            if obj.guard(@() obj.Laser.setPower(obj.Controls.Power.Value))
                obj.clearPending('SetPower');
            end
        end

        function onEmission(obj, tf)
            % Turns emission on or off at once.
            obj.guard(@() obj.Laser.setEnabled(tf));
            obj.refresh();
        end

        function onStopAll(obj)
            % Emission off, whatever else is happening.
            if ~obj.Laser.stopAll() && ~strcmp(obj.Laser.State, 'Disconnected')
                obj.showError('EMISSION OFF was not confirmed by the laser. Check it by eye.');
            end
            obj.refresh();
        end

        function onKey(obj, evt)
            % Esc is EMISSION OFF.
            if strcmp(evt.Key, 'escape')
                obj.onStopAll();
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
            % One status() read, shown in the Readback panel.
            s = obj.Laser.status();
            obj.LastStatus = s;
            obj.Controls.ReadbackText.Text = sprintf(['%s, %s   setpoint %.2f mW   output ' ...
                '%.2f mW   %.1f C   status %s   fault %s'], ternary(s.IsEnabled, 'on', ...
                'off'), char(s.Mode), s.SetpointmW, s.OutputmW, s.BaseplateC, s.StatusCode, ...
                s.FaultCode);
        end

        function markPending(obj, button)
            % Shows that a Set button has a change waiting.
            obj.Controls.(button).UserData = true;
            obj.Controls.(button).FontWeight = 'bold';
        end

        function clearPending(obj, button)
            % The change was sent.
            obj.Controls.(button).UserData = false;
            obj.Controls.(button).FontWeight = 'normal';
            obj.refresh();
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
            % Shows an error in the log and, when the window is visible, as an alert.
            obj.LastError = message;
            obj.LogLines{end + 1} = ['ERROR: ' message];
            obj.showLog();
            if ~isempty(obj.Figure) && isvalid(obj.Figure) && strcmp(obj.Figure.Visible, 'on')
                uialert(obj.Figure, message, 'OBIS laser');
            end
        end

        function showLog(obj)
            % The last commands from the laser's log, newest last, with errors shown here.
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

    methods (Static, Hidden)
        function onLaserEvent(ref)
            % A laser event redraws the window, if it still exists.
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


function setMaxPower(laser, value)
% Sets the laser's MaxPowermW.
laser.MaxPowermW = value;
end


function value = ternary(condition, a, b)
% a when condition is true, else b.
if condition
    value = a;
else
    value = b;
end
end
