/* Digital filter designed by mkfilter/mkshape/gencode   A.J. Fisher
   Command line: /www/usr/fisher/helpers/mkfilter -Bu -Lp -o 6 -a 1.4000000000e-02 0.0000000000e+00 -l */

final int NZEROS = 6;
final int NPOLES = 6;
final float GAIN = 1.631110475e+08;

float [] xv[] = new float[semg_channel][NZEROS + 1];
float [] yv[] = new float[semg_channel][NPOLES + 1];


// 6th order butterworth LPF w/ 35Hz -3db @ 2500Hz
float LPF_step(int ch, float next_val) {
    xv[ch][0] = xv[ch][1]; xv[ch][1] = xv[ch][2]; xv[ch][2] = xv[ch][3]; xv[ch][3] = xv[ch][4]; xv[ch][4] = xv[ch][5]; xv[ch][5] = xv[ch][6];
    xv[ch][6] = next_val / GAIN;
    yv[ch][0] = yv[ch][1]; yv[ch][1] = yv[ch][2]; yv[ch][2] = yv[ch][3]; yv[ch][3] = yv[ch][4]; yv[ch][4] = yv[ch][5]; yv[ch][5] = yv[ch][6];
    yv[ch][6] =   (xv[ch][0] + xv[ch][6]) + 6 * (xv[ch][1] + xv[ch][5]) + 15 * (xv[ch][2] + xv[ch][4])
              + 20 * xv[ch][3]
              + ( -0.7117645479 * yv[ch][0]) + (  4.5124787928 * yv[ch][1])
              + (-11.9273711340 * yv[ch][2]) + ( 16.8245332670 * yv[ch][3])
              + (-13.3580291260 * yv[ch][4]) + (  5.6601523551 * yv[ch][5]);
    return yv[ch][6];
}
