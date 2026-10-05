classdef (Abstract) Transport < handle
% obis.transport.Transport is the line link between obis.Laser and an OBIS remote port.
%
%   The OBIS remote speaks SCPI over a serial port: each command is one line ending in CR/LF,
%   and with handshaking on (obis.Laser turns it on at connect) the laser answers every
%   command with OK, every query with its value and then OK, and a refused command with
%   ERR-<code> (docs/scpi.md). A transport only moves lines; obis.Laser interprets them.
%
%   Subclasses implement:
%       open()                       open the port; errors if it cannot
%       close()                      close the port; never throws
%       tf = isOpen()
%       writeLine(text)              send one line (the terminator is added)
%       line = readLine(timeoutS)    the next line without its terminator, or [] on timeout
%       flush()                      discard anything unread
%
%   Description (read-only)  where the transport goes, e.g. 'COM15 @ 115200', for records.
%
%   See also obis.transport.SerialTransport, obis.transport.SimulatedTransport, obis.Laser

    properties (Abstract, SetAccess = protected)
        Description  % where the transport goes, for records and the log
    end

    methods (Abstract)
        open(obj)
        close(obj)
        tf = isOpen(obj)
        writeLine(obj, text)
        line = readLine(obj, timeoutS)
        flush(obj)
    end
end
