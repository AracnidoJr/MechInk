function I = draw(a, I, m, n)
% DRAW  Recorre recursivamente bordes (1) vecinos y dibuja con el plotter.
% - Evita accesos fuera de rango en bordes
% - Usa vecindad recortada y any() para el chequeo inicial
% - Mantiene recursividad y marcado I(m,n)=0

    % Tamaño imagen
    [rows, cols] = size(I);

    % Recorta vecindad a los límites de la imagen
    r1 = max(1, m-1); r2 = min(rows, m+1);
    c1 = max(1, n-1); c2 = min(cols, n+1);

    % Submatriz vecina e ignora el centro
    neigh = I(r1:r2, c1:c2);
    % Índices locales del centro dentro de la ventana
    ci = m - r1 + 1; cj = n - c1 + 1;
    neigh(ci, cj) = 0;

    % ¿Hay al menos un vecino = 1?
    if any(neigh(:))
        reach(a, m, n, [rows, cols]);
        servoWrite(a, 7, 92);    % lápiz abajo
        pause(0.01);

        % Marca el actual como visitado
        I(m, n) = 0;

        % Recorre vecinos dentro de la ventana recortada
        for i = r1:r2
            for j = c1:c2
                if I(i, j) == 1
                    I = draw(a, I, i, j);
                end
            end
        end
    end

    % Lápiz arriba (si no había vecinos, simplemente no dibuja)
    servoWrite(a, 7, 85);
    pause(0.01);
end

function reach(a, m, n, sz)
% REACH  Convierte (m,n) a ángulos y mueve servos suavemente.

    % sz = [rows cols]
    t = calct(m, n, sz(1), sz(2));
    p = calcp(m, n, sz(1), sz(2));

    % Clamp de seguridad a [0,180]
    p = min(max(p, 0), 180);
    t = min(max(t, 0), 180);

    % Orden original: articulación 9 con 180 - p, articulación 8 con 180 - t
    servoAngle(a, 9, 180 - p);
    servoAngle(a, 8, 180 - t);

    % Actualiza globals (si no existen, se crean)
    global E R;
    E = 180 - p;
    R = 180 - t;
end

function t = calct(r, c, o, u)
% CALCT  Ángulo t (redondeado a 0.1°). Misma fórmula con saneo numérico.

    % Mapeo de índice de imagen a coordenadas "físicas"
    y = (r / o) * 30 + 4;
    x = (c / u) * 20 + 4;

    % h en [-1,1] para evitar NaN por redondeos numéricos
    h = (800 - (x*x + y*y)) / 800;
    h = min(1, max(-1, h));

    k = acosd(h);
    k = k * 10;
    t = round(k) / 10;
end

function p = calcp(r, c, o, u)
% CALCP  Ángulo p (redondeado a 0.1°). Usa atan2d para evitar y=0 y cuadrantes.

    y = (r / o) * 30 + 4;
    x = (c / u) * 20 + 4;

    h = (800 - (x*x + y*y)) / 800;
    h = min(1, max(-1, h));
    l = acosd(h);

    % atan2d(x,y) ≈ atan2(x, y) en grados, robusto si y=0
    base = atan2d(x, y);

    k = base + (l / 2);
    k = k * 10;
    p = round(k) / 10;
end

function servoAngle(a, p, n)
% SERVOANGLE  Interpola del ángulo previo al nuevo con pasos de 0.1°.
% Mantiene la lógica de globals y pausas, pero con inicialización segura.

    global E R;

    % Inicializa si están vacíos (primera llamada del programa)
    if isempty(E), E = n; end
    if isempty(R), R = n; end

    % Clamp de seguridad
    n = min(max(n, 0), 180);

    if p == 9
        prev = E;
    else
        prev = R;
    end

    if abs(prev - n) > 1
        if n > prev
            % De prev a n
            for i = prev : 0.1 : n
                servoWrite(a, p, i);
            end
            pause(0.5);
        else
            % De n a prev, manteniendo los mismos pasos que el original
            for i = n : 0.1 : prev
                servoWrite(a, p, prev - i + n);
            end
            pause(0.5);
        end
    else
        servoWrite(a, p, n);
    end

    % Actualiza el global correspondiente
    if p == 9
        E = n;
    else
        R = n;
    end
end
