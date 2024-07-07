#include <Servo.h>
#include <ESP8266WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>

int sensorPin = A0;
Servo myservo;

WiFiClient espClient;
PubSubClient mqttClient(espClient);

const char* mqttBroker = "mqtt-dashboard.com";
const int mqttPort = 1883;
const char* mqttUsername = "";  // Jika dibutuhkan
const char* mqttPassword = "";  // Jika dibutuhkan
const char* mqttClientId = "FishFeeder_ID";

bool isServoMoving = false;

void servoCallback(char* topic, byte* payload, unsigned int length) {
  // Handle messages received on the topic "servo/publish"
  payload[length] = '\0'; // Null-terminate the payload
  String message = String((char*)payload);
  
  if (message == "1" && !isServoMoving) {
    isServoMoving = true;

    myservo.write(180);
    Serial.println("Servo bergerak ke posisi 180 derajat");
    delay(2000);

    myservo.write(0);
    Serial.println("Servo bergerak ke posisi 0 derajat");
    delay(2000);

    myservo.write(180);
    Serial.println("Servo bergerak ke posisi 180 derajat");
    delay(2000);

    myservo.write(0);
    Serial.println("Servo bergerak ke posisi 0 derajat");
    delay(2000);

    isServoMoving = false;
  }
}

void setup() {
  Serial.begin(9600);
  WiFiManager wifiManager;
  
  if (!wifiManager.autoConnect("NodeMCU-Config")) {
    Serial.println("Gagal terhubung dan tidak ada konfigurasi");
    delay(3000);
    ESP.reset();
    delay(5000);
  }

  Serial.println("Terhubung ke WiFi!");

  myservo.attach(D4);
  mqttClient.setServer(mqttBroker, mqttPort);
  mqttClient.setCallback(servoCallback);

  Serial.println("Setup selesai. Mulai loop...");
}

void loop() {
  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();

  int sensorValue = analogRead(sensorPin);
  Serial.println(sensorValue);
  int turbidity = map(sensorValue, 0, 750, 100, 0);
  String waterStatus = (sensorValue > 500) ? "Jernih" : "Keruh";
  String waterStatus2 = (turbidity < 500) ? "air_jernih" : "air_keruh";
  Serial.print(turbidity);
  Serial.print("°C, Status Air: ");
  Serial.println(waterStatus);
  
  // Publish water status to MQTT
  String mqttTopic = "water/status";
  mqttClient.publish(mqttTopic.c_str(), waterStatus.c_str());
  
  String mqttTopic1 = "water/status1";
  mqttClient.publish(mqttTopic1.c_str(), String(sensorValue).c_str());

  delay(1000);
}

void reconnectMQTT() {
  while (!mqttClient.connected()) {
    Serial.println("Mencoba terhubung ke MQTT...");
    if (mqttClient.connect(mqttClientId, mqttUsername, mqttPassword)) {
      Serial.println("Terhubung ke broker MQTT");
      mqttClient.subscribe("servo/publish");
    } else {
      Serial.print("Gagal terhubung ke broker MQTT, coba lagi dalam 5 detik...");
      delay(5000);
    }
  }
}
