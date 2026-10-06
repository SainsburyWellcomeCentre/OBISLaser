function devices = listDevices(varargin)
% obis.listDevices lists the serial ports and which of them belong to an OBIS laser.
%
%   devices = obis.listDevices()               ports Windows offers now (no traffic)
%   devices = obis.listDevices('Probe', true)  also asks each free port *IDN? and keeps
%                                              the answer
%
%   Returns a table, one row per port Windows offers now:
%       Port         'COM15'
%       Available    not held by another program
%       IsObis       the port is a Coherent USB device (USB vendor 0D4D: OBIS LX/LS/LG,
%                    "Coherent OBIS Device" in Device Manager). Read from the Windows
%                    registry, with no traffic on any port. An OBIS behind an OBIS Remote
%                    or a USB-serial adapter is not a Coherent USB device: probe for it
%       Description  the device's name in Device Manager, or ''
%       Idn          empty unless probed, or when the port did not answer as an OBIS
%
%   Probing opens each free port at 115200 baud and sends *IDN?, a query that changes
%   nothing on an OBIS. Another device on a probed port receives that line too, so probe
%   only on a PC where that is harmless, or name the port yourself. A port that answers
%   as an OBIS is marked IsObis too.
%
%   Example
%       devices = obis.listDevices();
%       port = devices.Port(devices.IsObis);   % e.g. {'COM15'}
%
% See also obis.Laser, obis.config, obis.app, serialportlist
    parser = inputParser;
    parser.addParameter('Probe', false, @(x) islogical(x) || isnumeric(x));
    parser.addParameter('TimeoutS', 0.5, @isnumeric);
    parser.parse(varargin{:});

    listed = cellstr(serialportlist("all"));
    free = cellstr(serialportlist("available"));
    port = listed(:);
    available = ismember(port, free);
    [usbPorts, usbNames] = coherentUsbPorts();
    [isObis, where] = ismember(upper(port), upper(usbPorts));
    description = repmat({''}, numel(port), 1);
    description(isObis) = usbNames(where(isObis));
    idn = repmat({''}, numel(port), 1);
    if parser.Results.Probe
        for k = find(available(:))'
            idn{k} = probe(port{k}, parser.Results.TimeoutS);
        end
        isObis = isObis | ~cellfun(@isempty, idn);
    end
    devices = table(port, available, isObis, description, idn, 'VariableNames', ...
        {'Port', 'Available', 'IsObis', 'Description', 'Idn'});
end


function [ports, names] = coherentUsbPorts()
% The COM ports Windows has given Coherent USB devices (vendor 0D4D), and their names.
%
%   Reads HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_0D4D&PID_*\<instance>: FriendlyName
%   and Device Parameters\PortName. Entries stay after a device is unplugged, so the
%   caller keeps only ports Windows offers now. Never throws: off Windows, or if the
%   registry cannot be read, nothing is found.
ports = {};
names = {};
if ~ispc()
    return
end
try
    % .NET must be started before its names resolve; NET.isNETSupported starts it
    if ~NET.isNETSupported
        return
    end
    machine = Microsoft.Win32.Registry.LocalMachine;
    usb = machine.OpenSubKey('SYSTEM\CurrentControlSet\Enum\USB');
    if isempty(usb)
        return
    end
    closeUsb = onCleanup(@() usb.Close());
    devices = usb.GetSubKeyNames();
    for d = 1:devices.Length
        device = char(devices(d));
        if ~startsWith(device, 'VID_0D4D', 'IgnoreCase', true)
            continue
        end
        instances = usb.OpenSubKey(device);
        instanceNames = instances.GetSubKeyNames();
        for k = 1:instanceNames.Length
            instance = instances.OpenSubKey(instanceNames(k));
            parameters = instance.OpenSubKey('Device Parameters');
            if ~isempty(parameters)
                portName = char(parameters.GetValue('PortName', ''));
                parameters.Close();
                if ~isempty(portName)
                    ports{end + 1} = portName; %#ok<AGROW>
                    names{end + 1} = char(instance.GetValue('FriendlyName', '')); %#ok<AGROW>
                end
            end
            instance.Close();
        end
        instances.Close();
    end
catch
    % A registry that cannot be read means no port is recognised; the user picks one.
end
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
