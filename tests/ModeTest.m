classdef ModeTest < matlab.unittest.TestCase
% ModeTest checks obis.Mode's commands, replies and names.
%
% See also obis.Mode

    methods (Test)
        function everyModeHasItsCommandAndReply(testCase)
            testCase.verifyEqual(obis.Mode.CWP.Command, 'SOURce:AM:INTernal CWP');
            testCase.verifyEqual(obis.Mode.Digital.Command, 'SOURce:AM:EXTernal DIGital');
            testCase.verifyEqual(obis.Mode.Analog.Reply, 'ANALOG');
            testCase.verifyFalse(obis.Mode.CWC.IsExternal);
            testCase.verifyTrue(obis.Mode.Mixed.IsExternal);
        end

        function namesAndRepliesAreRead(testCase)
            testCase.verifyEqual(obis.Mode.fromText('digital'), obis.Mode.Digital);
            testCase.verifyEqual(obis.Mode.fromText('DIGITAL'), obis.Mode.Digital);
            testCase.verifyEqual(obis.Mode.fromText(' cwp '), obis.Mode.CWP);
            testCase.verifyEqual(obis.Mode.fromText("Mix"), obis.Mode.Mixed);
            testCase.verifyEqual(obis.Mode.fromText(obis.Mode.Analog), obis.Mode.Analog);
            testCase.verifyError(@() obis.Mode.fromText('pulsed'), 'obis:Mode:unknown');
        end
    end
end
