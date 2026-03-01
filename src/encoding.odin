package main

import "core:math/bits"
import "base:intrinsics"
import "core:encoding/varint"
import "core:math"
import "core:mem"

// To keep track of writes to the byte buffer
DebugInfo :: struct {
  start: u64,
  end:   u64,
}

Writer :: struct {
  data: []byte,
  offset: int,
}

// Will serialize any sequence of data. Does not write
// the length
writer_write_array :: proc(writer: ^Writer, array: []$T) {
  remaining := len(writer.data) - writer.offset
  assert(size_of(T)*len(array) <= remaining)
  ptr := raw_data(writer.data[writer.offset:])
  dst := mem.slice_ptr((^T)(ptr), len(array))
  copy(dst, array)
  writer.offset += size_of(T) * len(array)
}

writer_write_string :: proc(writer: ^Writer, str: string) {
  remaining := len(writer.data) - writer.offset
  assert(size_of(byte)*len(str) <= remaining)
  ptr := raw_data(writer.data[writer.offset:])
  dst := mem.slice_ptr((^byte)(ptr), len(str))
  copy(dst, str)
  writer.offset += size_of(byte) * len(str)
}

writer_write_value :: proc(writer: ^Writer, value: $T) {
  remaining := len(writer.data) - writer.offset
  assert(size_of(T) <= remaining)
  ptr := raw_data(writer.data[writer.offset:])
  (^T)(ptr)^ = value
  writer.offset += size_of(T)
}

writer_write_bytes :: proc(writer: ^Writer, buf: []byte) {
  writer_write_array(writer, buf)
}

// Fixed IEEE-754 floats (Helpers around the writer interface)

write_float64 :: proc(writer: ^Writer, f: f64) {
  writer_write_value(writer, f)
}

write_float32 :: proc(writer: ^Writer, f: f32) {
  writer_write_value(writer, f)
}

write_float16 :: proc(writer: ^Writer, f: f16) {
  writer_write_value(writer, f)
}

write_int8 :: proc(writer: ^Writer, i: i8) {
  writer_write_value(writer, i)
}

// Fixed signed interger variants

write_int16 :: proc(writer: ^Writer, i: i16) {
  writer_write_value(writer, i)
}

write_int32 :: proc(writer: ^Writer, i: i32) {
  writer_write_value(writer, i)
}

write_int64 :: proc(writer: ^Writer, i: i64) {
  writer_write_value(writer, i)
}

// Fixed unsigned interger variants

write_uint8 :: proc(writer: ^Writer, i: u8) {
  writer_write_value(writer, i)
}

write_uint16 :: proc(writer: ^Writer, i: u16) {
  writer_write_value(writer, i)
}

write_uint32 :: proc(writer: ^Writer, i: u32) {
  writer_write_value(writer, i)
}

write_uint64 :: proc(writer: ^Writer, i: u64) {
  writer_write_value(writer, i)
}

// Variable-byte encoding

encode_zigzag :: proc(x: i128) -> u128 {
  return u128((2 * x) ~ (x >> (size_of(i128) * 8 - 1)));
}

decode_zigzag :: proc(x: u128) -> i128 {
  return i128((x >> 1) ~ (-(x & 1)));
}

@(private = "file")
conv_to_varint :: proc(i: i128) -> (int, [varint.LEB128_MAX_BYTES]byte) {
  buffer: [varint.LEB128_MAX_BYTES]byte
  zigzag_int := encode_zigzag(i)
  size, err := varint.encode_uleb128(buffer[:], zigzag_int)
  assert(err == .None, "varint.encode_uleb128 failed with error")
  return size, buffer
}

// LEB-128 (zig-zag encoded)
// note(iyaan): Need to make this very optimized. Add SIMD
// support
write_varint :: proc(writer: ^Writer, i: i128) {
  size, buffer := conv_to_varint(i)
  writer_write_bytes(writer, buffer[:size])
}

write_string :: proc(writer: ^Writer, s: string) {
  write_varint(writer, i128(len(s)))
  writer_write_string(writer, s)
}

write_enum :: proc(writer: ^Writer, e: u8) {
  // note(iyaan): Lottie does not have any enums that requires
  // more than 1 byte of storage.
  write_uint8(writer, u8(e))  
}

write_bool :: proc(writer: ^Writer, b: bool) {
  writer_write_value(writer, b)
}

write_array :: proc(writer: ^Writer, array: []$T) {
  write_varint(writer, i128(len(array)))
  writer_write_array(writer, array)
}

write_vector4 :: proc(writer: ^Writer, vec: Vec4) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
  write_float32(writer, f32(vec[2]))
  write_float32(writer, f32(vec[3]))
}

write_vector3 :: proc(writer: ^Writer, vec: Vec3) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
  write_float32(writer, f32(vec[2]))
}

write_vector2 :: proc(writer: ^Writer, vec: Vec2) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
}

// note(iyaan): HexColor will also contain the preliminary # character
// as well
write_hexcolor :: proc(writer: ^Writer, hex_color: HexColor) {
  hex_digit :: proc(char: byte) -> (u8, bool) {
    switch char {
    case '0'..='9': return char - '0', true
    case 'a'..='f': return char - 'a' + 10, true
    case 'A'..='F': return char - 'A' + 10, true
    case:           return 0, false
    }
  }

  conv_str_hexcolor_to_rgb :: proc(hex_color: []u8) -> [3]byte {
    HEX_STR_MAX_LEN :: 6
    HEX_SHORTHAND_LEN :: 3
    if len(hex_color) == HEX_STR_MAX_LEN {
      value: [3]byte
      hex_color_bytes: [6]byte
      for idx in 0..<len(hex_color) {
        if b, ok := hex_digit(hex_color[idx]); ok {
          hex_color_bytes[idx] = b
        } else {
          // TODO: log errors
          assert(ok == true, "cannot convert byte to hex 0..f")
        }
      }

      b := (hex_color_bytes[4] << 8) | hex_color_bytes[5]
      g := (hex_color_bytes[2] << 8) | hex_color_bytes[3]
      r := (hex_color_bytes[0] << 8) | hex_color_bytes[1]
      value = {r, g, b}
      return value
    } else if len(hex_color) == HEX_SHORTHAND_LEN {
      value: [3]byte
      hex_color_bytes: [3]byte
      for idx in 0..<len(hex_color) {
        if b, ok := hex_digit(hex_color[idx]); ok {
          hex_color_bytes[idx] = b
        } else {
          // TODO: log errors
          assert(ok == true, "cannot convert byte to hex 0..f")
        }
      }

      b := (hex_color_bytes[2] << 8) | hex_color_bytes[2]
      g := (hex_color_bytes[1] << 8) | hex_color_bytes[1]
      r := (hex_color_bytes[0] << 8) | hex_color_bytes[0]
      value = {r, g, b}
      return value
    } else {
      assert(false, "incorrect hex color length")
      return {0, 0, 0}
    }
  }

  assert(hex_color[0] == '#', "Missing hash for hex color")
  hex_color_u8 := transmute([]u8)hex_color
  rgb := conv_str_hexcolor_to_rgb(hex_color_u8[1:])

  writer_write_bytes(writer, rgb[:])
}

write_color3 :: proc(writer: ^Writer, color3: Color3) {
  color3_vec := transmute(Vec3)color3
  write_vector3(writer, color3_vec)
}

write_color4 :: proc(writer: ^Writer, color4: Color4) {
  color4_vec := transmute(Vec4)color4
  write_vector4(writer, color4_vec)
}

write_gradient :: proc(writer: ^Writer, gradient: Gradient) {
  // note(iyaan): offset1, r, g, b, offset2, r, g, b ... alpha_stops
  // Just dump the floats as u8
  for stop in gradient {
    normalized_255 := u64(math.floor(stop * 255))
    assert(normalized_255 <= 255, "gradeient stop large than 1.0 probably")
    write_uint8(writer, u8(normalized_255))
  }
}

// A more general transform version supporting for all vector sizes
transform_array_vec_change_size :: proc(vec_array: [][$Y]$T, target_vec_size: int, allocator := context.temp_allocator) -> [][Y]T {
  r_vec_array := make_slice([][Y]T, len(vec_array), allocator)
  for i in 0..<len(vec_array) {
    for j in 0..<Y {
      r_vec_array[i][j] = vec_array[i][j]
    }
  }
  return r_vec_array
}

transform_array_vec3_to_vec2 :: proc($T: typeid, vec3_array: [][3]T, allocator := context.temp_allocator) -> [][2]T {
  vec2_array := make_slice([][2]T, len(vec3_array), allocator)
  for i in 0..<len(vec3_array) {
    vec2_array[i] = vec3_array[i].xy
  }
  return vec2_array
}

transform_array_vec3_intern_type :: proc($T: typeid, comp: []Vec3, allocator := context.temp_allocator) -> [][3]T {
  vec_array := make_slice([][3]T, len(comp), allocator)

  for i in 0..<len(comp) {
    vec := [3]T{
      T(comp[i].x),
      T(comp[i].y),
      T(comp[i].z),
    }
    vec_array[i] = vec
  }

  return vec_array
}

LEB128Res :: struct {
  buffer: [varint.LEB128_MAX_BYTES]byte,
  size: int
}
transform_array_vec_intern_varint :: proc(vec_slice: [][$T]i128, allocator := context.temp_allocator) -> [][T]LEB128Res {
  #assert(T <= 3, "Why is your vector size un-natural???")
  r_array := make_slice([][T]LEB128Res, len(vec_slice), allocator)
  for i in 0..<len(vec_slice) {
    vec := vec_slice[i]
    r_struct := [T]LEB128Res{}
    for j in 0..<T {
      size, buf := conv_to_varint(vec[j])
      r_struct[i] = LEB128Res{buf, size}
    }
    r_array[i] = r_struct
  }
  return r_array
}

// Will compute the delta, of each subsequent value. Use the first value as the first
// reference point. The values will then be encoded in LEB128
// TODO: Make this a SIMD algorithm. Maybe Daniel Lemiere's algorithm.
transform_array_delta_enc :: proc(array: $T/[]$E, allocator := context.temp_allocator) -> []LEB128Res
  where intrinsics.type_is_float(E) || intrinsics.type_is_integer(E) {
  assert(len(array) >= 2, "delta encoding requires at least two elements")
  r_array := make_slice([]LEB128Res, len(array), allocator)
  for i in 1..<len(array) {
    delta := array[i] - array[i - 1]
    size, buf := conv_to_varint(i128(delta))
    r_array[i] = LEB128Res{buf, size}
  }
  return r_array
}

// Delta encoding variant for 3d vectors
transform_array_vec3_delta_enc :: proc(array: []Vec3, allocator := context.allocator) -> [][3]LEB128Res {
  assert(len(array) >= 2, "delta encoding requires at least two elements")
  r_array := make_slice([][3]LEB128Res, len(array), allocator)
  for i in 1..<len(array) {
    delta := array[i].xyz - array[i - 1].xyz
    size_x, buf_x := conv_to_varint(i128(delta.x))
    size_y, buf_y := conv_to_varint(i128(delta.y))
    size_z, buf_z := conv_to_varint(i128(delta.z))
    r_struct := [3]LEB128Res{
      LEB128Res{buf_x, size_x},
      LEB128Res{buf_y, size_y},
      LEB128Res{buf_z, size_z}
    }
    r_array[i] = r_struct
  }
  return r_array
}

BezierShapeFlags :: enum u8 {
  Closed_Loop,
  As_Float32,  // Encode all vector values as f32
  As_Float16,
  As_Varint,   // Will truncate floating point values
  Use_Vec2,    // Use Vec2 instead of Vec3
}

// Will free the temporary allocator
write_bezier :: proc(writer: ^Writer,
                     bezier_shape: BezierShapeValue,
                     flags: bit_set[BezierShapeFlags; u8]) {
  #assert(size_of(flags) == size_of(u8), "flags should be an u8")
  write_uint8(writer, transmute(u8)flags)
  // note(iyaan): The vector fileds are supposed to have the same length
  expected_len := len(bezier_shape.i)
  assert(len(bezier_shape.o) == expected_len, "mismatched i and o in bezier shape")
  assert(len(bezier_shape.v) == expected_len, "mismatched i and v in bezier shape")


  if .As_Float16 in flags {
    f16_i_vecs := transform_array_vec3_intern_type(f16, bezier_shape.i)
    f16_o_vecs := transform_array_vec3_intern_type(f16, bezier_shape.o)
    f16_v_vecs := transform_array_vec3_intern_type(f16, bezier_shape.v)

    if .Use_Vec2 in flags {
      f16_i_vec2s := transform_array_vec3_to_vec2(f16, f16_i_vecs)
      f16_o_vec2s := transform_array_vec3_to_vec2(f16, f16_o_vecs)
      f16_v_vec2s := transform_array_vec3_to_vec2(f16, f16_v_vecs)
      write_array(writer, f16_i_vec2s)
      write_array(writer, f16_i_vec2s)
      write_array(writer, f16_i_vec2s)
    } else {
      write_array(writer, f16_i_vecs)
      write_array(writer, f16_o_vecs)
      write_array(writer, f16_v_vecs)
    }
  } else if .As_Varint in flags {
    // note(iyaan): Force truncate floats to varints. You will lose the
    // float precision
    varint_i_vecs := transform_array_vec3_intern_type(i128, bezier_shape.i)
    varint_o_vecs := transform_array_vec3_intern_type(i128, bezier_shape.o)
    varint_v_vecs := transform_array_vec3_intern_type(i128, bezier_shape.v)

    if .Use_Vec2 in flags {
      varint_i_vec2s := transform_array_vec3_to_vec2(i128, varint_i_vecs)
      varint_o_vec2s := transform_array_vec3_to_vec2(i128, varint_o_vecs)
      varint_v_vec2s := transform_array_vec3_to_vec2(i128, varint_v_vecs)

      varint_i_array := transform_array_vec_intern_varint(varint_i_vec2s)
      varint_o_array := transform_array_vec_intern_varint(varint_o_vec2s)
      varint_v_array := transform_array_vec_intern_varint(varint_v_vec2s)
      write_array(writer, varint_i_array)
      write_array(writer, varint_o_array)
      write_array(writer, varint_v_array)
    } else {
      varint_i_array := transform_array_vec_intern_varint(varint_i_vecs)
      varint_o_array := transform_array_vec_intern_varint(varint_o_vecs)
      varint_v_array := transform_array_vec_intern_varint(varint_v_vecs)
      write_array(writer, varint_i_array)
      write_array(writer, varint_o_array)
      write_array(writer, varint_v_array)
    }
  } else {
    f32_i_vecs := transform_array_vec3_intern_type(f32, bezier_shape.i)
    f32_o_vecs := transform_array_vec3_intern_type(f32, bezier_shape.o)
    f32_v_vecs := transform_array_vec3_intern_type(f32, bezier_shape.v)

    if .Use_Vec2 in flags {
      f32_i_vec2s := transform_array_vec3_to_vec2(f32, f32_i_vecs)
      f32_o_vec2s := transform_array_vec3_to_vec2(f32, f32_o_vecs)
      f32_v_vec2s := transform_array_vec3_to_vec2(f32, f32_v_vecs)
      write_array(writer, f32_i_vec2s)
      write_array(writer, f32_i_vec2s)
      write_array(writer, f32_i_vec2s)
    } else {
      write_array(writer, f32_i_vecs)
      write_array(writer, f32_o_vecs)
      write_array(writer, f32_v_vecs)
    }
  }

  free_all(context.temp_allocator)
}

@(deprecated="use the bitset version")
isset_old :: #force_inline proc "contextless" (value: u64, bit: uint) -> bool {
  // note(iyaan): odin implementation
  // of this produces better ASM than my impl in odin
  return bits.bitfield_extract_u64(value, bit, 1) == 1
}

isset :: #force_inline proc "contextless" (value: Bit64, bit: int) -> bool {
  return bit in value
}

@(deprecated="use the bitset version")
extract_bit_indices_old :: proc(flags: u64) -> [64]u8 {
  flags1 := flags
  r := [64]u8{}
  for flags1 > 0 {
    trail_zeros := intrinsics.count_trailing_zeros(flags1)
    // note(iyaan): The number of trailing zeros will also
    // conveniently give the index of the rightmost 1 bit
    // Eg: 00011010 (26) = 1 trailing zero, idx of right most
    // is 1
    r[trail_zeros] = 1
    flags1 &= flags1 - 1
  }
  return r
}

Bit64 :: bit_set[0..<64]
// A utility function that will give a convenient
// bitset, depending on whether the respective
// index position in the parameter is set or not. The first
// element of the resulting array corresponds to the rightmost
// bit of the parameter
extract_bit_indices :: proc(flags: u64) -> (r: Bit64) {
  r = transmute(Bit64)flags
  return r
}

write_prop_vector_keyframe :: proc(writer: ^Writer, vec_keyframe: PropVectorKeyframe) {
  flags := transmute(Bit64)vec_keyframe._flags
  write_uint8(writer, u8(vec_keyframe._flags))
  if isset(flags, 0) do write_varint(writer, i128(vec_keyframe.t))
  if isset(flags, 1) do write_varint(writer, i128(vec_keyframe.h))
  if isset(flags, 2) do write_keyframe_easing(writer, vec_keyframe.i)
  if isset(flags, 3) do write_keyframe_easing(writer, vec_keyframe.o)
  write_vector3(writer, vec_keyframe.s)
}

write_prop_vector :: proc(writer: ^Writer, vector: PropVector) {
  // note(iyaan): These are required fields as by lottie-schema
  // https://lottie.github.io/lottie-spec/latest/specs/schema/#/$defs/helpers/slottable-property

  switch type in vector {
  case PropVectorSingle:
    vector_single := vector.(PropVectorSingle)
    write_uint8(writer, u8(vector_single._flags))
    flags := transmute(Bit64)vector_single._flags
    
    if isset(flags, 0) do write_string(writer, vector_single.sid)
    if isset(flags, 1) do write_bool(writer, vector_single.a)
    if isset(flags, 2) do write_vector3(writer, vector_single.k)
  case PropVectorAnim:
    vector_anim := vector.(PropVectorAnim)
    write_uint8(writer, u8(vector_anim._flags))
    flags := transmute(Bit64)vector_anim._flags
    if isset(flags, 0) do write_string(writer, vector_anim.sid)
    if isset(flags, 1) do write_bool(writer, vector_anim.a)

    if isset(flags, 2) {
      // write the keyframes as an array
      write_varint(writer, i128(len(vector_anim.k)))
      for frame in vector_anim.k {
        write_prop_vector_keyframe(writer, frame)
      }
    }
  }
}

write_prop_scalar_keyframe :: proc(writer: ^Writer, scalar_keyframe: PropScalarKeyframe) {
  flags := transmute(Bit64)scalar_keyframe._flags
  write_uint8(writer, u8(scalar_keyframe._flags))
  if isset(flags, 0) do write_varint(writer, i128(scalar_keyframe.t))
  if isset(flags, 1) do write_varint(writer, i128(scalar_keyframe.h))
  if isset(flags, 2) do write_keyframe_easing(writer, scalar_keyframe.i)
  if isset(flags, 3) do write_keyframe_easing(writer, scalar_keyframe.o)
  write_float32(writer, f32(scalar_keyframe.s))
}

write_prop_scalar :: proc(writer: ^Writer, scalar: PropScalar) {
  switch type in scalar {
  case PropScalarSingle:
    scalar_single := scalar.(PropScalarSingle)
    flags := transmute(Bit64)scalar_single._flags
    write_uint8(writer, u8(transmute(u64)flags))
    
    if isset(flags, 0) do write_string(writer, scalar_single.sid)
    if isset(flags, 2) do write_float32(writer, f32(scalar_single.k))
  case PropScalarAnim:
    scalar_anim := scalar.(PropScalarAnim)
    flags := transmute(Bit64)scalar_anim._flags
    assert(1 in flags, "Animated position does not have the `a` flag set")
    if isset(flags, 0) do write_string(writer, scalar_anim.sid)
    
    write_varint(writer, i128(len(scalar_anim.k)))
    for frame in scalar_anim.k {
      write_prop_scalar_keyframe(writer, frame)
    }
  }
}

write_prop_position_keyframe :: proc(writer: ^Writer, position_keyframe: PropPositionKeyframe) {
  flags := transmute(Bit64)position_keyframe._flags
  write_uint8(writer, u8(position_keyframe._flags))
  if isset(flags, 0) do write_varint(writer, i128(position_keyframe.t))
  if isset(flags, 1) do write_varint(writer, i128(position_keyframe.h))
  if isset(flags, 2) do write_keyframe_easing(writer, position_keyframe.i)
  if isset(flags, 3) do write_keyframe_easing(writer, position_keyframe.o)
  // TODO(iyaan): In the base lottie spec there are no 3d dimensional
  // animations therefore positions are always 2d vectors. Need to change
  // later
  write_vector2(writer, position_keyframe.s.xy)
  write_vector2(writer, position_keyframe.ti.xy)
  write_vector2(writer, position_keyframe.to.xy)
}

write_prop_position :: proc(writer: ^Writer, position: PropPosition) {
  switch type in position {
  case PropPositionSingle:
    position_single := position.(PropPositionSingle)
    flags := transmute(Bit64)position_single._flags
    write_uint8(writer, u8(transmute(u64)flags))
    if isset(flags, 0) do write_string(writer, position_single.sid)
    vec2 := Vec2{position_single.k.x, position_single.k.y}
    if isset(flags, 2) do write_vector2(writer, vec2)
  case PropPositionAnim:
    position_anim := position.(PropPositionAnim)
    flags := transmute(Bit64)position_anim._flags
    assert(1 in flags, "Animated position does not have the `a` flag set")
    if isset(flags, 0) do write_string(writer, position_anim.sid)
    write_varint(writer, i128(len(position_anim.k)))
    for frame in position_anim.k {
      write_prop_position_keyframe(writer, frame)
    }
  case PropSplitPosition:
    position_split := position.(PropSplitPosition)
    write_bool(writer, position_split.s)
    write_prop_scalar(writer, position_split.x)
    write_prop_scalar(writer, position_split.y)
  }
}

write_keyframe_easing :: proc(writer: ^Writer, easing: PropKeyframeEasing) {
  switch type in easing {
  case PropKeyframeEasingScalar:
    easing_scalar := easing.(PropKeyframeEasingScalar)
    write_varint(writer, i128(easing_scalar.x))
    write_varint(writer, i128(easing_scalar.y))
  case PropKeyframeEasingVec:
    easing_vector := easing.(PropKeyframeEasingVec)
    // TODO: Probably should not write just write each vector
    // as plain f32 here
    write_vector3(writer, easing_vector.x)
    write_vector3(writer, easing_vector.y)
  case:
    panic("Unidentifed union type in PropKeyframeEasing")
  }
}

write_transform :: proc(writer: Writer, transform: Transform) {
  
}
