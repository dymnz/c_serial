import processing.serial.*;

Serial c_serial;


final String SERIAL_NAME = "/dev/pts/21";

void setup() {
  println(Serial.list()); // Use this to print connected serial devices  
  c_serial = new Serial(this, SERIAL_NAME, 230400); // Set this to your serial port obtained using the line above
}


void serialEvent(Serial c_serial) {
  
  while (c_serial.available() > 0) {
    char ch = (char) c_serial.read();

  }
}

int frame_count = 0;
String send_str = "";
void draw() {
  frame_count++;
  
  send_str = "" + frame_count;
  c_serial.write(send_str);
}
