classdef FindPortTest < matlab.unittest.TestCase
% FindPortTest checks obis.findPort with made-up ports and answers: no port is opened.
%
% See also obis.findPort

    methods (Test)
        function withoutAWavelengthTheFirstFreeObisPortIsTaken(testCase)
            asked = {};
            function idn = identify(p)
                asked{end + 1} = p;
                idn = '';
            end
            port = obis.findPort('ListDevices', @() devices(), 'Identify', @identify);
            testCase.verifyEqual(port, 'COM8');
            testCase.verifyEmpty(asked);  % nothing is sent without a wavelength
        end

        function aWavelengthPicksItsLaser(testCase)
            [port, found] = obis.findPort('WavelengthNm', 561, 'ListDevices', ...
                @() devices(), 'Identify', @answer);
            testCase.verifyEqual(port, 'COM15');
            testCase.verifyEqual(found.WavelengthNm', [489 561]);
        end

        function aWavelengthMatchesWithinTolerance(testCase)
            port = obis.findPort('WavelengthNm', 488, 'ListDevices', @() devices(), ...
                'Identify', @answer);
            testCase.verifyEqual(port, 'COM8');
        end

        function onlyFreeObisPortsAreAsked(testCase)
            asked = {};
            function idn = identify(p)
                asked{end + 1} = p;
                idn = answer(p);
            end
            obis.findPort('WavelengthNm', 561, 'ListDevices', @() devices(), ...
                'Identify', @identify);
            testCase.verifyEqual(asked, {'COM8', 'COM15'});  % never COM3 (not an OBIS)
        end

        function aMissingLaserNamesTheOthers(testCase)
            testCase.verifyError(@() obis.findPort('WavelengthNm', 640, 'ListDevices', ...
                @() devices(), 'Identify', @answer), 'obis:findPort:notFound');
            try
                obis.findPort('WavelengthNm', 640, 'ListDevices', @() devices(), ...
                    'Identify', @answer);
            catch err
                testCase.verifySubstring(err.message, 'COM8: 489 nm');
                testCase.verifySubstring(err.message, 'COM15: 561 nm');
            end
        end

        function heldPortsAreSkippedAndNamed(testCase)
            d = devices();
            d.Available(:) = false;
            try
                obis.findPort('ListDevices', @() d);
                testCase.verifyFail('Expected obis:findPort:notFound.');
            catch err
                testCase.verifyEqual(err.identifier, 'obis:findPort:notFound');
                testCase.verifySubstring(err.message, 'COM8, COM15 in use');
            end
        end
    end
end


function d = devices()
% COM3 (not an OBIS), COM8 and COM15 (two OBIS lasers), all free.
d = table({'COM3'; 'COM8'; 'COM15'}, true(3, 1), [false; true; true], ...
    {''; 'Coherent OBIS Device (COM8)'; 'Coherent OBIS Device (COM15)'}, {''; ''; ''}, ...
    'VariableNames', {'Port', 'Available', 'IsObis', 'Description', 'Idn'});
end


function idn = answer(port)
% What each made-up laser answers to the model and wavelength queries.
switch port
    case 'COM8'
        idn = '489 nm';  % a '488 nm' laser, as the rig's reports itself
    case 'COM15'
        idn = '561 nm';
    otherwise
        idn = '';
end
end
