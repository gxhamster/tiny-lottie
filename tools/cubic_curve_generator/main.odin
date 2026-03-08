package cubic_curve_generator

import "core:fmt"
import "core:flags"
import "core:strings"
import "core:strconv"
import "core:os"
import "base:runtime"
import enc "src:/"

// This is a tool made just to generate sampled points from cubic
// curve. You can pass in the coordinates to the control points
// and get the generated coordinates. Made just to plug into matplotlib
// or gnuplot


vec2_type_checker :: proc(
  data: rawptr,
	data_type: typeid,
	unparsed_value: string,
	args_tag: string,
) -> (
  error: string,
	handled: bool,
	alloc_error: runtime.Allocator_Error,
) {
  if data_type == enc.Vec2 {
    handled = true
    vec_ptr := (^enc.Vec2)(data)
    digit_count := 0
    num_strings, err := strings.split(unparsed_value, ",", context.temp_allocator)
    if err != .None {
      panic("Could not allocate for string splitting")
    }


    if len(num_strings) != 2 {
      fmt.println("coordinates should be 2D")
      os.exit(1)
    }

    for i in 0..<len(num_strings) {
      x, ok := strconv.parse_f64(num_strings[i])
      if !ok {
        fmt.printf("could not convert %v to f64\n", num_strings[i])
      }
      vec_ptr[i] = x
    }


  } else {
    error = "Not vector2 coordinates"
  }
  return
}

MAX_SAMPLES :: 1_000_000
cubic_curve_approx :: proc(p1, p2: enc.Vec2, samples: int) -> []enc.Vec2 {
  if samples > MAX_SAMPLES {
    panic("dont sample too much")
  }

  p0 := enc.Vec2{0, 0}
  p3 := enc.Vec2{1, 1}

  t: f64 = 0.0
  sampled_points := make_slice([]enc.Vec2, samples, context.temp_allocator)
  for i in 0..<samples {
    x := enc.cubic_bezier(t, p0.x, p1.x, p2.x, p3.x) 
    y := enc.cubic_bezier(t, p0.y, p1.y, p2.y, p3.y) 
    sampled_points[i] = enc.Vec2{x, y}
    t += f64(1.0) / f64(samples)
  }

  return sampled_points
}

DEFAULT_SAMPLES :: 8
DEFAULT_FLOAT_PRECISION_WIDTH :: 16
main :: proc() {
  DisplayOps :: enum {
    normal,
    flat,
    sep,
    gnuplot,
  }
  Args :: struct {
    p1: enc.Vec2 `args:"required" usage:"P1 control points"`,    
    p2: enc.Vec2 `args:"required" usage:"P2 control points"`,    
    samples: int `usage:"how many samples to take from the curve"`,
    display: DisplayOps `usage:"how to display the points (normal, flat, sep)"`,
    fw: int `usage:"the width of the float precision"`
  }

  args : Args
  style : flags.Parsing_Style = .Odin
  flags.register_type_setter(vec2_type_checker)
  flags.parse_or_exit(&args, os.args, style)
  if args.samples == 0 {
    args.samples = DEFAULT_SAMPLES 
  }

  args.fw = args.fw > 0 && args.fw < DEFAULT_FLOAT_PRECISION_WIDTH ? args.fw : DEFAULT_FLOAT_PRECISION_WIDTH 
  points := cubic_curve_approx(args.p1, args.p2, args.samples)
  switch args.display {
  case .normal:
  {
    builder, err := strings.builder_make(0, allocator = context.temp_allocator)
    if err != .None {
      panic("cannot allocate for string builder")
    }
    strings.write_string(&builder, "[%.")
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f, %.");
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f]");
    
    fmt.printf("[")
    for vec2 in points {
      fmt.printf(strings.to_string(builder), vec2.x, vec2.y)
    }
    fmt.printf("]\n")
    strings.builder_destroy(&builder)
  }
  case .flat:
  {
    builder, err := strings.builder_make(0, allocator = context.temp_allocator)
    if err != .None {
      panic("cannot allocate for string builder")
    }
    strings.write_string(&builder, "%.")
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f, %.");
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f, ");

    fmt.print("[")
    for vec2 in points {
      fmt.printf(strings.to_string(builder), vec2.x, vec2.y)
    }
    fmt.print("]\n")
    strings.builder_destroy(&builder)
  }
  case .sep:
  {
    builder, err := strings.builder_make(0, allocator = context.temp_allocator)
    if err != .None {
      panic("cannot allocate for string builder")
    }
    strings.write_string(&builder, "%.")
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f, ")

    fmt.print("[")
    for vec2 in points {
      fmt.printf(strings.to_string(builder), vec2.x)
    }
    fmt.print("]\n")
    fmt.print("[")
    for vec2 in points {
      fmt.printf(strings.to_string(builder), vec2.y)
    }
    fmt.print("]\n")
    strings.builder_destroy(&builder)
  }
  case .gnuplot:
  {
    builder, err := strings.builder_make(0, allocator = context.temp_allocator)
    if err != .None {
      panic("cannot allocate for string builder")
    }
    strings.write_string(&builder, "%.");
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f %.");
    strings.write_int(&builder, args.fw)
    strings.write_string(&builder, "f\n");
    for vec2 in points {
      fmt.printf(strings.to_string(builder), vec2.x, vec2.y)
    }
    strings.builder_destroy(&builder)
  }
  }
}
