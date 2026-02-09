package main

import "core:bytes"
import "core:encoding/varint"
import "core:math"

// To keep track of writes to the byte buffer
DebugInfo :: struct {
  start: u64,
  end:   u64,
}

Writer :: struct {
  data: []byte,
  offset: u64,
}

TinyLottieWriter :: struct {
  // TODO(iyaan): Create my own byte buffer. It seems write calls to bytes.Buffer
  // have some complexity behind them by looking at the assembly. It
  // handles the resizing of the underlying dynamic array as well.
  data:             bytes.Buffer,
  debug_info_trace: [dynamic]DebugInfo,
}

writer_write_raw_ptr_with_size :: proc(writer: ^TinyLottieWriter, ptr: rawptr, size: int) {
  written, io_err := bytes.buffer_write_ptr(&writer.data, ptr, size)
  assert(written == size)
}

writer_write_bytes :: proc(writer: ^TinyLottieWriter, buf: []byte) {
  written, io_err := bytes.buffer_write(&writer.data, buf)
  assert(written == len(buf))
}

writer_write_string :: proc(writer: ^TinyLottieWriter, str: string) {
  written, io_err := bytes.buffer_write_string(&writer.data, str)
  assert(written == len(str))
}

// Fixed IEEE-754 floats

write_float64 :: proc(writer: ^TinyLottieWriter, f: f64) {
  buf := transmute([8]byte)f
  writer_write_bytes(writer, buf[:])
}

write_float32 :: proc(writer: ^TinyLottieWriter, f: f32) {
  buf := transmute([4]byte)f
  writer_write_bytes(writer, buf[:])
}

write_float16 :: proc(writer: ^TinyLottieWriter, f: f16) {
  buf := transmute([2]byte)f
  writer_write_bytes(writer, buf[:])
}

write_int8 :: proc(writer: ^TinyLottieWriter, i: i8) {
  buf := transmute([1]byte)i
  writer_write_bytes(writer, buf[:])
}

// Fixed signed interger variants

write_int16 :: proc(writer: ^TinyLottieWriter, i: i16) {
  buf := transmute([2]byte)i
  writer_write_bytes(writer, buf[:])
}

write_int32 :: proc(writer: ^TinyLottieWriter, i: i32) {
  buf := transmute([4]byte)i
  writer_write_bytes(writer, buf[:])
}

write_int64 :: proc(writer: ^TinyLottieWriter, i: i64) {
  buf := transmute([8]byte)i
  writer_write_bytes(writer, buf[:])
}

// Fixed unsigned interger variants

write_uint8 :: proc(writer: ^TinyLottieWriter, i: u8) {
  buf := transmute([1]byte)i
  writer_write_bytes(writer, buf[:])
}

write_uint16 :: proc(writer: ^TinyLottieWriter, i: u16) {
  buf := transmute([2]byte)i
  writer_write_bytes(writer, buf[:])
}

write_uint32 :: proc(writer: ^TinyLottieWriter, i: u32) {
  buf := transmute([4]byte)i
  writer_write_bytes(writer, buf[:])
}

write_uint64 :: proc(writer: ^TinyLottieWriter, i: u64) {
  buf := transmute([8]byte)i
  writer_write_bytes(writer, buf[:])
}

// Variable-byte encoding

encode_zigzag :: proc(x: i128) -> u128 {
  return u128((2 * x) ~ (x >> (size_of(i128) * 8 - 1)));
} 

decode_zigzag :: proc(x: u128) -> i128 {
  return i128((x >> 1) ~ (-(x & 1)));
}

// LEB-128 (zig-zag encoded)
// note(iyaan): Need to make this very optimized. Add SIMD
// support
write_varint :: proc(writer: ^TinyLottieWriter, i: i128) -> [varint.LEB128_MAX_BYTES]byte {
  buffer: [varint.LEB128_MAX_BYTES]byte
  zigzag_int := encode_zigzag(i)
  varint.encode_uleb128(buffer[:], zigzag_int)
  return buffer
}

write_string :: proc(writer: ^TinyLottieWriter, s: string) {
  write_varint(writer, i128(len(s)))
  writer_write_string(writer, s)
}

write_enum :: proc(writer: ^TinyLottieWriter, e: u8) {
  // note(iyaan): Lottie does not have any enums that requires
  // more than 1 byte of storage.
  write_uint8(writer, u8(e))  
}

write_bool :: proc(writer: ^TinyLottieWriter, b: bool) {
  b := transmute(u8)b
  write_uint8(writer, b)
}

write_array :: proc(writer: ^TinyLottieWriter, array: []$T) {
  write_varint(writer, i128(len(array)))
  raw := raw_data(array)
  writer_write_raw_ptr_with_size(writer, raw, len(array))
}

write_vector4 :: proc(writer: ^TinyLottieWriter, vec: Vec4) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
  write_float32(writer, f32(vec[2]))
  write_float32(writer, f32(vec[3]))
}

write_vector3 :: proc(writer: ^TinyLottieWriter, vec: Vec3) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
  write_float32(writer, f32(vec[2]))
}

write_vector2 :: proc(writer: ^TinyLottieWriter, vec: Vec2) {
  write_float32(writer, f32(vec[0]))
  write_float32(writer, f32(vec[1]))
}

// note(iyaan): HexColor will also contain the preliminary # character
// as well
write_hexcolor :: proc(writer: ^TinyLottieWriter, hex_color: HexColor) {
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
      // #00ff00
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
      // #0f0
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

write_color3 :: proc(writer: ^TinyLottieWriter, color3: Color3) {
  color3_vec := transmute(Vec3)color3
  write_vector3(writer, color3_vec)
}

write_color4 :: proc(writer: ^TinyLottieWriter, color4: Color4) {
  color4_vec := transmute(Vec4)color4
  write_vector4(writer, color4_vec)
}

write_gradient :: proc(writer: ^TinyLottieWriter, gradient: Gradient) {
  // note(iyaan): offset1, r, g, b, offset2, r, g, b ... alpha_stops
  // Just dump the floats as u8
  for stop in gradient {
    normalized_255 := u64(math.floor(stop * 255))
    assert(normalized_255 <= 255, "gradeient stop large than 1.0 probably")
    write_uint8(writer, u8(normalized_255))
  }
}

BezierShapeFlags :: enum u8 {
  Closed_Loop,
  As_Float32,  // Encode all vector values as f32
  As_Float16,
  As_Varint,   // Will truncate floating point values
  Use_Vec2,    // Use Vec2 instead of Vec3
}

write_bezier :: proc(writer: ^TinyLottieWriter,
                     bezier_shape: BezierShapeValue,
                     flags: bit_set[BezierShapeFlags; u8]) {
  #assert(size_of(flags) == size_of(u8), "flags should be an u8")
  write_uint8(writer, transmute(u8)flags)
  // note(iyaan): The vector fileds are supposed to have the same length
  expected_len := len(bezier_shape.i)
  assert(len(bezier_shape.o) == expected_len, "mismatched i and o in bezier shape")
  assert(len(bezier_shape.v) == expected_len, "mismatched i and v in bezier shape")


  conv_arr_vec3_intern_type :: proc($T: typeid, comp: []Vec3) -> [][3]T {
    vec_array := make_slice([][3]T, len(comp), context.temp_allocator)

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

  gather_as_vec2_from_vec3_array :: proc($T: typeid, vec3_array: [][3]T) -> [][2]T {
    vec2_array := make_slice([][2]T, len(vec3_array), context.temp_allocator)
    for i in 0..<len(vec3_array) {
      vec2_array[i] = vec3_array[i].xy
    }
    return vec2_array
  }

  if .As_Float16 in flags {
    f16_i_vecs := conv_arr_vec3_intern_type(f16, bezier_shape.i)
    f16_o_vecs := conv_arr_vec3_intern_type(f16, bezier_shape.o)
    f16_v_vecs := conv_arr_vec3_intern_type(f16, bezier_shape.v)

    if .Use_Vec2 in flags {
      f16_i_vec2s := gather_as_vec2_from_vec3_array(f16, f16_i_vecs)
      write_array(writer, f16_i_vec2s)

      f16_o_vec2s := gather_as_vec2_from_vec3_array(f16, f16_o_vecs)
      write_array(writer, f16_i_vec2s)

      f16_v_vec2s := gather_as_vec2_from_vec3_array(f16, f16_v_vecs)
      write_array(writer, f16_i_vec2s)
    } else {
      write_array(writer, f16_i_vecs)
      write_array(writer, f16_o_vecs)
      write_array(writer, f16_v_vecs)
    }
  } else if .As_Varint in flags {

  } else {

  }

  free_all(context.temp_allocator)
}

get_flag :: #force_inline proc(flags: u64, bit: u64) -> u8 {
  return u8(flags & (1 << bit))
}

is_set :: #force_inline proc(flags: u64, bit: u64) -> bool {
  return get_flag(flags, bit) == 1
}

// write_prop_vector :: proc(writer: ^TinyLottieWriter, vector: PropVector) {
//   if vector_single, ok := vector.(PropVectorSingle); ok {
//     if is_set(vector_single.mask, 0) {write_string(writer, vector_single.sid)}
//     if is_set(vector_single.mask, 1) {write_bool(writer, vector_single.a)}
//     if is_set(vector_single.mask, 2) {write_vec3(writer, vector_single.k)}
//   } else if vector_anim, ok := vector.(PropVectorAnim); ok {
//
//   }
// }


write_transform :: proc(writer: TinyLottieWriter, transform: Transform) {
  
}
