#include <string.h>
#include <stdio.h>

// Global state for different UI elements
static int counter_value = 0;
static int toggle_value = 0;
static int slider_value = 0;

int32_t get_counter() {
  return counter_value;
}

int32_t increment_counter() {
  counter_value++;
  return counter_value;
}

void reset_counter() {
  counter_value = 0;
}

int32_t get_toggle() {
  return toggle_value;
}

int32_t toggle_button() {
  toggle_value = toggle_value ? 0 : 1;
  return toggle_value;
}

void reset_toggle() {
  toggle_value = 0;
}

int32_t get_slider() {
  return slider_value;
}

int32_t increment_slider() {
  if (slider_value < 100) {
    slider_value += 10;
  }
  return slider_value;
}

void reset_slider() {
  slider_value = 0;
}

int32_t call_native(const char* method_name, const char* args) {
  if (strcmp(method_name, "increment_counter") == 0) {
    return increment_counter();
  } else if (strcmp(method_name, "get_counter") == 0) {
    return get_counter();
  } else if (strcmp(method_name, "reset_counter") == 0) {
    reset_counter();
    return 0;
  } else if (strcmp(method_name, "toggle_button") == 0) {
    return toggle_button();
  } else if (strcmp(method_name, "get_toggle") == 0) {
    return get_toggle();
  } else if (strcmp(method_name, "reset_toggle") == 0) {
    reset_toggle();
    return 0;
  } else if (strcmp(method_name, "increment_slider") == 0) {
    return increment_slider();
  } else if (strcmp(method_name, "get_slider") == 0) {
    return get_slider();
  } else if (strcmp(method_name, "reset_slider") == 0) {
    reset_slider();
    return 0;
  }

  return -1; // Unknown method
}
