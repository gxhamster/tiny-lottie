package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"

parse_layers :: proc(
  anim: ^Animation,
  layer_json_array: json.Array,
  allocator := context.allocator,
  loc := #caller_location,
) -> LottieError {
  p := (layer_json_array[0].(json.Object)["ks"])

  transform, err := parse_transform(p)
  return .None
}

parse_prop_scalar :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  scalar: PropScalar,
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    obj := value.(json.Object)
    sid_val := parse_string(obj["sid"]) or_return
    animated := parse_integer(obj["a"]) or_return
    if animated == 0 {
      single_scalar := PropScalarSingle {
        a   = false,
        sid = sid_val,
      }
      single_scalar.k = parse_number(obj["k"]) or_return
      scalar = single_scalar
      return scalar, .None
    } else {
      anim_scalar := PropScalarAnim {
        a   = true,
        sid = sid_val,
      }

      #partial switch type in obj["k"] {
      case json.Array:
        arr := obj["k"].(json.Array)
        // warning(iyaan): This allocation needs to be watched out for
        // when using non-arena allocators. Does it matter during pe
        // mode when using tracking allocator
        keyframes := make([dynamic]PropScalarKeyframe)
        resize(&keyframes, len(arr))
        for elem in arr {
          keyframe := parse_scalar_keyframe(elem) or_return
          append(&keyframes, keyframe)
        }
        anim_scalar.k = keyframes[:]
        return anim_scalar, .None
      case:
        return scalar, .IncompatibleArrayType
      }
    }
  case:
    return req_or_err(required, scalar, .IncompatiblePropScalarType)
  }

}

parse_prop_vector :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vector_prop: PropVector,
  err: LottieError,
) {

  #partial switch type in value {
  case json.Object:
    obj := value.(json.Object)
    sid_val := parse_string(obj["sid"]) or_return
    animated_val := parse_integer(obj["a"]) or_return

    if animated_val == 0 {
      single_vector := PropVectorSingle {
        a   = false,
        sid = sid_val,
      }
      single_vector.k = parse_value_vector(obj["k"]) or_return
      vector_prop = single_vector
      return vector_prop, .None
    } else if animated_val == 1 {
      anim_vector := PropVectorAnim {
        a = true,
      }
      anim_vector.sid = parse_string(obj["sid"]) or_return

      #partial switch type in obj["k"] {
      case json.Array:
        arr := obj["k"].(json.Array)
        // warning(iyaan): This allocation needs to be watched out for
        // when using non-arena allocators. Does it matter during debug
        // mode when using tracking allocator
        keyframes := make([dynamic]PropVectorKeyframe)
        resize(&keyframes, len(arr))
        for elem in arr {
          keyframe := parse_vector_keyframe(elem) or_return
          append(&keyframes, keyframe)
        }
        anim_vector.k = keyframes[:]
        return anim_vector, .None
      case:
        return vector_prop, .IncompatibleArrayType
      }
    } else {
      return vector_prop, .IncompatibleBooleanType
    }

  case:
    return req_or_err(required, vector_prop, .IncompatibleObjectType)
  }
}

parse_color_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  color_keyframe: PropColorKeyframe,
  err: LottieError,
) {

  if err := unmarshal_object(value, color_keyframe); err != .None {
    return req_or_err(required, color_keyframe, err)
  } else {
    return color_keyframe, .None
  }
}

parse_prop_color :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  color_prop: PropColor,
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    obj := value.(json.Object)
    animated_val := parse_integer(obj["a"], true) or_return
    sid_val := parse_string(obj["sid"]) or_return

    if animated_val == 0 {
      single_color := PropColorSingle {
        a   = false,
        sid = sid_val,
      }
      color_value: Color4
      unmarshal_array(obj["k"], color_value) or_return
      single_color.k = color_value
      color_prop = single_color
      return color_prop, .None
    } else if animated_val == 1 {
      anim_color_prop := PropColorAnim {
        a   = true,
        sid = sid_val,
      }

      #partial switch type in obj["k"] {
      case json.Array:
        arr := obj["k"].(json.Array)
        // warning(iyaan): This allocation needs to be watched out for
        // when using non-arena allocators. Does it matter during debug
        // mode when using tracking allocator
        keyframes := make([dynamic]PropColorKeyframe)
        resize(&keyframes, len(arr))
        for elem in arr {
          keyframe := parse_color_keyframe(elem) or_return
          append(&keyframes, keyframe)
        }
        anim_color_prop.k = keyframes[:]
        return anim_color_prop, .None
      case:
        return req_or_err(required, color_prop, .IncompatibleArrayType)
      }
    } else {
      return req_or_err(required, color_prop, .IncompatibleBooleanType)
    }
  case:
    return req_or_err(required, color_prop, .IncompatibleObjectType)
  }
}

parse_bezier_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  bezier_keyframe: PropBezierKeyframe,
  err: LottieError,
) {

  if err := unmarshal_object(value, bezier_keyframe); err != .None {
    return req_or_err(required, bezier_keyframe, err)
  } else {
    return bezier_keyframe, .None
  }
}

parse_prop_bezier :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  bezier_prop: PropBezier,
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    obj := value.(json.Object)
    animated_val := parse_integer(obj["a"], true) or_return

    if animated_val == 0 {
      single_bezier := PropBezierSingle {
        a = false,
      }
      bezier_shape_struct := BezierShapeValue{}
      unmarshal_object(obj["k"], bezier_shape_struct) or_return
      single_bezier.k = bezier_shape_struct
      bezier_prop = single_bezier
      return bezier_prop, .None
    } else if animated_val == 1 {
      anim_vector := PropBezierAnim {
        a = true,
      }

      #partial switch type in obj["k"] {
      case json.Array:
        arr := obj["k"].(json.Array)
        // warning(iyaan): This allocation needs to be watched out for
        // when using non-arena allocators. Does it matter during debug
        // mode when using tracking allocator
        keyframes := make([dynamic]PropBezierKeyframe)
        resize(&keyframes, len(arr))
        for elem in arr {
          keyframe := parse_bezier_keyframe(elem) or_return
          append(&keyframes, keyframe)
        }
        anim_vector.k = keyframes[:]
        return anim_vector, .None
      case:
        return req_or_err(required, bezier_prop, .IncompatibleArrayType)
      }
    } else {
      return req_or_err(required, bezier_prop, .IncompatibleBooleanType)
    }
  case:
    return req_or_err(required, bezier_prop, .IncompatibleObjectType)
  }
}


parse_value_vector :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vec: Vec3,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Array:
    vec: Vec3
    value_as_arr := value.(json.Array)
    if len(value_as_arr) > len(vec) {
      return req_or_err(required, Vec3{}, .TooLargeVector)
    }

    for idx in 0 ..< len(value_as_arr) {
      float_val := parse_number(value_as_arr[idx]) or_return
      vec[idx] = float_val
    }

    return vec, .None
  case:
    return req_or_err(required, Vec3{}, .IncompatibleVectorType)
  }

}

parse_string :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  string,
  LottieError,
) {
  #partial switch elem_type in value {
  case json.String:
    return value.(json.String), .None
  case:
    return req_or_err(required, "", .IncompatibleStringType)
  }
}


try_float :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  float_val: f64,
  err: LottieError,
) {
  #partial switch elem_type in value {
  case json.Float:
    return f64(value.(json.Float)), .None
  case json.Integer:
    return f64(value.(json.Integer)), .None
  case:
    return req_or_err(required, f64(0), .IncompatibleNumberType)
  }
}

parse_number :: try_float

parse_integer :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  i64,
  LottieError,
) {
  #partial switch elem_type in value {
  case json.Float:
    return i64(value.(json.Float)), .None
  case json.Integer:
    return i64(value.(json.Integer)), .None
  case:
    return req_or_err(required, i64(0), .IncompatibleIntegerType)
  }
}

// Some conveninent syntax to allow to use or_return
// The calling function will not return the error value
// if the callee function is called as non-required
req_or_err :: #force_inline proc(required: bool, ret_value: $T, error_type: LottieError) -> (T, LottieError) {
  if required {
    return ret_value, error_type
  } else {
    return ret_value, .None
  }
}

parse_bool :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  bool,
  LottieError,
) {
  #partial switch elem_type in value {
  case json.Boolean:
    return value.(json.Boolean), .None
  case json.Integer:
    int_val := value.(json.Integer)
    if int_val > 0 {
      return true, .None
    } else {
      return false, .None
    }
  case json.Float:
    // note(iyaan): Since json.parse in std library is called without the option
    // of parsing potential numbers as integers, almost all number values will be
    // in floats. Could be handy to have
    float_val := value.(json.Float)
    if float_val > 0.0 {
      return true, .None
    } else {
      return false, .None
    }

  case:
    return req_or_err(required, false, .IncompatibleBooleanType)
  }
}


parse_keyframe_easing_vec :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  easing_vec: PropKeyframeEasingVec,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Object:
    value_as_obj := value.(json.Object)

    easing_vec.x = parse_value_vector(value_as_obj["x"], true) or_return
    easing_vec.y = parse_value_vector(value_as_obj["y"], true) or_return

    return easing_vec, .None

  case:
    return req_or_err(required, easing_vec, .IncompatibleObjectType)

  }
}

parse_keyframe_easing_scalar :: proc(
  value: json.Value,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  ease_scalar: PropKeyframeEasingScalar,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Object:
    r_keyframe_easing := PropKeyframeEasingScalar{}
    value_as_obj := value.(json.Object)
    required_fields := []string{"x", "y"}
    for field in required_fields {
      if ok := field in value_as_obj; ok == false {
        return PropKeyframeEasingScalar{}, .MissingRequiredValue
      }
    }

    r_keyframe_easing.x = parse_number(value_as_obj["x"], true) or_return
    r_keyframe_easing.x = parse_number(value_as_obj["y"], true) or_return
    return r_keyframe_easing, .None
  case:
    return PropKeyframeEasingScalar{}, .IncompatibleObjectType

  }
}

// Checks for keys in an json.Object
check_missing_required :: proc(
  value: json.Value,
  required_fields: []string,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    value_as_obj := value.(json.Object)
    for field in required_fields {
      if ok := field in value_as_obj; ok == false {
        return .MissingRequiredValue
      }
    }
    return .None
  case:
    return .IncompatibleObjectType
  }
}


parse_split_position :: proc(
  value: json.Value,
  allocator := context.allocator,
  required := false,
  loc := #caller_location,
) -> (
  pos: PropPosition,
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    obj := value.(json.Object)
    if "s" in obj {
      required_fields := [?]string{"s", "x", "y"}
      split_pos := PropSplitPosition{}
      check_missing_required(value, required_fields[:]) or_return
      split_pos.s = parse_bool(obj["s"]) or_return
      split_pos.x = parse_prop_scalar(obj["x"]) or_return
      split_pos.y = parse_prop_scalar(obj["y"]) or_return
      pos = split_pos
      return pos, .None
    } else {
      normal_pos := parse_position(value) or_return
      pos = normal_pos
      return pos, .None
    }
  case:
    return req_or_err(required, pos, .IncompatiblePositionType)
  }
}

parse_scalar_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  scalar_keyframe: PropScalarKeyframe,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    scalar_keyframe.t = parse_integer(object["t"]) or_return
    scalar_keyframe.h = parse_integer(object["h"]) or_return
    scalar_keyframe.i = parse_keyframe_easing_scalar(object["i"]) or_return
    scalar_keyframe.o = parse_keyframe_easing_scalar(object["o"]) or_return
    scalar_keyframe.s = parse_number(object["s"]) or_return

    return scalar_keyframe, .None

  case:
    return req_or_err(required, scalar_keyframe, .IncompatibleObjectType)
  }
}


parse_vector_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vec_keyframe: PropVectorKeyframe,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    vec_keyframe.h = parse_integer(object["h"]) or_return
    vec_keyframe.i = parse_keyframe_easing_vec(object["i"]) or_return
    vec_keyframe.o = parse_keyframe_easing_vec(object["o"]) or_return
    vec_keyframe.s = parse_value_vector(object["s"]) or_return

    return vec_keyframe, .None

  case:
    return req_or_err(required, vec_keyframe, .IncompatibleObjectType)
  }
}

parse_position_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  pos_keyframe: PropPositionKeyframe,
  err: LottieError,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    pos_keyframe.h = parse_integer(object["h"]) or_return
    pos_keyframe.i = parse_keyframe_easing_vec(object["i"]) or_return
    pos_keyframe.o = parse_keyframe_easing_vec(object["o"]) or_return
    pos_keyframe.s = parse_value_vector(object["s"]) or_return
    pos_keyframe.ti = parse_value_vector(object["ti"]) or_return
    pos_keyframe.to = parse_value_vector(object["to"]) or_return

    return pos_keyframe, .None

  case:
    return req_or_err(required, pos_keyframe, .IncompatibleObjectType)
  }
}


parse_position :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  position: PropPosition,
  err: LottieError,
) {
  #partial switch type in value {
  case json.Object:
    position_obj := value.(json.Object)
    required_fields := []string{"a", "k"}
    check_missing_required(value, required_fields) or_return

    animated := parse_integer(position_obj["a"], true) or_return
    if animated == 0 {
      single_pos := PropPositionSingle {
        a = false,
      }
      single_pos.k = parse_value_vector(position_obj["k"]) or_return
      return single_pos, .None
    } else {
      position_anim := PropPositionAnim {
        a = true,
      }

      #partial switch type in position_obj["k"] {
      case json.Array:
        arr := position_obj["k"].(json.Array)
        keyframes := make([dynamic]PropPositionKeyframe)
        resize(&keyframes, len(arr))
        for elem in arr {
          keyframe := parse_position_keyframe(elem) or_return
          append(&keyframes, keyframe)
        }
        position_anim.k = keyframes[:]
        return position_anim, .None
      case:
        return position_anim, .IncompatibleArrayType
      }

      return position_anim, .None
    }
  case:
    return position, .None
  }
}

parse_transform :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  transform: Transform,
  err: LottieError,
) {
  transform_struct := Transform{}
  unmarshal_object(value, transform_struct) or_return
  return transform_struct, .None
}

read_file_handle :: proc(
  fd: ^os.File,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  data: JsonLottie,
  err: Error,
) {

  data.raw = os.read_entire_file_from_file(fd, allocator, loc) or_return
  parsed_json, parse_err := json.parse(data.raw)
  if parse_err != nil {
    return JsonLottie{}, parse_err
  }
  // note(iyaan): Need to call json.destroy_value on parsed_json
  // after we have fully parsed it into the structure
  defer delete(data.raw, allocator)
  defer json.destroy_value(parsed_json)

  return data, LottieError.None
}

read_file_name :: proc(
  file_name: string,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  data: JsonLottie,
  err: Error,
) {
  context.allocator = allocator
  fd := os.open(file_name) or_return
  defer os.close(fd)
  return read_file_handle(fd, allocator, loc)
}

main :: proc() {
  // note(iyaan): For debug mode setup the tracking allocator
  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    tracking_allocator := mem.tracking_allocator(&track)
    context.allocator = tracking_allocator

    logger := log.create_console_logger(allocator = tracking_allocator)
    context.logger = logger

    defer {
      log.destroy_console_logger(logger, allocator = tracking_allocator)

      if len(track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
          fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }

      }
      if len(track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
          fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  } else {
    // note(iyaan): All allocations related to the JsonLottie struct
    // and all its sub structs would be nice to have in one arena block
    // so that it would be easy to free it all together
    json_lottie_arena: vmem.Arena
    arena_err := vmem.arena_init_growing(&json_lottie_arena)
    ensure(arena_err == nil)
    json_lottie_arena_allocator := vmem.arena_allocator(&json_lottie_arena)

    context.allocator = json_lottie_arena_allocator

    // You free the underlying buffer for the arena. Not the
    // stack allocated arena struct. Hmm very C like!
    defer vmem.arena_destroy(&json_lottie_arena)
  }


  lottie_struct, err := read_file_name("../data/Fire.json", context.allocator)
  if err != nil && err != LottieError.None {
    fmt.eprintf("Could not read lottie json file due to %s\n", err)
    panic("Could not read lottie json file")
  }
}
