classdef ListDevicesTest < matlab.unittest.TestCase
% ListDevicesTest checks obis.listDevices without probing: it reads Windows' lists only.
%
%   No port is opened. Which ports exist depends on the PC, so only the table's form and
%   its agreement with serialportlist are checked.
%
% See also obis.listDevices

    methods (Test)
        function listsEveryPortWithoutTraffic(testCase)
            devices = obis.listDevices();
            testCase.verifyEqual(devices.Properties.VariableNames, ...
                {'Port', 'Available', 'IsObis', 'Description', 'Idn'});
            expected = cellstr(serialportlist("all"));
            testCase.verifyEqual(sort(devices.Port), sort(expected(:)));
            testCase.verifyClass(devices.IsObis, 'logical');
            testCase.verifyTrue(all(cellfun(@isempty, devices.Idn)));
        end

        function anObisPortIsNamed(testCase)
            devices = obis.listDevices();
            obisPorts = devices(devices.IsObis, :);
            testCase.assumeNotEmpty(obisPorts, 'No Coherent USB device on this PC.');
            testCase.verifyTrue(all(startsWith(obisPorts.Port, 'COM')));
            testCase.verifyTrue(all(~cellfun(@isempty, obisPorts.Description)));
        end
    end
end
