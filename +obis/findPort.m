function [port, found] = findPort(varargin)
% obis.findPort finds the port of an OBIS laser, by wavelength when there are several.
%
%   port = obis.findPort()                     the first free Coherent USB port (no traffic)
%   port = obis.findPort('WavelengthNm', 488)  the free Coherent USB port whose laser is
%                                              488 nm (within obis.Laser.
%                                              WavelengthToleranceNm: it may report 489)
%   [port, found] = obis.findPort(...)         also the ports asked: a table Port, Idn (the
%                                              laser's model and wavelength as answered),
%                                              WavelengthNm (NaN when it did not answer)
%
%   Only Coherent USB ports that no program holds are considered (obis.listDevices,
%   IsObis and Available), so no other device on the PC is ever sent anything. With a
%   wavelength, each is opened in turn, asked the laser's wavelength
%   (SYSTem:INFormation:WAVelength?, a query that changes nothing) and closed again; the
%   first that is that wavelength is returned. *IDN? and MODel? would not do: on this rig
%   each laser sits behind an OBIS Mini-Controller, and both name the controller, while
%   WAVelength? reaches the laser (docs/rig-checks.md, 2026-10-05).
%
%   Options
%       WavelengthNm  the laser wanted, nm ([] or 0: any; default [])
%       Driver        how the ports are opened: 'coherent' or 'serial' (default from
%                     obis.config)
%       DllFolder     for the 'coherent' driver (default from obis.config)
%       TimeoutS      wait for each answer (default 1)
%       ListDevices   fcn() returning a table like obis.listDevices (tests)
%       Identify      fcn(port) returning text naming the laser on port, e.g. '561 nm',
%                     or '' for none (tests)
%
%   Errors with 'obis:findPort:notFound' naming every laser it found instead.
%
%   Example
%       laser = obis.Laser('Port', obis.findPort('WavelengthNm', 488), ...
%           'ExpectedWavelengthNm', 488);
%
% See also obis.listDevices, obis.Laser, obis.app
    cfg = obis.config();
    parser = inputParser;
    parser.addParameter('WavelengthNm', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
    parser.addParameter('Driver', cfg.Driver, @(x) ischar(x) || isstring(x));
    parser.addParameter('DllFolder', cfg.DllFolder, @(x) ischar(x) || isstring(x));
    parser.addParameter('TimeoutS', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    parser.addParameter('ListDevices', @obis.listDevices, @(x) isa(x, 'function_handle'));
    parser.addParameter('Identify', [], @(x) isempty(x) || isa(x, 'function_handle'));
    parser.parse(varargin{:});
    options = parser.Results;
    wanted = options.WavelengthNm;
    if ~isempty(wanted) && wanted == 0
        wanted = [];
    end
    identify = options.Identify;
    if isempty(identify)
        driver = obis.Laser.checkDriver(options.Driver);
        identify = @(p) askLaser(p, driver, char(options.DllFolder), options.TimeoutS);
    end

    devices = options.ListDevices();
    candidates = devices.Port(devices.IsObis & devices.Available);
    candidates = cellstr(candidates(:));
    found = table(candidates, repmat({''}, numel(candidates), 1), ...
        nan(numel(candidates), 1), 'VariableNames', {'Port', 'Idn', 'WavelengthNm'});
    if isempty(candidates)
        held = devices.Port(devices.IsObis & ~devices.Available);
        detail = '';
        if ~isempty(held)
            detail = sprintf([' (%s in use by another program: close it, or Coherent ' ...
                'Connection)'], strjoin(cellstr(held), ', '));
        end
        error('obis:findPort:notFound', 'No free OBIS laser port found%s.', detail);
    end
    if isempty(wanted)
        port = candidates{1};
        return
    end
    for k = 1:numel(candidates)
        idn = char(identify(candidates{k}));
        found.Idn{k} = idn;
        found.WavelengthNm(k) = wavelengthOf(idn);
        if abs(found.WavelengthNm(k) - wanted) <= obis.Laser.WavelengthToleranceNm
            port = candidates{k};
            return
        end
    end
    seen = cell(1, height(found));
    for k = 1:height(found)
        seen{k} = sprintf('%s: %s', found.Port{k}, describeIdn(found.Idn{k}, ...
            found.WavelengthNm(k)));
    end
    error('obis:findPort:notFound', 'No free %g nm OBIS laser found. Found %s.', wanted, ...
        strjoin(seen, '; '));
end


function text = askLaser(port, driver, dllFolder, timeoutS)
% 'WAVELENGTH nm' as the laser on port answers, or '' if none does. Never throws.
text = '';
if strcmp(driver, 'coherent')
    transport = obis.transport.CoherentTransport(port, 'DllFolder', dllFolder);
else
    transport = obis.transport.SerialTransport(port);
end
cleanup = onCleanup(@() transport.close());
try
    transport.open();
    transport.flush();
    wavelength = ask(transport, 'SYSTem:INFormation:WAVelength?', timeoutS);
    if ~isempty(wavelength)
        text = sprintf('%s nm', wavelength);
    end
catch
    % A port that will not open or answer has no laser to offer.
end
end


function value = ask(transport, query, timeoutS)
% The value line of one query, read up to its OK; '' when refused or silent.
value = '';
transport.writeLine(query);
started = tic;
while toc(started) < timeoutS
    line = transport.readLine(max(timeoutS - toc(started), 0.01));
    if isempty(line) || strcmpi(line, 'OK') || startsWith(line, 'ERR', 'IgnoreCase', true)
        return
    elseif isempty(value)
        value = char(strtrim(line));
    end
end
end


function nm = wavelengthOf(idn)
% The wavelength a laser's description names ('489 nm'), or NaN.
nm = NaN;
token = regexp(idn, '(\d{3,4})\s*nm', 'tokens', 'once', 'ignorecase');
if ~isempty(token)
    nm = str2double(token{1});
end
end


function text = describeIdn(idn, nm)
% A short description of what answered on a port.
if isempty(idn)
    text = 'no answer';
elseif isnan(nm)
    text = idn;
else
    text = sprintf('%g nm', nm);
end
end
