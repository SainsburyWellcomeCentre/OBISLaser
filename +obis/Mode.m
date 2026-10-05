classdef Mode
% obis.Mode is the source an OBIS laser takes its output power from.
%
%   The laser's SOURce:AM commands choose it (docs/scpi.md). In the two internal modes the
%   laser emits whenever emission is enabled; in the three external ones the modulation
%   input on the laser's SMB connector (or the OBIS remote's) also controls it.
%
%   CWP      continuous wave, constant power: output held at the setpoint by the power loop
%   CWC      continuous wave, constant current: no power loop, so output drifts with
%            temperature
%   Digital  external TTL gates output on (high) and off (low) at the setpoint
%   Analog   external 0-5 V input scales output from 0 to the laser's maximum power
%   Mixed    external TTL and analog input together (the laser manual's mixed mode)
%
%   m = obis.Mode.fromText('digital')    any letter case, also the laser's own replies
%                                       ('DIGITAL', 'CWP') and short forms ('DIG')
%
%   Properties
%       Command    the line that selects the mode, e.g. 'SOURce:AM:EXTernal DIGital'
%       Reply      what SOURce:AM:SOURce? answers in this mode, e.g. 'DIGITAL'
%       IsExternal true for Digital, Analog and Mixed
%
%   See also obis.Laser

    properties (SetAccess = immutable)
        Command     % line that selects the mode
        Reply       % SOURce:AM:SOURce? reply in this mode
        IsExternal  % true when the modulation input controls output
    end

    enumeration
        CWP     ('SOURce:AM:INTernal CWP', 'CWP', false)
        CWC     ('SOURce:AM:INTernal CWC', 'CWC', false)
        Digital ('SOURce:AM:EXTernal DIGital', 'DIGITAL', true)
        Analog  ('SOURce:AM:EXTernal ANALog', 'ANALOG', true)
        Mixed   ('SOURce:AM:EXTernal MIXed', 'MIXED', true)
    end

    methods
        function obj = Mode(command, reply, isExternal)
            obj.Command = command;
            obj.Reply = reply;
            obj.IsExternal = isExternal;
        end
    end

    methods (Static)
        function mode = fromText(text)
            % mode = obis.Mode.fromText(text) is the mode a name or a laser reply stands for.
            %
            %   Errors with 'obis:Mode:unknown' for anything else.
            if isa(text, 'obis.Mode')
                mode = text;
                return
            end
            key = strtrim(char(text));
            aliases = {'CWP', 'CWP'; 'CWC', 'CWC'; 'DIGITAL', 'Digital'; 'DIG', 'Digital'; ...
                'ANALOG', 'Analog'; 'ANAL', 'Analog'; 'MIXED', 'Mixed'; 'MIX', 'Mixed'};
            match = strcmpi(aliases(:, 1), key);
            if ~any(match)
                error('obis:Mode:unknown', ['Unknown mode "%s". Valid: CWP, CWC, Digital, ' ...
                    'Analog, Mixed.'], char(text));
            end
            mode = obis.Mode.(aliases{match, 2});
        end
    end
end
