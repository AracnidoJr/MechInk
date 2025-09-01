function servoWrite(~, pin, val)
% STUB: registra todo en un log accesible desde el workspace
persistent LOG
if isempty(LOG)
    LOG = struct('t',[], 'pin',[], 'val',[]);
end
LOG.t(end+1)   = now;
LOG.pin(end+1) = pin;
LOG.val(end+1) = val;
assignin('base','SERVO_LOG',LOG);
% comentar si no quieres spam en consola:
% fprintf('[STUB] servoWrite pin %d = %g\n', pin, val);
end
