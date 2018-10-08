
final int[][] NN_color_list = {{255, 30, 30}, {30, 255, 30}};
final int[][] GT_color_list = {{255, 130, 130}, {130, 255, 130}};


/*
final int [] RPY_minValue = {-180, -180, -180};
final int [] RPY_maxValue = {+180, +180, +180};
*/
final int [] RPY_minValue = { -1, -1};
final int [] RPY_maxValue = { +1, +1};

int last_draw_idx = 0;
int max_valid_buffer_idx = 0;

float x = 0;
float last_x = 0;

int [] GT_last_height = new int[NN_channel];
int [] NN_last_height = new int[NN_channel];

void drawAll() {
  int draw_value;
  strokeWeight(4);

  max_valid_buffer_idx = get_max_valid_buffer_idx() % value_buffer_size;

  while (last_draw_idx < max_valid_buffer_idx) {
    // Sanity check for synced NN-GT
    for (int ch = 0; ch < NN_channel; ++ch) {
      if (NN_buffer_idx[ch] != max_valid_buffer_idx || GT_buffer_idx[ch] != max_valid_buffer_idx) {
        println("GT_buffer_idx!=NN_buffer_idx");
        exit();
      }
    }
    
    // Draw GT angles
    for (int i = 0; i < NN_channel; ++i) {
      stroke(GT_color_list[i][0], GT_color_list[i][1], GT_color_list[i][2]);
      draw_value = int(map(GT_buffer[i][last_draw_idx % value_buffer_size], RPY_minValue[i], RPY_maxValue[i], 0, height));
      line(last_x, GT_last_height[i], x, height - draw_value);

      GT_last_height[i] = int(height - draw_value);
    }

    // Draw NN angles
    for (int i = 0; i < NN_channel; ++i) {
      stroke(NN_color_list[i][0], NN_color_list[i][1], NN_color_list[i][2]);
      draw_value = int(map(NN_buffer[i][last_draw_idx % value_buffer_size], RPY_minValue[i], RPY_maxValue[i], 0, height));
      line(last_x, NN_last_height[i], x, height - draw_value);

      NN_last_height[i] = int(height - draw_value);
    }
    ++last_draw_idx;

    last_x = x;
    x += graph_x_step;

  }

  if (x >= width) {
    x = 0;
    last_x = 0;
    resetGraph();
  }
}

void resetGraph() {
  background(255);
  strokeWeight(2);
}


int get_max_valid_buffer_idx() {

  int max_valid_idx = GT_buffer_idx[0];

  // Find min for NN
  for (int ch = 0; ch < NN_channel; ++ch) {
    max_valid_idx = min(max_valid_idx, NN_buffer_idx[ch]);
  }

  // Find min for GT
  for (int ch = 0; ch < NN_channel; ++ch) {
    max_valid_idx = min(max_valid_idx, GT_buffer_idx[ch]);
  }

  return max_valid_idx;
}
