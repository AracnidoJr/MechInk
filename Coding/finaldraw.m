function finaldraw()
% FINALDRAW con preprocesado y análisis integrados (sim o hardware).
% - Mantiene la lógica original: Canny -> (opcional ojos) -> rotación -> draw
% - Añade: parámetros para reducir densidad de bordes, métricas y progreso.

    %% ================== PARÁMETROS EDITABLES ==================
    IMG_NAME     = 'xim2.png';   
    COM_PORT     = 'COM3';      
    ROTATE180    = false;         % true = imrotate(...,180) como el original

    % Canny
    CANNY_THR    = [0.05, 0.20]; % subir p.ej. [0.08 0.25] para menos bordes
    CANNY_SIGMA  = 1.0;          % sigma del filtro Gauss antes de Canny

    % PREPROCESADO (para reducir #de bordes)
    DO_RESIZE    = false;        % true para reducir tamaño antes de Canny
    RESIZE_SCALE = 0.50;         % 0.5 = 50% (si DO_RESIZE=true)
    DO_CLEAN     = true;         % limpieza morfológica post-Canny
    MIN_ISLAND   = 20;           % bwareaopen: elimina islitas < MIN_ISLAND píxeles (si DO_CLEAN)
    DO_THIN      = true;         % adelgazar a 1 píxel de ancho
    DO_SPUR      = true;         % podar ramitas cortas
    SPUR_ITERS   = 5;            % iteraciones de spur

    % Detector de ojos; requiere Computer Vision Toolbox)
    USE_EYEBOOST = true;         % refuerzo de bordes en la franja de ojos (como el original)
    EYE_THRESH   = 72;           % i<72 => w=1 en esa franja

    % Servo
    PEN_UP       = 85;          
    PEN_DOWN     = 92;           

    % Visualización y progreso
    SHOW_PLOTS   = true;         % mostrar figuras
    PROGRESS_EVERY_ROWS = 50;    % imprime progreso cada N filas
    %% ==========================================================

    clc;

    % ---------- 1) Cargar imagen ----------
    assert(exist(IMG_NAME,'file')==2, 'No encuentro %s', IMG_NAME);
    u = imread(IMG_NAME);
    if size(u,3) > 1
        i = rgb2gray(u);
    else
        i = u;
    end

    % Opcional: reducir la imagen antes de Canny
    if DO_RESIZE
        i = imresize(i, RESIZE_SCALE, 'nearest');
    end

    % ---------- 2) Canny ----------
    % Nota: si subes CANNY_THR reduces bordes -> menos tiempo de trazo.
    w = edge(i, 'canny', CANNY_THR, CANNY_SIGMA);

    % ---------- 3) Refuerzo en zona de ojos (opcional) ----------
    if USE_EYEBOOST
        hasCV = ~isempty(which('vision.CascadeObjectDetector'));
        if hasCV
            try
                EyeDetect = vision.CascadeObjectDetector('EyePairBig');
                BB = EyeDetect(u);              % llamada moderna (sin step)
                if ~isempty(BB)
                    bb = BB(1,:);               % [x y w h] del primer par de ojos
                    l  = round(bb(4)/3);
                    s1 = bb(2) + l;   s2 = bb(2) + 2*l;
                    t1 = bb(1);       t2 = bb(1) + bb(3);

                    % Si hiciste DO_RESIZE, hay desajuste de escalas entre u (original) e i (redimensionada).
                    % Ajustamos el BB a la escala de i.
                    if DO_RESIZE
                        s1 = round(s1 * RESIZE_SCALE);
                        s2 = round(s2 * RESIZE_SCALE);
                        t1 = round(t1 * RESIZE_SCALE);
                        t2 = round(t2 * RESIZE_SCALE);
                    end

                    [H,W] = size(i);
                    s1 = max(1, min(H, s1)); s2 = max(1, min(H, s2));
                    t1 = max(1, min(W, t1)); t2 = max(1, min(W, t2));
                    if s2>=s1 && t2>=t1
                        mask = i(s1:s2, t1:t2) < EYE_THRESH;
                        w(s1:s2, t1:t2) = w(s1:s2, t1:t2) | mask;
                    end
                end
            catch
                % si falla el detector, seguimos con w tal cual
            end
        end
    end

    % ---------- 4) Limpieza post-Canny (opcional, no cambia tu lógica) ----------
    if DO_CLEAN && MIN_ISLAND>0
        w = bwareaopen(w, MIN_ISLAND);
    end
    if DO_THIN
        w = bwmorph(w, 'thin', Inf);
    end
    if DO_SPUR && SPUR_ITERS>0
        w = bwmorph(w, 'spur', SPUR_ITERS);
    end

    % ---------- 5) Rotación (misma idea del original) ----------
    if ROTATE180
        I = imrotate(w, 180);
    else
        I = w;
    end

    % Mostrar la máscara EXACTA que se dibujará
    if SHOW_PLOTS
        figure('Name','Máscara a dibujar');
        imshow(I); title('Máscara que se dibujará (final)');
        impixelinfo;
    end

    % Métrica rápida de densidad de trabajo
    n_est = nnz(I);
    fprintf('[INFO] #pixeles 1 a dibujar (estimación de trabajo): %d\n', n_est);

    % Guarda copia "antes" para análisis
    assignin('base','I_before', I);

    % ---------- 6) Conectar a Arduino (o stub) ----------
    try
        a = arduino(COM_PORT);  % ArduinoIO (o stub si simulas)
    catch ME
        error('No se pudo abrir %s: %s', COM_PORT, ME.message);
    end
    servoAttach(a,9);
    servoAttach(a,8);
    servoAttach(a,7);

    set(0,'RecursionLimit',2000);

    % Lápiz arriba e inicialización de globals como en tu flujo
    servoWrite(a,7,PEN_UP);
    pause(0.02);
    global E R;
    E = servoRead(a,9);
    R = servoRead(a,8);
    pause(0.1);

    % ---------- 7) Barrido y dibujo ----------
    [rows, cols] = size(I);
    tStart = tic;
    for p = 2:rows
        if mod(p, PROGRESS_EVERY_ROWS)==0
            fprintf('Fila %d de %d\n', p, rows);
        end
        for t = 2:cols
            if I(p,t) == 1
                I = draw(a, I, p, t);
            end
        end
    end
    t_total = toc(tStart);

    % Guarda copia "después" para análisis
    assignin('base','I_after', I);

    % ---------- 8) Métricas finales ----------
    n_before = nnz(evalin('base','I_before'));
    n_after  = nnz(I);

    fprintf('--- RESUMEN FINALDRAW ---\n');
    fprintf('Pixeles 1 antes:  %d\n', n_before);
    fprintf('Pixeles 1 después:%d\n', n_after);
    fprintf('Tiempo total:     %.2f s\n', t_total);

    % Si hubo stub de servoWrite, habrá SERVO_LOG en el workspace.
    hasLog = evalin('base','exist(''SERVO_LOG'',''var'')');
    if hasLog
        LOG = evalin('base','SERVO_LOG');
        nCalls = numel(LOG.pin);
        fprintf('Llamadas a servoWrite: %d\n', nCalls);

        % Conteo por pin
        [upins,~,ic] = unique(LOG.pin);
        counts = accumarray(ic,1);
        T = table(upins(:), counts, 'VariableNames', {'Pin','Calls'});
        disp(T);

        % Estimar strokes (bajadas/subidas de lápiz)
        penIdx  = find(LOG.pin==7);
        penVals = LOG.val(penIdx);
        penDown = PEN_DOWN; penUp = PEN_UP;
        isDown  = abs(penVals - penDown) < 1e-6;
        isUp    = abs(penVals - penUp)   < 1e-6;
        downs   = sum(diff([0; isDown])==1);
        ups     = sum(diff([0; isUp])==1);
        fprintf('Strokes (pen down): %d | Pen-ups: %d\n', downs, ups);

        % Asignar log a base por si quieres explorar luego
        assignin('base','SERVO_LOG',LOG);

        if SHOW_PLOTS
            figure('Name','Evolución de valores enviados a servos');
            plot(LOG.val); xlabel('Paso'); ylabel('Valor'); grid on;
            title('Valores enviados (todos los pines intercalados)');
        end
    else
        fprintf('No se encontró SERVO_LOG (quizá estás en hardware real).\n');
    end

    if SHOW_PLOTS
        figure('Name','Antes vs Después de draw');
        subplot(1,2,1); imshow(evalin('base','I_before')); title('Máscara antes');
        subplot(1,2,2); imshow(I);                         title('Tras barrido con draw');
    end

    fprintf('--- FIN ---\n');
end

%VALIDACIONES EN TERMINAL
%nnz(I_before) --> cuántos pixeles "1" había al inicio
%nnz(I_after) --> deberían ser 0 (ya barridos)
%size(SERVO_LOG.pin) --> cuántas llamadas totales a servo (si simulas)
