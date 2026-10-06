classdef SerialTransportTest < matlab.unittest.TestCase
% SerialTransportTest checks the real transport without a laser: construction and refusals.
%
%   Opens only a port that does not exist (COM250), so no device is touched.
%
% See also obis.transport.SerialTransport

    methods (Test)
        function constructorTouchesNothing(testCase)
            t = obis.transport.SerialTransport('COM250', 'BaudRate', 9600);
            testCase.verifyFalse(t.isOpen());
            testCase.verifyEqual(t.Description, 'COM250 @ 9600');
            testCase.verifyError(@() t.writeLine('*IDN?'), 'obis:SerialTransport:notOpen');
            t.close();   % never throws, even unopened
        end

        function aMissingPortIsReportedClearly(testCase)
            t = obis.transport.SerialTransport('COM250');
            testCase.verifyError(@() t.open(), 'obis:SerialTransport:openFailed');
            testCase.verifyFalse(t.isOpen());
        end

        function aLaserOnAMissingPortStaysDisconnected(testCase)
            laser = obis.Laser('Port', 'COM250', 'Driver', 'serial');
            testCase.verifyError(@() laser.connect(), 'obis:SerialTransport:openFailed');
            testCase.verifyEqual(laser.State, 'Disconnected');
        end
    end
end
