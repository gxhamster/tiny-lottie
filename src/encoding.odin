package main

import "core:slice"
import "core:math/bits"
import "base:intrinsics"
import "core:encoding/varint"
import "core:math"
import "core:mem"
import "core:testing"
import "core:log"
import "core:fmt"
import "core:simd"

// To keep track of writes to the byte buffer
DebugInfoType :: enum {
  meta,
  f16,
  f32,
  f64,
  i8,
  i16,
  i32,
  i64,
  u8,
  u16,
  u32,
  u64,
  varint,
  bool,
  string,
}
DebugInfo :: struct {
  name: string,
  type: DebugInfoType,
  start_byte: int,
  start_bit: uint,
  end_byte: int,
  end_bit: uint,
}

Writer :: struct {
  data: []byte,
  offset: int,
  bits: uint,     // This is the bit offset within the current byte specified by `offset` in `data`
  debug: [dynamic]DebugInfo,
}

writer_reset :: proc(writer: ^Writer) {
  writer.bits = 0
  writer.offset = 0
  mem.zero(&writer.data[0], len(writer.data))
}

// note(iyaan): Allows for encoding fields not aligned at 
// byte boundaries will take care of the proper offsets
// note(iyaan): when serializing flags do not call this function
// for each individual flag bit. Do it for the whole thing.
// All writing functions must use this otherwise it will not respect
// the bit offset
write_bits :: proc(writer: ^Writer, value: int, num_bits: uint) {
  ptr := cast(^int)raw_data(writer.data[writer.offset:])
  mask := int(1 << num_bits - 1)
  base := ptr^
	res := (base & ~(mask << writer.bits)) | ((value & mask) << writer.bits)
  total_bit_offset := int(writer.bits + num_bits)
  writer.offset += total_bit_offset / 8
  writer.bits = uint(total_bit_offset) % 8
  ptr^ = res
}

// Will serialize any sequence of data. Does not write
// the length.
@(deprecated = "cannot write in between bytes")
writer_write_array :: proc(writer: ^Writer, array: []$T) {
  remaining := len(writer.data) - writer.offset
  assert(size_of(T)*len(array) <= remaining)
  ptr := raw_data(writer.data[writer.offset:])
  dst := mem.slice_ptr((^T)(ptr), len(array))
  copy(dst, array)
  writer.offset += size_of(T) * len(array)
}

writer_write_string :: proc(writer: ^Writer, str: string) {
  for idx in 0..<len(str) {
    write_bits(writer, int(str[idx]), size_of(byte))
  }
}

@(deprecated="cannot write sub-byte values")
writer_write_value :: proc(writer: ^Writer, value: $T) {
  remaining := len(writer.data) - writer.offset
  assert(size_of(T) <= remaining)
  ptr := raw_data(writer.data[writer.offset:])
  (^T)(ptr)^ = value
  writer.offset += size_of(T)
}

writer_write_bytes :: proc(writer: ^Writer, buf: []byte) {
  for b in buf {
    write_bits(writer, int(b), size_of(byte))
  }
}

// captures the writers position state,
// call before writing the actual information
// to writer
begin_debug_info :: proc(writer: ^Writer, debug_name: string, type: DebugInfoType) -> DebugInfo {
  info := DebugInfo{}
  info.name = debug_name
  info.type = type
  info.start_byte = writer.offset
  info.start_bit = writer.bits

  return info
}

// captures the writers position state,
// call after writing the actual information
// to writer
end_debug_info :: proc(info: ^DebugInfo, writer: ^Writer) {
  info.end_byte = writer.offset
  info.end_bit = writer.bits
  append(&writer.debug, info^)
}

// Fixed IEEE-754 floats (Helpers around the writer interface)

write_float64 :: proc(writer: ^Writer, f: f64, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .f64)
  #assert(size_of(f64) == size_of(int))
  write_bits(writer, int(f), size_of(f64))
  end_debug_info(&info, writer)
}

write_float32 :: proc(writer: ^Writer, f: f32, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .f32)
  write_bits(writer, int(f), size_of(f32))
  end_debug_info(&info, writer)
}

write_float16 :: proc(writer: ^Writer, f: f16, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .f16)
  write_bits(writer, int(f), size_of(f32))
  end_debug_info(&info, writer)
}

// Fixed signed interger variants

write_int8 :: proc(writer: ^Writer, i: i8, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .i8)
  write_bits(writer, int(i), size_of(i8))
  end_debug_info(&info, writer)
}

write_int16 :: proc(writer: ^Writer, i: i16, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .i16)
  write_bits(writer, int(i), size_of(i16))
  end_debug_info(&info, writer)
}

write_int32 :: proc(writer: ^Writer, i: i32, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .i32)
  write_bits(writer, int(i), size_of(i32))
  end_debug_info(&info, writer)
}

write_int64 :: proc(writer: ^Writer, i: i64, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .i64)
  write_bits(writer, int(i), size_of(i64))
  end_debug_info(&info, writer)
}

// Fixed unsigned interger variants

write_uint8 :: proc(writer: ^Writer, i: u8, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .u8)
  write_bits(writer, int(i), size_of(u8))
  end_debug_info(&info, writer)
}

write_uint16 :: proc(writer: ^Writer, i: u16, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .u16)
  write_bits(writer, int(i), size_of(u16))
  end_debug_info(&info, writer)
}

write_uint32 :: proc(writer: ^Writer, i: u32, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .u32)
  write_bits(writer, int(i), size_of(u32))
  end_debug_info(&info, writer)
}

write_uint64 :: proc(writer: ^Writer, i: u64, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .u64)
  write_bits(writer, int(i), size_of(u64))
  end_debug_info(&info, writer)
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
write_varint :: proc(writer: ^Writer, i: i128, debug_name: string = "") {
  size, buffer := conv_to_varint(i)
  info := begin_debug_info(writer, debug_name, .varint)
  writer_write_bytes(writer, buffer[:size])
  end_debug_info(&info, writer)
}

write_string :: proc(writer: ^Writer, s: string, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .string)
  write_varint(writer, i128(len(s)))
  writer_write_string(writer, s)
  end_debug_info(&info, writer)
}

write_enum :: proc(writer: ^Writer, e: u8) {
  // note(iyaan): Lottie does not have any enums that requires
  // more than 1 byte of storage.
  write_uint8(writer, u8(e))  
}

write_bool :: proc(writer: ^Writer, b: bool, debug_name: string = "") {
  info := begin_debug_info(writer, debug_name, .bool)
  write_bits(writer, int(b), 1)
  end_debug_info(&info, writer)
}

write_array :: proc(writer: ^Writer, array: []$T) {
  write_varint(writer, i128(len(array)))
  writer_write_array(writer, array)
}

VecInternType :: enum int {
  F32 = 0,
  F16 = 1,
  I8  = 3,
}

check_optimal_intern_size :: proc(vec: [$Y]f64) -> VecInternType {
  // note(iyaan): maybe later we can experiment
  // after analysing of more lottie files on what
  // the most apropriate theshold could be.
  FLOAT_THRESHOLD :: 0.00001
  opt := [Y]VecInternType{}
  for idx in 0..<Y {
    f := vec[idx]
    if f < math.F16_MAX && f > math.F16_MIN {
      opt[idx] = .F16
    }
    i, frac := math.modf_f64(f)
    if frac < FLOAT_THRESHOLD {
      // Can be considered an integer, if the fractional
      // part is so insignificant
      as_int := (int)(i)
      if as_int < int(max(i8)) && as_int > int(min(i8)) {
        opt[idx] = .I8
      }
    }
  }
  
  res := slice.min(opt[:])
  return res
} 

@(test)
check_optimal_intern_size_test :: proc(t: ^testing.T) {
  v1 := [2]f64{51.983, 10.645}
  v2 := [2]f64{51.0000000983, 10.00000000000645}
  v3 := [2]f64{51234.983, 1000501.645}
  v4 := [3]f64{5123.983, 100.645, 10.0}
  v5 := [3]f64{125.0, 100, 127}
  v6 := [4]f64{125.0, 100, 126, 0.0000}
  v7 := [4]f64{125.0, 100, 132, 0.0000}
  testing.expect_value(t, check_optimal_intern_size(v1), VecInternType.F16)
  testing.expect_value(t, check_optimal_intern_size(v2), VecInternType.I8)
  testing.expect_value(t, check_optimal_intern_size(v3), VecInternType.F32)
  testing.expect_value(t, check_optimal_intern_size(v3), VecInternType.F32)
  testing.expect_value(t, check_optimal_intern_size(v5), VecInternType.F16)
  testing.expect_value(t, check_optimal_intern_size(v6), VecInternType.I8)
  testing.expect_value(t, check_optimal_intern_size(v7), VecInternType.F16)
}

write_vector_intern :: proc(writer: ^Writer, vec: [$Y]f64) {
  // writing the type information in 2-bits
  type := check_optimal_intern_size(vec)
  write_bits(writer, int(type), 2)
  switch type {
  case .F16:
    for i in 0..<Y {
      write_float16(writer, f16(vec[i]))
    }
  case .F32:
    for i in 0..<Y {
      write_float32(writer, f32(vec[i]))
    }
  case .I8:
    for i in 0..<Y {
      write_int8(writer, i8(vec[i]))
    }
  }
   
}

write_vector4 :: proc(writer: ^Writer, vec: Vec4, debug_name: string = "") {
  vec4 := cast([4]f64)vec
  info := begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec4)
  end_debug_info(&info, writer)
}

write_vector3 :: proc(writer: ^Writer, vec: Vec3, debug_name: string = "") {
  vec3 := cast([3]f64)vec
  info := begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec3)
  end_debug_info(&info, writer)
}

write_vector2 :: proc(writer: ^Writer, vec: Vec2, debug_name: string = "") {
  vec2 := cast([2]f64)vec
  info := begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec2)
  end_debug_info(&info, writer)
}

// note(iyaan): HexColor will also contain the preliminary # character
// as well
write_hexcolor :: proc(writer: ^Writer, hex_color: HexColor, debug_name: string = "") {
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
  
  info := begin_debug_info(writer, debug_name, .meta)
  writer_write_bytes(writer, rgb[:])
  end_debug_info(&info, writer)
}

write_color3 :: proc(writer: ^Writer, color3: Color3, debug_name: string = "") {
  color3_vec := transmute(Vec3)color3
  info := begin_debug_info(writer, debug_name, .meta)
  write_vector3(writer, color3_vec)
  end_debug_info(&info, writer)
}

write_color4 :: proc(writer: ^Writer, color4: Color4, debug_name: string = "") {
  color4_vec := transmute(Vec4)color4
  info := begin_debug_info(writer, debug_name, .meta)
  write_vector4(writer, color4_vec)
  end_debug_info(&info, writer)
}

write_gradient :: proc(writer: ^Writer, gradient: Gradient, debug_name: string = "") {
  // note(iyaan): offset1, r, g, b, offset2, r, g, b ... alpha_stops
  // Just dump the floats as u8
  info := begin_debug_info(writer, debug_name, .meta)
  for stop in gradient {
    norm255 := u64(math.floor(stop * 255))
    assert(norm255 <= 255, "gradient stop large than 1.0 probably")
    write_uint8(writer, u8(norm255))
  }
  end_debug_info(&info, writer)
}

// A more general transform version supporting for all vector sizes
trans_array_vec_change_size :: proc(vec_array: [][$Y]$T, target_vec_size: int, allocator := context.temp_allocator) -> [][Y]T {
  r_vec_array := make_slice([][Y]T, len(vec_array), allocator)
  for i in 0..<len(vec_array) {
    for j in 0..<Y {
      r_vec_array[i][j] = vec_array[i][j]
    }
  }
  return r_vec_array
}

trans_array_vec3_to_vec2 :: proc($T: typeid, vec3_array: [][3]T, allocator := context.temp_allocator) -> [][2]T {
  vec2_array := make_slice([][2]T, len(vec3_array), allocator)
  for i in 0..<len(vec3_array) {
    vec2_array[i] = vec3_array[i].xy
  }
  return vec2_array
}

trans_array_vec3_intern_type :: proc($T: typeid, comp: []Vec3, allocator := context.temp_allocator) -> [][3]T {
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
trans_array_vec_intern_varint :: proc(vec_slice: [][$T]i128, allocator := context.temp_allocator) -> [][T]LEB128Res {
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
trans_array_delta :: proc(array: $T/[]$E, allocator := context.temp_allocator) -> []LEB128Res
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
trans_array_vec3_delta :: proc(array: []Vec3, allocator := context.allocator) -> [][3]LEB128Res {
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

can_be_vec2 :: proc{
  can_be_vec2_vec3,
  can_be_vec2_generic
}
can_be_vec2_vec3 :: proc(vec: Vec3) -> bool {
  return vec.z == 0 ? true : false
}
can_be_vec2_generic :: proc(vec: [$T]f64) -> bool {
  if T == 2 {
    return true
  }
  else if T > 2 {
    for i in 2..<T {
      if vec[i] != 0 {
        return false
      } 
    }
    return true
  }
  else {
    return false
  }
}

write_bezier :: proc(writer: ^Writer,
                     bezier_shape: BezierShapeValue,
                     debug_name: string = "") {

  info := begin_debug_info(writer, debug_name, .meta) 
  expected_len := len(bezier_shape.i)
  assert(len(bezier_shape.o) == expected_len, "mismatched i and o in bezier shape")
  assert(len(bezier_shape.v) == expected_len, "mismatched i and v in bezier shape")
  
  // note(iyaan): Vec2 optimization can only be applied
  // if all the vector fields can be converted
  // vector2. So it is applied to the whole bezier not
  // just individual fields
  truncate_to_vec2 := true
  for i in 0..<len(bezier_shape.i) {
    if !can_be_vec2(bezier_shape.i[i]) \
    || !can_be_vec2(bezier_shape.o[i]) \
    || !can_be_vec2(bezier_shape.v[i]) {
      truncate_to_vec2 = false
      break
    }
  }

  flags : bit_set[0..<2; u8]
  if truncate_to_vec2 do flags += {1}
  if bezier_shape.c do flags += {0}
  
  // TODO: Why are we wasting 1 whole byte just for 2 flags?
  write_uint8(writer, transmute(u8)flags, "flags")
  
  write_varint(writer, i128(len(bezier_shape.i)), "length")

  i_info := begin_debug_info(writer, "i", .meta) 
  for ivec in bezier_shape.i {
    if truncate_to_vec2 {
      write_vector2(writer, ivec.xy)
    } else {
      write_vector3(writer, ivec)
    }
  }
  end_debug_info(&i_info, writer)
  o_info := begin_debug_info(writer, "o", .meta) 
  for ovec in bezier_shape.o {
    if truncate_to_vec2 {
      write_vector2(writer, ovec.xy)
    } else {
      write_vector3(writer, ovec)
    }
  }
  end_debug_info(&o_info, writer)
  v_info := begin_debug_info(writer, "v", .meta) 
  for vvec in bezier_shape.v {
    if truncate_to_vec2 {
      write_vector2(writer, vvec.xy)
    } else {
      write_vector3(writer, vvec)
    }
  }
  end_debug_info(&v_info, writer)
  end_debug_info(&info, writer)
}

isset :: #force_inline proc "contextless" (value: Bit64, bit: int) -> bool {
  return bit in value
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
  if isset(flags, 2) && isset(flags, 3) {
    // note(iyaan): i is the tangent point at the end of the curve
    // and i is the tangent point at the start of the curve. so they will
    // be o = p0 i = p1
    // is it possible for one of o or i to exist without one or another.
    // then the below function would not be the most effective, but it 
    // also does not make sense to have one. I think that is like an invalid
    // state
    write_easing_curve(writer, vec_keyframe.o, vec_keyframe.i) 
  }
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
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, scalar_keyframe.o, scalar_keyframe.i)
  }
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

write_easing_curve :: proc(writer: ^Writer, p0, p1: PropKeyframeEasing) {
  // note(iyaan): if one point is a scalar then the other point
  // also has to be scalar
  p0_scalar, p0_scalar_ok := p0.(PropKeyframeEasingScalar)
  p1_scalar, p1_scalar_ok := p1.(PropKeyframeEasingScalar)
  p0_vector, p0_vector_ok := p0.(PropKeyframeEasingVec)
  p1_vector, p1_vector_ok := p1.(PropKeyframeEasingVec)
  
  FLAG_COUNT :: 3 // Number of enums must match this bit width
  EasingCurveFlag :: enum {
    Vector, // if not set it is a scalar
    Enum,   // If this flag is set no other values except the enum is set
    Vector2 // Specify the either vector3 or vector2
  }

  EasingCurveFlag_Set :: bit_set[EasingCurveFlag; int]

  if p0_scalar_ok && p1_scalar_ok {
    v1 := Vec2{p0_scalar.x, p0_scalar.y}
    v2 := Vec2{p1_scalar.x, p1_scalar.y}
    easing := cubic_curve_approx(v1, v2)
    flags : EasingCurveFlag_Set
    if easing != .Error {
      flags = {.Enum}
      write_bits(writer, transmute(int)flags, FLAG_COUNT)
      write_enum(writer, u8(easing))
    } else {
      // just write the point information
      flags = {}
      write_bits(writer, transmute(int)flags, FLAG_COUNT)
      write_vector2(writer, v1)
      write_vector2(writer, v2)
    }
  } else if p0_vector_ok && p1_vector_ok {
    flags : EasingCurveFlag_Set
    vec_length := 0
    if p0_vector.x.z == 0 && p1_vector.y.z == 0 && p1_vector.x.z == 0 && p1_vector.y.z == 0 {
      flags += {.Vector2}
      vec_length = 2
    } else {
      flags -= {.Vector2}
      vec_length = 3
    } 
    for i in 0..<vec_length {
      point0 := Vec2{p0_vector.x.x, p0_vector.y.y}
      point1 := Vec2{p1_vector.x.x, p1_vector.y.y}
      easing := cubic_curve_approx(point0, point1)
      if easing != .Error {
        flags += {.Enum}
        write_bits(writer, transmute(int)flags, FLAG_COUNT)
        flags -= {.Enum}
        write_enum(writer, u8(easing))
      } else {
        flags += {.Vector}
        write_bits(writer, transmute(int)flags, FLAG_COUNT)
        flags -= {.Vector}
        write_vector2(writer, point0)
        write_vector2(writer, point1)
      }
    }
  } else {
    assert(false, "mismatched types with the p0 and p1")
  }
}

write_prop_position_keyframe :: proc(writer: ^Writer, position_keyframe: PropPositionKeyframe) {
  flags := transmute(Bit64)position_keyframe._flags
  write_uint8(writer, u8(position_keyframe._flags))
  if isset(flags, 0) do write_varint(writer, i128(position_keyframe.t))
  if isset(flags, 1) do write_bool(writer, bool(position_keyframe.h))
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, position_keyframe.o, position_keyframe.i)
  }
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
  {
    position_single := position.(PropPositionSingle)
    flags := transmute(Bit64)position_single._flags
    write_uint8(writer, u8(transmute(u64)flags))
    vec2 := Vec2{position_single.k.x, position_single.k.y}
    if isset(flags, 0) do write_string(writer, position_single.sid)
    if isset(flags, 2) do write_vector2(writer, vec2)
  }
  case PropPositionAnim:
  {
    position_anim := position.(PropPositionAnim)
    flags := transmute(Bit64)position_anim._flags
    assert(1 in flags, "Animated position does not have the `a` flag set")
    if isset(flags, 0) do write_string(writer, position_anim.sid)
    write_varint(writer, i128(len(position_anim.k)))
    for frame in position_anim.k {
      write_prop_position_keyframe(writer, frame)
    }
  }
  case PropSplitPosition:
  {
    position_split := position.(PropSplitPosition)
    write_bool(writer, position_split.s)
    write_prop_scalar(writer, position_split.x)
    write_prop_scalar(writer, position_split.y)
  }
  }
}

write_prop_bezier_keyframe :: proc(writer: ^Writer, bezier_keyframe: PropBezierKeyframe) {
  flags := transmute(Bit64)bezier_keyframe._flags
  write_uint8(writer, u8(bezier_keyframe._flags))
  if isset(flags, 0) do write_varint(writer, i128(bezier_keyframe.t))
  if isset(flags, 1) do write_bool(writer, bool(bezier_keyframe.h))
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, bezier_keyframe.o, bezier_keyframe.i)
  }
  write_bezier(writer, bezier_keyframe.s)
}

write_prop_bezier_shape :: proc(writer: ^Writer, bezier: PropBezier) {
  switch _ in bezier {
  case PropBezierSingle:
  {
    bezier_single := bezier.(PropBezierSingle)
    write_bool(writer, bezier_single.a)
    write_bezier(writer, bezier_single.k)
  }
  case PropBezierAnim:
  {
    bezier_anim := bezier.(PropBezierAnim)
    write_bool(writer, bezier_anim.a)
    write_varint(writer, i128(len(bezier_anim.k)))
    for frame in bezier_anim.k {
      write_prop_bezier_keyframe(writer, frame)
    }
  }
  }
}

@(deprecated = "use write_easing_curve()")
write_keyframe_easing_handle :: proc(writer: ^Writer, easing: PropKeyframeEasing) {
  // TODO(iyaan): use the cubic bezier correlation optimization to
  // know which type of cubic bezier easing function does the following control
  // points to generate and get the enum
  switch type in easing {
  case PropKeyframeEasingScalar:
    easing_scalar := easing.(PropKeyframeEasingScalar)
    write_float16(writer, f16(easing_scalar.x))
    write_float16(writer, f16(easing_scalar.y))
  case PropKeyframeEasingVec:
    easing_vector := easing.(PropKeyframeEasingVec)
    write_vector3(writer, easing_vector.x)
    write_vector3(writer, easing_vector.y)
  case:
    panic("Unidentifed union type in PropKeyframeEasing")
  }
}

write_transform :: proc(writer: ^Writer, transform: Transform) {
  write_uint8(writer, u8(transform._flags))
  flags := transmute(Bit64)transform._flags
  if isset(flags, 0) do write_prop_position(writer, transform.a)
  if isset(flags, 1) do write_prop_position(writer, transform.p)
  if isset(flags, 2) do write_prop_scalar(writer, transform.r)
  if isset(flags, 3) do write_prop_vector(writer, transform.s)
  if isset(flags, 4) do write_prop_scalar(writer, transform.o)
  if isset(flags, 5) do write_prop_scalar(writer, transform.sk)
  if isset(flags, 6) do write_prop_scalar(writer, transform.sa)
}

// note(iyaan): I want to be able to take the control points
// from https://lottie.github.io/lottie-spec/latest/specs/properties/#easing-handle
// and figure out what kind of curve it could be most related to. I have
// seen that a lot of the sample files have mostly linear or ease-in-out easing functions
// Maybe we can figure out what kind of curve it is and refrain from serializing the actual
// control points each time and just encode some enum.
cubic_bezier :: #force_inline proc(t: f64, p0, p1, p2, p3: f64) -> f64 {
  // Cubic bezier parametric formula
  // P = (1-t)**3 * p0 + t*p1*(3*(1-t)**2) + p2*(3*(1-t)*t**2) + p3*t**3
  return math.pow(1 - t, 3) * p0 \ 
  + t * p1 * (3 * math.pow(1 - t, 2)) \ 
  + p2 * (3 * (1 - t) * math.pow(t, 2)) \ 
  + p3 * math.pow(t, 3)
}

SAMPLING_RATE :: 8
LINEAR_THRESHOLD :: 0.10
cubic_curve_approx :: cubic_curve_approx_simd
cubic_curve_approx_scalar :: proc(p1, p2: Vec2) -> EasingFunction {
  p0 := Vec2{0, 0}
  p3 := Vec2{1, 1}
  
  // Linear check
  y_grad := p2.y - p1.y
  x_grad := p2.x - p1.x
  thresh := math.abs(f64(1.0) - (y_grad / x_grad))

  if x_grad != 0 && thresh < LINEAR_THRESHOLD {
    return .Linear
  }

  t: f64 = 0.0
  sampled_points := [SAMPLING_RATE]Vec2{}
  for i in 0..<SAMPLING_RATE {
    x := cubic_bezier(t, p0.x, p1.x, p2.x, p3.x) 
    y := cubic_bezier(t, p0.y, p1.y, p2.y, p3.y) 
    sampled_points[i] = Vec2{x, y}
    t += 1.0 / SAMPLING_RATE
  }

  // TODO(iyaan): Do this in a more simd friendly way
  least_diff := f64(1_000_000.0)
  most_probable := EasingFunction.Error 
  for i in 0..<len(cubic_easing_functions_tbl) {
    sum := f64(0.0)
    for j := 0; j < SAMPLING_RATE*2; j += 2 {
      vec := Vec2{f64(cubic_easing_functions_tbl[i][j]), f64(cubic_easing_functions_tbl[i][j+1])}
      diff := vec.xy - sampled_points[j/2].xy
      sum += math.abs(diff.x) + math.abs(diff.y)
    }
    if (sum) < least_diff {
      least_diff = sum
      most_probable = EasingFunction(i)
    }
  }
  
  return most_probable
}

cubic_curve_approx_simd :: proc(p1, p2: Vec2) -> EasingFunction {
  p0 := Vec2{0, 0}
  p3 := Vec2{1, 1}
  
  // Linear check
  y_grad := p2.y - p1.y
  x_grad := p2.x - p1.x
  thresh := math.abs(f64(1.0) - (y_grad / x_grad))

  if x_grad != 0 && thresh < LINEAR_THRESHOLD {
    return .Linear
  }

  t: f64 = 0.0
  sx: [SAMPLING_RATE]f32
  sy: [SAMPLING_RATE]f32

  for i in 0..<SAMPLING_RATE {
    sx[i] = f32(cubic_bezier(t, p0.x, p1.x, p2.x, p3.x))
    sy[i] = f32(cubic_bezier(t, p0.y, p1.y, p2.y, p3.y))
    t += 1.0 / SAMPLING_RATE
  }

  sx_simd := simd.from_array(sx)
  sy_simd := simd.from_array(sy)
  
  MAX_MAGNITUDE_THRESH :: 0.25
  for i in 0..<len(cubic_easing_functions_tbl) {
    cubic : simd.f32x16 = simd.from_array(cubic_easing_functions_tbl[i])
    x := simd.swizzle(cubic, 0, 2, 4, 6, 8, 10, 12, 14)
    y := simd.swizzle(cubic, 1, 3, 5, 7, 9, 11, 13, 15)
    diff_x := simd.sub(x, sx_simd)
    diff_y := simd.sub(y, sy_simd)
    diff_x2 := simd.mul(diff_x, diff_x)
    diff_y2 := simd.mul(diff_y, diff_y)
    r1 := simd.add(diff_x2, diff_y2)
    mag := simd.sqrt(r1)
    mag_thresh := #simd[SAMPLING_RATE]f32{}
    mag_thresh = MAX_MAGNITUDE_THRESH
    largest_mag := simd.lanes_gt(mag, mag_thresh)
    is_zero := simd.reduce_or(largest_mag)
    if is_zero == 0 {
      return EasingFunction(i)
    }
  }
  return EasingFunction.Error
}


// note(iyaan): generated using cubic_curve_gen tool in
// tools directory. Parameters for function taken from 
// https://easings.net, add more easig functions here later
EasingFunction :: enum u8 {
  Ease,
  EaseIn,
  EaseOut,
  EaseInOut,
  Linear = 32,
  Error = 255
}
// note(iyaan): Blindly increasing the sampling rate would
// increase computation time.
cubic_easing_functions_tbl := [?][SAMPLING_RATE*2]f32{
  { // ease
    0.0000, 0.0000, 0.0840, 0.0717, 0.1562, 0.1984, 0.2285, 0.3604,
    0.3125, 0.5375, 0.4199, 0.7100, 0.5625, 0.8578, 0.7520, 0.961
  },
  { // ease-in (0.32, 0, 0.67, 0)
    0.0000, 0.0000, 0.1213, 0.0020, 0.2448, 0.0156, 0.3700, 0.0527, 
    0.4963, 0.1250, 0.6229, 0.2441, 0.7495, 0.4219, 0.8754, 0.6699
  },

  { // ease-out
    0.0000, 0.0000, 0.1246, 0.3301, 0.2505, 0.5781, 0.3771, 0.7559, 
    0.5038, 0.8750, 0.6300, 0.9473, 0.7552, 0.9844, 0.8787, 0.9980
  },
  { // ease-in-out
    0.0000, 0.0000, 0.2029, 0.0430, 0.3391, 0.1562, 0.4307, 0.3164, 
    0.5000, 0.5000, 0.5693, 0.6836, 0.6609, 0.8438, 0.7971, 0.9570
  },
}


@(test)
cubic_curve_simd_test :: proc(t: ^testing.T) {
  {
    // Ease-out curve
    p0 := Vec2{0.0,0.919}
    p1 := Vec2{0.535,1.079}
    r0 := cubic_curve_approx_scalar(p0, p1)
    r1 := cubic_curve_approx(p0, p1)
    log.debug(r1)
    testing.expect(t, r0 == r1, "simd and scalar approach gave different results (not .Linear)")
  }

  {
    // Invalid curve
    p0 := Vec2{0.158, 0.919}
    p1 := Vec2{0.0, 0.0}
    r := cubic_curve_approx(p0, p1)
    log.debug(r)
  }

  {
    // Random curve
    p0 := Vec2{0, 0.865}
    p1 := Vec2{1, 0.124}
    r := cubic_curve_approx(p0, p1)
    log.debug(r)
  }
  {
    // Ease-in
    p0 := Vec2{0.32, 0.0}
    p1 := Vec2{0.67, 0.0}
    r := cubic_curve_approx(p0, p1)
    log.debug(r)
  }

}


@(test)
write_bits_test :: proc(t: ^testing.T) {
  writer := Writer{}
  buf := [10]byte{}
  writer.data = buf[:]
  write_bits(&writer, 1, 2)
  write_bits(&writer, 2, 2)
  write_bits(&writer, 3, 2)

  testing.expect_value(t, (buf[0] & 0x03) >> 0, 1)
  testing.expect_value(t, (buf[0] & 0x0c) >> 2, 2)
  testing.expect_value(t, (buf[0] & 0x30) >> 4, 3)

  writer_reset(&writer)
  write_bits(&writer, 2002, 23)
  write_bits(&writer, 10, 4)
  write_bits(&writer, 16, 5)


  testing.expect_value(t, (^u16)(&buf[0])^ & 0x7ff, 2002)
  testing.expect_value(t,  (buf[3] & 0x07) << 1 | (buf[2] & 0x80) >> 7, 10)
  testing.expect_value(t,  (buf[3] & 0x07) << 1 | (buf[2] & 0x80) >> 7, 10)
  testing.expect_value(t, (buf[3] & 0xf8) >> 3, 16)

  testing.expect(t, writer.offset == 4, "next byte offset is 4")
  testing.expect(t, writer.bits == 0, "next bit offset is 0")
}
