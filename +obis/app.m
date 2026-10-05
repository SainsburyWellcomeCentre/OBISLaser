function varargout = app(varargin)
% obis.app opens the laser control window.
%
%   obis.app()               opens a window that owns its own obis.Laser (real laser)
%   obis.app(laser)          attaches to an existing obis.Laser (never disconnects it)
%   obis.app(..., 'Name', value)  options of obis.gui.LaserApp
%   a = obis.app(...)        returns the obis.gui.LaserApp object
%
% See also obis.gui.LaserApp, obis.Laser
    appObject = obis.gui.LaserApp(varargin{:});
    if nargout > 0
        varargout{1} = appObject;
    end
end
