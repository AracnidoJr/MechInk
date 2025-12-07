(--- Cuadrado simple desde origen (0,0) ---)

G21
G90

(Pluma arriba)
M5
G4 P0.2

; Ir al origen de la hoja
G0 X0 Y0 F6000
G4 P0.2

; Mover al inicio del cuadrado
G0 X10 Y10 F6000

(Pluma abajo)
M3
G4 P0.1

; DIBUJAR CUADRADO 50x50

; 1. Lado superior → derecha
G1 X60 Y10 F1500

; 2. Lado derecho → arriba
G1 X60 Y60 F1500

; 3. Lado inferior → izquierda
G1 X10 Y60 F1500

; 4. Lado izquierdo → abajo (cerrar cuadrado)
G1 X10 Y10 F1500

(Pluma arriba)
M5

; volver a origen
G0 X0 Y0 F6000
G4 P0.2
