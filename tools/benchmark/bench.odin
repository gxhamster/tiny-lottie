package benchmark

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:os"
import "core:time"
import lottie "src:/"

BenchmarkData :: struct {
  size: int,
}

benchmark_encoding :: proc(fd: os.Handle) -> BenchmarkData {
  arena: vmem.Arena
  arena_allocator := vmem.arena_allocator(&arena)

  data, ok := os.read_entire_file_from_handle(fd)
  defer delete(data)

  if !ok {
    log.fatalf("could not read from file")
  }

  value, err := json.parse(data, parse_integers = true)
  if err != .None {
    log.fatalf("could not parse json due to %v", err)
  }
  defer json.destroy_value(value)

  writer := lottie.Writer{}
  // Somehow calling writer_init adds 200ms (its fine. Allocated once anyways)
  lottie.writer_init(&writer, data_len = 1 << 33, allocator = arena_allocator)
  anim := lottie.Animation{}
  start_time := time.now()
  unmarshal_err := lottie.unmarshal_object(value, anim, allocator = arena_allocator)
  if unmarshal_err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", unmarshal_err, anim)
  }
  optim_ok := lottie.color_pallete_optim_pass(&anim, &writer.header)


  lottie.write_animation(&writer, anim)
  end_time := time.now()
  fmt.printfln("Original=%v, After=%v, Time=%v", len(data), writer.offset, time.diff(start_time, end_time))
  result := BenchmarkData{}
  result.size = writer.offset
  vmem.arena_destroy(&arena)
  return result
}

Args :: struct {
  file: os.Handle `args:"pos=0,required,file=r" usage:"The data json file to validate"`,
}

main :: proc() {
  args: Args
  flags.parse_or_exit(&args, os.args, .Odin, context.temp_allocator)
  benchmark_encoding(args.file)
}
