classdef LaserTest < matlab.unittest.TestCase
% LaserTest checks obis.Laser's connection, commands, limits, faults and records.
%
%   Runs on obis.transport.SimulatedTransport only; no hardware is touched.
%
% See also obis.Laser, obis.transport.SimulatedTransport

    properties
        Transport
        Laser
    end

    methods (TestMethodSetup)
        function makeLaser(testCase)
            testCase.Transport = obis.transport.SimulatedTransport();
            testCase.Laser = obis.Laser('Transport', testCase.Transport, 'TimeoutS', 0.2);
            testCase.addTeardown(@() delete(testCase.Laser));
        end
    end

    methods (Test)
        %% Connection

        function constructorTouchesNothing(testCase)
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.verifyEqual(testCase.Laser.State, 'Disconnected');
        end

        function aWrongLaserIsRefusedBeforeAnyCommand(testCase)
            laser = obis.Laser('Transport', testCase.Transport, 'ExpectedWavelengthNm', 488);
            testCase.verifyError(@() laser.connect(), 'obis:Laser:wrongLaser');
            testCase.verifyEqual(laser.State, 'Disconnected');
            testCase.verifyFalse(testCase.Transport.isOpen());
            sent = {testCase.Transport.Calls.Line};
            commands = sent(~endsWith(sent, '?') & ~strcmp(sent, 'SYST:COMM:HAND ON'));
            testCase.verifyEmpty(commands);
        end

        function theExpectedLaserConnects(testCase)
            laser = obis.Laser('Transport', testCase.Transport, 'ExpectedWavelengthNm', 561);
            laser.connect();
            testCase.addTeardown(@() laser.disconnect());
            testCase.verifyEqual(laser.State, 'Ready');
            testCase.verifyError(@() setExpected(laser, 488), 'obis:Laser:portLocked');
        end

        function expectedWavelengthIsChecked(testCase)
            testCase.verifyError(@() obis.Laser('ExpectedWavelengthNm', -5), ...
                'obis:Laser:badValue');
            laser = obis.Laser('ExpectedWavelengthNm', 488);
            laser.ExpectedWavelengthNm = [];
            testCase.verifyEmpty(laser.ExpectedWavelengthNm);
        end

        function connectReadsIdentityAndLimitsAndTurnsEmissionOff(testCase)
            testCase.Transport.open();
            testCase.Transport.writeLine('SOURce:POWer:LEVel:IMMediate:AMPLitude 0.012');
            testCase.Transport.close();
            testCase.Transport.clearCalls();
            testCase.Laser.connect();
            laser = testCase.Laser;
            testCase.verifyEqual(laser.State, 'Ready');
            testCase.verifyEqual(laser.Identity.Model, 'OBIS 561nm LS 165mW');
            testCase.verifyEqual(laser.Identity.WavelengthNm, 561);
            testCase.verifyEqual(laser.DeviceMaxPowermW, 165, 'AbsTol', 1e-9);
            testCase.verifyEqual(laser.MaxPowermW, 165, 'AbsTol', 1e-9);
            testCase.verifyEqual(laser.CommandedPowermW, 12, 'AbsTol', 1e-9);
            testCase.verifyEqual(laser.Mode, obis.Mode.CWP);
            testCase.verifyFalse(laser.IsEnabled);
            testCase.verifyFalse(testCase.Transport.Enabled);
            lines = {testCase.Transport.Calls.Line};
            testCase.verifyEqual(lines{1}, 'SYST:COMM:HAND ON');
            testCase.verifyNotEmpty(testCase.Transport.callsOf('SOURce:AM:STATe OFF'));
        end

        function connectLeavesTheModeAsFound(testCase)
            testCase.Transport.open();
            testCase.Transport.writeLine('SOURce:AM:EXTernal DIGital');
            testCase.Transport.close();
            testCase.Laser.connect();
            testCase.verifyEqual(testCase.Laser.Mode, obis.Mode.Digital);
            testCase.verifyEqual(testCase.Transport.Mode, 'DIGITAL');
        end

        function connectWorksWhenHandshakeWasOff(testCase)
            testCase.Transport.open();
            testCase.Transport.writeLine('SYST:COMM:HAND OFF');
            testCase.Transport.close();
            testCase.Laser.connect();
            testCase.verifyEqual(testCase.Laser.State, 'Ready');
            testCase.verifyTrue(testCase.Transport.Handshake);
        end

        function connectTwiceIsHarmless(testCase)
            testCase.Laser.connect();
            count = numel(testCase.Transport.Calls);
            testCase.Laser.connect();
            testCase.verifyEqual(numel(testCase.Transport.Calls), count);
        end

        function connectWithNoPortSaysHowToGiveOne(testCase)
            laser = obis.Laser('Port', '');
            testCase.verifyError(@() laser.connect(), 'obis:Laser:noPort');
        end

        function aLimitAboveTheLasersIsRefusedAtConnect(testCase)
            laser = obis.Laser('Transport', obis.transport.SimulatedTransport(), ...
                'MaxPowermW', 500);
            testCase.verifyError(@() laser.connect(), 'obis:Laser:limitAboveDevice');
            testCase.verifyEqual(laser.State, 'Disconnected');
            testCase.verifyFalse(laser.Transport.isOpen());
        end

        function disconnectTurnsEmissionOffAndCloses(testCase)
            testCase.Laser.connect();
            testCase.Laser.setEnabled(true);
            testCase.Laser.disconnect();
            testCase.verifyFalse(testCase.Transport.Enabled);
            testCase.verifyFalse(testCase.Transport.isOpen());
            testCase.verifyEqual(testCase.Laser.State, 'Disconnected');
            testCase.Laser.disconnect();   % idempotent
        end

        function deleteTurnsEmissionOff(testCase)
            transport = obis.transport.SimulatedTransport();
            laser = obis.Laser('Transport', transport);
            laser.connect();
            laser.setEnabled(true);
            delete(laser);
            testCase.verifyFalse(transport.Enabled);
        end

        function portCannotChangeWhileConnected(testCase)
            testCase.Laser.connect();
            testCase.verifyError(@() setProperty(testCase.Laser, 'Port', 'COM9'), ...
                'obis:Laser:portLocked');
        end

        %% Commands

        function commandsNeedAConnection(testCase)
            testCase.verifyError(@() testCase.Laser.setPower(1), 'obis:Laser:notReady');
            testCase.verifyError(@() testCase.Laser.setEnabled(true), 'obis:Laser:notReady');
            testCase.verifyError(@() testCase.Laser.setMode('CWP'), 'obis:Laser:notReady');
            testCase.verifyError(@() testCase.Laser.powermW(), 'obis:Laser:notReady');
        end

        function setPowerSendsWatts(testCase)
            testCase.Laser.connect();
            testCase.Laser.setPower(12.5);
            lines = testCase.Transport.callsOf('SOURce:POWer:LEVel:IMMediate:AMPLitude 0');
            testCase.verifyEqual(lines{end}, 'SOURce:POWer:LEVel:IMMediate:AMPLitude 0.012500');
            testCase.verifyEqual(testCase.Transport.SetpointW, 0.0125, 'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.Laser.CommandedPowermW, 12.5);
            testCase.verifyEqual(testCase.Laser.setpointmW(), 12.5, 'AbsTol', 1e-6);
        end

        function powerAboveTheLimitIsRefusedAndNotSent(testCase)
            testCase.Laser.connect();
            testCase.Laser.MaxPowermW = 20;
            testCase.Transport.clearCalls();
            testCase.verifyError(@() testCase.Laser.setPower(20.001), 'obis:Laser:aboveLimit');
            testCase.verifyEmpty(testCase.Transport.Calls);
            testCase.Laser.setPower(20);
            testCase.verifyEqual(testCase.Laser.CommandedPowermW, 20);
        end

        function badPowersAreRefused(testCase)
            testCase.Laser.connect();
            for value = {-1, NaN, Inf, [1 2], 'ten'}
                testCase.verifyError(@() testCase.Laser.setPower(value{1}), ...
                    'obis:Laser:badValue');
            end
        end

        function limitCannotExceedTheLasersOwn(testCase)
            testCase.Laser.connect();
            testCase.verifyError(@() setProperty(testCase.Laser, 'MaxPowermW', 166), ...
                'obis:Laser:limitAboveDevice');
        end

        function limitCannotDropBelowTheCommandedPower(testCase)
            testCase.Laser.connect();
            testCase.Laser.setPower(30);
            testCase.verifyError(@() setProperty(testCase.Laser, 'MaxPowermW', 10), ...
                'obis:Laser:limitBelowCommanded');
            testCase.Laser.setPower(5);
            testCase.Laser.MaxPowermW = 10;
            testCase.verifyEqual(testCase.Laser.MaxPowermW, 10);
        end

        function setModeSendsEachMode(testCase)
            testCase.Laser.connect();
            for name = {'CWC', 'Digital', 'Analog', 'Mixed', 'CWP'}
                testCase.Laser.setMode(name{1});
                testCase.verifyEqual(testCase.Laser.Mode, obis.Mode.(name{1}));
                testCase.verifyEqual(testCase.Transport.Mode, obis.Mode.(name{1}).Reply);
            end
        end

        function emissionFollowsSetEnabled(testCase)
            testCase.Laser.connect();
            testCase.Laser.setPower(10);
            testCase.Laser.setEnabled(true);
            testCase.verifyTrue(testCase.Transport.Enabled);
            testCase.verifyEqual(testCase.Laser.powermW(), 10, 'AbsTol', 1e-6);
            testCase.Laser.setEnabled(false);
            testCase.verifyFalse(testCase.Transport.Enabled);
            testCase.verifyEqual(testCase.Laser.powermW(), 0);
        end

        function statusReadsEveryValue(testCase)
            testCase.Laser.connect();
            testCase.Laser.setMode('Digital');
            testCase.Laser.setPower(8);
            testCase.Laser.setEnabled(true);
            testCase.Transport.ModulationInput = 1;
            s = testCase.Laser.status();
            testCase.verifyTrue(s.IsEnabled);
            testCase.verifyEqual(s.Mode, obis.Mode.Digital);
            testCase.verifyEqual(s.SetpointmW, 8, 'AbsTol', 1e-6);
            testCase.verifyEqual(s.OutputmW, 8, 'AbsTol', 1e-6);
            testCase.verifyEqual(s.BaseplateC, 25);
            testCase.verifyEqual(s.FaultCode, '00000000');
        end

        function rawCommandsCannotSetPower(testCase)
            testCase.Laser.connect();
            testCase.verifyError(@() testCase.Laser.command( ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude 0.1'), 'obis:Laser:useSetPower');
            testCase.verifyEqual(testCase.Transport.SetpointW, 0);
            testCase.verifyEqual(testCase.Laser.query( ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude?'), '0.00000');
        end

        function rawCommandsReachTheLaser(testCase)
            testCase.Laser.connect();
            testCase.Laser.command('SOURce:AM:STATe ON');
            testCase.verifyTrue(testCase.Transport.Enabled);
            testCase.verifyEqual(testCase.Laser.query('SYSTem:INFormation:SNUMber?'), 'SIM0001');
        end

        %% Faults

        function aRefusalNamesTheLasersCode(testCase)
            testCase.Laser.connect();
            testCase.Transport.failNext('SOURce:AM:EXTernal', 'ERR-350');
            testCase.verifyError(@() testCase.Laser.setMode('Digital'), 'obis:Laser:deviceError');
            testCase.verifyEqual(testCase.Laser.Mode, obis.Mode.CWP);
            testCase.verifyEqual(testCase.Laser.State, 'Ready');
            entries = testCase.Laser.log();
            testCase.verifyEqual(entries.Reply{end}, 'ERR-350');
            testCase.verifyFalse(entries.Ok(end));
        end

        function noAnswerFaultsTheLaser(testCase)
            testCase.Laser.connect();
            testCase.Transport.hangNext('SOURce:POWer');
            testCase.verifyError(@() testCase.Laser.setPower(5), 'obis:Laser:timeout');
            testCase.verifyEqual(testCase.Laser.State, 'Faulted');
            testCase.verifyNotEmpty(testCase.Laser.FaultReason);
            testCase.verifyError(@() testCase.Laser.setPower(5), 'obis:Laser:notReady');
            testCase.verifyFalse(testCase.Laser.IsBusy);
        end

        function stopAllWorksWhenFaulted(testCase)
            testCase.Laser.connect();
            testCase.Laser.setEnabled(true);
            testCase.Transport.hangNext('SOURce:POWer');
            try
                testCase.Laser.setPower(5);
            catch
            end
            testCase.verifyTrue(testCase.Laser.stopAll());
            testCase.verifyFalse(testCase.Transport.Enabled);
        end

        function stopAllNeverThrows(testCase)
            testCase.verifyFalse(testCase.Laser.stopAll());   % never connected
            testCase.Laser.connect();
            testCase.Transport.unplug();
            testCase.verifyFalse(testCase.Laser.stopAll());
            testCase.Laser.disconnect();
            testCase.verifyEqual(testCase.Laser.State, 'Disconnected');
        end

        function aPulledCableErrorsTheCommand(testCase)
            testCase.Laser.connect();
            testCase.Transport.unplug();
            testCase.verifyError(@() testCase.Laser.setPower(1), ...
                'obis:SimulatedTransport:unplugged');
            testCase.verifyFalse(testCase.Laser.IsBusy);
        end

        %% Events and records

        function eventsFire(testCase)
            seen = {};
            l1 = addlistener(testCase.Laser, 'StateChanged', @(~, ~) note('state'));
            l2 = addlistener(testCase.Laser, 'CommandCompleted', @(~, ~) note('command'));
            cleanup = onCleanup(@() delete([l1 l2]));
            testCase.Laser.connect();
            testCase.Laser.setPower(1);
            testCase.verifyEqual(seen, {'state', 'command'});
            clear cleanup
            function note(what)
                seen{end + 1} = what;
            end
        end

        function recordIsPlainData(testCase)
            testCase.Laser.connect();
            testCase.Laser.setPower(3);
            s = testCase.Laser.record();
            testCase.verifyEqual(s.Package, 'obis');
            testCase.verifyEqual(s.Version, obis.version());
            testCase.verifyEqual(s.Mode, 'CWP');
            testCase.verifyEqual(s.CommandedPowermW, 3);
            testCase.verifyEqual(s.Connection, 'simulated OBIS');
            testCase.verifyTrue(ischar(s.Log(1).Time));
            testCase.verifyFalse(any(structfun(@isobject, s)));
        end

        function logKeepsOnlyItsCapacity(testCase)
            testCase.Laser.LogCapacity = 5;
            testCase.Laser.connect();
            for k = 1:10
                testCase.Laser.setPower(k);
            end
            entries = testCase.Laser.log();
            testCase.verifyEqual(height(entries), 5);
            testCase.verifyEqual(entries.Command{end}, ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude 0.010000');
        end

        function unknownOptionsAreRefused(testCase)
            testCase.verifyError(@() obis.Laser('Colour', 'green'), 'obis:Laser:invalidOption');
            testCase.verifyError(@() obis.Laser('Port'), 'obis:Laser:invalidOption');
        end
    end
end


function setProperty(object, name, value)
% Sets a property, for verifyError.
object.(name) = value;
end


function setExpected(laser, nm)
% Sets ExpectedWavelengthNm, for verifyError.
laser.ExpectedWavelengthNm = nm;
end
