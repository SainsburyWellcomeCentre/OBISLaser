classdef CoherentTransportTest < matlab.unittest.TestCase
% CoherentTransportTest checks the DLL transport without a laser: construction and refusals.
%
%   Opens only a port that does not exist (COM250), so no device is touched. The tests
%   that load the DLL are skipped where Coherent Connection is not installed.
%
% See also obis.transport.CoherentTransport

    methods (Test)
        function constructorTouchesNothing(testCase)
            t = obis.transport.CoherentTransport('COM250');
            testCase.verifyFalse(t.isOpen());
            testCase.verifySubstring(t.Description, 'COM250');
            testCase.verifyError(@() t.writeLine('*IDN?'), 'obis:CoherentTransport:notOpen');
            t.close();   % never throws, even unopened
        end

        function aMissingDllIsReportedClearly(testCase)
            t = obis.transport.CoherentTransport('COM250', 'DllFolder', tempname);
            testCase.verifyError(@() t.open(), 'obis:CoherentTransport:noDll');
        end

        function aMissingPortIsReportedClearly(testCase)
            testCase.assumeTrue(obis.transport.CoherentTransport.isAvailable(), ...
                'Coherent Connection is not installed.');
            t = obis.transport.CoherentTransport('COM250');
            testCase.verifyError(@() t.open(), 'obis:CoherentTransport:openFailed');
            testCase.verifyFalse(t.isOpen());
        end

        function aLaserOnTheDllDriverUsesIt(testCase)
            testCase.assumeTrue(obis.transport.CoherentTransport.isAvailable(), ...
                'Coherent Connection is not installed.');
            laser = obis.Laser('Port', 'COM250', 'Driver', 'coherent');
            testCase.verifyError(@() laser.connect(), 'obis:CoherentTransport:openFailed');
            testCase.verifyClass(laser.Transport, 'obis.transport.CoherentTransport');
            testCase.verifyEqual(laser.State, 'Disconnected');
        end

        function driverIsCheckedAndLockedWhileConnected(testCase)
            testCase.verifyError(@() obis.Laser('Driver', 'usb'), 'obis:Laser:invalidOption');
            laser = obis.Laser('Transport', obis.transport.SimulatedTransport(), ...
                'Driver', 'Serial');
            testCase.verifyEqual(laser.Driver, 'serial');
            laser.connect();
            testCase.addTeardown(@() delete(laser));
            testCase.verifyError(@() setDriver(laser, 'coherent'), 'obis:Laser:portLocked');
        end
    end
end


function setDriver(laser, value)
% Sets Driver, for verifyError.
laser.Driver = value;
end
