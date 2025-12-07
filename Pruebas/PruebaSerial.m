%% ===============================================================
%   PREVIEW + CONFIRM + SEND GCODE A MECHINK
% ===============================================================

clear; clc;

%% ===============================================================
%   1. Seleccionar archivo G-code
% ===============================================================
[gfile, gpath] = uigetfile({'*.gcode','GCODE Files'});
if isequal(gfile,0)
    error("No seleccionaste archivo.");
end

filePath = fullfile(gpath, gfile);
fprintf("Archivo cargado: %s\n", filePath);


%% ===============================================================
%   2. Leer archivo y extraer todas las líneas
% ===============================================================
fid = fopen(filePath,'r');
rawLines = {};
line = fgetl(fid);

while ischar(line)
    rawLines{end+1} = strtrim(line);
    line = fgetl(fid);
end

fclose(fid);


%% ===============================================================
%   3. Parseo de trayectoria para visualización
% ===============================================================

X = [];   % puntos X
Y = [];   % puntos Y

currX = 0;
currY = 0;

for i = 1:length(rawLines)
    L = rawLines{i};

    % Saltar comentarios
    if isempty(L) || startsWith(L,"(") || startsWith(L,";")
        continue;
    end

    %% -------- Extraer X --------
    idxX = strfind(L,'X');
    if ~isempty(idxX)
        j = idxX + 1;
        s = '';
        while j <= length(L) && (isstrprop(L(j),'digit') || L(j)=='.' || L(j)=='-')
            s = [s L(j)];
            j = j + 1;
        end
        currX = str2double(s);
    end

    %% -------- Extraer Y --------
    idxY = strfind(L,'Y');
    if ~isempty(idxY)
        j = idxY + 1;
        s = '';
        while j <= length(L) && (isstrprop(L(j),'digit') || L(j)=='.' || L(j)=='-')
            s = [s L(j)];
            j = j + 1;
        end
        currY = str2double(s);
    end

    %% Guardar SOLO movimientos G0/G1
    if startsWith(L,"G0") || startsWith(L,"G1")
        X(end+1) = currX;
        Y(end+1) = currY;
    end
end


%% ===============================================================
%   4. Visualización de trayectoria
% ===============================================================

figure; hold on; axis equal;
plot(X, Y, 'w.-', 'LineWidth', 1.3);
xlabel('X (mm)'); ylabel('Y (mm)');
title("PREVIEW — Trayectoria MECHINK");
set(gca,'Color','k');   % fondo negro
grid on;

% Dibujar hoja carta
paperW = 216;  % mm
paperH = 279;  % mm
rectangle("Position",[0 0 paperW paperH], ...
          "EdgeColor",[0 0.6 1],"LineWidth",1.2);

disp("Revisa la trayectoria en la figura.");

%% ===============================================================
%   5. Confirmación del usuario
% ===============================================================

choice = questdlg("¿Deseas enviar este G-code al robot MECHINK?", ...
                  "Confirmar envío", ...
                  "Sí","No","No");

if strcmp(choice,"No")
    disp("Envío cancelado por el usuario.");
    return;
end


%% ===============================================================
%   6. Enviar G-code a Arduino (handshake "ok")
% ===============================================================

portName = "COM10";
baudRate = 115200;

disp("Conectando a MECHINK...");
arduino = serialport(portName, baudRate);
pause(2);  % tiempo para que Arduino reseteé

disp("Enviando comandos...");

for i = 1:length(rawLines)

    L = strtrim(rawLines{i});

    % Saltar comentarios y vacíos
    if isempty(L) || startsWith(L,"(") || startsWith(L,";")
        continue;
    end

    writeline(arduino, L);

    % Esperar "ok" o "err"
    while true
        if arduino.NumBytesAvailable > 0
            resp = strtrim(readline(arduino));

            if strcmp(resp, "ok")
                break;
            elseif strcmp(resp, "err")
                error("ERROR desde Arduino: IK fuera de rango o movimiento inválido.");
            end
        end
    end

    fprintf("OK: %s\n", L);
end

clear arduino;
disp("MECHINK completó la ejecución del archivo.");
