package main

import "core:bytes"
import "core:encoding/varint"

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
  write_uint8(b)
}

write_array :: proc(writer: ^TinyLottieWriter, array: []$T) {

}

write_vector4 :: proc(writer: ^TinyLottieWriter, vec: Vec4) {
  write_float32(vec[0])
  write_float32(vec[1])
  write_float32(vec[2])
  write_float32(vec[3])
}

write_vector3 :: proc(writer: ^TinyLottieWriter, vec: Vec3) {
  write_float32(vec[0])
  write_float32(vec[1])
  write_float32(vec[2])
}

write_vector2 :: proc(writer: ^TinyLottieWriter, vec: Vec2) {
  write_float32(vec[0])
  write_float32(vec[1])
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
    } else len(hex_color) == HEX_SHORTHAND_LEN {
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
    }
  }

  assert(hex_color[0] == '#', "Missing hash for hex color")
  hex_color_u8 := transmute([]u8)hex_color
  rgb := conv_str_hexcolor_to_rgb(hex_color_u8[1:])

  writer_write_bytes(writer, rgb[:])
}

write_color3 :: proc(writer: ^TinyLottieWriter, color3: Color3) {
  color3_vec := transmute(Vec3)color3
  write_vec3(color3_vec)
}

write_color4 :: proc(writer: ^TinyLottieWriter, color4: Color4) {
  color4_vec := transmute(Vec4)color4
  write_vec4(color4_vec)
}

write_gradient :: proc(writer: ^TinyLottieWriter, vector: Vec3) {

}

write_bezier :: proc(writer: ^TinyLottieWriter, vector: Vec3) {

}

get_flag :: #force_inline proc(flags: u64, bit: u64) -> u8 {
  return u8(flags & (1 << bit))
}

is_set :: #force_inline proc(flags: u64, bit: u64) -> bool {
  return get_flag(flags, bit) == 1
}

write_prop_vector :: proc(writer: ^TinyLottieWriter, vector: PropVector) {
  if vector_single, ok := vector.(PropVectorSingle); ok {
    if is_set(vector_single.mask, 0) {write_string(writer, vector_single.sid)} 
    if is_set(vector_single.mask, 1) {write_bool(writer, vector_single.a)} 
    if is_set(vector_single.mask, 2) {write_vec3(writer, vector_single.k)} 
  } else if vector_anim, ok := vector.(PropVectorAnim); ok {

  }


}


write_transform :: proc(writer: TinyLottieWriter, transform: Transform) {
  
}
