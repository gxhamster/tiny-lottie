package main

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

VarintResult :: struct {
  buffer: [varint.LEB128_MAX_BYTES]byte,
  size: int
}
transform_array_vec_intern_varint :: proc(vec_slice: [][$T]i128, allocator := context.temp_allocator) -> [][T]VarintResult {
  #assert(T <= 3, "Why is your vector size un-natural???")
  r_array := make_slice([][T]VarintResult, len(vec_slice), allocator)
  for i in 0..<len(vec_slice) {
    vec := vec_slice[i]
    r_struct := [T]VarintResult{}
    for j in 0..<T {
      size, buf := conv_to_varint(vec[j])
      r_struct[i] = VarintResult{buf, size}
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

get_flag :: #force_inline proc(flags: u64, bit: u64) -> u8 {
  return u8(flags & (1 << bit))
}

is_set :: #force_inline proc(flags: u64, bit: u64) -> bool {
  return get_flag(flags, bit) == 1
}

write_prop_vector :: proc(writer: ^Writer, vector: PropVector) {
  if vector_single, ok := vector.(PropVectorSingle); ok {
    if is_set(vector_single.mask, 0) {write_string(writer, vector_single.sid)}
    if is_set(vector_single.mask, 1) {write_bool(writer, vector_single.a)}
    if is_set(vector_single.mask, 2) {write_vector3(writer, vector_single.k)}
  } else if vector_anim, ok := vector.(PropVectorAnim); ok {

  }
}


write_transform :: proc(writer: Writer, transform: Transform) {
  
}
