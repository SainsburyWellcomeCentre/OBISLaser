classdef CalibrationTest < matlab.unittest.TestCase
% CalibrationTest checks obis.Calibration's table rules, both conversions and its refusals.
%
% See also obis.Calibration

    methods (Test)
        function convertsBothWays(testCase)
            cal = obis.Calibration([0 10 20 40], [0 2 4 9]);
            testCase.verifyEqual(cal.setpointFor(3), 15, 'AbsTol', 1e-12);
            testCase.verifyEqual(cal.powerFor(30), 6.5, 'AbsTol', 1e-12);
            testCase.verifyEqual(cal.setpointFor(cal.powerFor(25)), 25, 'AbsTol', 1e-12);
        end

        function rowsWithNoMeasuredPowerAreDropped(testCase)
            cal = obis.Calibration([0 5 10 15], [0 0 1 2]);
            testCase.verifyEqual(cal.SetpointmW, [10; 15]);
            testCase.verifyEqual(cal.Range, [1 2]);
        end

        function rowsAreSortedBySetpoint(testCase)
            cal = obis.Calibration([20 10 30], [4 2 6]);
            testCase.verifyEqual(cal.SetpointmW, [10; 20; 30]);
            testCase.verifyEqual(cal.PowermW, [2; 4; 6]);
        end

        function outsideTheTableIsRefused(testCase)
            cal = obis.Calibration([10 20], [2 4]);
            testCase.verifyError(@() cal.setpointFor(1.9), 'obis:Calibration:outOfRange');
            testCase.verifyError(@() cal.setpointFor([3 4.1]), 'obis:Calibration:outOfRange');
            testCase.verifyError(@() cal.powerFor(25), 'obis:Calibration:outOfRange');
            testCase.verifyError(@() cal.setpointFor(NaN), 'obis:Calibration:outOfRange');
            testCase.verifyEqual(cal.setpointFor([2 4]), [10 20]);
        end

        function aPowerThatFallsIsRefused(testCase)
            testCase.verifyError(@() obis.Calibration([10 20 30], [2 5 4]), ...
                'obis:Calibration:notMonotonic');
            testCase.verifyError(@() obis.Calibration([10 10 30], [2 3 4]), ...
                'obis:Calibration:notMonotonic');
        end

        function tooFewRowsAreRefused(testCase)
            testCase.verifyError(@() obis.Calibration([0 10], [0 2]), 'obis:Calibration:badTable');
            testCase.verifyError(@() obis.Calibration([1 2 3], [1 2]), 'obis:Calibration:badTable');
        end

        function scalingKeepsTheSetpoints(testCase)
            cal = obis.Calibration([10 20], [2 4]).scaled(0.5);
            testCase.verifyEqual(cal.Range, [1 2]);
            testCase.verifyEqual(cal.setpointFor(1.5), 15, 'AbsTol', 1e-12);
            testCase.verifyError(@() cal.scaled(0), 'obis:Calibration:badTable');
        end

        function readsACsv(testCase)
            file = [tempname '.csv'];
            testCase.addTeardown(@() delete(file));
            writetable(table([0; 5; 10], [0; 1.7; 3.4], [99; 99; 99], 'VariableNames', ...
                {'power_setting_mW', 'power_at_sample_mW', 'intensity_at_camera'}), file);
            cal = obis.Calibration.fromCsv(file);
            testCase.verifyEqual(cal.SetpointmW, [5; 10]);
            testCase.verifyEqual(cal.Source, file);
            testCase.verifyError(@() obis.Calibration.fromCsv(file, 'PowerColumn', 'mW'), ...
                'obis:Calibration:badTable');
        end
    end
end
