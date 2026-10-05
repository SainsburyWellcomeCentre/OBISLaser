function devices = listDevices(varargin)
% obis.listDevices lists the serial ports and, if asked, which of them answer as an OBIS.
%
%   devices = obis.listDevices()               ports Windows offers now (no traffic)
%   devices = obis.listDevices('Probe', true)  also asks each free port *IDN? and keeps
%                                              the answer
%
%   Returns a table: Port, Available (not held by another program), Idn (empty unless
%   probed, or when the port did not answer as an OBIS).
%
%   Probing opens each free port at 115200 baud and sends *IDN?, a query that changes
%   nothing on an OBIS. Another device on a probed port receives that line too, so probe
%   only on a PC where that is harmless, or name the port yourself.
%
% See also obis.Laser, obis.config, serialportlist
    parser = inputParser;
    parser.addParameter('Probe', false, @(x) islogical(x) || isnumeric(x));
    parser.addParameter('TimeoutS', 0.5, @isnumeric);
    parser.parse(varargin{:});

    listed = cellstr(serialportlist("all"));
    free = cellstr(serialportlist("available"));
    port = listed(:);
    available = ismember(port, free);
    idn = repmat({''}, numel(port), 1);
    if parser.Results.Probe
        for k = find(available(:))'
            idn{k} = probe(port{k}, parser.Results.TimeoutS);
        end
    end
    devices = table(port, available, idn, 'VariableNames', {'Port', 'Available', 'Idn'});
end


function idn = probe(port, timeoutS)
% The *IDN? answer of an OBIS on port, or '' if nothing like one answers.
idn = '';
transport = obis.transport.SerialTransport(port);
cleanup = onCleanup(@() transport.close());
try
    transport.open();
    transport.writeLine('*IDN?');
    line = transport.readLine(timeoutS);
    if ~isempty(line) && contains(line, 'OBIS', 'IgnoreCase', true)
        idn = char(line);
    end
catch
    % A port that will not open or answer is not an OBIS for this purpose.
end
end
