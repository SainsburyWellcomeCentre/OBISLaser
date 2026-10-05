classdef SimulatedTransportTest < matlab.unittest.TestCase
% SimulatedTransportTest checks that the simulated laser answers as docs/scpi.md describes.
%
% See also obis.transport.SimulatedTransport

    properties
        Transport
    end

    methods (TestMethodSetup)
        function openTransport(testCase)
            testCase.Transport = obis.transport.SimulatedTransport();
            testCase.Transport.open();
        end
    end

    methods (Test)
        function aCommandIsAnsweredOk(testCase)
            testCase.verifyEqual(testCase.exchange('SOURce:AM:STATe ON'), {'OK'});
            testCase.verifyTrue(testCase.Transport.Enabled);
        end

        function aQueryIsAnsweredWithItsValueThenOk(testCase)
            testCase.verifyEqual(testCase.exchange('SOURce:POWer:LIMit:HIGH?'), ...
                {'0.16500', 'OK'});
        end

        function lettersCaseDoesNotMatter(testCase)
            testCase.verifyEqual(testCase.exchange('source:am:state?'), {'OFF', 'OK'});
        end

        function unknownAndOutOfRangeAreErrors(testCase)
            testCase.verifyEqual(testCase.exchange('SOUR:AM:STAT ON'), {'ERR-100'});
            testCase.verifyEqual(testCase.exchange( ...
                'SOURce:POWer:LEVel:IMMediate:AMPLitude 0.2'), {'ERR-102'});
            testCase.verifyEqual(testCase.Transport.SetpointW, 0);
            testCase.verifyEqual(testCase.exchange('SOURce:AM:STATe MAYBE'), {'ERR-102'});
        end

        function handshakeOffDropsTheOk(testCase)
            testCase.exchange('SYST:COMM:HAND OFF');
            testCase.verifyEmpty(testCase.exchange('SOURce:AM:STATe ON'));
            testCase.verifyEqual(testCase.exchange('SOURce:AM:STATe?'), {'ON'});
        end

        function outputFollowsModeEmissionAndInput(testCase)
            t = testCase.Transport;
            testCase.exchange('SOURce:POWer:LEVel:IMMediate:AMPLitude 0.01');
            testCase.verifyEqual(testCase.exchange('SOURce:POWer:LEVel?'), {'0.00000', 'OK'});
            testCase.exchange('SOURce:AM:STATe ON');
            testCase.verifyEqual(testCase.exchange('SOURce:POWer:LEVel?'), {'0.01000', 'OK'});
            testCase.exchange('SOURce:AM:EXTernal DIGital');
            testCase.verifyEqual(testCase.exchange('SOURce:POWer:LEVel?'), {'0.00000', 'OK'});
            t.ModulationInput = 1;
            testCase.verifyEqual(testCase.exchange('SOURce:POWer:LEVel?'), {'0.01000', 'OK'});
        end

        function faultsAreInjected(testCase)
            t = testCase.Transport;
            t.failNext('SOURce:AM', 'ERR-999');
            testCase.verifyEqual(testCase.exchange('SOURce:AM:STATe ON'), {'ERR-999'});
            testCase.verifyFalse(t.Enabled);
            t.hangNext('*IDN');
            testCase.verifyEmpty(testCase.exchange('*IDN?'));
            testCase.verifyNotEmpty(testCase.exchange('*IDN?'));
            t.unplug();
            testCase.verifyError(@() t.writeLine('*IDN?'), 'obis:SimulatedTransport:unplugged');
        end

        function callsAreRecorded(testCase)
            testCase.exchange('*IDN?');
            testCase.exchange('SOURce:AM:STATe ON');
            testCase.verifyEqual(testCase.Transport.callsOf('source:am'), {'SOURce:AM:STATe ON'});
            testCase.Transport.clearCalls();
            testCase.verifyEmpty(testCase.Transport.Calls);
        end

        function aClosedPortRefusesLines(testCase)
            testCase.Transport.close();
            testCase.verifyError(@() testCase.Transport.writeLine('*IDN?'), ...
                'obis:SimulatedTransport:notOpen');
        end
    end

    methods (Access = private)
        function replies = exchange(testCase, line)
            % Sends a line and collects every reply it produced.
            testCase.Transport.writeLine(line);
            replies = {};
            while true
                reply = testCase.Transport.readLine(0);
                if isempty(reply)
                    break
                end
                replies{end + 1} = reply; %#ok<AGROW>
            end
        end
    end
end
