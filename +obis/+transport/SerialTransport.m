classdef SerialTransport < obis.transport.Transport
% obis.transport.SerialTransport talks to an OBIS laser over a serial (USB virtual COM) port.
%
%   t = obis.transport.SerialTransport('COM15')
%   t = obis.transport.SerialTransport('COM15', 'BaudRate', 115200)
%
%   Uses MATLAB's serialport (base MATLAB since R2019b). The OBIS remote and the OBIS LX/LS
%   USB port both run at 115200 baud, 8 data bits, no parity, 1 stop bit, and end lines with
%   CR/LF. The port is opened by open(), not by the constructor, so a transport can be
%   made, inspected and handed to obis.Laser without touching the hardware.
%
%   Properties
%       Port      serial port name, e.g. 'COM15'
%       BaudRate  bits per second (default 115200)
%
%   Errors with 'obis:SerialTransport:openFailed' when the port cannot be opened (missing,
%   or held by another program such as Coherent Connection) and
%   'obis:SerialTransport:notOpen' when a line is sent before open().
%
%   See also obis.transport.Transport, obis.Laser, obis.listDevices, serialport

    properties (SetAccess = private)
        Port      % serial port name, e.g. 'COM15'
        BaudRate  % bits per second
    end

    properties (SetAccess = protected)
        Description = ''  % 'COM15 @ 115200'
    end

    properties (Access = private)
        Device = []  % the serialport object while open
    end

    methods
        function obj = SerialTransport(port, varargin)
            parser = inputParser;
            parser.addRequired('Port', @(x) ischar(x) || isstring(x));
            parser.addParameter('BaudRate', 115200, @(x) isnumeric(x) && isscalar(x) && x > 0);
            parser.parse(port, varargin{:});
            obj.Port = char(parser.Results.Port);
            obj.BaudRate = parser.Results.BaudRate;
            obj.Description = sprintf('%s @ %d', obj.Port, obj.BaudRate);
        end

        function open(obj)
            if obj.isOpen()
                return
            end
            try
                obj.Device = serialport(obj.Port, obj.BaudRate);
            catch err
                error('obis:SerialTransport:openFailed', ['Could not open %s (%s). Check the ' ...
                    'port with obis.listDevices() and close any other program using it ' ...
                    '(Coherent Connection).'], obj.Port, err.message);
            end
            configureTerminator(obj.Device, "CR/LF");
            flush(obj.Device);
        end

        function close(obj)
            try
                if ~isempty(obj.Device) && isvalid(obj.Device)
                    delete(obj.Device);
                end
            catch
                % Closing must never throw: it runs from delete and cleanup paths.
            end
            obj.Device = [];
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Device) && isvalid(obj.Device);
        end

        function writeLine(obj, text)
            obj.requireOpen();
            writeline(obj.Device, text);
        end

        function line = readLine(obj, timeoutS)
            obj.requireOpen();
            obj.Device.Timeout = timeoutS;
            % readline warns and returns [] on timeout; the caller treats [] as no reply.
            previous = warning('off', 'serialport:serialport:ReadlineWarning');
            restore = onCleanup(@() warning(previous));
            line = readline(obj.Device);
            if ~isempty(line)
                line = strtrim(char(line));
            end
        end

        function flush(obj)
            if obj.isOpen()
                flush(obj.Device);
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function requireOpen(obj)
            % Errors unless the port is open.
            if ~obj.isOpen()
                error('obis:SerialTransport:notOpen', '%s is not open; call open() first.', ...
                    obj.Port);
            end
        end
    end
end
