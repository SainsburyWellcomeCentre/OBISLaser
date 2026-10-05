classdef GuiTest < matlab.unittest.TestCase
% GuiTest drives obis.gui.LaserApp on the simulated laser, with a hidden window.
%
%   Controls are driven as a user would: set a component's Value, then call its callback.
%   Mode and Power send nothing until their Set buttons.
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
                'Visible', false, 'AutoRefresh', false);
            testCase.addTeardown(@() testCase.App.close());
        end
    end

    methods (Test)
        function opensWithoutTouchingTheLaser(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.App.Laser.State, 'Disconnected');
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Connect');
            testCase.verifyEqual(testCase.App.Controls.StopAll.Enable, ...
                matlab.lang.OnOffSwitchState('on'));
        end

        function connectButtonConnectsAndDisconnects(testCase)
            testCase.connectApp();
            testCase.verifyEqual(testCase.App.Laser.State, 'Ready');
            testCase.verifyEqual(testCase.App.Controls.Connect.Text, 'Disconnect');
            testCase.verifySubstring(testCase.App.Controls.Identity.Text, 'OBIS 561nm');
            testCase.verifyNotEmpty(testCase.App.LastStatus);
            testCase.press(testCase.App.Controls.Connect);
            testCase.verifyEqual(testCase.App.Laser.State, 'Disconnected');
        end

        function powerIsSentOnlyBySetPower(testCase)
            testCase.connectApp();
            testCase.Transport.clearCalls();
            testCase.setValue(testCase.App.Controls.Power, 12);
            testCase.verifyEmpty(testCase.Transport.callsOf('SOURce:POWer:LEVel:IMM'));
            testCase.press(testCase.App.Controls.SetPower);
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.012, 'AbsTol', 1e-12);
        end

        function modeIsSentOnlyBySetMode(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Mode, 'Digital');
            testCase.verifyEqual(testCase.Transport.Mode, 'CWP');
            testCase.press(testCase.App.Controls.SetMode);
            testCase.verifyEqual(testCase.Transport.Mode, 'DIGITAL');
        end

        function maxPowerLimitsThePowerControl(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.MaxPower, 30);
            testCase.verifyEqual(testCase.App.Laser.MaxPowermW, 30);
            testCase.verifyEqual(testCase.App.Controls.Power.Limits, [0 30]);
        end

        function aRefusedLimitIsShownNotThrown(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.MaxPower, 500);
            testCase.verifySubstring(testCase.App.LastError, 'above this laser');
            testCase.verifyEqual(testCase.App.Laser.MaxPowermW, 165, 'AbsTol', 1e-9);
        end

        function emissionSwitchActsAtOnce(testCase)
            testCase.connectApp();
            testCase.setValue(testCase.App.Controls.Emission, 'On');
            testCase.verifyTrue(testCase.Transport.Enabled);
            testCase.setValue(testCase.App.Controls.Emission, 'Off');
            testCase.verifyFalse(testCase.Transport.Enabled);
        end

        function stopAllAndEscapeTurnEmissionOff(testCase)
            testCase.connectApp();
            testCase.App.Laser.setEnabled(true);
            testCase.press(testCase.App.Controls.StopAll);
            testCase.verifyFalse(testCase.Transport.Enabled);
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
            testCase.verifyEqual(testCase.App.Controls.Emission.Value, 'On');
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
    end

    methods (Access = private)
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
