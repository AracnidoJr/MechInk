%% ===============================================================
%       SCARA – Vectorizador
% ===============================================================

clear; close all; clc;

%% 1. Seleccionar imagen
[filename, pathname] = uigetfile({'*.png;*.jpg;*.jpeg','Imágenes'});
if isequal(filename,0), return; end

I = imread(fullfile(pathname, filename));

if size(I,3)>1
    Igray = rgb2gray(I);
else
    Igray = I;
end

figure; imshow(Igray); title("Imagen original en gris");

%% ===============================================================
%   2. FILTRO ANTI-TEXTURA PROFESIONAL
% ===============================================================

If1 = imbilatfilt(Igray, 50, 20);
If2 = imgaussfilt(If1, 1.0);
se = strel('disk',1);
If3 = imopen(If2, se);

If4 = imguidedfilter(If3, 'NeighborhoodSize', 17, ...
                            'DegreeOfSmoothing', 0.001);

figure; imshow(If4); title("ANTI-TEXTURA (base para bordes)");


%% ===============================================================
%   3. DETECCIÓN DE BORDES
% ===============================================================

T = graythresh(If4);
E1 = edge(If4,'canny',[0.3*T 1.2*T]);
E2 = edge(If4,'sobel', 0.12);

E = E1 | E2;

E = bwmorph(E,'clean');
E = bwareaopen(E, 40);

figure; imshow(E); title("Bordes combinados y limpios");


%% ===============================================================
%   4. SKELETON
% ===============================================================

Sk = bwskel(E);
Sk = bwareaopen(Sk, 30);

figure; imshow(Sk); title("Skeleton final");


%% ===============================================================
%   5. EXTRAER CURVAS
% ===============================================================

CC = bwconncomp(Sk, 8);
curvas = {};
maxJump = 15;

for i = 1:CC.NumObjects
    pix = CC.PixelIdxList{i};
    if numel(pix) < 30, continue; end

    [y,x] = ind2sub(size(Sk), pix);
    P = [x y];

    remaining = P;
    [~, idx0] = min(remaining(:,2));
    cur = remaining(idx0,:);
    remaining(idx0,:) = [];
    curve = cur;

    while ~isempty(remaining)
        d = sum((remaining - cur).^2, 2);
        [~, idxMin] = min(d);
        cur = remaining(idxMin,:);
        curve(end+1,:) = cur;
        remaining(idxMin,:) = [];
    end

    seg = curve(1,:);
    for k = 2:size(curve,1)
        if norm(curve(k,:) - curve(k-1,:)) > maxJump
            if size(seg,1) > 2
                curvas{end+1} = seg;
            end
            seg = curve(k,:);
        else
            seg(end+1,:) = curve(k,:);
        end
    end
    if size(seg,1) > 2
        curvas{end+1} = seg;
    end
end


%% ===============================================================
%   6. MOSTRAR CURVAS
% ===============================================================

figure; hold on; axis equal; set(gca,'YDir','reverse');
title("Curvas finales – Travel Optimization");
for i = 1:length(curvas)
    plot(curvas{i}(:,1), curvas{i}(:,2), 'LineWidth', 1.2);
end
grid on;

%% ===============================================================
%   7. GENERAR ARCHIVO G-CODE, PREVIEW Y ENVÍO
% ===============================================================

disp("Generando G-Code...");

feedrate   = 2000;
travelrate = 6000;
px_to_mm   = 0.25;     % mm por pixel

%% ===============================================================
%   7. GENERAR ARCHIVO G-CODE, PREVIEW Y ENVÍO
% ===============================================================

disp("Generando G-Code...");

feedrate   = 2000;
travelrate = 6000;
px_to_mm   = 0.25;     % mm por pixel

%% ================== 7.1 Bounding box global ====================
allPts = vertcat(curvas{:});
allPtsMM = allPts * px_to_mm;

minX = min(allPtsMM(:,1));
maxX = max(allPtsMM(:,1));
minY = min(allPtsMM(:,2));
maxY = max(allPtsMM(:,2));

W = maxX - minX;
H = maxY - minY;

%% ================== 7.2 Config hoja carta + margen 40mm ========
paperW = 216;    % mm
paperH = 279;    % mm
margin = 40;     % margen uniforme en los 4 lados

usableW = paperW - 2*margin;    % = 136 mm
usableH = paperH - 2*margin;    % = 199 mm

% Escala para que el dibujo quepa dentro del área útil
scale = min(usableW/W, usableH/H);

%% ================== 7.3 Crear archivo ===========================
outputFile = "output.gcode";
fid = fopen(outputFile,"w");

fprintf(fid,"(=== MECH INK — GCODE DESDE IMAGEN ===)\n");
fprintf(fid,"G21\n");
fprintf(fid,"G90\n");
fprintf(fid,"M5\n");
fprintf(fid,"G4 P0.2\n");

% Origen seguro
fprintf(fid,"G0 X0 Y0 F6000\n");
fprintf(fid,"G4 P0.2\n");

%% ================== 7.4 Generar trazos ==========================
for i = 1:length(curvas)

    P = curvas{i};
    Pmm = P * px_to_mm;

    % Mapear a hoja dentro del margen 40 mm
    Xpage = margin + (Pmm(:,1) - minX) * scale;
    Ypage = margin + (maxY - Pmm(:,2)) * scale;

    fprintf(fid,"; --- curva %d ---\n", i);

    % travel
    fprintf(fid,"G0 X%.2f Y%.2f F%d\n", Xpage(1), Ypage(1), travelrate);

    % pluma abajo
    fprintf(fid,"M3\n");

    % dibujar
    for k = 2:length(Xpage)
        fprintf(fid,"G1 X%.2f Y%.2f F%d\n", Xpage(k), Ypage(k), feedrate);
    end

    % pluma arriba
    fprintf(fid,"M5\n");
end

% Regresar a origen seguro
fprintf(fid,"G0 X0 Y0 F6000\n");
fprintf(fid,"G4 P0.2\n");

fclose(fid);
disp("G-code escrito en archivo: " + outputFile);


%% ===============================================================
%   7.5 Cargar archivo para PREVIEW
% ===============================================================

fileText = fileread(outputFile);
fileLines = splitlines(string(fileText));

Xprev = [];
Yprev = [];

currX = 0;
currY = 0;

for i = 1:length(fileLines)

    L = strtrim(fileLines(i));
    if L == "" || startsWith(L,"(") || startsWith(L,";")
        continue;
    end

    if startsWith(L,"G0") || startsWith(L,"G1")

        % convertir línea a char
        Lc = char(L);

        % -------- X --------
        idx = strfind(Lc,"X");
        if ~isempty(idx)
            j = idx+1; s = "";
            while j <= length(Lc) && (isstrprop(Lc(j),'digit') || Lc(j)=='.' || Lc(j)=='-')
                s = s + Lc(j);
                j = j+1;
            end
            currX = str2double(s);
        end

        % -------- Y --------
        idx = strfind(Lc,"Y");
        if ~isempty(idx)
            j = idx+1; s = "";
            while j <= length(Lc) && (isstrprop(Lc(j),'digit') || Lc(j)=='.' || Lc(j)=='-')
                s = s + Lc(j);
                j = j+1;
            end
            currY = str2double(s);
        end

        Xprev(end+1) = currX;
        Yprev(end+1) = currY;
    end
end

%% ================== 7.6 PREVIEW (FIX DEFINITIVO) =================
figure; hold on; axis equal;
set(gca,'Color','k');

% Forzar límites EXACTOS de la hoja carta
xlim([0 paperW]);
ylim([0 paperH]);

% Marco 40mm
rectangle("Position",[margin margin usableW usableH], ...
          "EdgeColor",[0 0.6 1], "LineWidth",1.3);

% Dibujar trayectoria
plot(Xprev, Yprev, 'w.-', 'LineWidth', 1.2);

title("PREVIEW — Trayectoria MECHINK (Margen 40 mm)");
xlabel("X (mm)");
ylabel("Y (mm)");
grid on;

disp("Revisa la trayectoria mostrada.");


%% ===============================================================
%   7.7 Confirmación antes de enviar serial
% ===============================================================

choice = questdlg("¿Enviar este G-code al robot MECHINK?", ...
                  "Confirmar", ...
                  "Sí","No","No");

if strcmp(choice,"No")
    disp("Envío cancelado.");
    return;
end


%% ===============================================================
%   7.8 ENVÍO SERIAL CON HANDSHAKE "ok"
% ===============================================================

portName = "COM10";
arduino = serialport(portName,115200);
pause(2);

disp("Enviando comandos al robot...");

for i = 1:length(fileLines)

    L = strtrim(fileLines(i));

    if L=="" || startsWith(L,"(") || startsWith(L,";")
        continue;
    end

    writeline(arduino, L);

    while true
        if arduino.NumBytesAvailable > 0
            resp = strtrim(readline(arduino));

            if resp == "ok"
                break;

            elseif resp == "err"
                error("ERROR del robot (IK o movimiento inválido).");
            end
        end
    end

    fprintf("OK: %s\n", L);
end

clear arduino;
disp("G-code ejecutado correctamente por MECHINK.");
