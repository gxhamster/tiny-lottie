#include <iostream>
#include <chrono>
#include "simdjson.h"
using namespace simdjson;

int main(int argc, char *argv[])
{
  if (argc < 2) {
    std::cout << "Need file name" << std::endl;
    return 1;
  }
  const std::string file_path = argv[1];
  std::cout << file_path << std::endl;
  auto start_time = std::chrono::steady_clock::now();
  ondemand::parser parser;
  padded_string json = padded_string::load(file_path);
  ondemand::document parsed_lottie = parser.iterate(json);
  auto end_time = std::chrono::steady_clock::now();
  auto elapsed_duration = end_time - start_time;
  double elapsed_milliseconds = std::chrono::duration<double, std::milli>(elapsed_duration).count();
  std::cout << elapsed_milliseconds << " ms\n";
}