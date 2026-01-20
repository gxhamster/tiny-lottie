package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"


JL_Error :: enum {
  None,
  Missing_Required_Value,
  Outof_Range_Value,
  Unmarshal_Err,
  Incompatible_Vector_Type,
  Incompatible_Vector_Inner_Type,
  Incompatible_Object_Type,
  Incompatible_Scalar_Type,
  Incompatible_Integer_Type,
  Incompatible_Array_Type,
  Incompatible_Number_Type,
  Incompatible_Boolean_Type,
  Incompatible_String_Type,
  Incompatible_Position_Type,
  Incompatible_Prop_Scalar_Type,
  Incompatible_Transform_Type,
  Too_Large_Vector,
  Too_Small_Vector,
  Unmarshal_Unknown_Value_Type,
  Unmarshal_Unknown_Array_Type,
  Unmarshal_Unknown_Object_Type,
  Unmarshal_Unknown_Array_Inner_Type,
  Unmarshal_Unknown_Struct_Field_Type,
  Unmarshal_Unknown_Union_Field_Type,
  Unmarshal_Allocation_Error,
  Unmarshal_Deallocation_Error,
}

Error :: union {
  os.Error,
  JL_Error,
  json.Error,
}

Animation :: struct {
  nm:      string,
  ver:     i64,
  fr:      f64,
  ip:      f64,
  op:      f64,
  w:       i64,
  h:       i64,
  layers:  json.Array,
  assets:  json.Array,
  markers: json.Array,
  slots:   json.Object,
}

// Values
Vec3 :: distinct [3]f64
Vec2 :: distinct [2]f64

// note(iyaan): sometimes you might find color values
// with 4 components (the 4th being alpha) but most
// players ignore the last component.
Color3 :: Vec3
Color4 :: distinct [4]f64
HexColor :: distinct string
Gradient :: distinct []f64

BezierShapeValue :: struct {
  c: bool,
  i: []Vec3,
  o: []Vec3,
  v: []Vec3,
}

// Properties
PropKeyframeEasingVec :: struct {
  x: Vec3,
  y: Vec3,
}

PropKeyframeEasingScalar :: struct {
  x: f64,
  y: f64,
}

PropScalar :: union {
  PropScalarSingle,
  PropScalarAnim,
}

PropScalarSingle :: struct {
  sid: string,
  a:   bool,
  k:   f64,
}

PropScalarKeyframe :: struct {
  t: f64,
  h: i64,
  i: PropKeyframeEasingScalar,
  o: PropKeyframeEasingScalar,
  s: f64,
}

PropScalarAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropScalarKeyframe,
}

PropBezier :: union {
  PropBezierSingle,
  JsonLottie_Prop_Bezier_Anim,
}

PropBezierSingle :: struct {
  a: bool,
  k: BezierShapeValue,
}

PropBezierKeyframe :: struct {
  t: f64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: BezierShapeValue,
}

JsonLottie_Prop_Bezier_Anim :: struct {
  a: bool,
  k: []PropBezierKeyframe,
}


PropColor :: union {
  PropColorSingle,
  PropColorAnim,
}

PropColorSingle :: struct {
  sid: string,
  a:   bool,
  k:   Color4,
}

PropColorKeyframe :: struct {
  t: f64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: Color4,
}

PropColorAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropColorKeyframe,
}

PropVector :: union {
  PropVectorSingle,
  PropVectorAnim,
}

PropVectorSingle :: struct {
  sid: string,
  a:   bool,
  k:   Vec3,
}

PropVectorKeyframe :: struct {
  t: f64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: Vec3,
}

PropVectorAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropVectorKeyframe,
}

// 2D version of a Vector property
PropPosition :: union {
  PropPositionSingle,
  PropPositionAnim,
  PropSplitPosition,
}

PropPositionSingle :: PropVectorSingle
PropPositionKeyframe :: struct {
  t:  f64,
  h:  i64,
  i:  PropKeyframeEasingVec,
  o:  PropKeyframeEasingVec,
  s:  Vec3,
  ti: Vec3,
  to: Vec3,
}

PropPositionAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropPositionKeyframe,
}

PropSplitPosition :: struct {
  s: bool,
  x: PropScalar,
  y: PropScalar,
}

// Helpers
Transform :: struct {
  a:  PropPosition,
  p:  PropPosition,
  r:  PropScalar,
  s:  PropVector,
  o:  PropScalar,
  sk: PropScalar,
  sa: PropScalar,
}

Layer :: struct {
  nm:     string,
  hd:     bool,
  ty:     i64,
  ind:    i64,
  parent: i64,
  ip:     f64,
  op:     f64,
}

ShapeLayer :: struct {}

ImageLayer :: struct {}

NullLayer :: struct {}

SolidLayer :: struct {}

PrecompLayer :: struct {}

JsonLottie :: struct {
  animation: Animation,
  raw:       []u8,
}

CoreTypes :: enum {
  Null,
  Array,
  Object,
  Float,
  Integer,
  Bool,
  String,
}

json_obj_val_type :: proc(
  root: ^json.Object,
  key: string,
) -> CoreTypes {
  if root[key] == nil {
    return .Null
  }
  data := root[key]
  #partial switch type_val in data {
  case json.Null:
    return .Null
  case json.Array:
    return .Array
  case json.Object:
    return .Object
  case json.Float:
    return .Float
  case json.Integer:
    return .Integer
  }
  panic("unexpected type")
}

field_expect_type :: proc(
  root: ^json.Object,
  key: string,
  expected: CoreTypes,
) -> bool {
  data := root[key]
  union_type := CoreTypes.Null
  switch type_val in data {
  case json.Null:
    union_type = .Null
  case json.Array:
    union_type = .Array
  case json.Object:
    union_type = .Object
  case json.Boolean:
    union_type = .Bool
  case json.Integer:
    union_type = .Integer
  case json.Float:
    union_type = .Float
  case json.String:
    union_type = .String
  }

  if union_type == expected {
    return true
  } else {
    return false
  }
}

parse_layers :: proc(
  anim: ^Animation,
  layer_json_array: json.Array,
  allocator := context.allocator,
  loc := #caller_location,
) -> JL_Error {
  p := (layer_json_array[0].(json.Object)["ks"])

  transform, err := parse_transform(p)
  // if err != .None {
  //      fmt.println(err)
  // } else {
  //      fmt.println(transform)
  // }
  return .None
}

parse_prop_scalar :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  scalar: PropScalar,
  err: JL_Error,
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
        return scalar, .Incompatible_Array_Type
      }
    }
  case:
    return req_or_err(
      required,
      scalar,
      .Incompatible_Prop_Scalar_Type,
    )
  }

}

parse_prop_vector :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vector_prop: PropVector,
  err: JL_Error,
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
        return vector_prop, .Incompatible_Array_Type
      }
    } else {
      return vector_prop, .Incompatible_Boolean_Type
    }

  case:
    return req_or_err(
      required,
      vector_prop,
      .Incompatible_Object_Type,
    )
  }
}

parse_color_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  color_keyframe: PropColorKeyframe,
  err: JL_Error,
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
  err: JL_Error,
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
        return req_or_err(
          required,
          color_prop,
          .Incompatible_Array_Type,
        )
      }
    } else {
      return req_or_err(
        required,
        color_prop,
        .Incompatible_Boolean_Type,
      )
    }
  case:
    return req_or_err(
      required,
      color_prop,
      .Incompatible_Object_Type,
    )
  }
}

parse_bezier_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  bezier_keyframe: PropBezierKeyframe,
  err: JL_Error,
) {

  if err := unmarshal_object(value, bezier_keyframe);
     err != .None {
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
  err: JL_Error,
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
      anim_vector := JsonLottie_Prop_Bezier_Anim {
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
        return req_or_err(
          required,
          bezier_prop,
          .Incompatible_Array_Type,
        )
      }
    } else {
      return req_or_err(
        required,
        bezier_prop,
        .Incompatible_Boolean_Type,
      )
    }
  case:
    return req_or_err(
      required,
      bezier_prop,
      .Incompatible_Object_Type,
    )
  }
}


parse_value_vector :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vec: Vec3,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Array:
    vec: Vec3
    value_as_arr := value.(json.Array)
    if len(value_as_arr) > len(vec) {
      return req_or_err(required, Vec3{}, .Too_Large_Vector)
    }

    for idx in 0 ..< len(value_as_arr) {
      float_val := parse_number(value_as_arr[idx]) or_return
      vec[idx] = float_val
    }

    return vec, .None
  case:
    return req_or_err(required, Vec3{}, .Incompatible_Vector_Type)
  }

}

parse_string :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  string,
  JL_Error,
) {
  #partial switch elem_type in value {
  case json.String:
    return value.(json.String), .None
  case:
    return req_or_err(required, "", .Incompatible_String_Type)
  }
}


try_float :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  float_val: f64,
  err: JL_Error,
) {
  #partial switch elem_type in value {
  case json.Float:
    return f64(value.(json.Float)), .None
  case json.Integer:
    return f64(value.(json.Integer)), .None
  case:
    return req_or_err(required, f64(0), .Incompatible_Number_Type)
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
  JL_Error,
) {
  #partial switch elem_type in value {
  case json.Float:
    return i64(value.(json.Float)), .None
  case json.Integer:
    return i64(value.(json.Integer)), .None
  case:
    return req_or_err(required, i64(0), .Incompatible_Integer_Type)
  }
}

// Some conveninent syntax to allow to use or_return
// The calling function will not return the error value
// if the callee function is called as non-required
req_or_err :: #force_inline proc(
  required: bool,
  ret_value: $T,
  error_type: JL_Error,
) -> (
  T,
  JL_Error,
) {
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
  JL_Error,
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
    return req_or_err(required, false, .Incompatible_Boolean_Type)
  }
}


parse_keyframe_easing_vec :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  easing_vec: PropKeyframeEasingVec,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Object:
    value_as_obj := value.(json.Object)

    easing_vec.x = parse_value_vector(
      value_as_obj["x"],
      true,
    ) or_return
    easing_vec.y = parse_value_vector(
      value_as_obj["y"],
      true,
    ) or_return

    return easing_vec, .None

  case:
    return req_or_err(
      required,
      easing_vec,
      .Incompatible_Object_Type,
    )

  }
}

parse_keyframe_easing_scalar :: proc(
  value: json.Value,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  ease_scalar: PropKeyframeEasingScalar,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Object:
    r_keyframe_easing := PropKeyframeEasingScalar{}
    value_as_obj := value.(json.Object)
    required_fields := []string{"x", "y"}
    for field in required_fields {
      if ok := field in value_as_obj; ok == false {
        return PropKeyframeEasingScalar{},
          .Missing_Required_Value
      }
    }

    r_keyframe_easing.x = parse_number(
      value_as_obj["x"],
      true,
    ) or_return
    r_keyframe_easing.x = parse_number(
      value_as_obj["y"],
      true,
    ) or_return
    return r_keyframe_easing, .None
  case:
    return PropKeyframeEasingScalar{}, .Incompatible_Object_Type

  }
}

// Checks for keys in an json.Object
check_missing_required :: proc(
  value: json.Value,
  required_fields: []string,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  err: JL_Error,
) {
  #partial switch type in value {
  case json.Object:
    value_as_obj := value.(json.Object)
    for field in required_fields {
      if ok := field in value_as_obj; ok == false {
        return .Missing_Required_Value
      }
    }
    return .None
  case:
    return .Incompatible_Object_Type
  }
}


parse_split_position :: proc(
  value: json.Value,
  allocator := context.allocator,
  required := false,
  loc := #caller_location,
) -> (
  pos: PropPosition,
  err: JL_Error,
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
    return req_or_err(required, pos, .Incompatible_Position_Type)
  }
}

parse_scalar_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  scalar_keyframe: PropScalarKeyframe,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    scalar_keyframe.t = parse_number(object["t"]) or_return
    scalar_keyframe.h = parse_integer(object["h"]) or_return
    scalar_keyframe.i = parse_keyframe_easing_scalar(
      object["i"],
    ) or_return
    scalar_keyframe.o = parse_keyframe_easing_scalar(
      object["o"],
    ) or_return
    scalar_keyframe.s = parse_number(object["s"]) or_return

    return scalar_keyframe, .None

  case:
    return req_or_err(
      required,
      scalar_keyframe,
      .Incompatible_Object_Type,
    )
  }
}


parse_vector_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  vec_keyframe: PropVectorKeyframe,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    vec_keyframe.t = parse_number(object["t"]) or_return
    vec_keyframe.h = parse_integer(object["h"]) or_return
    vec_keyframe.i = parse_keyframe_easing_vec(
      object["i"],
    ) or_return
    vec_keyframe.o = parse_keyframe_easing_vec(
      object["o"],
    ) or_return
    vec_keyframe.s = parse_value_vector(object["s"]) or_return

    return vec_keyframe, .None

  case:
    return req_or_err(
      required,
      vec_keyframe,
      .Incompatible_Object_Type,
    )
  }
}

parse_position_keyframe :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  pos_keyframe: PropPositionKeyframe,
  err: JL_Error,
) {
  #partial switch value_type in value {
  case json.Object:
    object := value.(json.Object)

    pos_keyframe.t = parse_number(object["t"]) or_return
    pos_keyframe.h = parse_integer(object["h"]) or_return
    pos_keyframe.i = parse_keyframe_easing_vec(
      object["i"],
    ) or_return
    pos_keyframe.o = parse_keyframe_easing_vec(
      object["o"],
    ) or_return
    pos_keyframe.s = parse_value_vector(object["s"]) or_return
    pos_keyframe.ti = parse_value_vector(object["ti"]) or_return
    pos_keyframe.to = parse_value_vector(object["to"]) or_return

    return pos_keyframe, .None

  case:
    return req_or_err(
      required,
      pos_keyframe,
      .Incompatible_Object_Type,
    )
  }
}


parse_position :: proc(
  value: json.Value,
  required := false,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  position: PropPosition,
  err: JL_Error,
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
      single_pos.k = parse_value_vector(
        position_obj["k"],
      ) or_return
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
        return position_anim, .Incompatible_Array_Type
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
  err: JL_Error,
) {
  transform_struct := Transform{}
  unmarshal_object(value, transform_struct) or_return
  return transform_struct, .None
}

read_file_handle :: proc(
  fd: os.Handle,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  data: JsonLottie,
  err: Error,
) {

  data.raw = os.read_entire_file_from_handle_or_err(
    fd,
    allocator,
    loc,
  ) or_return
  parsed_json, parse_err := json.parse(data.raw)
  if parse_err != nil {
    return JsonLottie{}, parse_err
  }
  // note(iyaan): Need to call json.destroy_value on parsed_json
  // after we have fully parsed it into the structure
  defer delete(data.raw, allocator)
  defer json.destroy_value(parsed_json)

  root := parsed_json.(json.Object)
  if root["h"] == nil ||
     root["w"] == nil ||
     root["fr"] == nil ||
     root["op"] == nil ||
     root["ip"] == nil {
    return JsonLottie{}, JL_Error.Missing_Required_Value
  }

  data.animation.nm = root["nm"].(json.String)
  data.animation.fr = root["fr"].(json.Float)
  data.animation.op = root["op"].(json.Float)
  data.animation.ip = root["ip"].(json.Float)
  data.animation.w = i64(root["w"].(json.Float))
  data.animation.h = i64(root["h"].(json.Float))

  if data.animation.h < 0 {
    return JsonLottie{}, JL_Error.Outof_Range_Value
  }
  if data.animation.w < 0 {
    return JsonLottie{}, JL_Error.Outof_Range_Value
  }
  if data.animation.fr < 1 {
    return JsonLottie{}, JL_Error.Outof_Range_Value
  }
  LOTTIE_VERSION_MIN :: 10000
  if root["ver"] != nil && root["ver"].(json.Integer) < LOTTIE_VERSION_MIN {
    return JsonLottie{}, JL_Error.Outof_Range_Value
  } else if root["ver"] != nil &&
     root["ver"].(json.Integer) > LOTTIE_VERSION_MIN {
    data.animation.ver = root["ver"].(json.Integer)
  }

  layer_ok := field_expect_type(&root, "layers", .Array)
  marker_ok := field_expect_type(&root, "markers", .Array)
  assets_ok := field_expect_type(&root, "assets", .Array)
  slots_ok := field_expect_type(&root, "slots", .Object)


  if layer_ok {
    parse_layers(&data.animation, root["layers"].(json.Array))
  }
  if marker_ok {
    data.animation.markers = root["markers"].(json.Array)
  }
  if assets_ok {
    data.animation.assets = root["assets"].(json.Array)
  }
  if slots_ok {
    data.animation.slots = root["slots"].(json.Object)
  }
  return data, JL_Error.None
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
  fd := os.open(file_name, os.O_RDONLY, 0) or_return
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
    log.
    context.logger = logger

    defer {
      log.destroy_console_logger(logger, allocator = tracking_allocator)

      if len(track.allocation_map) > 0 {
        fmt.eprintf(
          "=== %v allocations not freed: ===\n",
          len(track.allocation_map),
        )
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


  lottie_struct, err := read_file_name(
    "./data/Fire.json",
    context.allocator,
  )
  if err != nil && err != JL_Error.None {
    fmt.eprintf("Could not read lottie json file due to %s\n", err)
    panic("Could not read lottie json file")
  }
}
