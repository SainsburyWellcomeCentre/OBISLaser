classdef ExamplesTest < matlab.unittest.TestCase
% ExamplesTest runs the files in examples/ end to end on the simulated laser.
%
%   The examples default to the simulated transport, so this never touches hardware. It
%   also keeps the examples from drifting away from the API.
%
% See also obis.Laser

    properties
        ExamplesDir
    end

    methods (TestMethodSetup)
        function addExamplesToPath(testCase)
            testCase.ExamplesDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                'examples');
            previous = path();
            testCase.addTeardown(@() path(previous));
            addpath(testCase.ExamplesDir);
        end
    end

    methods (Test)
        function basicScriptRuns(testCase)
            run(fullfile(testCase.ExamplesDir, 'example_basic.m'));
            testCase.verifyEqual(session.MaxPowermW, 20);
            testCase.verifyEqual(session.Mode, 'Digital');
            testCase.verifyTrue(session.IsEnabled);
            testCase.verifyEqual(laser.State, 'Disconnected');
        end

        function bpodSoftCodeExampleRuns(testCase)
            session = example_bpod_softcode();
            powers = {session.Log.Command};
            powers = powers(startsWith(powers, 'SOURce:POWer:LEVel:IMMediate:AMPLitude 0'));
            testCase.verifyEqual(numel(powers), 6);   % 0 at setup, then five trials
            testCase.verifyEqual(session.CommandedPowermW, 10);
        end

        function calibrationScriptRuns(testCase)
            run(fullfile(testCase.ExamplesDir, 'example_calibration.m'));
            testCase.verifyEqual(cal.setpointFor(cal.powerFor(100)), 100, 'AbsTol', 1e-9);
        end
    end
end
