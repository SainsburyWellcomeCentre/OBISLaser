classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives obis.gui.LaserApp on the simulated laser, with a hidden window.
%
%   Controls are driven as a user would: set a component's Value, then call its callback.
%   Power and mode are sent as soon as they change, as in Coherent Connection.
%
% See also obis.gui.LaserApp, obis.Laser

    properties
        Transport
        App
    end

    methods (TestMethodSetup)
        function makeApp(testCase)
            testCase.Transport = obis.transport.SimulatedTransport();
            testCase.App = obis.gui.LaserApp('Transport', testCase.Transport, ...
                'Visible', false, 'AutoRefresh', false, 'SavePreferences', false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)

        function windowStaysOnTheScreen(testCase)
            screen = get(groot, 'ScreenSize');
            app = testCase.App;
            for unfolded = [false true false]
                app.showDetails(unfolded);
                position = app.Figure.Position;
                testCase.verifyGreaterThanOrEqual(position(2), 50);
                testCase.verifyLessThanOrEqual(position(2) + position(4), screen(4) - 40 + 1e-9);
            end
        end
        function opensWithoutTouchingTheLaser(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Laser.State, 'Disconnected');
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Connect');
            testCase.verifyEqual(testCase.App.Controls.Stop.Enable, ...
                matlab.lang.OnOffSwitchState('on'));
            testCase.verifyEqual(testCase.App.Controls.Start.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function connectButtonConnectsAndDisconnects(testCase)
            testCase.connectApp();
            testCase.verifyEqual(testCase.App.Laser.State, 'Ready');
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Disconnect');
            testCase.verifySubstring(testCase.App.Controls.Name.Text, 'OBIS 561nm');
            testCase.verifyNotEmpty(testCase.App.LastStatus);
            testCase.verifySubstring(testCase.App.Controls.Readout.Text, 'mW');
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual(testCase.App.Laser.State, 'Disconnected');
        end

        function pulseStartsAndStopStopsIt(testCase)
            testCase.connectApp();
            c = testCase.App.Controls;
            testCase.setValue(c.Frequency, 5);
            testCase.setValue(c.Duty, 20);
            testCase.verifySubstring(c.PulseInfo.Text, 'on 40 ms, off 160 ms');
            testCase.setValue(c.Pulse, true);
            testCase.press(c.Start);
            testCase.verifyTrue(testCase.App.Pulser.Running);
            testCase.verifyEqual(c.Start.Text, 'Pulsing');
            testCase.verifyEqual(c.Duty.Enable, matlab.lang.OnOffSwitchState('off'));
            pause(0.5);
            testCase.press(c.Stop);
            testCase.verifyFalse(testCase.App.Pulser.Running);
            testCase.verifyFalse(testCase.Transport.Enabled);
            testCase.verifyEqual(c.Duty.Enable, matlab.lang.OnOffSwitchState('on'));
        end

        function lockStopsPulsing(testCase)
            % A host taking the laser over (a session) leaves no pulsing running under it.
            testCase.connectApp();
            c = testCase.App.Controls;
            testCase.setValue(c.Pulse, true);
            testCase.press(c.Start);
            testCase.verifyTrue(testCase.App.Pulser.Running);
            testCase.App.lock('session running');
            testCase.verifyFalse(testCase.App.Pulser.Running);
            testCase.verifyFalse(testCase.Transport.Enabled);
        end

        function tooShortPhasesAreFlagged(testCase)
            c = testCase.App.Controls;
            testCase.setValue(c.Frequency, 20);
            testCase.setValue(c.Duty, 10);
            testCase.verifySubstring(c.PulseInfo.Text, 'under 20 ms');
        end

        function theCalibratedPowerIsShown(testCase)
            testCase.connectApp();
            app = testCase.App;
            app.setCalibration(obis.Calibration([10 50 100], [1 5 10]), 'Out of objective');
            testCase.setValue(app.Controls.Power, 50);
            testCase.verifySubstring(app.Controls.Objective.Text, 'Out of objective: 5 mW');
            testCase.verifySubstring(app.Controls.Objective.Text, 'laser setpoint 50.0 mW');
            testCase.setValue(app.Controls.Duty, 20);
            testCase.setValue(app.Controls.Pulse, true);
            testCase.verifySubstring(app.Controls.Objective.Text, 'average 1 mW at 20 %');
            testCase.setValue(app.Controls.Power, 120);
            testCase.verifySubstring(app.Controls.Objective.Text, 'outside the calibration');
            app.setCalibration([]);
            testCase.verifyEmpty(app.Controls.Objective.Text);
        end

        function aLockedPanelIsViewOnlyButStopWorks(testCase)
            testCase.connectApp();
            app = testCase.App;
            app.lock('session running');
            off = matlab.lang.OnOffSwitchState('off');
            for name = {'Connect', 'Start', 'Mode', 'Power', 'PowerSlider', 'MaxPower'}
                testCase.verifyEqual(app.Controls.(name{1}).Enable, off, name{1});
            end
            testCase.verifyEqual(app.Controls.Stop.Enable, matlab.lang.OnOffSwitchState('on'));
            testCase.verifySubstring(app.Controls.State.Text, 'view only: session running');
            app.refresh();  % stays locked through a redraw
            testCase.verifyEqual(app.Controls.Start.Enable, off);
            app.unlock();
            testCase.verifyEqual(app.Controls.Start.Enable, matlab.lang.OnOffSwitchState('on'));
            testCase.verifyEqual(app.Controls.Connect.Enable, matlab.lang.OnOffSwitchState('on'));
            testCase.verifyEmpty(app.LockReason);
        end

        function startAndStopSwitchEmission(testCase)
            testCase.connectApp();
            testCase.press(testCase.App.Controls.Start);
            testCase.verifyTrue(testCase.Transport.Enabled);
            testCase.verifyEqual(testCase.App.Controls.Start.Text, 'Emitting');
            testCase.press(testCase.App.Controls.Stop);
            testCase.verifyFalse(testCase.Transport.Enabled);
            testCase.verifyEqual(testCase.App.Controls.Start.Text, 'Start');
        end

        function typedPowerIsSentAtOnce(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Power, 12);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.012, 'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.App.Controls.PowerSlider.Value, 12, 'AbsTol', 1e-9);
        end

        function arrowsStepThePower(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Power, 10);
            testCase.App.Controls.Step.Value = 2.5;
            testCase.press(testCase.App.Controls.PowerUp);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.0125, 'AbsTol', 1e-12);
            testCase.press(testCase.App.Controls.PowerDown);
            testCase.press(testCase.App.Controls.PowerDown);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.0075, 'AbsTol', 1e-12);
        end

        function aStepNeverGoesBelowZero(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Power, 1);
            testCase.App.Controls.Step.Value = 5;
            testCase.press(testCase.App.Controls.PowerDown);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0, 'AbsTol', 1e-12);
        end

        function sliderSetsThePower(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.PowerSlider, 40);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.040, 'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.App.Controls.Power.Value, 40, 'AbsTol', 1e-9);
            testCase.verifySubstring(testCase.App.Controls.Percent.Text, '%');
        end

        function modeIsSentAtOnce(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Mode, 'Digital');
            testCase.verifyEqual(testCase.Transport.Mode, 'DIGITAL');
        end

        function modesAreNamedLikeCoherentConnection(testCase)
            testCase.verifyEqual(testCase.App.Controls.Mode.Items, ...
                {'CW:Power', 'CW:Current', 'Digital', 'Analog', 'Mixed'});
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Mode, 'CWC');
            testCase.verifyEqual(testCase.Transport.Mode, 'CWC');
            testCase.verifySubstring(testCase.App.Controls.Readout.Text, 'CW:Current');
        end

        function connectionControlsAreInDetails(testCase)
            c = testCase.App.Controls;
            for name = {'Port', 'Scan', 'Driver', 'DllFolder', 'Browse', 'ReadbackText'}
                testCase.verifyTrue(isDescendant(c.(name{1}), c.DetailsArea), name{1});
            end
            testCase.verifyFalse(isDescendant(c.Connect, c.DetailsArea));
            testCase.verifyFalse(isDescendant(c.Mode, c.DetailsArea));
        end

        function connectScansForThePort(testCase)
            app = testCase.appWithPorts(@() ports({'COM3', 'COM15'}, [false true]));
            app.Controls.Port.Value = 'COM3';
            % Connect scans first, so the OBIS's port is used, not the one shown
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM15');
            testCase.verifyEqual(app.Laser.State, 'Ready');
        end

        function aPortPickedByHandIsKept(testCase)
            app = testCase.appWithPorts(@() ports({'COM3', 'COM15'}, [false true]));
            testCase.setValue(app.Controls.Port, 'COM3');
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM3');
            testCase.verifyEqual(app.Laser.State, 'Ready');
        end

        function connectFindsTheLaserByWavelength(testCase)
            app = testCase.appForTwoLasers();
            testCase.setValue(app.Controls.Wavelength, 561);
            testCase.verifyEqual(app.Controls.Name.Text, 'OBIS 561 nm');
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM15');
            testCase.verifyEqual(app.Laser.State, 'Ready');
            testCase.verifyEqual(app.Controls.Wavelength.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function aWrongLaserIsShownNotConnected(testCase)
            % COM8 answers 489 nm, but the simulated laser behind it is 561 nm
            app = testCase.appForTwoLasers();
            testCase.setValue(app.Controls.Wavelength, 488);
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM8');
            testCase.verifyEqual(app.Laser.State, 'Disconnected');
            testCase.verifySubstring(app.LastError, 'not the 488 nm laser');
        end

        function aMissingWavelengthIsShown(testCase)
            app = testCase.appForTwoLasers();
            testCase.setValue(app.Controls.Wavelength, 640);
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Laser.State, 'Disconnected');
            testCase.verifySubstring(app.LastError, 'No free 640 nm');
        end

        function aControllerIsNamedByWavelength(testCase)
            transport = obis.transport.SimulatedTransport();
            transport.Model = 'OBIS MINI-CONTROLLER';
            app = obis.gui.LaserApp('Transport', transport, 'Visible', false, ...
                'AutoRefresh', false, 'SavePreferences', false);
            testCase.addTeardown(@() app.close());
            testCase.press(app.Controls.Connect);
            testCase.verifyEqual(app.Controls.Name.Text, 'OBIS 561 nm');
        end

        function lampIsTheWavelengthsColour(testCase)
            lamp = testCase.App.Controls.EmissionLamp;
            testCase.verifyEqual(lamp.Color, obis.gui.LaserApp.OffColour);  % nothing known
            testCase.connectApp();
            dim = obis.gui.LaserApp.DimFactor * obis.gui.LaserApp.wavelengthColour(561);
            testCase.verifyEqual(lamp.Color, dim, 'AbsTol', 1e-12);
            testCase.press(testCase.App.Controls.Start);
            testCase.verifyEqual(lamp.Color, obis.gui.LaserApp.wavelengthColour(561), ...
                'AbsTol', 1e-12);
            testCase.press(testCase.App.Controls.Stop);
            testCase.verifyEqual(lamp.Color, dim, 'AbsTol', 1e-12);
        end

        function anExpectedWavelengthColoursTheLampBeforeConnect(testCase)
            testCase.setValue(testCase.App.Controls.Wavelength, 488);
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                obis.gui.LaserApp.DimFactor * obis.gui.LaserApp.wavelengthColour(488), ...
                'AbsTol', 1e-12);
        end

        function wavelengthColoursLookRight(testCase)
            blue = obis.gui.LaserApp.wavelengthColour(488);
            green = obis.gui.LaserApp.wavelengthColour(561);
            red = obis.gui.LaserApp.wavelengthColour(640);
            testCase.verifyGreaterThan(blue(3), blue(1));       % 488: blue, some green
            testCase.verifyGreaterThan(green(2), green(3));     % 561: yellow-green
            testCase.verifyGreaterThan(red(1), red(3));         % 640: red
            uv = obis.gui.LaserApp.wavelengthColour(355);
            testCase.verifyTrue(all(uv >= 0.1 & uv <= 1));       % out of range: still visible
        end

        function windowTitleNamesTheLaser(testCase)
            testCase.connectApp();
            testCase.verifyEqual(testCase.App.Figure.Name, 'OBIS 561nm LS 165mW');
        end

        function dllFolderIsChosenAndChecked(testCase)
            folder = tempname;
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, 's'));
            c = testCase.App.Controls;
            testCase.setValue(c.Driver, 'serial');
            testCase.setValue(c.DllFolder, folder);
            testCase.verifyEqual(testCase.App.Laser.DllFolder, folder);
            testCase.verifyEqual(c.DllStatus.Text, 'no DLL here');
            testCase.verifyEqual(testCase.App.Laser.Driver, 'serial');
            fclose(fopen(fullfile(folder, 'CoherentConnectionLibrary.dll'), 'w'));
            testCase.setValue(c.DllFolder, folder);
            testCase.verifyEqual(c.DllStatus.Text, 'DLL found');
            testCase.verifyEqual(testCase.App.Laser.Driver, 'coherent');
        end

        function dllFolderIsLockedWhileConnected(testCase)
            testCase.connectApp();
            testCase.verifyEqual(testCase.App.Controls.DllFolder.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
            testCase.verifyEqual(testCase.App.Controls.Browse.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function maxPowerLimitsPowerAndSlider(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.MaxPower, 30);
            testCase.verifyEqual(testCase.App.Laser.MaxPowermW, 30);
            testCase.verifyEqual(testCase.App.Controls.Power.Limits, [0 30]);
            testCase.verifyEqual(testCase.App.Controls.PowerSlider.Limits, [0 30]);
        end

        function aRefusedPowerIsShownAndUndone(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Power, 10);
            testCase.App.Laser.MaxPowermW = 20;
            testCase.App.Controls.Power.Limits = [0 100];  % as if typed past the field
            testCase.setValue(testCase.App.Controls.Power, 50);
            testCase.verifySubstring(testCase.App.LastError, 'above MaxPowermW');
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.010, 'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.App.Controls.Power.Value, 10, 'AbsTol', 1e-9);
        end

        function aRefusedLimitIsShownNotThrown(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.MaxPower, 500);
            testCase.verifySubstring(testCase.App.LastError, 'above this laser');
            testCase.verifyEqual(testCase.App.Laser.MaxPowermW, 165, 'AbsTol', 1e-9);
        end

        function driverIsChosenOnlyWhileDisconnected(testCase)
            testCase.setValue(testCase.App.Controls.Driver, 'serial');
            testCase.verifyEqual(testCase.App.Laser.Driver, 'serial');
            testCase.connectApp();
            testCase.verifyEqual(testCase.App.Controls.Driver.Enable, ...
                matlab.lang.OnOffSwitchState('off'));
        end

        function escapeIsStop(testCase)
            testCase.connectApp();
            testCase.App.Laser.setEnabled(true);
            fig = testCase.App.Figure;
            fig.KeyPressFcn(fig, struct('Key', 'escape'));
            testCase.verifyFalse(testCase.Transport.Enabled);
        end

        function scriptChangesShowInTheWindow(testCase)
            testCase.connectApp();
            testCase.App.Laser.setPower(7);
            testCase.App.Laser.setEnabled(true);
            testCase.verifyEqual(testCase.App.Controls.Power.Value, 7);
            testCase.verifyEqual(testCase.App.Controls.EmissionLamp.Color, ...
                obis.gui.LaserApp.wavelengthColour(561), 'AbsTol', 1e-12);
        end

        function closingAnOwnedLaserTurnsItOff(testCase)
            testCase.connectApp();
            testCase.App.Laser.setEnabled(true);
            testCase.App.close();
            testCase.verifyFalse(testCase.Transport.Enabled);
            testCase.verifyFalse(testCase.Transport.isOpen());
        end

        function closingAnAttachedWindowLeavesTheLaser(testCase)
            transport = obis.transport.SimulatedTransport();
            laser = obis.Laser('Transport', transport);
            testCase.addTeardown(@() delete(laser));
            laser.connect();
            laser.setEnabled(true);
            app = obis.gui.LaserApp(laser, 'Visible', false);
            testCase.verifyEqual(app.Controls.AutoRefresh.Value, false);
            app.close();
            testCase.verifyEqual(laser.State, 'Ready');
            testCase.verifyTrue(transport.Enabled);
        end

        function scanSelectsTheObisPort(testCase)
            app = testCase.appWithPorts(ports({'COM3', 'COM15', 'COM14'}, [false true false]));
            testCase.verifyEqual(app.Controls.Port.Items, {'COM3', 'COM15', 'COM14'});
            testCase.verifyEqual(app.Controls.Port.Value, 'COM15');
            testCase.verifySubstring(app.Controls.Identity.Text, 'Found COM15');
        end

        function scanPrefersAFreeObisPort(testCase)
            devices = ports({'COM15', 'COM16'}, [true true]);
            devices.Available = [false; true];
            app = testCase.appWithPorts(devices);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM16');
            testCase.verifySubstring(app.Controls.Identity.Text, '2 OBIS ports');
        end

        function scanSaysWhenTheObisPortIsHeld(testCase)
            devices = ports({'COM15'}, true);
            devices.Available = false;
            app = testCase.appWithPorts(devices);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM15');
            testCase.verifySubstring(app.Controls.Identity.Text, 'Coherent Connection');
        end

        function scanWithoutAnObisKeepsTheChoice(testCase)
            app = testCase.appWithPorts(ports({'COM3', 'COM4'}, [false false]));
            app.Controls.Port.Value = 'COM4';
            testCase.press(app.Controls.Scan);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM4');
            testCase.verifySubstring(app.Controls.Identity.Text, 'No OBIS found');
        end

        function scanAgainFindsAPluggedInLaser(testCase)
            store = containers.Map();
            store('now') = ports({'COM3'}, false);
            app = testCase.appWithPorts(@() store('now'));
            testCase.verifyEqual(app.Controls.Port.Value, 'COM3');
            % store is a handle, so the lister sees this
            store('now') = ports({'COM3', 'COM15'}, [false true]); %#ok<NASGU>
            app.Controls.Scan.ButtonPushedFcn(app.Controls.Scan, []);
            testCase.verifyEqual(app.Controls.Port.Value, 'COM15');
        end

        function aGivenPortIsKeptAtOpen(testCase)
            lister = @() ports({'COM15', 'COM20'}, [true false]);
            app = obis.gui.LaserApp('Port', 'COM20', 'Visible', false, 'AutoRefresh', false, ...
                'ListDevices', lister);
            testCase.addTeardown(@() app.close());
            testCase.verifyEqual(app.Controls.Port.Value, 'COM20');
        end

        function detailsStartFoldedAndToggle(testCase)
            c = testCase.App.Controls;
            testCase.verifyFalse(c.Details.Value);
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('off'));
            testCase.verifyEqual(c.DetailsArea.Parent.RowHeight{end}, 0);
            height = testCase.App.Figure.Position(4);
            testCase.setValue(c.Details, true);
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('on'));
            testCase.verifySubstring(c.Details.Text, char(9662));
            testCase.verifyGreaterThan(testCase.App.Figure.Position(4), height);
            testCase.setValue(c.Details, false);
            testCase.verifyEqual(c.DetailsArea.Visible, matlab.lang.OnOffSwitchState('off'));
            testCase.verifyEqual(testCase.App.Figure.Position(4), height);
        end

        function foldedReadbackStillUpdates(testCase)
            testCase.connectApp();
            testCase.App.Laser.setPower(9);
            testCase.App.readback();
            testCase.verifySubstring(testCase.App.Controls.ReadbackText.Text, 'setpoint 9.00');
        end

        function embedsInAnotherWindow(testCase)
            host = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(host));
            grid = uigridlayout(host, [1 2]);
            uilabel(grid, 'Text', 'host content');
            app = obis.gui.LaserApp('Transport', obis.transport.SimulatedTransport(), ...
                'Parent', grid, 'AutoRefresh', false);
            testCase.verifyEqual(app.Figure, host);
            testCase.verifyEqual(app.Root.Parent, grid);
            testCase.verifyEmpty(app.Controls.Log);
            app.close();
            testCase.verifyTrue(isvalid(host));
            testCase.verifyFalse(isvalid(app.Root));
            testCase.verifyNumElements(grid.Children, 1);
        end

        function embedsInAClassicFigure(testCase)
            host = figure('Visible', 'off');
            testCase.addTeardown(@() delete(host));
            holder = uipanel(host, 'Units', 'pixels', 'Position', [10 10 600 440]);
            app = obis.gui.LaserApp('Transport', obis.transport.SimulatedTransport(), ...
                'Parent', holder, 'AutoRefresh', false);
            testCase.addTeardown(@() app.close());
            app.Controls.Connect.ButtonPushedFcn(app.Controls.Connect, []);
            testCase.verifyEqual(app.Laser.State, 'Ready');
        end
    end

    methods (Access = private)
        function app = appWithPorts(testCase, devices)
            % An app on a real-port laser (never connected) whose Scan sees devices.
            if isa(devices, 'function_handle')
                lister = devices;
            else
                lister = @() devices;
            end
            app = obis.gui.LaserApp('Visible', false, 'AutoRefresh', false, ...
                'ListDevices', lister, 'SavePreferences', false, ...
                'Transport', obis.transport.SimulatedTransport());
            testCase.addTeardown(@() app.close());
        end

        function app = appForTwoLasers(testCase)
            % Two Coherent ports: COM8 answers 488 nm, COM15 561 nm (the simulated laser).
            answers = containers.Map({'COM8', 'COM15'}, {'489 nm', '561 nm'});
            app = obis.gui.LaserApp('Visible', false, 'AutoRefresh', false, ...
                'ListDevices', @() ports({'COM3', 'COM8', 'COM15'}, [false true true]), ...
                'Identify', @(p) answers(p), 'SavePreferences', false, ...
                'Transport', obis.transport.SimulatedTransport());
            testCase.addTeardown(@() app.close());
        end

        function connectApp(testCase)
            % Presses Connect.
            testCase.press(testCase.App.Controls.Connect);
        end

        function press(~, button)
            % Calls a button's callback as a click would.
            button.ButtonPushedFcn(button, []);
        end

        function setValue(~, component, value)
            % Sets a component's value and calls its callback as an edit would.
            component.Value = value;
            component.ValueChangedFcn(component, []);
        end
    end
end


function devices = ports(names, isObis)
% A port table like obis.listDevices, every port free.
names = names(:);
n = numel(names);
description = repmat({''}, n, 1);
description(logical(isObis)) = {'Coherent OBIS Device'};
devices = table(names, true(n, 1), logical(isObis(:)), description, repmat({''}, n, 1), ...
    'VariableNames', {'Port', 'Available', 'IsObis', 'Description', 'Idn'});
end


function tf = isDescendant(component, ancestorComponent)
% True when component sits somewhere inside ancestorComponent.
tf = false;
node = component.Parent;
while ~isempty(node) && ~isa(node, 'matlab.ui.Figure')
    if node == ancestorComponent
        tf = true;
        return
    end
    node = node.Parent;
end
end
