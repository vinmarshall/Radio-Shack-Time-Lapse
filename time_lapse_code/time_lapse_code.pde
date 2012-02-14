/*
 * Radio Shack - Rugged Outdoor Time Lapse 
 * Version 1.0
 *
 * This code drives a modified Canon powershot camera in a 
 * ruggedized, solar powered, very long term time lapse setup.
 *
 * Check the repository for the most recent version of this code:
 * https://github.com/vinmarshall/Radio-Shack-Time-Lapse
 *
 * Copyright (c) 2012 Vin Marshall (vlm@2552.com, www.2552.com)
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.  
 */

#define SUNLIGHT_THRESHOLD 250
#define CAMERA_SCREEN_THRESHOLD 250 
#define WAKEUP_TIME 4000
#define SHUTOFF_TIME 120000 
#define DEBUG 1

const int enableSwPin = 2;
const int powerRelayPin = 9;
const int shutterRelayPin = 8;
const int intervalPin = A0;
const int sunlightPin= A1;
const int cameraScreenPin = A2;
const int sunlightLedPin = 12;
const int statusLedPin = 11;

bool sunlight = false;
bool enabled = false;
bool lastEnableState = 0;
bool pictureTaken = false;
unsigned long interval = 0;
unsigned long lastMillis = 0;
unsigned long lastPictureMillis = 0;
unsigned long numPictures = 0;

unsigned long debounceTime = 0;
unsigned long debounceInterval = 50;

 
void setup() {
  pinMode(enableSwPin, INPUT);
  pinMode(powerRelayPin, OUTPUT);
  pinMode(shutterRelayPin, OUTPUT);
  pinMode(sunlightLedPin, OUTPUT);
  pinMode(statusLedPin, OUTPUT);

  // Make sure our relays are off by default
  digitalWrite(powerRelayPin, LOW);
  digitalWrite(shutterRelayPin, LOW);

  if (DEBUG) {
    Serial.begin(9600);
    Serial.println("Starting...");
  }
}
 
void loop() {

  /*
   * Read the "enable" switch's state
   *
   * The enable switch is on the control panel, to the left of the 
   * timer interval pot.  It enables or disables picture taking.
   */

  bool enableReading = digitalRead(enableSwPin);
  if (enableReading != lastEnableState) {
    debounceTime = millis();
  }

  if ((millis() - debounceTime) > debounceInterval) {
    enabled = enableReading;
  }

  lastEnableState = enableReading;

  /*
   * Check for daylight
   *
   * We read the photoresistor mounted in the camera's glass portal 
   * to determine whether it is day or night outside.  You may need to 
   * adjust the constants used in this section (defined above) to get
   * a day/night cutoff point that works for you.
   */

  int sunlightReading = analogRead(sunlightPin);
  sunlight = (sunlightReading >= SUNLIGHT_THRESHOLD);
  digitalWrite(sunlightLedPin, sunlight);

  /*
   * Read the interval setting
   *
   * We are reading the "timer interval" pot on the front panel and 
   * mapping it to a number of seconds between pictures.
   */

  int intervalReading = analogRead(intervalPin) + 5;  // minimum of 5
  interval = 1000 * (unsigned long) intervalReading;  // 1 to 1 sec.


  /*
   * At the end of an interval if the sun is out and the camera is 
   * enabled, shoot a picture.
   *
   * The second line of this test handles rollovers - it ensures that
   * if there has been a rollover, then both our lastMillis + interval 
   * timer AND the millis() timer have both rolled over.
   */

  if ( (millis() > (lastMillis + interval)) &&
       ( (lastMillis + interval > lastMillis) || (millis() < lastMillis) ) ) {

    // Print debugging info 
    if (DEBUG) { 
      Serial.print("Interval Timer: ");
      printInfo(); 
    }

    // Take a picture if the camera is enabled and the sun is out
    if (enabled && sunlight) {
      digitalWrite(statusLedPin, HIGH);  // blink front panel lamp 

      // Turn the camera on if it is not already on.
      if (!isCameraOn()) {
        if (DEBUG) { Serial.println("Camera On."); }
        toggleCameraPower(); 
        delay(WAKEUP_TIME); // give camera a chance to boot up
      }
      
      // Take the picture 
      numPictures++;
      if (DEBUG) { 
        Serial.print("Taking Picture: "); 
        Serial.println(numPictures);
      }
      takePicture();
      lastPictureMillis = millis();
      pictureTaken = true;
     
      digitalWrite(statusLedPin, LOW); // unblink front panel lamp
    }

    // Record when this interval ended / when the next one starts
    lastMillis = millis(); // reset interval timer
  }

  /*
   * If the next picture won't be for a while and if the last picture was 
   * taken more than 5 seconds ago, turn the camera off.
   *
   * The pictureTaken bool tells us if a picture has been taken since 
   * the last time we thought about turning off the camera - i.e. if 
   * the camera might be on.  Using this keeps us from having to poll
   * isCameraOn() all the time, which can involve energizing the shutter
   * button relay.
   */

  if ((millis() - lastPictureMillis) > 5000) {
    if ((!enabled) || (!sunlight) || (interval > SHUTOFF_TIME)) {
      if (pictureTaken && isCameraOn()) {
        if (DEBUG) { 
          Serial.print("Camera Off:  "); 
          printInfo();
        }
        pictureTaken = false;
        toggleCameraPower();
      }
    }
  }

}

/*
 * printInfo
 *
 * Used for debugging, this prints the crucial stats.
 */
void printInfo() {
  Serial.print("[Enabled: ");
  Serial.print(enabled);
  Serial.print("  Sunlight: ");
  Serial.print(sunlight);
  Serial.print("  Interval: ");
  Serial.print(interval);
  Serial.println("]");
}

/*
 * isCameraOn
 *
 * Uses a photoresistor mounted on the screen of the camera to determine
 * if the camera is on or off.  Takes advantage of the fact that pressing
 * the shutter button when the screen is sleeping turns the screen back
 * on, but doesn't take a picture.
 */

bool isCameraOn() {
  int sensorReading = analogRead(cameraScreenPin);
  if (sensorReading > CAMERA_SCREEN_THRESHOLD) {
    return true;
  } else {
    takePicture();  // turns screen on when sleeping but doesn't take picture
    delay(WAKEUP_TIME);    // give the camera a chance to wake up
    sensorReading = analogRead(cameraScreenPin);
    return (sensorReading > CAMERA_SCREEN_THRESHOLD);
  }
}

/*
 * toggleCameraPower
 *
 * This turns on the relay connected to the leads piggybacked on the
 * power button of the camera.  This function mimics pushing the 
 * power button once.
 */

void toggleCameraPower() {
  digitalWrite(powerRelayPin, HIGH);  // relay on, "press" power button
  delay(100);                         // hold button down, let it register
  digitalWrite(powerRelayPin, LOW);   // relay off - release button
}

/*
 * takePpicture
 *
 * This turns on the relay connected to the leads piggybacked on the
 * shutter button of the camera.  This function mimics pushing the
 * shutter button once.
 */

void takePicture() {
  digitalWrite(shutterRelayPin, HIGH);  // relay on, "press" shutter button
  delay(100);                           // hold button down, let it register
  digitalWrite(shutterRelayPin, LOW);   // relay off - release button
}

