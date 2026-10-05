function cfg = config(varargin)
% obis.config is the resolved defaults of the obis package.
%
%   cfg = obis.config() returns a struct:
%       RootDir   package root (the folder containing +obis)
%       Port      default serial port for obis.Laser ('' when none is set)
%       BaudRate  default bits per second (115200, the OBIS remote's rate)
%       Version   package version (obis.version)
%
%   cfg = obis.config('Port', 'COM15') overrides entries for this call. Persistent
%   overrides use MATLAB preferences, kept per Windows user across sessions:
%       setpref('obis', 'Port', 'COM15')
%   Precedence: arguments, then preferences, then the defaults above.
%
%   Errors with 'obis:config:invalidOption' for an unknown or malformed option.
%
% See also obis.Laser, obis.listDevices
    cfg = struct();
    cfg.RootDir = fileparts(fileparts(mfilename('fullpath')));
    cfg.Port = '';
    cfg.BaudRate = 115200;
    cfg.Version = obis.version();

    overridable = {'Port', 'BaudRate'};
    for k = 1:numel(overridable)
        name = overridable{k};
        if ispref('obis', name)
            cfg.(name) = getpref('obis', name);
        end
    end
    if mod(numel(varargin), 2) ~= 0
        error('obis:config:invalidOption', 'Options must be name-value pairs.');
    end
    for k = 1:2:numel(varargin)
        match = strcmpi(overridable, char(varargin{k}));
        if ~any(match)
            error('obis:config:invalidOption', 'Unknown option "%s". Valid: %s.', ...
                char(varargin{k}), strjoin(overridable, ', '));
        end
        cfg.(overridable{match}) = varargin{k + 1};
    end
    cfg.Port = char(cfg.Port);
end
