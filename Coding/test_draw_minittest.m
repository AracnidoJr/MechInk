clear; clc;

% --- 1) Construye una imagen binaria simple con 2 componentes ---
I = false(40,40);
% Componente A: una "L"
I(5:20,10)   = true;   % vertical
I(20,10:25)  = true;   % horizontal
% Componente B: una pequeña diagonal aparte
idx = sub2ind(size(I), 30:34, 30:34);
I(idx) = true;

I0 = I;                            % copia para comparar
A_ones = nnz(I);

% --- 2) Llama a draw en la componente A (arrancando en un '1' seguro) ---
a = [];                            % objeto Arduino no usado por el stub
global E R; E = []; R = [];        % limpia estados iniciales de los "servos"
start_mn = [5,10];                 % un 1 de la "L"
I1 = draw(a, I, start_mn(1), start_mn(2));

% --- 3) Checks rápidos ---
% 3.1) Debe haber menos '1' que al inicio (al menos la componente A visitada -> 0)
A1_ones = nnz(I1);
assert(A1_ones < A_ones, 'No disminuyeron los 1: la visita no ocurrió.');

% 3.2) La componente B debe seguir ahí (no debería borrarse si no la tocamos)
%     Checamos un píxel de B
assert(I1(30,30)==true, 'La otra componente se borró sin haberse visitado.');

% 3.3) Debe haberse escrito log de servo (al menos lápiz up/down)
if evalin('base','exist(''SERVO_LOG'',''var'')')
    LOG = evalin('base','SERVO_LOG');
    assert(~isempty(LOG.pin), 'No hubo llamadas a servoWrite (stub).');
else
    error('No se encontró SERVO_LOG en workspace.');
end

% --- 4) Reporte mínimo en consola ---
fprintf('OK: draw() recorrió la componente A y dejó intacta la B.\n');
fprintf('Llamadas a servoWrite: %d (pins usados: %s)\n', ...
    numel(LOG.pin), mat2str(unique(LOG.pin)));

% --- 5) Visual opcional ---
% figure; subplot(1,2,1); imshow(I0); title('Antes');
% subplot(1,2,2); imshow(I1); title('Después de draw (componente A visitada)');
