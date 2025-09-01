function a = arduino(port, varargin)
% STUB: simula el objeto Arduino
if nargin<1, port = 'COM_SIM'; end
a = struct('Port', port, 'IsStub', true);
fprintf('[STUB] arduino conectado a %s (simulado)\n', port);
end
