package encoder_cli

import "core:fmt"
import "core:encoding/json"
import vmem "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:flags"
import lottie "src:/"

Args :: struct {
  file: string `args:"pos=0,required" usage:"The data json file to encode"`,
}



main :: proc() {
  arena: vmem.Arena
  arena_allocator := vmem.arena_allocator(&arena)

  args: Args
  flags.parse_or_exit(&args, os.args, .Odin, context.temp_allocator)

  data, error := os.read_entire_file_from_path(args.file, arena_allocator)

  if error != os.ERROR_NONE {
    fmt.printfln("could not read from file: %v", error)
    os.exit(1)
  }

  value, err := json.parse(data, parse_integers = true)
  if err != .None {
    fmt.printfln("could not parse json due to %v", err)
    os.exit(1)
  }

  defer json.destroy_value(value)


  anim := lottie.Animation{}
  unmarshal_err := lottie.unmarshal_object(value, anim, allocator = arena_allocator)
  if unmarshal_err != .None {
    fmt.printfln("unmarshal_object returned error = %v, %v", unmarshal_err, anim)
    os.exit(1)
  }
  writer := lottie.Writer{}
  optim_ok := lottie.color_pallete_optim_pass(&anim, &writer.header)
  lottie.writer_init(&writer, data_len = 1 << 33, allocator = arena_allocator)
  lottie.write_animation(&writer, anim)

  builder := lottie.gen_html(&writer)
  builder_str := strings.to_string(builder)
  FILE_NAME :: "data.html"
  write_error := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
  if write_error != os.ERROR_NONE {
    fmt.println("something went very wrong while file writing")
    os.exit(1)
  }

  out_file_name := filepath.base(args.file)
  out_file_path_arr := []string{out_file_name, ".lottieb"}
  out_file_path := strings.concatenate(out_file_path_arr[:], arena_allocator)
  fmt.println(out_file_path)
  out_file_err := os.write_entire_file_from_bytes(out_file_path, writer.data[:writer.offset])
  if out_file_err != os.ERROR_NONE {
    fmt.printfln("Could not save the encoded file, %v", out_file_err)
    os.exit(1)
  }


  lottie.writer_destroy(&writer)
  free_all(arena_allocator)
  vmem.arena_destroy(&arena)
}