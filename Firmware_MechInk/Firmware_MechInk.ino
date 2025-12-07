// ======================================================
//      MECH INK — Firmware SCARA
//      By: Iván Vázquez
// ======================================================

#include <AccelStepper.h>
#include <Servo.h>

// ======================================================
//                CONFIGURACIÓN DEL SERVO
// ======================================================
Servo penServo;
const int SERVO_PIN = 13;

const int PEN_UP   = 78; 
const int PEN_DOWN = 100;    

// ======================================================
//                  PINES CNC SHIELD V3
// ======================================================
// X.STEP → D2
// X.DIR  → D5
// Y.STEP → D3
// Y.DIR  → D6
// ENABLE → D8

AccelStepper motor1(AccelStepper::DRIVER, 2, 5);  // Joint 1 (hombro)
AccelStepper motor2(AccelStepper::DRIVER, 3, 6);  // Joint 2 (codo)

const int EN_PIN = 8;

// ======================================================
//                GEOMETRÍA DEL SCARA
// ======================================================
const float L1 = 219.5f;
const float L2 = 162.29f;

const float SCARA_OFFSET_X = -130.0f;
const float SCARA_OFFSET_Y = 18.0f;

// ======================================================
//               CALIBRACIÓN DE PASOS
// ======================================================
#define STEPS_PER_REV_MOTOR   3200.0f
#define GEAR_RATIO            3.0f
#define STEPS_PER_REV_JOINT  (STEPS_PER_REV_MOTOR * GEAR_RATIO)
#define STEPS_PER_DEG        (STEPS_PER_REV_JOINT / 360.0f)
#define STEPS_PER_RAD        (STEPS_PER_REV_JOINT / (2.0f * PI))

long angleToStepsDeg(float deg) {
  return (long)round(deg * STEPS_PER_DEG);
}

long angleToStepsRad(float rad) {
  return (long)round(rad * STEPS_PER_RAD);
}

// ======================================================
//              ESTADO DE POSICIÓN
// ======================================================
float currX = 0.0f, currY = 0.0f;

// ======================================================
//          API INTERNA DEL FIRMWARE
// ======================================================
void processGcode(String cmd);
float extractFloat(String s, char key, float fallback);
bool inverseKinematics(float x, float y, float &theta1_deg, float &theta2_deg);
void moveToXY(float x, float y);
void penDown();
void penUp();

// ======================================================
//                        SETUP
// ======================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  penServo.attach(SERVO_PIN);
  penUp();

  pinMode(EN_PIN, OUTPUT);
  digitalWrite(EN_PIN, LOW);

  motor1.setMaxSpeed(2000);
  motor1.setAcceleration(800);
  motor2.setMaxSpeed(2000);
  motor2.setAcceleration(800);

  motor1.setCurrentPosition(0);
  motor2.setCurrentPosition(0);

  //Serial.println("MECH INK Ready (IK ON)");
}

// ======================================================
//                        LOOP
// ======================================================
void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();

    if (line.length() > 0) {
      processGcode(line);
    }
  }

  motor1.run();
  motor2.run();
}

// ======================================================
//                PROCESAR G-CODE
// ======================================================
void processGcode(String cmd) {

  if (cmd.startsWith("G0") || cmd.startsWith("G1")) {

    float x = extractFloat(cmd, 'X', currX);
    float y = extractFloat(cmd, 'Y', currY);

    moveToXY(x, y);

    currX = x;
    currY = y;

    Serial.println("ok"); //flag para Matlab
    return;
  }

  if (cmd.startsWith("M3")) {
    penDown();
    Serial.println("ok");
    return;
  }

  if (cmd.startsWith("M5")) {
    penUp();
    Serial.println("ok");
    return;
  }

  Serial.println("ok");
}

// ======================================================
//              EXTRAER FLOAT DEL GCODE
// ======================================================
float extractFloat(String s, char key, float fallback) {
  int idx = s.indexOf(key);
  if (idx == -1) return fallback;

  int endIdx = idx + 1;
  while (endIdx < s.length() &&
        (isDigit(s[endIdx]) || s[endIdx]=='-' || s[endIdx]=='.'))
    endIdx++;

  return s.substring(idx+1, endIdx).toFloat();
}

// ======================================================
//          CINEMÁTICA INVERSA SCARA 
// ======================================================
bool inverseKinematics(float x, float y, float &theta1_deg, float &theta2_deg) {

  float Xp = x - SCARA_OFFSET_X;
  float Yp = y - SCARA_OFFSET_Y;

  float r2 = Xp*Xp + Yp*Yp;
  float r  = sqrtf(r2);

  float r_max = (L1 + L2);
  if (r > r_max) {
    Serial.println("err"); // flag para Matlab
    return false;
  }

  float C2 = (r2 - L1*L1 - L2*L2) / (2.0f * L1 * L2);
  C2 = constrain(C2, -1.0f, 1.0f);

  float S2_sq = 1.0f - C2*C2;
  if (S2_sq < 0.0f) S2_sq = 0.0f;
  float S2 = sqrtf(S2_sq);

  float psi  = atan2f(S2, C2);
  float K1 = L1 + L2 * C2;
  float K2 = L2 * S2;

  float theta = atan2f(Yp, Xp) - atan2f(K2, K1);

  theta1_deg = theta * 180.0f / PI;
  theta2_deg = psi   * 180.0f / PI;

  return true;
}

// ======================================================
//        MINI-PLANNER FINO (Modo A – Ultra Smooth)
// ======================================================
void moveLinear(float x0, float y0, float x1, float y1) {

  float dx = x1 - x0;
  float dy = y1 - y0;
  float dist = sqrtf(dx*dx + dy*dy);

  float segment_length = 1.2f; 
  int segments = max(40, (int)(dist / segment_length));

  float stepx = dx / segments;
  float stepy = dy / segments;

  float cx = x0;
  float cy = y0;

  for (int i = 1; i <= segments; i++) {

    cx += stepx;
    cy += stepy;

    float theta1, theta2;
    if (!inverseKinematics(cx, cy, theta1, theta2)) {
      //Serial.println("Segment IK FAIL");
      continue;
    }

    long s1 = angleToStepsDeg(theta1);
    long s2 = angleToStepsDeg(theta2);

    motor1.moveTo(s1);
    motor2.moveTo(s2);

    while (motor1.distanceToGo() != 0 || motor2.distanceToGo() != 0) {
      motor1.run();
      motor2.run();
    }
  }
}

// ======================================================
//          MOVER A UN PUNTO XY USANDO IK + PASOS
// ======================================================
void moveToXY(float x, float y) {

  /*
  Serial.println("========== MOVE TO XY ==========");
  Serial.print("Current  X="); Serial.print(currX);
  Serial.print("  Y="); Serial.println(currY);
  Serial.print("Target   X="); Serial.print(x);
  Serial.print("  Y="); Serial.println(y);
  Serial.print("Distance = "); Serial.println(dist);
  Serial.print("Segments = "); Serial.println(segments);
  Serial.println("----- BEGIN -----");
  */

  moveLinear(currX, currY, x, y);

  currX = x;
  currY = y;

  //Serial.println("MOVE COMPLETE");
}

// ======================================================
//                    SERVO PLUMA
// ======================================================
void penDown() {
  for (int a = PEN_UP; a <= PEN_DOWN; a++) {
    penServo.write(a);
    delay(4);
  }
  delay(80);
}

void penUp() {
  for (int a = PEN_DOWN; a >= PEN_UP; a--) {
    penServo.write(a);
    delay(4);
  }
}
