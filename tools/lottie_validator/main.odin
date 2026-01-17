package json_validator

import "core:os"
import "core:flags"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:mem"
import jlv "src:validator"

// A commandline application which uses the validator
// package to validate a data json file with a schema
// file


Args :: struct {
	file: os.Handle `args:"pos=0,required,file=r" usage:"The data json file to validate"`,
	schema: os.Handle `args:"required,file=r" usage:"The schema file used for validation"`
}

main :: proc() {

  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    tracking_allocator := mem.tracking_allocator(&track)
    context.allocator = tracking_allocator
    logger := log.create_console_logger(allocator = tracking_allocator)
    context.logger = logger
  } else {
    DEFAULT_PROG_MEM :: 50 * mem.Megabyte
    prog_arena: vmem.Arena
    arena_err := vmem.arena_init_growing(&prog_arena, DEFAULT_PROG_MEM)
    ensure(arena_err == nil)
    prog_arena_allocator := vmem.arena_allocator(&prog_arena)
    context.allocator = prog_arena_allocator
    defer vmem.arena_destroy(&prog_arena)
  }

	args: Args
	flags.parse_or_exit(&args, os.args, .Odin, context.temp_allocator)

  filedata: []u8
  schema_filedata: []u8
  {
    ok: bool
	  filedata, ok = os.read_entire_file_from_handle(args.file, context.temp_allocator)
    if !ok {
      fmt.println("Could not read the data file")
      return
    }
  }
  {
    ok: bool
	  schema_filedata, ok = os.read_entire_file_from_handle(args.schema, context.temp_allocator)
    if !ok {
      fmt.println("Could not read the schema file")
      return
    }
  }


  ctx := jlv.Context{}
  jlv.init_context(&ctx, 1000, context.allocator)
  parsed_schema, schema_idx, err := jlv.parse_schema_from_string(
    string(schema_filedata),
    &ctx,
    context.allocator
  )

  if err !=. None {
    fmt.printf("Cannot parse schema file due to (%v)\n", err)
    return
  }

  ctx.root_schema = schema_idx


  validation_err := jlv.validate_string_with_schema(
    string(filedata),
    parsed_schema,
    &ctx,
    context.allocator
  )

  if validation_err != .None {
    fmt.printf("Validation did not succeed, error=(%v)", validation_err)
    return
  } else {
    fmt.println("Validation succeeded")
  }

	// note(iyaan): Not really needed but will include
	// for explicit readability
	free_all(context.temp_allocator)
}
