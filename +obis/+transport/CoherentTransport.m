classdef CoherentTransport < obis.transport.Transport
% obis.transport.CoherentTransport talks to an OBIS laser through Coherent's own DLL.
%
%   t = obis.transport.CoherentTransport('COM15')
%   t = obis.transport.CoherentTransport('COM15', 'DllFolder', folder)
%
%   The port is opened by the serial layer of Coherent Connection
%   (CoherentConnectionLibrary.dll, ConnectionLibrary.SerialCommunicator), the same code
%   Coherent Connection uses, instead of MATLAB's serialport. Lines go through unchanged,
%   so obis.Laser and its limits work as with obis.transport.SerialTransport. The DLL is a
%   .NET assembly loaded with NET.addAssembly (Windows only). The port is opened by open(),
%   not by the constructor.
%
%   Properties
%       Port       serial port name, e.g. 'COM15'
%       DllFolder  folder holding CoherentConnectionLibrary.dll (default:
%                  obis.transport.CoherentTransport.defaultDllFolder())
%
%   Static
%       folder = obis.transport.CoherentTransport.defaultDllFolder()
%                  the Coherent Connection 6 install folder
%       tf = obis.transport.CoherentTransport.isAvailable()
%                  true on Windows when the DLL is there
%
%   Errors
%       obis:CoherentTransport:noDll       the DLL is not in DllFolder (or not Windows)
%       obis:CoherentTransport:openFailed  the port could not be opened (missing, or held
%                                          by another program such as Coherent Connection)
%       obis:CoherentTransport:notOpen     a line sent before open()
%
%   See also obis.transport.Transport, obis.transport.SerialTransport, obis.Laser

    properties (SetAccess = private)
        Port       % serial port name, e.g. 'COM15'
        DllFolder  % folder holding CoherentConnectionLibrary.dll
    end

    properties (SetAccess = protected)
        Description = ''  % 'COM15 via CoherentConnectionLibrary'
    end

    properties (Access = private)
        Communicator = []  % ConnectionLibrary.SerialCommunicator while open
    end

    properties (Constant, Hidden)
        DllName = 'CoherentConnectionLibrary.dll'
    end

    methods
        function obj = CoherentTransport(port, varargin)
            parser = inputParser;
            parser.addRequired('Port', @(x) ischar(x) || isstring(x));
            parser.addParameter('DllFolder', ...
                obis.transport.CoherentTransport.defaultDllFolder(), ...
                @(x) ischar(x) || isstring(x));
            parser.parse(port, varargin{:});
            obj.Port = char(parser.Results.Port);
            obj.DllFolder = char(parser.Results.DllFolder);
            obj.Description = sprintf('%s via %s', obj.Port, obj.DllName);
        end

        function open(obj)
            if obj.isOpen()
                return
            end
            obj.loadDll();
            try
                communicator = ConnectionLibrary.SerialCommunicator(obj.Port, ...
                    ConnectionLibrary.Serial_Detector());
                communicator.Open();
            catch err
                error('obis:CoherentTransport:openFailed', ['Could not open %s through ' ...
                    'the Coherent DLL (%s). Check the port with obis.listDevices() and ' ...
                    'close any other program using it (Coherent Connection).'], obj.Port, ...
                    firstLine(err.message));
            end
            obj.Communicator = communicator;
            obj.flush();
        end

        function close(obj)
            try
                if ~isempty(obj.Communicator)
                    obj.Communicator.Close();
                end
            catch
                % Closing must never throw: it runs from delete and cleanup paths.
            end
            obj.Communicator = [];
        end

        function tf = isOpen(obj)
            tf = false;
            try
                tf = ~isempty(obj.Communicator) && obj.Communicator.IsOpen;
            catch
            end
        end

        function writeLine(obj, text)
            obj.requireOpen();
            obj.Communicator.WriteLine(char(text));
        end

        function line = readLine(obj, timeoutS)
            % The next line, or [] when none comes within timeoutS.
            obj.requireOpen();
            obj.Communicator.ReadTimeout = int32(max(1, round(1000 * timeoutS)));
            try
                line = strtrim(char(obj.Communicator.ReadOneLine()));
            catch
                line = [];  % the DLL throws on a timeout; the caller treats [] as no reply
                return
            end
            if isempty(line)
                line = [];
            end
        end

        function flush(obj)
            if obj.isOpen()
                obj.Communicator.ClearInputAndOutputBuffers();
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Static)
        function folder = defaultDllFolder()
            % The Coherent Connection 6 install folder.
            folder = fullfile(getenv('ProgramFiles(x86)'), 'Coherent', ...
                'Coherent Connection 6');
            if isempty(getenv('ProgramFiles(x86)'))
                folder = fullfile('C:\Program Files (x86)', 'Coherent', ...
                    'Coherent Connection 6');
            end
        end

        function tf = isAvailable(folder)
            % True on Windows when CoherentConnectionLibrary.dll is in folder (default above).
            if nargin < 1
                folder = obis.transport.CoherentTransport.defaultDllFolder();
            end
            tf = ispc() && isfile(fullfile(folder, obis.transport.CoherentTransport.DllName));
        end
    end

    methods (Access = private)
        function loadDll(obj)
            % Loads the assembly once per MATLAB session (NET.addAssembly is idempotent).
            file = fullfile(obj.DllFolder, obj.DllName);
            if ~obis.transport.CoherentTransport.isAvailable(obj.DllFolder)
                error('obis:CoherentTransport:noDll', ['%s not found (Windows only). ' ...
                    'Install Coherent Connection 6, or use obis.transport.SerialTransport.'], ...
                    file);
            end
            NET.addAssembly(file);
        end

        function requireOpen(obj)
            % Errors unless the port is open.
            if ~obj.isOpen()
                error('obis:CoherentTransport:notOpen', '%s is not open; call open() first.', ...
                    obj.Port);
            end
        end
    end
end


function text = firstLine(text)
% The first non-empty line of a .NET error message.
lines = strtrim(splitlines(string(text)));
lines = lines(lines ~= "");
if isempty(lines)
    text = '';
else
    text = char(erase(lines(1), "Message: "));
end
end
