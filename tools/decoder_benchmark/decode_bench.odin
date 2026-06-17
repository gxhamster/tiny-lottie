package benchmark

import "core:encoding/json"
import "core:time"
import "core:flags"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:os"
import lottie "src:/"

BenchmarkData :: struct {
  size: int,
}

benchmark_encoding :: proc(fd: os.Handle)  {
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


  anim := lottie.Animation{}
  unmarshal_err := lottie.unmarshal_object(value, anim, allocator = arena_allocator)
  if unmarshal_err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", unmarshal_err, anim)
  }
  writer := lottie.Writer{}
  optim_ok := lottie.color_pallete_optim_pass(&anim, &writer.header)
  lottie.writer_init(&writer, data_len = 1 << 33, allocator = arena_allocator)
  lottie.write_animation(&writer, anim)

  start_time := time.now()
  reader := lottie.reader_from_writer(&writer, arena_allocator)
  anim1, err1 := lottie.read_animation(&reader)
  end_time := time.now()
  duration := time.diff(start_time, end_time)
  fmt.printf("Decoding took: %vms\n", time.duration_milliseconds(duration))

  vmem.arena_destroy(&arena)
}

Args :: struct {
  file: os.Handle `args:"pos=0,required,file=r" usage:"The data json file to validate"`,
}

main :: proc() {
  args: Args
  flags.parse_or_exit(&args, os.args, .Odin, context.temp_allocator)
  benchmark_encoding(args.file)
}
