package main

import "core:slice"
import "core:math/bits"
import "base:intrinsics"
import "core:encoding/varint"
import "base:runtime"
import "core:math"
import "core:mem"
import "core:testing"
import "core:log"
import "core:fmt"
import "core:simd"

BYTE_BITS :: 8

// To keep track of writes to the byte buffer
DebugInfoType :: enum {
  meta,
  flags,
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
  Enum,
}

DebugInfo :: struct {
  name: string,
  type: DebugInfoType,
  start_byte: int,
  end_byte: int,
  start_bit: uint,
  end_bit: uint,
  end_idx: int,   // Used to idenitfy the range of debug info in case of a meta (inclusive)
}

DEBUG_STACK_SIZE :: 64
Writer :: struct {
  data: []byte,
  offset: int,
  bits: uint,     // This is the bit offset within the current byte specified by `offset` in `data`
  debug: [dynamic]DebugInfo,
  debug_stack: [DEBUG_STACK_SIZE]int,
  debug_stack_top: int,
}

DEFAULT_WRITER_DATA_LEN :: 1 << 15
writer_init :: proc(writer: ^Writer, data_len := DEFAULT_WRITER_DATA_LEN, allocator := context.allocator) {
 writer.data = make([]byte, data_len, allocator)
 writer.debug = make([dynamic]DebugInfo, 0, data_len, allocator)
 writer.offset = 0
 writer.bits = 0
 writer.debug_stack_top = -1
}

writer_reset :: proc(writer: ^Writer) {
  writer.bits = 0
  writer.offset = 0
  writer.debug_stack_top = -1
  mem.zero(&writer.data[0], len(writer.data))
  clear(&writer.debug)
}

calc_bits_from :: proc(start_byte, end_byte: int, start_bit, end_bit: uint) -> int {
  return (end_byte - start_byte) * BYTE_BITS + int(end_bit - start_bit)
}


debug_stack_pop :: proc(writer: ^Writer) -> int {
  top := writer.debug_stack[writer.debug_stack_top]
  if top > -1 do writer.debug_stack_top -= 1
  return top
}

debug_stack_push :: proc(writer: ^Writer, info_idx: int) {
  if writer.debug_stack_top + 1 < DEBUG_STACK_SIZE {
    writer.debug_stack_top += 1
    writer.debug_stack[writer.debug_stack_top] = info_idx
  } else {
    panic("cannot push to debug stack, full")
  }
}

// captures the writers position state,
// call before writing the actual information
// to writer
begin_debug_info :: proc(writer: ^Writer, debug_name: string, type: DebugInfoType) {
  info := DebugInfo{}
  info.name = debug_name
  info.type = type
  info.start_byte = writer.offset
  info.start_bit = writer.bits
  append(&writer.debug, info) 

  debug_stack_push(writer, len(&writer.debug) - 1)
}

// captures the writers position state,
// call after writing the actual information
// to writer
end_debug_info :: proc(writer: ^Writer) {
  info_idx := debug_stack_pop(writer)
  info := &writer.debug[info_idx]
  info.end_byte = writer.offset
  info.end_bit = writer.bits
  info.end_idx = len(writer.debug) - 1
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
EASING_FUNCTION_BITS :: 3
EasingFunction :: enum u8 {
  Ease      = 0,
  EaseIn    = 1,
  EaseOut   = 2,
  EaseInOut = 3,
  Linear    = 4,
  Error     = 5
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
    testing.expect(t, r0 == r1, "simd and scalar approach gave different results (not .Linear)")
  }

  {
    // Invalid curve
    p0 := Vec2{0.158, 0.919}
    p1 := Vec2{0.0, 0.0}
    r := cubic_curve_approx(p0, p1)
  }

  {
    // Random curve
    p0 := Vec2{0, 0.865}
    p1 := Vec2{1, 0.124}
    r := cubic_curve_approx(p0, p1)
  }
  {
    // Ease-in
    p0 := Vec2{0.32, 0.0}
    p1 := Vec2{0.67, 0.0}
    r := cubic_curve_approx(p0, p1)
  }

}


@(test)
write_bits_test :: proc(t: ^testing.T) {
  writer := Writer{}
  buf := make([]byte, 4096, context.temp_allocator)
  writer.data = buf
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

writer_write_string :: proc(writer: ^Writer, str: string) {
  begin_debug_info(writer, "string", .string) 
  for idx in 0..<len(str) {
    write_bits(writer, int(str[idx]), size_of(byte) * BYTE_BITS)
  }
  end_debug_info(writer)
}

writer_write_bytes :: proc(writer: ^Writer, buf: []byte) {
  for b in buf {
    write_bits(writer, int(b), size_of(byte) * BYTE_BITS)
  }
}

write_flags :: proc(writer: ^Writer, flags: Bit64, bits: uint, debug_name: string = "flags") {
  begin_debug_info(writer, debug_name, .flags)
  write_bits(writer, transmute(int)flags, bits)
  end_debug_info(writer)
}

// Fixed IEEE-754 floats (Helpers around the writer interface)

write_float64 :: proc(writer: ^Writer, f: f64, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .f64)
  f1 := f
  interpret := (^u64)(&f1)^
  write_bits(writer, int(interpret), size_of(f64) * BYTE_BITS)
  end_debug_info(writer)
}

write_float32 :: proc(writer: ^Writer, f: f32, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .f32)
  f1 := f
  interpret := (^u32)(&f1)^
  write_bits(writer, int(interpret), size_of(f32) * BYTE_BITS)
  end_debug_info(writer)
}

write_float16 :: proc(writer: ^Writer, f: f16, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .f16)
  f1 := f
  interpret := (^u16)(&f1)^
  write_bits(writer, int(interpret), size_of(f16) * BYTE_BITS)
  end_debug_info(writer)
}

// Fixed signed interger variants

write_int8 :: proc(writer: ^Writer, i: i8, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .i8)
  write_bits(writer, int(i), size_of(i8) * BYTE_BITS)
  end_debug_info(writer)
}

write_int16 :: proc(writer: ^Writer, i: i16, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .i16)
  write_bits(writer, int(i), size_of(i16) * BYTE_BITS)
  end_debug_info(writer)
}

write_int32 :: proc(writer: ^Writer, i: i32, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .i32)
  write_bits(writer, int(i), size_of(i32) * BYTE_BITS)
  end_debug_info(writer)
}

write_int64 :: proc(writer: ^Writer, i: i64, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .i64)
  write_bits(writer, int(i), size_of(i64) * BYTE_BITS)
  end_debug_info(writer)
}

// Fixed unsigned interger variants

write_uint8 :: proc(writer: ^Writer, i: u8, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .u8)
  write_bits(writer, int(i), size_of(u8) * BYTE_BITS)
  end_debug_info(writer)
}

write_uint16 :: proc(writer: ^Writer, i: u16, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .u16)
  write_bits(writer, int(i), size_of(u16) * BYTE_BITS)
  end_debug_info(writer)
}

write_uint32 :: proc(writer: ^Writer, i: u32, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .u32)
  write_bits(writer, int(i), size_of(u32) * BYTE_BITS)
  end_debug_info(writer)
}

write_uint64 :: proc(writer: ^Writer, i: u64, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .u64)
  write_bits(writer, int(i), size_of(u64) * BYTE_BITS)
  end_debug_info(writer)
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
  begin_debug_info(writer, debug_name, .varint)
  writer_write_bytes(writer, buffer[:size])
  end_debug_info(writer)
}

write_string :: proc(writer: ^Writer, s: string, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .meta)
  write_varint(writer, i128(len(s)))
  writer_write_string(writer, s)
  end_debug_info(writer)
}

ENUM_DEFAULT_BITS :: size_of(u8) * BYTE_BITS
write_enum :: proc(writer: ^Writer, e: u8, enum_bits: uint = ENUM_DEFAULT_BITS, debug_name: string = "") {
  // note(iyaan): Lottie does not have any enums that requires
  // more than 1 byte of storage.
  
  begin_debug_info(writer, debug_name, .Enum)
  write_bits(writer, int(e), enum_bits)
  end_debug_info(writer)
}

write_bool :: proc(writer: ^Writer, b: bool, debug_name: string = "") {
  begin_debug_info(writer, debug_name, .bool)
  write_bits(writer, int(b), 1)
  end_debug_info(writer)
}

VecInternType :: enum int {
  F32 = 3,
  F16 = 2,
  // note(iyaan): If a vector value is zero it an I8 would
  // be selected as the internal type. Therefore the 2-bit
  // flags value of the vector would also be zero. This will
  // allow for us to perform the zero default value optimization.
  U8  = 1,
  I8  = 0,
}

check_optimal_intern_size :: proc(vec: [$Y]f64) -> VecInternType {
  // note(iyaan): maybe later we can experiment
  // after analysing of more lottie files on what
  // the most apropriate theshold could be.
  FLOAT_THRESHOLD :: 0.00001
  opt := [Y]VecInternType{}
  for idx in 0..<Y {
    // note(iyaan): Default size is f32
    opt[idx] = .F32

    f := vec[idx]
    f_abs := abs(f)
    if f_abs < math.F16_MAX && f_abs > math.F16_MIN {
      opt[idx] = .F16
    }
    i, frac := math.modf_f64(f)
    if abs(frac) < FLOAT_THRESHOLD {
      // Can be considered an integer, if the fractional
      // part is so insignificant
      as_int := (int)(i)

      if as_int  < int(max(u8)) && as_int > int(min(u8)) {
        opt[idx] = .U8
      }

      if as_int < int(max(i8)) && as_int > int(min(i8)) {
        opt[idx] = .I8
      }
    }
  }
  
  res := slice.max(opt[:])
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
  testing.expect_value(t, check_optimal_intern_size(v5), VecInternType.U8)
  testing.expect_value(t, check_optimal_intern_size(v6), VecInternType.I8)
  testing.expect_value(t, check_optimal_intern_size(v7), VecInternType.U8)
}

VECTOR_INTERN_FLAG_BITS :: 2
write_vector_intern :: proc(writer: ^Writer, vec: [$Y]f64) {
  // writing the type information in 2-bits
  type := check_optimal_intern_size(vec)
  write_flags(writer, transmute(Bit64)int(type), VECTOR_INTERN_FLAG_BITS)
  switch type {
  case .F16:
    for i in 0..<Y {
      write_float16(writer, f16(vec[i]))
    }
  case .F32:
    for i in 0..<Y {
      write_float32(writer, f32(vec[i]))
    }
  case .U8:
    for i in 0..<Y {
      write_uint8(writer, u8(vec[i]))
    }
  case .I8:
    for i in 0..<Y {
      write_int8(writer, i8(vec[i]))
    }
  }
   
}

write_vector4 :: proc(writer: ^Writer, vec: Vec4, debug_name: string = "Vector4") {
  vec4 := cast([4]f64)vec
  begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec4)
  end_debug_info(writer)
}

write_vector3 :: proc(writer: ^Writer, vec: Vec3, debug_name: string = "Vector3") {
  vec3 := cast([3]f64)vec
  begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec3)
  end_debug_info(writer)
}

write_vector2 :: proc(writer: ^Writer, vec: Vec2, debug_name: string = "Vector2") {
  vec2 := cast([2]f64)vec
  begin_debug_info(writer, debug_name, .meta)
  write_vector_intern(writer, vec2)
  end_debug_info(writer)
}

// note(iyaan): HexColor will also contain the preliminary # character
// as well
write_hexcolor :: proc(writer: ^Writer, hex_color: HexColor, debug_name: string = "hexcolor") {
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
  
  begin_debug_info(writer, debug_name, .meta)
  writer_write_bytes(writer, rgb[:])
  end_debug_info(writer)
}

write_color3 :: proc(writer: ^Writer, color3: Color3, debug_name: string = "color3") {
  color3_vec := transmute(Vec3)color3
  begin_debug_info(writer, debug_name, .meta)
  write_vector3(writer, color3_vec)
  end_debug_info(writer)
}

write_color4 :: proc(writer: ^Writer, color4: Color4, debug_name: string = "color4") {
  color4_vec := transmute(Vec4)color4
  begin_debug_info(writer, debug_name, .meta)
  write_vector4(writer, color4_vec)
  end_debug_info(writer)
}

write_gradient :: proc(writer: ^Writer, gradient: Gradient, debug_name: string = "gradient_value") {
  // note(iyaan): offset1, r, g, b, offset2, r, g, b ... alpha_stops
  // Just dump the floats as u8
  begin_debug_info(writer, debug_name, .meta)
  for stop in gradient {
    norm255 := u64(math.floor(stop * 255))
    assert(norm255 <= 255, "gradient stop large than 1.0 probably")
    write_uint8(writer, u8(norm255))
  }
  end_debug_info(writer)
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

write_bezier :: proc(writer: ^Writer, bezier_shape: BezierShapeValue, debug_name := "bezier_value") {

  begin_debug_info(writer, debug_name, .meta) 
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

  BEZIER_FLAG_BITS :: 2
  flags : Bit64
  if truncate_to_vec2 do flags += {1}
  if bezier_shape.c do flags += {0}
  
  write_flags(writer, flags, BEZIER_FLAG_BITS, "flags")
  
  write_varint(writer, i128(len(bezier_shape.i)), "length")

  begin_debug_info(writer, "i", .meta) 
  for ivec in bezier_shape.i {
    if truncate_to_vec2 {
      write_vector2(writer, ivec.xy)
    } else {
      write_vector3(writer, ivec)
    }
  }
  end_debug_info(writer)
  begin_debug_info(writer, "o", .meta) 
  for ovec in bezier_shape.o {
    if truncate_to_vec2 {
      write_vector2(writer, ovec.xy)
    } else {
      write_vector3(writer, ovec)
    }
  }
  end_debug_info(writer)
  begin_debug_info(writer, "v", .meta) 
  for vvec in bezier_shape.v {
    if truncate_to_vec2 {
      write_vector2(writer, vvec.xy)
    } else {
      write_vector3(writer, vvec)
    }
  }
  end_debug_info(writer)
  end_debug_info(writer)
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
  vector_keyframe_offset_tbl :: [?]StructInfo{
    { offset_of(PropVectorKeyframe, t),  size_of(vec_keyframe.t) },
    { offset_of(PropVectorKeyframe, h),  size_of(vec_keyframe.h) },
    { offset_of(PropVectorKeyframe, i),  size_of(vec_keyframe.i) },
    { offset_of(PropVectorKeyframe, o),  size_of(vec_keyframe.o) },
    { offset_of(PropVectorKeyframe, s),  size_of(vec_keyframe.s) },
  }

  #assert(PROP_VECTOR_KEYFRAME_FIELDS == len(vector_keyframe_offset_tbl), "Not equal")
  temp_struct := vec_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, vector_keyframe_offset_tbl)

  begin_debug_info(writer, "vector_keyframe", .meta)
  write_flags(writer, flags, PROP_VECTOR_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(vec_keyframe.t), "t")
  if isset(flags, 1) do write_varint(writer, i128(vec_keyframe.h), "h")
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
  write_vector3(writer, vec_keyframe.s, "s")
  end_debug_info(writer)
}

write_prop_vector :: proc(writer: ^Writer, vector: PropVector, debug_name := "prop_vector") {
  switch type in vector {
  case PropVectorSingle:
  {
    vector_single := vector.(PropVectorSingle)
    flags := transmute(Bit64)vector_single._flags
    vector_single_offset_tbl := [?]StructInfo{
      { offset_of(PropVectorSingle, sid), size_of(vector_single.sid) },
      { offset_of(PropVectorSingle, a),   size_of(vector_single.a) },
      { offset_of(PropVectorSingle, k),   size_of(vector_single.k) },
    }

    #assert(PROP_VECTOR_SINGLE_FIELDS == len(vector_single_offset_tbl), "Not equal")
    temp_struct := vector_single
    remove_zero_default_value_optim(&flags, &temp_struct, vector_single_offset_tbl)

    truncate_to_vec2 := false
    if truncate_to_vec2 = can_be_vec2(vector_single.k); truncate_to_vec2 {
      // note(iyaan): Do not overwrite the field mask
      // portion
      flags += {PROP_VECTOR_SINGLE_FIELDS}
    }

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_VECTOR_SINGLE_FIELDS)
    
    if isset(flags, 0) do write_string(writer, vector_single.sid, "sid")
    if isset(flags, 1) do write_bool(writer, vector_single.a, "a")
    if isset(flags, 2) {
      if truncate_to_vec2 {
        write_vector2(writer, vector_single.k.xy, "k")
      } else {
        write_vector3(writer, vector_single.k, "k")
      }
    }
    end_debug_info(writer)
  }
  case PropVectorAnim:
  {
    vector_anim := vector.(PropVectorAnim)
    flags := transmute(Bit64)vector_anim._flags
    vector_anim_offset_tbl := [?]StructInfo{
      { offset_of(PropVectorAnim, sid), size_of(vector_anim.sid) },
      { offset_of(PropVectorAnim, a),   size_of(vector_anim.a) },
      { offset_of(PropVectorAnim, k),   size_of(vector_anim.k) },
    }

    #assert(PROP_VECTOR_ANIM_FIELDS == len(vector_anim_offset_tbl), "Not equal")
    temp_struct := vector_anim
    remove_zero_default_value_optim(&flags, &temp_struct, vector_anim_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_VECTOR_ANIM_FIELDS)
    if isset(flags, 0) do write_string(writer, vector_anim.sid, "sid")
    if isset(flags, 1) do write_bool(writer, vector_anim.a, "a")

    if isset(flags, 2) {
      // write the keyframes as an array
      write_varint(writer, i128(len(vector_anim.k)))
      for frame in vector_anim.k {
        write_prop_vector_keyframe(writer, frame)
      }
    }
    end_debug_info(writer)
  }
  }
}

write_prop_scalar_keyframe :: proc(writer: ^Writer, scalar_keyframe: PropScalarKeyframe) {
  flags := transmute(Bit64)scalar_keyframe._flags
  scalar_keyframe_offset_tbl := [?]StructInfo{
    { offset_of(PropScalarKeyframe, t), size_of(scalar_keyframe.t) },
    { offset_of(PropScalarKeyframe, h), size_of(scalar_keyframe.h) },
    { offset_of(PropScalarKeyframe, i), size_of(scalar_keyframe.i) },
    { offset_of(PropScalarKeyframe, o), size_of(scalar_keyframe.o) },
    { offset_of(PropScalarKeyframe, s), size_of(scalar_keyframe.s) },
  }

  #assert(PROP_SCALAR_KEYFRAME_FIELDS == len(scalar_keyframe_offset_tbl), "Not equal")
  temp_struct := scalar_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, scalar_keyframe_offset_tbl)

  begin_debug_info(writer, "scalar_keyframe", .meta)
  write_flags(writer, flags, PROP_SCALAR_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(scalar_keyframe.t), "t")
  if isset(flags, 1) do write_varint(writer, i128(scalar_keyframe.h), "h")
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, scalar_keyframe.o, scalar_keyframe.i)
  }
  if isset(flags, 3) do write_scalar_value(writer, scalar_keyframe.s, "s")
  end_debug_info(writer)
}

write_scalar_value :: proc(writer: ^Writer, scalar_number: f64, debug_name: string = "scalar_value") {
  begin_debug_info(writer, debug_name, .meta)
  scalars := [1]f64{scalar_number}
  write_vector_intern(writer, scalars) 
  end_debug_info(writer)
}

write_prop_scalar :: proc(writer: ^Writer, scalar: PropScalar, debug_name := "prop_scalar") {
  switch type in scalar {
  case PropScalarSingle:
  {
    scalar_single := scalar.(PropScalarSingle)
    flags := transmute(Bit64)scalar_single._flags
    scalar_single_offset_tbl := [?]StructInfo{
      { offset_of(PropScalarSingle, sid),  size_of(scalar_single.sid) },
      { offset_of(PropScalarSingle, a),    size_of(scalar_single.a) },
      { offset_of(PropScalarSingle, k),    size_of(scalar_single.k) },
    }

    #assert(PROP_SCALAR_SINGLE_FIELDS == len(scalar_single_offset_tbl), "Not equal")
    temp_struct := scalar_single
    remove_zero_default_value_optim(&flags, &temp_struct, scalar_single_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_SCALAR_SINGLE_FIELDS)
    if isset(flags, 0) do write_string(writer, scalar_single.sid, "sid")
    if isset(flags, 1) do write_bool(writer, scalar_single.a, "a")
    if isset(flags, 2) do write_scalar_value(writer, scalar_single.k, "k")
    end_debug_info(writer)
  }
  case PropScalarAnim:
  {
    scalar_anim := scalar.(PropScalarAnim)
    flags := transmute(Bit64)scalar_anim._flags
    scalar_anim_offset_tbl := [?]StructInfo{
      { offset_of(PropScalarAnim, sid),  size_of(scalar_anim.sid) },
      { offset_of(PropScalarAnim, a),    size_of(scalar_anim.a) },
      { offset_of(PropScalarAnim, k),    size_of(scalar_anim.k) },
    }

    #assert(PROP_SCALAR_ANIM_FIELDS == len(scalar_anim_offset_tbl), "Not equal")
    temp_struct := scalar_anim
    remove_zero_default_value_optim(&flags, &temp_struct, scalar_anim_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_SCALAR_ANIM_FIELDS)
    if isset(flags, 0) do write_string(writer, scalar_anim.sid, "sid")
    if isset(flags, 1) do write_bool(writer, scalar_anim.a, "a")

    write_varint(writer, i128(len(scalar_anim.k)))
    for frame in scalar_anim.k {
      write_prop_scalar_keyframe(writer, frame)
    }
    end_debug_info(writer)
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
  
  FLAG_COUNT :: 3 // Number of enums must match this bit width. Enough
                  // to hold the EasingCurveFlag_Set
  EasingCurveFlag :: enum {
    Vector, // if not set it is a scalar
    Enum,   // If this flag is set no other values except the enum is set
    Vector2 // Specify the either vector3 or vector2
  }

  EasingCurveFlag_Set :: bit_set[EasingCurveFlag; int]
  begin_debug_info(writer, "easing", .meta)
  if p0_scalar_ok && p1_scalar_ok {
    v1 := Vec2{p0_scalar.x, p0_scalar.y}
    v2 := Vec2{p1_scalar.x, p1_scalar.y}
    easing := cubic_curve_approx(v1, v2)
    flags : EasingCurveFlag_Set
    if easing != .Error {
      flags = {.Enum}
      write_flags(writer, transmute(Bit64)flags, FLAG_COUNT)
      write_enum(writer, u8(easing), EASING_FUNCTION_BITS)
    } else {
      // just write the point information
      flags = {}
      write_flags(writer, transmute(Bit64)flags, FLAG_COUNT)
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
        write_flags(writer, transmute(Bit64)flags, FLAG_COUNT)
        flags -= {.Enum}
        write_enum(writer, u8(easing), EASING_FUNCTION_BITS)
      } else {
        flags += {.Vector}
        write_flags(writer, transmute(Bit64)flags, FLAG_COUNT)
        flags -= {.Vector}
        write_vector2(writer, point0)
        write_vector2(writer, point1)
      }
    }
  } else {
    assert(false, "mismatched types with the p0 and p1")
  }

  end_debug_info(writer)
}

StructInfo :: struct {
  offset: uintptr,
  size: int
}

remove_zero_default_value_optim :: proc(flags: ^Bit64, struct_ptr: rawptr, table: [$T]StructInfo) {
  // note(iyaan): The length of the table and the no. of fields in the struct (without _flags)
  // needs to match so that we can flip the correct the bit in the flags
  for field, idx in table {
    offset := rawptr(uintptr(struct_ptr) + field.offset)
    is_zero := runtime.memory_compare_zero(offset, field.size) == 0
    if is_zero {
      flags^ -= {idx}
    }
  }
}

write_prop_position_keyframe :: proc(writer: ^Writer, position_keyframe: PropPositionKeyframe) {
  flags := transmute(Bit64)position_keyframe._flags
  position_keyframe_offset_tbl :: [?]StructInfo{
    { offset_of(PropPositionKeyframe, t),  size_of(position_keyframe.t) },
    { offset_of(PropPositionKeyframe, h),  size_of(position_keyframe.h) },
    { offset_of(PropPositionKeyframe, i),  size_of(position_keyframe.i) },
    { offset_of(PropPositionKeyframe, o),  size_of(position_keyframe.o) },
    { offset_of(PropPositionKeyframe, s),  size_of(position_keyframe.s) },
    { offset_of(PropPositionKeyframe, ti), size_of(position_keyframe.ti) },
    { offset_of(PropPositionKeyframe, to), size_of(position_keyframe.to) },
  }

  #assert(PROP_POSITION_KEYFRAME_FIELDS == len(position_keyframe_offset_tbl), "Not equal")
  temp_struct := position_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, position_keyframe_offset_tbl)


  begin_debug_info(writer, "position_keyframe", .meta)
  write_flags(writer, flags, PROP_POSITION_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(position_keyframe.t), "t")
  if isset(flags, 1) do write_bool(writer, bool(position_keyframe.h), "h")
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, position_keyframe.o, position_keyframe.i)
  }
  // TODO(iyaan): In the base lottie spec there are no 3d dimensional
  // animations therefore positions are always 2d vectors. Need to change
  // later
  if isset(flags, 4) do write_vector2(writer, position_keyframe.s.xy, "s")
  if isset(flags, 5) do write_vector2(writer, position_keyframe.ti.xy, "ti")
  if isset(flags, 6) do write_vector2(writer, position_keyframe.to.xy, "to")
  end_debug_info(writer)
}

write_prop_position :: proc(writer: ^Writer, position: PropPosition, debug_name := "prop_position") {
  switch type in position {
  case PropPositionSingle:
  {
    position_single := position.(PropPositionSingle)
    flags := transmute(Bit64)position_single._flags
    position_single_offset_tbl := [?]StructInfo{
      { offset_of(PropPositionSingle, sid), size_of(position_single.sid) },
      { offset_of(PropPositionSingle, a),   size_of(position_single.a) },
      { offset_of(PropPositionSingle, k),   size_of(position_single.k) },
    }

    #assert(PROP_VECTOR_SINGLE_FIELDS == len(position_single_offset_tbl), "Not equal")
    temp_struct := position_single
    remove_zero_default_value_optim(&flags, &temp_struct, position_single_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_VECTOR_SINGLE_FIELDS)
    vec2 := Vec2{position_single.k.x, position_single.k.y}
    if isset(flags, 0) do write_string(writer, position_single.sid, "sid")
    if isset(flags, 2) do write_vector2(writer, vec2, "k")
    end_debug_info(writer)
  }
  case PropPositionAnim:
  {
    position_anim := position.(PropPositionAnim)
    flags := transmute(Bit64)position_anim._flags
    position_anim_offset_tbl := [?]StructInfo{
      { offset_of(PropPositionAnim, sid), size_of(position_anim.sid) },
      { offset_of(PropPositionAnim, a),   size_of(position_anim.a) },
      // note(iyaan): The structure of a slice is [ ptr (8) | len (8) ]
      // I am targetting the len field in the slice so that I can see if 
      // it is zero. Because the ptr is most likely never zero.
      { offset_of(PropPositionAnim, k) + size_of(rawptr), size_of(int) },
    }

    #assert(PROP_VECTOR_ANIM_FIELDS == len(position_anim_offset_tbl), "Not equal")
    temp_struct := position_anim
    remove_zero_default_value_optim(&flags, &temp_struct, position_anim_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_VECTOR_ANIM_FIELDS)
    if isset(flags, 0) do write_string(writer, position_anim.sid, "sid")
    write_varint(writer, i128(len(position_anim.k)))
    for frame in position_anim.k {
      write_prop_position_keyframe(writer, frame)
    }
    end_debug_info(writer)
  }
  case PropSplitPosition:
  {
    position_split := position.(PropSplitPosition)
    flags := transmute(Bit64)position_split._flags

    split_position_offset_tbl := [?]StructInfo{
      { offset_of(PropSplitPosition, s), size_of(position_split.s) },
      // note(iyaan): tag of a union in Odin are placed at the end after the variants
      // of the data. Size of a union is the size of the largest variant plus tag which
      // needs to be aligned 8 bytes (usually u64)
      { offset_of(PropSplitPosition, x), size_of(position_split.x) - SCALAR_TAG_SIZE },
      { offset_of(PropSplitPosition, y), size_of(position_split.y) - SCALAR_TAG_SIZE },
    }

    #assert(PROP_SPLIT_POSITION_FIELDS == len(split_position_offset_tbl), "Not equal")
    temp_struct := position_split
    remove_zero_default_value_optim(&flags, &temp_struct, split_position_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_SPLIT_POSITION_FIELDS)
    write_bool(writer, position_split.s, "s")
    write_prop_scalar(writer, position_split.x, "x")
    write_prop_scalar(writer, position_split.y, "y")
    end_debug_info(writer)
  }
  }
}

write_prop_bezier_keyframe :: proc(writer: ^Writer, bezier_keyframe: PropBezierKeyframe) {
  flags := transmute(Bit64)bezier_keyframe._flags
  bezier_keyframe_offset_tbl := [?]StructInfo{
    { offset_of(PropBezierKeyframe, t), size_of(bezier_keyframe.t) },
    { offset_of(PropBezierKeyframe, h), size_of(bezier_keyframe.h) },
    { offset_of(PropBezierKeyframe, i), size_of(bezier_keyframe.i) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(PropBezierKeyframe, o), size_of(bezier_keyframe.o) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(PropBezierKeyframe, s), size_of(bezier_keyframe.s) },
  }

  #assert(PROP_BEZIER_KEYFRAME_FIELDS == len(bezier_keyframe_offset_tbl), "Not equal")
  temp_struct := bezier_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, bezier_keyframe_offset_tbl)

  begin_debug_info(writer, "Bezier_Keyframe", .meta)
  write_flags(writer, flags, PROP_BEZIER_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(bezier_keyframe.t), "t")
  if isset(flags, 1) do write_bool(writer, bool(bezier_keyframe.h), "h")
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, bezier_keyframe.o, bezier_keyframe.i)
  }
  begin_debug_info(writer, "s", .meta)
  write_varint(writer, i128(len(bezier_keyframe.s)), "len")
  for bezier in bezier_keyframe.s {
    write_bezier(writer, bezier)
  }

  end_debug_info(writer)
  end_debug_info(writer)  
}

write_prop_bezier_shape :: proc(writer: ^Writer, bezier: PropBezier, debug_name := "PropBezier") {
  switch _ in bezier {
  case PropBezierSingle:
  {
    bezier_single := bezier.(PropBezierSingle)
    flags := transmute(Bit64)bezier_single._flags
    bezier_single_offset_tbl := [?]StructInfo{
      { offset_of(PropBezierSingle, a), size_of(bezier_single.a) },
      { offset_of(PropBezierSingle, k), size_of(bezier_single.k) },
    }

    #assert(PROP_BEZIER_SINGLE_FIELDS == len(bezier_single_offset_tbl), "Not equal")
    temp_struct := bezier_single
    remove_zero_default_value_optim(&flags, &temp_struct, bezier_single_offset_tbl)
    
    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_BEZIER_SINGLE_FIELDS)
    write_bool(writer, bezier_single.a, "a")
    write_bezier(writer, bezier_single.k, "k")
    end_debug_info(writer)
  }
  case PropBezierAnim:
  {
    bezier_anim := bezier.(PropBezierAnim)
    flags := transmute(Bit64)bezier_anim._flags
    bezier_anim_offset_tbl := [?]StructInfo{
      { offset_of(PropBezierAnim, a), size_of(bezier_anim.a) },
      { offset_of(PropBezierAnim, k) + size_of(rawptr), size_of(int) },
    }
    #assert(PROP_BEZIER_ANIM_FIELDS == len(bezier_anim_offset_tbl), "Not equal")
    temp_struct := bezier_anim
    remove_zero_default_value_optim(&flags, &temp_struct, bezier_anim_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_BEZIER_ANIM_FIELDS)
    write_bool(writer, bezier_anim.a, "a")
    write_varint(writer, i128(len(bezier_anim.k)))
    for frame in bezier_anim.k {
      write_prop_bezier_keyframe(writer, frame)
    }
    end_debug_info(writer)
  }
  }
}

write_prop_color_keyframe :: proc(writer: ^Writer, color_keyframe: PropColorKeyframe) {
  flags := transmute(Bit64)color_keyframe._flags
  color_keyframe_offset_tbl := [?]StructInfo{
    { offset_of(PropColorKeyframe, t), size_of(color_keyframe.t) },
    { offset_of(PropColorKeyframe, h), size_of(color_keyframe.h) },
    { offset_of(PropColorKeyframe, i), size_of(color_keyframe.i) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(PropColorKeyframe, o), size_of(color_keyframe.o) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(PropColorKeyframe, s), size_of(color_keyframe.s) },
  }
  #assert(PROP_COLOR_KEYFRAME_FIELDS == len(color_keyframe_offset_tbl), "Not equal")
  temp_struct := color_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, color_keyframe_offset_tbl)

  write_flags(writer, flags, PROP_COLOR_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(color_keyframe.t), "t")
  if isset(flags, 1) do write_bool(writer, bool(color_keyframe.h), "h")
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, color_keyframe.o, color_keyframe.i)
  }
  if isset(flags, 4) do write_color4(writer, color_keyframe.s, "s")
}

write_prop_color :: proc(writer: ^Writer, color: PropColor, debug_name := "PropColor") {
  switch _ in color {
  case PropColorSingle:
  {
    color_single := color.(PropColorSingle)
    flags := transmute(Bit64)color_single._flags
    color_single_offset_tbl := [?]StructInfo{
      { offset_of(PropColorSingle, sid), size_of(color_single.sid) },
      { offset_of(PropColorSingle, a), size_of(color_single.a) },
      { offset_of(PropColorSingle, k), size_of(color_single.k) },
    }

    #assert(PROP_COLOR_SINGLE_FIELDS == len(color_single_offset_tbl), "Not equal")
    temp_struct := color_single
    remove_zero_default_value_optim(&flags, &temp_struct, color_single_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_COLOR_SINGLE_FIELDS)
    
    if isset(flags, 0) do write_string(writer, color_single.sid)
    if isset(flags, 1) do write_bool(writer, color_single.a)
    if isset(flags, 2) do write_color4(writer, color_single.k)
    end_debug_info(writer)
  }
  case PropColorAnim:
  {
    color_anim := color.(PropColorAnim)
    flags := transmute(Bit64)color_anim._flags
    color_anim_offset_tbl := [?]StructInfo{
      { offset_of(PropColorAnim, sid), size_of(color_anim.sid) },
      { offset_of(PropColorAnim, a), size_of(color_anim.a) },
      { offset_of(PropColorAnim, k) + size_of(rawptr), size_of(int) },
    }

    #assert(PROP_COLOR_ANIM_FIELDS == len(color_anim_offset_tbl), "Not equal")
    temp_struct := color_anim
    remove_zero_default_value_optim(&flags, &temp_struct, color_anim_offset_tbl)

    begin_debug_info(writer, debug_name, .meta)
    write_flags(writer, flags, PROP_COLOR_ANIM_FIELDS)
    if isset(flags, 0) do write_string(writer, color_anim.sid)
    if isset(flags, 1) do write_bool(writer, color_anim.a)

    if isset(flags, 2) {
      write_varint(writer, i128(len(color_anim.k)))
      for frame in color_anim.k {
        write_prop_color_keyframe(writer, frame)
      }
    }
    end_debug_info(writer)
  }
  }
}

write_prop_gradient_keyframe :: proc(writer: ^Writer, gradient_keyframe: GradientKeyframe) {
  flags := transmute(Bit64)gradient_keyframe._flags
  gradient_keyframe_offset_tbl := [?]StructInfo{
    { offset_of(GradientKeyframe, t), size_of(gradient_keyframe.t) },
    { offset_of(GradientKeyframe, h), size_of(gradient_keyframe.h) },
    { offset_of(GradientKeyframe, i), size_of(gradient_keyframe.i) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(GradientKeyframe, o), size_of(gradient_keyframe.o) - KEYFRAME_EASING_UNION_TAG_SIZE },
    { offset_of(GradientKeyframe, s), size_of(gradient_keyframe.s) },
  }
  #assert(PROP_GRADIENT_KEYFRAME_FIELDS == len(gradient_keyframe_offset_tbl), "Not equal")
  temp_struct := gradient_keyframe
  remove_zero_default_value_optim(&flags, &temp_struct, gradient_keyframe_offset_tbl)

  begin_debug_info(writer, "GRADIENT_KEYFAME", .meta)

  write_flags(writer, flags, PROP_GRADIENT_KEYFRAME_FIELDS)
  if isset(flags, 0) do write_varint(writer, i128(gradient_keyframe.t), "t")
  if isset(flags, 1) do write_bool(writer, bool(gradient_keyframe.h), "h")
  if isset(flags, 2) && isset(flags, 3) {
    write_easing_curve(writer, gradient_keyframe.o, gradient_keyframe.i)
  }
  if isset(flags, 4) do write_gradient(writer, gradient_keyframe.s, "s")

  end_debug_info(writer)
}

write_prop_gradient :: proc(writer: ^Writer, gradient: PropGradient, debug_name := "PropGradient") {
  write_varint(writer, i128(gradient.p))
  switch _ in gradient.k {
  case GradientStopSingle:
  {
    grad_single := gradient.k.(GradientStopSingle)
    begin_debug_info(writer, debug_name, .meta)
    write_bool(writer, grad_single.a, "a")
    write_gradient(writer, grad_single.k, "k")
    end_debug_info(writer)
  }
  case GradientStopAnim:
  {
    grad_anim := gradient.k.(GradientStopAnim)
    begin_debug_info(writer, debug_name, .meta)
    write_bool(writer, grad_anim.a, "a")
    write_varint(writer, i128(len(grad_anim.k)))
    for frame in grad_anim.k {
      write_prop_gradient_keyframe(writer, frame)
    }
    end_debug_info(writer)
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


write_transform :: proc(writer: ^Writer, transform: Transform, debug_name := "transform") {
  flags := transmute(Bit64)transform._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, TRANSFORM_FIELDS)
  if isset(flags, 0) do write_prop_position(writer, transform.a, "a")
  if isset(flags, 1) do write_prop_position(writer, transform.p, "p")
  if isset(flags, 2) do write_prop_scalar(writer, transform.r, "r")
  if isset(flags, 3) do write_prop_vector(writer, transform.s, "s")
  if isset(flags, 4) do write_prop_scalar(writer, transform.o, "o")
  if isset(flags, 5) do write_prop_scalar(writer, transform.sk, "sk")
  if isset(flags, 6) do write_prop_scalar(writer, transform.sa, "sa")
  end_debug_info(writer)
}


graphic_elem_type_conv_tbl := [34]i8{
    -1, -1, -1, -1, -1, -1, -1,  2,
    -1, -1, -1,  0,  1, -1, -1,  7,
    -1, -1, -1,  4,  3,  5, -1, -1,
    -1, -1, -1, 10, -1, -1, -1,  6,
     9,  8
}

conv_graphic_elem_type_to_enum :: proc(str: string) -> GraphicElemType {
  if len(str) == 2 {
    OFFSET :: 99
    MAX :: 17

    b0 := (str[0] - OFFSET) <= MAX ? (str[0] - OFFSET) : 0
    b1 := (str[1] - OFFSET) <= MAX ? (str[1] - OFFSET) : 0
    hs := b0 + b1
    state := graphic_elem_type_conv_tbl[hs]
    return GraphicElemType(state)
  } else {
    return .Error
  }
}

write_ellipse :: proc(writer: ^Writer, ellipse: Ellipse, debug_name := "ellipse") {
  flags := transmute(Bit64)ellipse._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, PATH_FIELDS)
  if isset(flags, 0) do write_string(writer, ellipse.nm, "nm")
  if isset(flags, 1) do write_bool(writer, ellipse.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(ellipse.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_enum(writer, u8(ellipse.d), SHAPE_DIR_ENUM_BITS, "d")
  if isset(flags, 4) do write_prop_position(writer, ellipse.p, "p")
  if isset(flags, 5) do write_prop_vector(writer, ellipse.s, "s")
  end_debug_info(writer)
}

write_rectangle :: proc(writer: ^Writer, rect: Rectangle, debug_name := "rectangle") {
  flags := transmute(Bit64)rect._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, PATH_FIELDS)
  if isset(flags, 0) do write_string(writer, rect.nm, "nm")
  if isset(flags, 1) do write_bool(writer, rect.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(rect.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_enum(writer, u8(rect.d), SHAPE_DIR_ENUM_BITS, "d")
  if isset(flags, 4) do write_prop_position(writer, rect.p, "p")
  if isset(flags, 5) do write_prop_vector(writer, rect.s, "s")
  if isset(flags, 6) do write_prop_scalar(writer, rect.r, "r")
  end_debug_info(writer)
}

write_path :: proc(writer: ^Writer, path: Path, debug_name := "path") {
  flags := transmute(Bit64)path._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, PATH_FIELDS)
  if isset(flags, 0) do write_string(writer, path.nm, "nm")
  if isset(flags, 1) do write_bool(writer, path.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(path.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_enum(writer, u8(path.d), SHAPE_DIR_ENUM_BITS, "d")
  if isset(flags, 4) do write_prop_bezier_shape(writer, path.ks, "ks")
  end_debug_info(writer)
}

write_polystar :: proc(writer: ^Writer, star: Polystar, debug_name := "polystar") {
  flags := transmute(Bit64)star._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, PATH_FIELDS)
  if isset(flags, 0) do write_string(writer, star.nm, "nm")
  if isset(flags, 1) do write_bool(writer, star.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(star.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3)  do write_enum(writer, u8(star.d), SHAPE_DIR_ENUM_BITS, "d")
  if isset(flags, 4)  do write_prop_position(writer, star.p, "p")
  if isset(flags, 5)  do write_prop_scalar(writer, star.or, "or")
  if isset(flags, 6)  do write_prop_scalar(writer, star.os, "os")
  if isset(flags, 7)  do write_prop_scalar(writer, star.os, "r")
  if isset(flags, 8)  do write_prop_scalar(writer, star.pt, "pt")
  if isset(flags, 9)  do write_enum(writer, u8(star.sy), STAR_TYPE_BITS, "sy")
  if isset(flags, 10) do write_prop_scalar(writer, star.ir, "ir")
  if isset(flags, 11) do write_prop_scalar(writer, star.is, "is")

  end_debug_info(writer)
}

write_group :: proc(writer: ^Writer, group: Group, debug_name := "group") {
  flags := transmute(Bit64)group._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, GROUP_FIELDS)
  if isset(flags, 0) do write_string(writer, group.nm, "nm")
  if isset(flags, 1) do write_bool(writer, group.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(group.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")
  if isset(flags, 3) do write_varint(writer, i128(group.np), "np")

  // Group can store any GraphicElement
  begin_debug_info(writer, "it", .meta)
  write_varint(writer, i128(len(group.it)))
  for graphic_elem in group.it {
    write_graphic_elem(writer, graphic_elem)
  }

  end_debug_info(writer)
  end_debug_info(writer)
}

write_graphic_elem :: proc(writer: ^Writer, graphic_elem: GraphicElement, debug_name := "") {
  switch _ in graphic_elem {
  case Ellipse:        write_ellipse(writer, graphic_elem.(Ellipse))
  case Rectangle:      write_rectangle(writer, graphic_elem.(Rectangle))
  case Path:           write_path(writer, graphic_elem.(Path))
  case Polystar:       write_polystar(writer, graphic_elem.(Polystar))
  case Group:          write_group(writer, graphic_elem.(Group))
  case TransformShape: write_transform_shape(writer, graphic_elem.(TransformShape))
  case Fill:           write_fill(writer, graphic_elem.(Fill))
  case Stroke:         write_stroke(writer, graphic_elem.(Stroke))
  case GradientFill:   write_gradient_fill(writer, graphic_elem.(GradientFill))
  case GradientStroke: write_gradient_stroke(writer, graphic_elem.(GradientStroke)) 
  case TrimPath:       write_trim_path(writer, graphic_elem.(TrimPath))
  }
}

write_transform_shape :: proc(writer: ^Writer, transform_shape: TransformShape, debug_name := "Transform_Shape") {
  flags := transmute(Bit64)transform_shape._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, TRANSFORM_SHAPE_FIELDS)

  if isset(flags, 0) do write_string(writer, transform_shape.nm, "nm")
  if isset(flags, 1) do write_bool(writer, transform_shape.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(transform_shape.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_prop_position(writer, transform_shape.a, "a")
  if isset(flags, 4) do write_prop_position(writer, transform_shape.p, "p")
  if isset(flags, 5) do write_prop_scalar(writer, transform_shape.r, "r")
  if isset(flags, 6) do write_prop_vector(writer, transform_shape.s, "s")
  if isset(flags, 7) do write_prop_scalar(writer, transform_shape.o, "o")
  if isset(flags, 8) do write_prop_scalar(writer, transform_shape.sk, "sk")
  if isset(flags, 9) do write_prop_scalar(writer, transform_shape.sa, "sa")

  end_debug_info(writer)
}

write_fill :: proc(writer: ^Writer, fill: Fill, debug_name := "Fill") {
  flags := transmute(Bit64)fill._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, FILL_FIELDS)

  if isset(flags, 0) do write_string(writer, fill.nm, "nm")
  if isset(flags, 1) do write_bool(writer, fill.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(fill.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_prop_scalar(writer, fill.o, "o")
  if isset(flags, 4) do write_prop_color(writer, fill.c, "c")
  if isset(flags, 5) do write_enum(writer, u8(fill.r), FILL_RULE_BITS, "r")

  end_debug_info(writer)
}

write_stroke :: proc(writer: ^Writer, stroke: Stroke, debug_name := "Stroke") {
  flags := transmute(Bit64)stroke._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, STROKE_FIELDS)

  if isset(flags, 0) do write_string(writer, stroke.nm, "nm")
  if isset(flags, 1) do write_bool(writer, stroke.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(stroke.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")
  if isset(flags, 3) do write_prop_scalar(writer, stroke.o, "o")
  if isset(flags, 4) do write_enum(writer, u8(stroke.lc), LINE_CAP_BITS, "lc")
  if isset(flags, 5) do write_enum(writer, u8(stroke.lj), LINE_JOIN_BITS, "lj")
  if isset(flags, 6) do write_varint(writer, i128(stroke.ml), "ml")
  if isset(flags, 7) do write_prop_scalar(writer, stroke.ml2, "ml2")
  if isset(flags, 8) do write_prop_scalar(writer, stroke.w, "w")
  if isset(flags, 9) {
    write_varint(writer, i128(len(stroke.d)), "len")
    for stroke_dash in stroke.d {
      write_stroke_dash(writer, stroke_dash) 
    }
  }
  if isset(flags, 10) do write_prop_color(writer, stroke.c, "c")

  end_debug_info(writer)
}


write_gradient_fill :: proc(writer: ^Writer, gradient_fill: GradientFill, debug_name := "Gradient_Fill") {
  flags := transmute(Bit64)gradient_fill._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, GRADIENT_FILL_FIELDS)

  if isset(flags, 0) do write_string(writer, gradient_fill.nm, "nm")
  if isset(flags, 1) do write_bool(writer, gradient_fill.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(gradient_fill.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")
  
  if isset(flags, 3) do write_prop_scalar(writer, gradient_fill.o, "o")
  if isset(flags, 4) do write_prop_gradient(writer, gradient_fill.g, "g")
  if isset(flags, 5) do write_prop_position(writer, gradient_fill.s, "s")
  if isset(flags, 6) do write_prop_position(writer, gradient_fill.e, "e")
  if isset(flags, 7) do write_enum(writer, u8(gradient_fill.t), GRADIENT_TYPE_BITS, "t")
  if isset(flags, 8) do write_prop_scalar(writer, gradient_fill.h, "h")
  if isset(flags, 9) do write_prop_scalar(writer, gradient_fill.a, "a")
  if isset(flags, 10) do write_enum(writer, u8(gradient_fill.r), FILL_RULE_BITS, "r")

  end_debug_info(writer)
}

write_stroke_dash :: proc(writer: ^Writer, dash: StrokeDash, debug_name := "Stroke_Dash") {
  begin_debug_info(writer, debug_name, .meta)
  flags := transmute(Bit64)dash._flags
  write_flags(writer, flags, STROKE_DASH_FIELDS)
  if isset(flags, 0) do write_string(writer, dash.nm, "nm")
  if isset(flags, 1) {
    // mapping the char enums to a range of 0 - 2
    enum_val : u8
    switch dash.n {
    case .Dash:   enum_val = 0
    case .Gap:    enum_val = 1
    case .Offset: enum_val = 2
    }
    write_enum(writer, enum_val, STROKE_DASH_TYPE_BITS, "n")
  }
  if isset(flags, 2) do write_prop_scalar(writer, dash.v, "v")
  end_debug_info(writer)
}

write_gradient_stroke :: proc(writer: ^Writer, stroke: GradientStroke, debug_name := "Gradient_Stroke") {
  flags := transmute(Bit64)stroke._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, GRADIENT_STROKE_FIELDS)

  if isset(flags, 0) do write_string(writer, stroke.nm, "nm")
  if isset(flags, 1) do write_bool(writer, stroke.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(stroke.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")

  if isset(flags, 3) do write_prop_scalar(writer, stroke.o, "o")
  if isset(flags, 4) do write_enum(writer, u8(stroke.lc), LINE_CAP_BITS, "lc")
  if isset(flags, 5) do write_enum(writer, u8(stroke.lj), LINE_JOIN_BITS, "lj")
  if isset(flags, 6) do write_varint(writer, i128(stroke.ml), "ml")
  if isset(flags, 7) do write_prop_scalar(writer, stroke.ml2, "ml2")
  if isset(flags, 8) do write_prop_scalar(writer, stroke.w, "w")
  if isset(flags, 9) {
    write_varint(writer, i128(len(stroke.d)), "len")
    for stroke_dash in stroke.d {
      write_stroke_dash(writer, stroke_dash) 
    }
  }
  if isset(flags, 10) do write_prop_gradient(writer, stroke.g, "g")
  if isset(flags, 11) do write_prop_position(writer, stroke.s, "s")
  if isset(flags, 12) do write_prop_position(writer, stroke.e, "e")
  if isset(flags, 13) do write_enum(writer, u8(stroke.t), GRADIENT_TYPE_BITS, "t")
  if isset(flags, 14) do write_prop_scalar(writer, stroke.h, "h")
  if isset(flags, 15) do write_prop_scalar(writer, stroke.a, "a")
  end_debug_info(writer)
}

write_trim_path :: proc(writer: ^Writer, trim_path: TrimPath, debug_name := "TrimPath") {
  flags := transmute(Bit64)trim_path._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, FILL_FIELDS)

  if isset(flags, 0) do write_string(writer, trim_path.nm, "nm")
  if isset(flags, 1) do write_bool(writer, trim_path.hd, "hd")
  graphic_elem_type := conv_graphic_elem_type_to_enum(trim_path.ty)
  write_enum(writer, u8(graphic_elem_type), GRAPHIC_ELEM_TYPE_BITS, "ty")
  
  if isset(flags, 3) do write_prop_scalar(writer, trim_path.s, "s")
  if isset(flags, 4) do write_prop_scalar(writer, trim_path.e, "e")
  if isset(flags, 5) do write_prop_scalar(writer, trim_path.o, "o")
  if isset(flags, 6) do write_enum(writer, u8(trim_path.m), TRIM_MULTIPLE_SHAPES_BITS, "m")

  end_debug_info(writer)
}

write_mask :: proc(writer: ^Writer, mask: Mask, debug_name := "mask") {
  flags := transmute(Bit64)mask._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, MASK_FIELDS)

  if isset(flags, 0) {
    enum_val := u8(0)
    switch mask.mode {
    case .None:      enum_val = 0
    case .Add:       enum_val = 1
    case .Subtract:  enum_val = 2
    case .Intersect: enum_val = 3
    }
    
    write_enum(writer, enum_val, MASK_MODE_BITS, "mode")
  }
  if isset(flags, 1) do write_prop_scalar(writer, mask.o, "o")
  if isset(flags, 2) do write_prop_bezier_shape(writer, mask.pt, "pt")
}

write_shape_layer :: proc(writer: ^Writer, shape_layer: ShapeLayer, debug_name := "shape_layer") {
  flags := transmute(Bit64)shape_layer._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, SHAPE_LAYER_FIELDS)

  if isset(flags, 0) do write_string(writer, shape_layer.nm, "nm")
  if isset(flags, 1) do write_bool(writer, shape_layer.hd, "hd")
  if isset(flags, 2) do write_enum(writer, u8(shape_layer.ty), LAYER_TYPE_BITS, "ty")
  if isset(flags, 3) do write_varint(writer, i128(shape_layer.ind), "ind")
  if isset(flags, 4) do write_varint(writer, i128(shape_layer.parent), "parent")
  if isset(flags, 5) do write_varint(writer, i128(shape_layer.ip), "ip")
  if isset(flags, 6) do write_varint(writer, i128(shape_layer.op), "op")
  if isset(flags, 7) do write_transform(writer, shape_layer.ks, "ks")
  if isset(flags, 8) do write_varint(writer, i128(shape_layer.ao), "ao")
  if isset(flags, 9) do write_enum(writer, u8(shape_layer.tt), MATTE_MODE_BITS, "tt")
  if isset(flags, 10) do write_varint(writer, i128(shape_layer.tp), "tp")

  if isset(flags, 11) {
    begin_debug_info(writer, "masksProperties", .meta)
    write_varint(writer, i128(len(shape_layer.masksProperties)), "len")
    for mask in shape_layer.masksProperties {
      write_mask(writer, mask)
    }
    end_debug_info(writer)
  }
  
  if isset(flags, 12) {
    begin_debug_info(writer, "shapes", .meta)
    write_varint(writer, i128(len(shape_layer.shapes)), "shapes")
    for shape in shape_layer.shapes {
      write_graphic_elem(writer, shape)
    }
    end_debug_info(writer)
  }
  
  end_debug_info(writer)
}

write_image_layer :: proc(writer: ^Writer, image_layer: ImageLayer, debug_name := "image_layer") {
  flags := transmute(Bit64)image_layer._flags
  begin_debug_info(writer, debug_name, .meta)
  write_flags(writer, flags, IMAGE_LAYER_FIELDS)

  if isset(flags, 0) do write_string(writer, image_layer.nm, "nm")
  if isset(flags, 1) do write_bool(writer, image_layer.hd, "hd")
  if isset(flags, 2) do write_enum(writer, u8(image_layer.ty), LAYER_TYPE_BITS, "ty")
  if isset(flags, 3) do write_varint(writer, i128(image_layer.ind), "ind")
  if isset(flags, 4) do write_varint(writer, i128(image_layer.parent), "parent")
  if isset(flags, 5) do write_varint(writer, i128(image_layer.ip), "ip")
  if isset(flags, 6) do write_varint(writer, i128(image_layer.op), "op")
  if isset(flags, 7) do write_transform(writer, image_layer.ks, "ks")
  if isset(flags, 8) do write_varint(writer, i128(image_layer.ao), "ao")
  if isset(flags, 9) do write_enum(writer, u8(image_layer.tt), MATTE_MODE_BITS, "tt")
  if isset(flags, 10) do write_varint(writer, i128(image_layer.tp), "tp")
  if isset(flags, 11) {
    begin_debug_info(writer, "masksProperties", .meta)
    write_varint(writer, i128(len(image_layer.masksProperties)), "len")
    for mask in image_layer.masksProperties {
      write_mask(writer, mask)
    }
    end_debug_info(writer)
  }

  // TODO: How we refer to images within the format will probably change later
  if isset(flags, 12) do write_string(writer, image_layer.refId, "refId")

  end_debug_info(writer)
}