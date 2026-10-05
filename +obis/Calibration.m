classdef Calibration
% obis.Calibration converts between an OBIS setpoint and the power it gives where you measured.
%
%   The setpoint is what the laser is told; the power is what a meter read at your sample (or
%   anywhere else in the light path) at that setpoint. The two differ by every loss on the
%   way, and not in proportion near the lasing threshold, so a measured table is
%   interpolated linearly in both directions.
%
%   cal = obis.Calibration.fromCsv('power_calibration.csv')
%   cal = obis.Calibration.fromCsv(file, 'SetpointColumn', 'power_setting_mW', ...
%                                        'PowerColumn', 'power_at_sample_mW')
%   cal = obis.Calibration(setpointmW, powermW)
%   setpoint = cal.setpointFor(2.5)    % mW to ask for, to get 2.5 mW at the sample
%   power = cal.powerFor(100)          % mW at the sample for a 100 mW setpoint
%   irr = cal.scaled(1 / 0.0151)       % the same table as irradiance, mW/mm2
%
%   Rows whose power is zero, negative or missing are dropped: below the lasing threshold the
%   meter reads nothing, so those setpoints say nothing about the setpoint for a given power.
%   The rest must give a power that rises with the setpoint, or the inverse is ambiguous.
%   Values outside the measured range are refused, never extrapolated.
%
%   Properties
%       SetpointmW  column of setpoints, rising (mW)
%       PowermW     column of measured powers at those setpoints, rising (in the table's unit;
%                   mW unless scaled)
%       Range       [lowest highest] measured power
%       Source      the file it was read from, or ''
%
%   Errors with 'obis:Calibration:badTable' (fewer than two usable rows, sizes that differ,
%   non-numeric values or a missing column), 'obis:Calibration:notMonotonic' (power does
%   not rise with setpoint) and 'obis:Calibration:outOfRange'.
%
%   This is a pure class: no hardware, unit-testable offline.
%
%   See also obis.Laser, obis.Calibration.fromCsv

    properties (SetAccess = private)
        SetpointmW = zeros(0, 1)  % setpoints, rising (mW)
        PowermW = zeros(0, 1)     % measured power at each setpoint, rising
        Source = ''               % file the table came from
    end

    properties (Dependent)
        Range  % [lowest highest] measured power
    end

    methods
        function obj = Calibration(setpointmW, powermW, source)
            if nargin == 0
                return
            end
            if nargin < 3
                source = '';
            end
            if ~isnumeric(setpointmW) || ~isnumeric(powermW) ...
                    || numel(setpointmW) ~= numel(powermW)
                error('obis:Calibration:badTable', ['Setpoints and powers must be numeric ' ...
                    'and the same size (%d and %d values).'], numel(setpointmW), ...
                    numel(powermW));
            end
            setpointmW = double(setpointmW(:));
            powermW = double(powermW(:));
            usable = isfinite(setpointmW) & isfinite(powermW) & powermW > 0;
            setpointmW = setpointmW(usable);
            powermW = powermW(usable);
            if numel(setpointmW) < 2
                error('obis:Calibration:badTable', ['A calibration needs at least two rows ' ...
                    'with a measured power above zero; %d found.'], numel(setpointmW));
            end
            [setpointmW, order] = sort(setpointmW);
            powermW = powermW(order);
            if any(diff(setpointmW) <= 0) || any(diff(powermW) <= 0)
                error('obis:Calibration:notMonotonic', ['Power must rise with setpoint, ' ...
                    'with no repeated setpoint; check the table%s.'], sourceNote(source));
            end
            obj.SetpointmW = setpointmW;
            obj.PowermW = powermW;
            obj.Source = char(source);
        end

        function range = get.Range(obj)
            range = [min(obj.PowermW), max(obj.PowermW)];
        end

        function setpointmW = setpointFor(obj, powermW)
            % setpointmW = setpointFor(powermW) is the setpoint giving each power.
            %
            %   Errors with 'obis:Calibration:outOfRange' if any power lies outside Range.
            obj.requireInside(powermW, obj.PowermW, 'power');
            setpointmW = interp1(obj.PowermW, obj.SetpointmW, powermW, 'linear');
        end

        function powermW = powerFor(obj, setpointmW)
            % powermW = powerFor(setpointmW) is the power measured, or interpolated, at each
            % setpoint.
            %
            %   Errors with 'obis:Calibration:outOfRange' if any setpoint lies outside the
            %   table's setpoints.
            obj.requireInside(setpointmW, obj.SetpointmW, 'setpoint');
            powermW = interp1(obj.SetpointmW, obj.PowermW, setpointmW, 'linear');
        end

        function cal = scaled(obj, factor)
            % cal = scaled(factor) is the same table with every power multiplied by factor.
            %
            %   For a quantity proportional to power, such as irradiance (power over the lit
            %   area) or power at another point of the path.
            if ~isnumeric(factor) || ~isscalar(factor) || ~(factor > 0) || ~isfinite(factor)
                error('obis:Calibration:badTable', 'The factor must be a positive number.');
            end
            cal = obis.Calibration(obj.SetpointmW, obj.PowermW * factor, obj.Source);
        end
    end

    methods (Static)
        function cal = fromCsv(file, varargin)
            % cal = obis.Calibration.fromCsv(file) reads a setpoint/power table from a CSV.
            %
            %   Options: 'SetpointColumn' (default 'power_setting_mW') and 'PowerColumn'
            %   (default 'power_at_sample_mW'). Other columns are ignored.
            parser = inputParser;
            parser.addParameter('SetpointColumn', 'power_setting_mW');
            parser.addParameter('PowerColumn', 'power_at_sample_mW');
            parser.parse(varargin{:});
            table = readtable(file);
            columns = {parser.Results.SetpointColumn, parser.Results.PowerColumn};
            missing = columns(~ismember(columns, table.Properties.VariableNames));
            if ~isempty(missing)
                error('obis:Calibration:badTable', '%s has no column %s.', char(file), ...
                    strjoin(missing, ' or '));
            end
            cal = obis.Calibration(table.(columns{1}), table.(columns{2}), char(file));
        end
    end

    methods (Access = private)
        function requireInside(obj, values, bounds, name)
            % Errors unless every value lies within the table's bounds.
            low = min(bounds);
            high = max(bounds);
            outside = ~(values >= low & values <= high);
            if any(outside(:))
                error('obis:Calibration:outOfRange', ['%s %s outside the calibrated range ' ...
                    '[%g, %g]%s.'], upperFirst(name), mat2str(values(outside)), low, high, ...
                    sourceNote(obj.Source));
            end
        end
    end
end


function note = sourceNote(source)
% ' (in <file>)' when the table came from a file, else ''.
if isempty(source)
    note = '';
else
    note = sprintf(' (in %s)', source);
end
end


function text = upperFirst(text)
% text with its first letter upper case.
text(1) = upper(text(1));
end
