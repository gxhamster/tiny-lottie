package benchmark

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:time"

import lottie "src:/"

benchmark_decoding :: proc(fd: ^os.File) {

  arena: vmem.Arena
  arena_allocator := vmem.arena_allocator(&arena)

  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    arena_allocator = mem.tracking_allocator(&track)
  }

  data, read_error := os.read_entire_file_from_file(fd, arena_allocator)
  if read_error != os.ERROR_NONE {
    fmt.printfln("benchmark failed: Could not read file (%v)", read_error)
    os.exit(1)
  }
  defer delete(data)

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
  decoded_anim, anim_decode_err := lottie.read_animation(&reader)
  end_time := time.now()
  duration := time.diff(start_time, end_time)
  fmt.printfln("Decoding took %v ms", time.duration_milliseconds(duration))

  //   vmem.arena_destroy(&arena)
}

Args :: struct {
  file: string `args:"pos=0,required" usage:"The data json file to validate"`,
}

main :: proc() {
  args: Args
  flags.parse_or_exit(&args, os.args, .Odin, context.temp_allocator)
  json_file, json_file_err := os.open(args.file)
  if json_file_err != os.ERROR_NONE {
    fmt.printfln("benchmark failed: Could not open file (%v)", json_file_err)
    os.exit(1)
  }
  benchmark_decoding(json_file)
}
