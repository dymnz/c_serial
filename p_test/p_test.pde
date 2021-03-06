/*
  Send angle in radians to C-echo and receive the value.
  Syncing the expected value and the value received from C-echo

  Expected sine value is generated in the program. Angle in radian
  will be sent to NN every N pts. (N = Real_sample_rate/Target_sample_rate, i.e. downsample)
  NN_buffer will only be filled when GT_buffer_idx > NN_buffer_idx.
  NOTE: In this case, GT_buffer_idx > NN_buffer_idx

  When sending actual processed sEMG value, the past 500 semg samples that
  passed through:
  1. RMS
  2. LPF
  will be sent to NN every N pts. (N = Real_sample_rate/Target_sample_rate, i.e. downsample)
*/

import processing.serial.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

enum SerialState {
    HOLD, SEMG_ALIGN, MPU_ALIGN, SEMG_READ, MPU_READ, SEMG_FIN, MPU_FIN
}

SerialState AR_state = SerialState.HOLD;

final int alignment_packet_len = 1;
final char[] semg_alignment_packet = {'$'};
final char[] quat_alignment_packet = {'@'};

final int semg_channel = 6;
final int semg_packet_byte = 2;
final int quat_channel = 4;
final int quat_packet_byte = 4;

final int semg_sample_rate = 2700;
final int target_sample_rate =35;
final int downsample_ratio = semg_sample_rate / target_sample_rate;


final int angle_channel = 3;

final int total_channel = quat_channel + semg_channel;
final int semg_packet_len = semg_channel * semg_packet_byte;
final int quat_packet_len = quat_channel * quat_packet_byte;

float[] semg_values = new float[semg_channel];
float[] quat_values = new float[quat_channel];
float[] angle_values = new float[angle_channel];
float[] radian_values = new float[angle_channel];

int AR_packet_cnt = 0;
int AR_align_cnt = 0;

final int width = 1440;
final int height = 900;
final float graph_x_step = 4;

final int sine_freq = 2000;
float [] sine_data = new float [sine_freq];

final int NN_channel = 2;
final int NN_packet_len = 4;
int [] NN_packet_cnt = new int[NN_channel];

final int value_buffer_size = 10000;
final int rms_window_size = 500;

float [] processed_semg_value = new float[semg_channel];
float [] mean_semg_value = {2048, 2048, 2048, 2048, 2048, 2048};
float [] semg_ring_buffer[] = new float[semg_channel][rms_window_size];
float [] angle_buffer[] = new float[angle_channel][value_buffer_size];
float [] GT_buffer[] = new float[NN_channel][value_buffer_size];
float [] NN_buffer[] = new float[NN_channel][value_buffer_size];

char[] semg_packet = new char[semg_packet_len];
char[] quat_packet = new char[quat_packet_len];
char[] NN_packet[] = new char[NN_channel][NN_packet_len];
float [] NN_value = new float[NN_channel];

int semg_buffer_idx = 0;
int angle_buffer_idx = 0;
int [] GT_buffer_idx = new int[NN_channel];
int [] NN_buffer_idx = new int[NN_channel];

int [] GT_draw_idx = new int[NN_channel];
int [] NN_draw_idx = new int[NN_channel];

boolean quat_tared = false;
char temp_byte;

int sample_since_last_send = 0;

final String AR_SERIAL_NAME = "/dev/ttyACM0";
final String [] NN_SERIAL_NAME = {"/dev/pts/25", "/dev/pts/27"};

Serial AR_serial;
Serial [] NN_serial = new Serial[NN_channel];


final String [] move_list = {"1: Hold init", "2: Hold init",
                             "3: Move to final", "4: Hold final", "5: Move to init",
                             "6: Hold init", "7: Hold init"
                            };

int sc_current_time = 0;
int sc_last_time = 0;
int sc_sample_count = 0;
int pm_current_time = 0;
int pm_last_time = 0;
int move_list_index = 0;
int move_count = 1;

/*
final float [] semg_normalization_max = {9.1804, 5.4334, 24.9513,    8.5455,   14.4549,    7.3071};
final float [] semg_normalization_min = {-3.67480010386515, -9.99041157741216, 0.000680513958738939, -5.24100740589618};
final float [][] TDSEP_matrix = {
    {1, 0, 0, 0, 0, 0},
    {0, 1, 0, 0, 0, 0},
    {0, 0, 1, 0, 0 , 0},
    {0, 0, 0, 1, 0, 0},
    {0, 0, 0, 0, 1, 0},
    {0, 0, 0, 0, 0, 1}
};
*/

///*
final float [] semg_normalization_max = {9.18041,5.43337,24.9513,8.54547,14.4549,7.30713};
final float [] semg_normalization_min = {  -5.16016,-0.0968648,  -8.33716,  -2.09257,  -11.2247,  -4.21584};
final float [][] TDSEP_matrix = 
{{0.006619,-0.017551,-0.007456,0.003243,-0.003471,0.028042},
{0.006228,0.002114,-0.001121,-0.000366,-0.001282,0.005107},
{0.007672,-0.009124,0.045514,0.002012,-0.038280,-0.011337},
{-0.002886,-0.002350,0.002571,0.004218,0.002164,-0.000767},
{0.039064,-0.025458,0.030922,-0.018745,0.026040,-0.033660},
{-0.024878,0.000792,0.017771,-0.011882,0.004427,0.026971}};
//*/

void settings() {
    size(width, height, FX2D);
}

void setup() {
    println(Serial.list());

    // Open NN serial port
    try {
        for (int i = 0; i < NN_channel; ++i) {
            NN_serial[i] = new Serial(this, NN_SERIAL_NAME[i], 230400);
        }
    } catch (Exception e) {
        println("Error opening NN port: " + e.getMessage());
        exit();
    }

    // Open AR serial port
    try {
        AR_serial = new Serial(this, AR_SERIAL_NAME, 4000000);
    } catch (Exception e) {
        println("Error opening AR port: " + AR_SERIAL_NAME);
        exit();
    }


    // Generate sin wave
    final float sine_inc = PI * 2 / sine_freq;
    for (int i = 0; i < sine_freq; ++i) {
        sine_data[i] = sin(sine_inc * i);
    }

    resetGraph();
    frameRate(1000);
}


void serialEvent(Serial serial) {

    if (serial == AR_serial) {
        receive_from_AR();
    } else {
        for (int i = 0; i < NN_channel; ++i) {
            if (serial == NN_serial[i])
                receive_from_NN(i);
        }
    }

}

int sine_wave_idx = 0;
void send_to_NN_sine_test() {

    NN_serial[0].write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(sine_data[sine_wave_idx]).array());
    NN_serial[1].write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(sine_data[(sine_wave_idx + sine_freq / 4) % sine_freq]).array());

    GT_buffer[0][GT_buffer_idx[0]] = sine_data[sine_wave_idx];
    GT_buffer[1][GT_buffer_idx[1]] = sine_data[(sine_wave_idx + sine_freq / 4) % sine_freq];

    //GT_buffer_idx[0] = (GT_buffer_idx[0] + 1) % value_buffer_size;
    //GT_buffer_idx[1] = (GT_buffer_idx[1] + 1) % value_buffer_size; 
    GT_buffer_idx[0] = GT_buffer_idx[0] + 1;
    GT_buffer_idx[1] = GT_buffer_idx[1] + 1; 

    sine_wave_idx = (sine_wave_idx + 1) % sine_freq;
}

void send_to_NN(float [] p_semg) {
    
    /*
    for (int ch = 0; ch < semg_channel; ++ch) {
        NN_serial[0].write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(p_semg[ch]).array());
        NN_serial[1].write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(p_semg[ch]).array());
    }
    */
    
    ByteBuffer data_buffer = ByteBuffer.allocate(4 * semg_channel).order(ByteOrder.LITTLE_ENDIAN);
    
    for (float v : p_semg)
        data_buffer.putFloat(v);
        
    NN_serial[0].write(data_buffer.array());  
    NN_serial[1].write(data_buffer.array());
    
    final int return_channel_0 = 0;
    GT_buffer[0][GT_buffer_idx[0]] = p_semg[return_channel_0] + 100;
    GT_buffer[1][GT_buffer_idx[1]] = p_semg[return_channel_0] + 100;

    //GT_buffer_idx[0] = (GT_buffer_idx[0] + 1) % value_buffer_size;
    //GT_buffer_idx[1] = (GT_buffer_idx[1] + 1) % value_buffer_size; 
    GT_buffer_idx[0] = GT_buffer_idx[0] + 1;
    GT_buffer_idx[1] = GT_buffer_idx[1] + 1; 
    
}


// Note that NN_value for different channel will not be in sync, unlike GT
void receive_from_NN(int ch) {
    while (NN_serial[ch].available() > 0) {
        temp_byte = (char) NN_serial[ch].read();

        NN_packet[ch][NN_packet_cnt[ch]] = temp_byte;

        ++NN_packet_cnt[ch];

        if (NN_packet_cnt[ch] >= NN_packet_len) {
            // https://stackoverflow.com/questions/4513498/java-bytes-to-floats-ints
            NN_value[ch] =  Float.intBitsToFloat( ((NN_packet[ch][3] & 0xFF) << 24) |
                                                  ((NN_packet[ch][2] & 0xFF) << 16) |
                                                  ((NN_packet[ch][1] & 0xFF) << 8)  |
                                                  (NN_packet[ch][0] & 0xFF));
            //println("receive from NN: " + ch);
            NN_packet_cnt[ch] = 0;

            NN_buffer[ch][NN_buffer_idx[ch] % value_buffer_size] = NN_value[ch];
            //NN_buffer_idx[ch] = (NN_buffer_idx[ch] + 1) % value_buffer_size;
            NN_buffer_idx[ch] = NN_buffer_idx[ch] + 1;
            
            //sampleCount();

        }
    }
}

void receive_from_AR() {
    while (AR_serial.available() > 0) {
        temp_byte = (char) AR_serial.read();

        if (AR_state == SerialState.HOLD) {
            if (temp_byte == semg_alignment_packet[AR_align_cnt]) {
                if (AR_align_cnt == 0)
                    AR_state = SerialState.SEMG_ALIGN;
                ++AR_align_cnt;
            } else if (temp_byte == quat_alignment_packet[AR_align_cnt]) {
                if (AR_align_cnt == 0)
                    AR_state = SerialState.MPU_ALIGN;
                ++AR_align_cnt;
            }

            if (AR_align_cnt >= alignment_packet_len) {
                if (AR_state == SerialState.SEMG_ALIGN)
                    AR_state = SerialState.SEMG_READ;
                else if (AR_state == SerialState.MPU_ALIGN)
                    AR_state = SerialState.MPU_READ;

                AR_align_cnt = 0;
            }
        } else if (AR_state == SerialState.SEMG_READ) {
            semg_packet[AR_packet_cnt] = temp_byte;

            ++AR_packet_cnt;

            if (AR_packet_cnt >= semg_packet_len) {
                for (int ch = 0; ch < semg_channel; ++ch) {
                    semg_values[ch] = (semg_packet[2 * ch + 1] << 8) | semg_packet[2 * ch];
                    semg_ring_buffer[ch][semg_buffer_idx] = semg_values[ch]; // TODO: Change 2048 to a dynamic mean value
                }

                semg_buffer_idx = (semg_buffer_idx + 1) % rms_window_size;

                AR_state = SerialState.HOLD;
                AR_packet_cnt = 0;


                /* Pre-process */
                mean_semg_value = calculate_semg_mean(semg_ring_buffer, rms_window_size);
                processed_semg_value = calculate_semg_rms_rmMean(semg_ring_buffer, rms_window_size, mean_semg_value);
                //processed_semg_value = calculate_semg_lpf(processed_semg_value);  /* Don't seem to be working, may be skipped? */
                processed_semg_value = apply_demix_matrix(processed_semg_value, TDSEP_matrix);
                processed_semg_value = semg_normalization(processed_semg_value, semg_normalization_max, semg_normalization_min);
                
                if (sample_since_last_send > downsample_ratio) {
                    //send_to_NN_sine_test();
                    send_to_NN(processed_semg_value);
                    sample_since_last_send = 0;
                }

                ++sample_since_last_send;

                if (quat_tared)
                    printMove();
               // else
                   // sampleCount();
            }

        } else if (AR_state == SerialState.MPU_READ) {
            quat_packet[AR_packet_cnt] = temp_byte;

            ++AR_packet_cnt;

            if (AR_packet_cnt >= quat_packet_len) {
                for (int i = 0; i < quat_channel; ++i) {
                    // https://stackoverflow.com/questions/4513498/java-bytes-to-floats-ints
                    quat_values[i] =  Float.intBitsToFloat( ((quat_packet[i * 4 + 3] & 0xFF) << 24) |
                                                            ((quat_packet[i * 4 + 2] & 0xFF) << 16) |
                                                            ((quat_packet[i * 4 + 1] & 0xFF) << 8)  |
                                                            (quat_packet[i * 4] & 0xFF));
                }

                quat_convert();

                for (int i = 0; i < angle_channel; ++i)
                    angle_buffer[i][angle_buffer_idx] = (int) angle_values[i];
                angle_buffer_idx = (angle_buffer_idx + 1) % value_buffer_size;

                AR_state = SerialState.HOLD;
                AR_packet_cnt = 0;
            }
        }
    }
}

void draw() {
    drawAll();
    sampleCount();
}


void printMove() {
    pm_current_time = millis();
    if (pm_current_time - pm_last_time > 1000) {
        println(move_list[move_list_index] + " --> " + move_count);

        pm_last_time = millis();
        move_list_index = (move_list_index + 1) % move_list.length;

        if (move_list_index == 0)
            ++move_count;
    }
}

void sampleCount() {
    sc_sample_count++;
    sc_current_time = millis();
    if (sc_current_time - sc_last_time > 1000) {
        println("SPS: " + sc_sample_count);

        sc_last_time = millis();
        sc_sample_count = 0;
    }
}

float[] calculate_semg_mean(float [] semg_buff[], final int win_size) {
    
    float [] mean = new float[semg_channel];

    for (int ch = 0; ch < semg_channel; ++ch) {
        for (int i = 0; i < win_size ; ++i) {
            mean[ch] += semg_buff[ch][i];
        }
        mean[ch] = mean[ch] / win_size;
    }
    return mean; 
}

float[] calculate_semg_rms_rmMean(float [] semg_buff[], final int win_size, float [] mean_val) {

    float [] rms = new float[semg_channel];

    for (int ch = 0; ch < semg_channel; ++ch) {
        for (int i = 0; i < win_size ; ++i) {
            rms[ch] += (semg_buff[ch][i] - mean_val[ch]) * (semg_buff[ch][i] - mean_val[ch]);
        }
        rms[ch] = sqrt(rms[ch] / win_size);
    }
    return rms;
}

float[] calculate_semg_lpf(float [] val) {

    float [] lpf_val = new float[semg_channel];

    for (int ch = 0; ch < semg_channel; ++ch) {
        lpf_val[ch] = LPF_step(ch, val[ch]);
    }

    return lpf_val;
}


float[] apply_demix_matrix(float [] val, float [][] mat) {
    
    float [] demix_val = new float[semg_channel];

    for (int i = 0; i < semg_channel; ++i) {
        for (int j = 0; j < semg_channel; ++j) {
            demix_val[i] += mat[i][j] * val[j];
        }
    }
    
    return demix_val;
}

float[] semg_normalization(float [] val, float [] max_val, float [] min_val) {
    
    float [] norm_val = new float[semg_channel];
    
    for (int ch = 0; ch < semg_channel; ++ch) {
        norm_val[ch] = val[ch] / (max_val[ch] - min_val[ch]);
    }
    
    return norm_val;
}
