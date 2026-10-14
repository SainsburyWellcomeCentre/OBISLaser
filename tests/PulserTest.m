classdef PulserTest < matlab.unittest.TestCase
% PulserTest checks obis.Pulser on the simulated laser.
%
%   Emission switched on and off at the frequency and duty asked, phases too short refused,
%   and emission off when it stops.

    properties
        Transport
        Laser
    end

    methods (TestMethodSetup)
        function connect(testCase)
            testCase.Transport = obis.transport.SimulatedTransport();
            testCase.Laser = obis.Laser('Transport', testCase.Transport);
            testCase.Laser.connect();
            testCase.addTeardown(@() testCase.Laser.disconnect());
        end
    end

    methods (Test)
        function itSwitchesEmissionOnAndOff(testCase)
            p = obis.Pulser(testCase.Laser, 'FrequencyHz', 10, 'DutyPercent', 50);
            testCase.addTeardown(@() delete(p));
            testCase.verifyEqual([p.OnS p.OffS], [0.05 0.05], 'AbsTol', 1e-12);
            testCase.Transport.clearCalls();
            p.start();
            testCase.verifyTrue(p.Running);
            pause(1.05);  % lets the timers run
            p.stop();
            lines = {testCase.Transport.Calls.Line};
            ons = nnz(contains(lines, 'AM:STATe ON', 'IgnoreCase', true));
            offs = nnz(contains(lines, 'AM:STATe OFF', 'IgnoreCase', true));
            testCase.verifyGreaterThanOrEqual(ons, 5);
            testCase.verifyGreaterThanOrEqual(offs, 5);
            testCase.verifyGreaterThanOrEqual(p.Cycles, 5);
            testCase.verifyFalse(p.Running);
            testCase.verifyFalse(testCase.Transport.Enabled);  % off at the end
        end

        function fullDutyStaysOnWithoutTimers(testCase)
            p = obis.Pulser(testCase.Laser, 'DutyPercent', 100);
            testCase.addTeardown(@() delete(p));
            p.start();
            testCase.verifyTrue(testCase.Transport.Enabled);
            testCase.verifyEmpty(timerfindall('Name', 'obis.Pulser'));
            p.stop();
            testCase.verifyFalse(testCase.Transport.Enabled);
        end

        function badSettingsAreRefused(testCase)
            p = obis.Pulser(testCase.Laser);
            testCase.addTeardown(@() delete(p));
            testCase.verifyError(@() setValue(p, 'FrequencyHz', 0), 'obis:Pulser:badValue');
            testCase.verifyError(@() setValue(p, 'FrequencyHz', 30), 'obis:Pulser:badValue');
            testCase.verifyError(@() setValue(p, 'DutyPercent', 150), 'obis:Pulser:badValue');
            p.FrequencyHz = 20;
            p.DutyPercent = 10;  % on for 5 ms: too short to switch reliably
            testCase.verifyError(@() p.start(), 'obis:Pulser:badValue');
            testCase.verifyFalse(p.Running);
        end

        function itNeedsAConnectedLaser(testCase)
            testCase.Laser.disconnect();
            p = obis.Pulser(testCase.Laser);
            testCase.addTeardown(@() delete(p));
            testCase.verifyError(@() p.start(), 'obis:Pulser:notReady');
        end

        function settingsAreFixedWhileRunning(testCase)
            p = obis.Pulser(testCase.Laser, 'FrequencyHz', 2, 'DutyPercent', 50);
            testCase.addTeardown(@() delete(p));
            p.start();
            testCase.verifyError(@() setValue(p, 'FrequencyHz', 5), 'obis:Pulser:badValue');
            p.stop();
        end
    end
end


function setValue(object, name, value)
object.(name) = value;
end
