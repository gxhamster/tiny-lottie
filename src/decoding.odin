package main

/* This is the default implementation for the decoder
 * for tiny lottie. In the future I want to make the decoder
 * a separate module so that it can be compiled as different
 * unit and be used independently and make it as lean as possible.
 * Why? Decoder will be shipped in clients as a library. I want that
 * to have as small of a footprint as possible
 */

import "core:encoding/varint"
import "core:log"
import "core:math/bits"
import "core:mem"
import "core:testing"


ReaderError :: enum {
  None,
  OutofBoundsRead,
  VarintDecodingErr,
  InvalidHex,
  InvalidPalleteIdx,
  InvalidEasingEnum,
  InvalidPositionUnionTag,
  InvalidGraphicElemEnum,
  InvalidShapeDirection,
  InvalidStarType,
  InvalidStrokeDashType,
  InvalidMaskModeEnum,
  InvalidLayerType,
  InvalidAssetType,
  NegativeStringSize,
}

Reader :: struct {
  data:       []byte,
  cur_offset: int,
  cur_bits:   uint,
  end_offset: int, // end_offset and end_bits is the byte and bit offset
  end_bits:   uint, // at which the writer was at the moment
  header:     Header,
  allocator:  mem.Allocator,
}

reader_get_cur_pos :: proc(reader: ^Reader) -> (offset: int, bits: uint) {
  return reader.cur_offset, reader.cur_bits
}

reader_set_cur_pos :: proc(reader: ^Reader, offset: int, bits: uint) {
  reader.cur_offset = offset
  reader.cur_bits = bits
}

// Returns the amount of bytes remaining in the internal
// buffer of the reader
reader_data_buf_remaining :: proc(reader: ^Reader) -> int {
  return len(reader.data) - reader.cur_offset
}

// Gives the amount of bits that are to be read from
// the reader stream
reader_get_unread_bits :: proc(reader: ^Reader) -> int {
  total_cur_bits := reader.cur_offset * BYTE_BITS + int(reader.cur_bits)
  total_end_bits := reader.end_offset * BYTE_BITS + int(reader.end_bits)
  remaining := total_end_bits - total_cur_bits
  return remaining
}

MAX_NUM_READ_BITS :: 64
read_bits :: proc(reader: ^Reader, num_bits: uint) -> (v: u64, read_bits: uint, err: ReaderError) {
  total_cur_bits := reader.cur_offset * BYTE_BITS + int(reader.cur_bits)
  total_end_bits := reader.end_offset * BYTE_BITS + int(reader.end_bits)
  if (total_cur_bits + int(num_bits)) > total_end_bits {
    log.fatalf("total_cur = %v total_end = %v", total_cur_bits, total_end_bits)
    return 0, 0, .OutofBoundsRead
  }

  ptr := cast(^u64)raw_data(reader.data[reader.cur_offset:])
  val := ptr^
  to_read := num_bits >= MAX_NUM_READ_BITS ? MAX_NUM_READ_BITS : num_bits
  v = bits.bitfield_extract_u64(val, reader.cur_bits, to_read)
  total_bit_offset := int(reader.cur_bits + to_read)
  reader.cur_offset += total_bit_offset / BYTE_BITS
  reader.cur_bits = uint(total_bit_offset) % BYTE_BITS

  return v, to_read, .None
}

// No allocation variant
reader_from_writer :: proc(writer: ^Writer, allocator := context.allocator) -> Reader {
  reader := Reader{}
  reader.data = writer.data
  reader.end_bits = writer.bits
  reader.end_offset = writer.offset
  reader.cur_bits = 0
  reader.cur_offset = 0
  reader.allocator = allocator

  return reader
}

// Does a copy of the writer's internal data buffer into the reader own
// and will allocate its own slice
reader_from_writer_owned :: proc(writer: ^Writer, allocator := context.allocator) -> Reader {
  reader := Reader{}
  reader.data = make([]byte, len(writer.data), allocator)
  copy(reader.data[:], writer.data[:])
  reader.end_bits = writer.bits
  reader.end_offset = writer.offset
  reader.allocator = allocator

  return reader
}

reader_destroy :: proc(reader: ^Reader) {
  empty_alloc := mem.Allocator{}
  if reader.allocator != empty_alloc {
    delete(reader.data, reader.allocator)
  }
}

@(test)
read_bits_test :: proc(t: ^testing.T) {
  writer := Writer{}
  writer_init(&writer)
  write_color4(&writer, Color4{1, 2, 3, 4})

  reader := reader_from_writer(&writer)
  v1, r1, e1 := read_bits(&reader, 2)
  v2, r2, e2 := read_bits(&reader, 8)
  v3, r3, e3 := read_bits(&reader, 8)
  v4, r4, e4 := read_bits(&reader, 8)
  v5, r5, e5 := read_bits(&reader, 8)
  testing.expect(t, v1 == 0 && v2 == 1 && v3 == 2 && v4 == 3 && v5 == 4, "not expected color values")
}

read_float64 :: proc(reader: ^Reader) -> (v: f64, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(f64) * BYTE_BITS)
  val_f64 := (^f64)(&r_value)
  return val_f64^, r_err
}

read_float32 :: proc(reader: ^Reader) -> (v: f32, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(f32) * BYTE_BITS)
  val_f32 := (^f32)(&r_value)
  return val_f32^, r_err
}

read_float16 :: proc(reader: ^Reader) -> (v: f16, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(f16) * BYTE_BITS)
  val_f16 := (^f16)(&r_value)
  return val_f16^, r_err
}

read_int8 :: proc(reader: ^Reader) -> (v: i8, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(i8) * BYTE_BITS)
  val_i8 := (^i8)(&r_value)
  return val_i8^, r_err
}

read_int16 :: proc(reader: ^Reader) -> (v: i16, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(i16) * BYTE_BITS)
  val_i16 := (^i16)(&r_value)
  return val_i16^, r_err
}

read_int32 :: proc(reader: ^Reader) -> (v: i32, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(i32) * BYTE_BITS)
  val_i32 := (^i32)(&r_value)
  return val_i32^, r_err
}

read_int64 :: proc(reader: ^Reader) -> (v: i64, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(i64) * BYTE_BITS)
  val_i64 := (^i64)(&r_value)
  return val_i64^, r_err
}

read_uint8 :: proc(reader: ^Reader) -> (v: u8, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(u8) * BYTE_BITS)
  val_u8 := (^u8)(&r_value)
  return val_u8^, r_err
}

read_uint16 :: proc(reader: ^Reader) -> (v: u16, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(u16) * BYTE_BITS)
  val_u16 := (^u16)(&r_value)
  return val_u16^, r_err
}

read_uint32 :: proc(reader: ^Reader) -> (v: u32, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(u32) * BYTE_BITS)
  val_u32 := (^u32)(&r_value)
  return val_u32^, r_err
}

read_uint64 :: proc(reader: ^Reader) -> (v: u64, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, size_of(u64) * BYTE_BITS)
  val_u64 := (^u64)(&r_value)
  return val_u64^, r_err
}

decode_zigzag :: proc(x: u128) -> i128 {
  return i128((x >> 1) ~ (-(x & 1)))
}

read_byte :: proc(reader: ^Reader) -> (v: byte, err: ReaderError) {
  r_value, _, r_err := read_bits(reader, BYTE_BITS)
  return byte(r_value), r_err
}

read_varint :: proc(reader: ^Reader) -> (v: i128, err: ReaderError) {
  buffer: [varint.LEB128_MAX_BYTES]byte
  unread_bytes := int(reader_get_unread_bits(reader) / BYTE_BITS)
  assert(unread_bytes > 0, "should not be negative")
  init_offset := reader.cur_offset
  reading_len := len(buffer)
  if unread_bytes < len(buffer) {
    reading_len = unread_bytes
  }
  for i := 0; i < reading_len; i += 1 {
    byte_val, r_err := read_byte(reader)
    if r_err != .None {
      return v, r_err
    }
    buffer[i] = byte_val
  }
  val, size, var_err := varint.decode_uleb128_buffer(buffer[:])
  if size == 0 || var_err != .None {
    return v, .VarintDecodingErr
  }
  // note(iyaan): adjust the reader cur_offset to the amount of bytes
  // that actually was part of the varint not the whole bytes
  // that was read.
  reader.cur_offset = init_offset + size

  zigzag_decoded := decode_zigzag(val)
  return zigzag_decoded, .None
}

@(test)
read_varint_test :: proc(t: ^testing.T) {
  writer := Writer{}
  writer_init(&writer)
  write_varint(&writer, i128(16))
  write_varint(&writer, i128(10))
  write_varint(&writer, i128(2002))
  reader := reader_from_writer(&writer)
  v1, e1 := read_varint(&reader)
  v2, e2 := read_varint(&reader)
  v3, e3 := read_varint(&reader)
  testing.expect_value(t, v1, 16)
  testing.expect_value(t, v2, 10)
  testing.expect_value(t, v3, 2002)

  writer_destroy(&writer)
}

read_flags :: proc(reader: ^Reader, flag_bits: uint) -> (v: Bit64, err: ReaderError) {
  flag_val, _, flag_err := read_bits(reader, flag_bits)
  bit64 := transmute(Bit64)flag_val
  return bit64, flag_err
}

read_enum :: proc(reader: ^Reader, enum_bits: uint = ENUM_DEFAULT_BITS) -> (v: u8, err: ReaderError) {
  enum_val, _, enum_err := read_bits(reader, enum_bits)
  assert(enum_val < u64(max(u8)), "whats wrong with this enum")
  return u8(enum_val), enum_err
}

read_bool :: proc(reader: ^Reader) -> (v: bool, err: ReaderError) {
  bool_val, _, bool_err := read_bits(reader, 1)
  return bool(bool_val), bool_err
}

read_string :: proc(reader: ^Reader) -> (v: string, err: ReaderError) {
  str_size := read_varint(reader) or_return
  if str_size < 0 {
    // note(iyaan): The decoder is probably out of sync atp
    panic("String size negaitve")
    // return v, .NegativeStringSize
  }
  buffer := make_dynamic_array_len([dynamic]u8, str_size, reader.allocator)

  for i in 0 ..< str_size {
    b := read_byte(reader) or_return
    append(&buffer, b)
  }
  str := string(buffer[:])
  return str, .None
}

read_vector_intern :: proc(reader: ^Reader, vec: ^[$Y]f64) -> (err: ReaderError) {
  vec_flags, vec_err := read_flags(reader, VECTOR_INTERN_FLAG_BITS)
  f := transmute(VecInternType)vec_flags
  switch f {
  case .F16:
    for i in 0 ..< Y {
      fval, ferr := read_float16(reader)
      if ferr != .None {
        return ferr
      }
      vec[i] = f64(fval)
    }
    return .None
  case .F32:
    for i in 0 ..< Y {
      fval, ferr := read_float32(reader)
      if ferr != .None {
        return ferr
      }
      vec[i] = f64(fval)
    }
    return .None
  case .U8:
    for i in 0 ..< Y {
      fval, ferr := read_uint8(reader)
      if ferr != .None {
        return ferr
      }
      vec[i] = f64(fval)
    }
    return .None
  case .I8:
    for i in 0 ..< Y {
      fval, ferr := read_int8(reader)
      if ferr != .None {
        return ferr
      }
      vec[i] = f64(fval)
    }
    return .None
  }
  return .None
}

read_vector4 :: proc(reader: ^Reader) -> (v: Vec4, err: ReaderError) {
  vec4 := transmute([4]f64)Vec4{}
  vec_err := read_vector_intern(reader, &vec4)
  return transmute(Vec4)vec4, vec_err
}

read_vector3 :: proc(reader: ^Reader) -> (v: Vec3, err: ReaderError) {
  vec3 := transmute([3]f64)Vec3{}
  vec_err := read_vector_intern(reader, &vec3)
  return transmute(Vec3)vec3, vec_err
}

read_vector2 :: proc(reader: ^Reader) -> (v: Vec2, err: ReaderError) {
  vec2 := transmute([2]f64)Vec2{}
  vec_err := read_vector_intern(reader, &vec2)
  return transmute(Vec2)vec2, vec_err
}

read_hexcolor :: proc(reader: ^Reader) -> (v: HexColor, err: ReaderError) {
  r, r_err := read_byte(reader)
  g, g_err := read_byte(reader)
  b, b_err := read_byte(reader)

  byte_to_hex :: proc(col_byte: byte) -> (byte, bool) {
    switch col_byte {
    case 0 ..= 9:
      return col_byte + '0', true
    case 10 ..= 15:
      return col_byte + 'a' - 10, true
    case:
      return 0, false
    }
  }

  h1, e1 := byte_to_hex((r << 8) & 0x0f)
  h2, e2 := byte_to_hex(r & 0x0f)
  h3, e3 := byte_to_hex((g << 8) & 0x0f)
  h4, e4 := byte_to_hex(g & 0x0f)
  h5, e5 := byte_to_hex((b << 8) & 0x0f)
  h6, e6 := byte_to_hex(b & 0x0f)

  if !e1 || !e2 || !e3 || !e4 || !e5 || !e6 {
    return v, .InvalidHex
  }

  u8_buffer := [?]u8{h1, h2, h3, h4, h5, h6}
  str_buffer := string(u8_buffer[:])
  return HexColor(str_buffer), .None
}

read_color3 :: proc(reader: ^Reader) -> (v: Color3, err: ReaderError) {
  if .ColorPallete in reader.header.optimization_flags {
    pallete_idx := read_uint8(reader) or_return
    if int(pallete_idx) >= 0 && int(pallete_idx) <= reader.header.pallete_size {
      color4 := reader.header.pallete[pallete_idx]
      return color4.xyz, .None
    } else {
      return v, .InvalidPalleteIdx
    }
  } else {
    vec3 := read_vector3(reader) or_return
    return vec3, .None
  }
}

read_color4 :: proc(reader: ^Reader) -> (v: Color4, err: ReaderError) {
  if .ColorPallete in reader.header.optimization_flags {
    pallete_idx := read_uint8(reader) or_return
    if int(pallete_idx) >= 0 && int(pallete_idx) <= reader.header.pallete_size {
      color4 := reader.header.pallete[pallete_idx]
      return color4, .None
    } else {
      return v, .InvalidPalleteIdx
    }
  } else {
    vec4 := read_vector4(reader) or_return
    return vec4, .None
  }
}

// Allocates slice. Caller need to handle freeing
read_gradient :: proc(reader: ^Reader, allocator := context.temp_allocator) -> (v: Gradient, err: ReaderError) {
  grad_len := read_varint(reader) or_return
  gradient := make(Gradient, grad_len, allocator)
  for i in 0 ..< grad_len {
    grad_val := read_uint8(reader) or_return
    gradient[i] = f64(grad_val) / 255.0
  }

  return gradient, .None
}

read_bezier :: proc(reader: ^Reader, allocator := context.temp_allocator) -> (v: BezierShapeValue, err: ReaderError) {
  flags := read_flags(reader, BEZIER_FLAG_BITS) or_return
  length := read_varint(reader) or_return

  v.i = make([]Vec3, length, allocator)
  v.o = make([]Vec3, length, allocator)
  v.v = make([]Vec3, length, allocator)
  v.c = 0 in flags
  truncate_to_vec2 := 1 in flags

  for i in 0 ..< length {
    if truncate_to_vec2 {
      vec2 := read_vector2(reader) or_return
      v.i[i] = Vec3{vec2.x, vec2.y, 0}
    } else {
      v.i[i] = read_vector3(reader) or_return
    }
  }
  for i in 0 ..< length {
    if truncate_to_vec2 {
      vec2 := read_vector2(reader) or_return
      v.o[i] = Vec3{vec2.x, vec2.y, 0}
    } else {
      v.o[i] = read_vector3(reader) or_return
    }
  }
  for i in 0 ..< length {
    if truncate_to_vec2 {
      vec2 := read_vector2(reader) or_return
      v.v[i] = Vec3{vec2.x, vec2.y, 0}
    } else {
      v.v[i] = read_vector3(reader) or_return
    }
  }

  return v, .None

}

// The order must match that `EasingFunction`
cubic_easing_functions_params := [EasingFunction.Error][4]f64 {
  {0.11, 0, 0.5, 0},
  {0.32, 0, 0.67, 0},
  {0.33, 1, 0.68, 1},
  {0.65, 0, 0.35, 1},
  {0, 0, 1, 1},
}

read_easing_curve :: proc(reader: ^Reader) -> (p0: PropKeyframeEasing, p1: PropKeyframeEasing, err: ReaderError) {
  prem_flags := read_flags(reader, EASING_CURVE_PREM_FLAGS_BITS) or_return
  easing_curve_flags := transmute(EasingCurveFlagPrem_Set)prem_flags
  if .IsVector in easing_curve_flags {
    vec_length := .IsVector2 in easing_curve_flags ? 2 : 3
    p0 := PropKeyframeEasingVec{}
    p1 := PropKeyframeEasingVec{}
    for i in 0 ..< vec_length {
      elem_flags := read_flags(reader, EASING_CURVE_ELEM_FLAGS_BITS) or_return
      easing_curve_elem_flags := transmute(EasingCurveElemFlag_Set)elem_flags
      if .IsEnum in easing_curve_elem_flags {
        r_enum := read_enum(reader, EASING_FUNCTION_BITS) or_return
        easing_func_enum := EasingFunction(r_enum)
        switch easing_func_enum {
        case .Linear, .Ease, .EaseIn, .EaseOut, .EaseInOut:
          {
            // note(iyaan): p0 is `o` and p1 is `i`
            ease_params := cubic_easing_functions_params[easing_func_enum]
            p0.x[i] = ease_params.x
            p0.y[i] = ease_params.y
            p1.x[i] = ease_params.z
            p1.y[i] = ease_params.w
          }
        case .Error:
          return p0, p1, .InvalidEasingEnum
        }
      } else {
        v0 := read_vector2(reader) or_return
        v1 := read_vector2(reader) or_return
        p0.x[i] = v0.x
        p0.y[i] = v0.y
        p1.x[i] = v1.x
        p1.y[i] = v1.y
      }
    }
    return p0, p1, .None
  } else {
    // Scalar
    elem_flags := read_flags(reader, EASING_CURVE_ELEM_FLAGS_BITS) or_return
    easing_curve_elem_flags := transmute(EasingCurveElemFlag_Set)elem_flags
    if .IsEnum in easing_curve_elem_flags {
      r_enum := read_enum(reader, EASING_FUNCTION_BITS) or_return
      easing_func_enum := EasingFunction(r_enum)
      switch easing_func_enum {
      case .Linear, .Ease, .EaseIn, .EaseOut, .EaseInOut:
        {
          // note(iyaan): p0 is `o` and p1 is `i`
          ease_params := cubic_easing_functions_params[easing_func_enum]
          p0 := PropKeyframeEasingScalar{ease_params.x, ease_params.y}
          p1 := PropKeyframeEasingScalar{ease_params.z, ease_params.w}
          return p0, p1, .None
        }
      case .Error:
        return p0, p1, .InvalidEasingEnum
      }
    } else {
      v0 := read_vector2(reader) or_return
      v1 := read_vector2(reader) or_return
      p0 := PropKeyframeEasingScalar{v0.x, v0.y}
      p1 := PropKeyframeEasingScalar{v1.x, v1.y}
      return p0, p1, .None
    }
  }
  return p0, p1, .None
}

@(test)
read_easing_curve_test :: proc(t: ^testing.T) {
  writer := Writer{}
  writer_init(&writer)
  p0 := PropKeyframeEasingScalar{0, 0}
  p1 := PropKeyframeEasingScalar{1, 1}
  write_easing_curve(&writer, p0, p1)

  p2 := PropKeyframeEasingVec {
    x = {0, 0, 0},
    y = {0, 0, 0},
  }
  p3 := PropKeyframeEasingVec {
    x = {1, 1, 1},
    y = {1, 1, 1},
  }
  write_easing_curve(&writer, p2, p3)

  // the vector encoder will probably encode them
  // as f16 instead of full f64. So need to take that
  // into consideration
  p4 := PropKeyframeEasingVec {
    x = {0.1, 2, 0},
    y = {0.5, 4, 0},
  }
  p5 := PropKeyframeEasingVec {
    x = {7, 0.2, 0},
    y = {9, 0.6, 0},
  }
  write_easing_curve(&writer, p4, p5)

  reader := reader_from_writer(&writer)
  pp0, pp1, e0 := read_easing_curve(&reader)
  testing.expect_value(t, pp0, p0)
  testing.expect_value(t, pp1, p1)

  pp2, pp3, e1 := read_easing_curve(&reader)
  testing.expect_value(t, pp2, p2)
  testing.expect_value(t, pp3, p3)

  pp4, pp5, e2 := read_easing_curve(&reader)
  for i in 0 ..< 3 {
    testing.expect_value(t, f16(pp4.(PropKeyframeEasingVec).x[i]), f16(p4.x[i]))
    testing.expect_value(t, f16(pp4.(PropKeyframeEasingVec).y[i]), f16(p4.y[i]))
    testing.expect_value(t, f16(pp5.(PropKeyframeEasingVec).x[i]), f16(p5.x[i]))
    testing.expect_value(t, f16(pp5.(PropKeyframeEasingVec).x[i]), f16(p5.x[i]))
  }

  writer_destroy(&writer)
}

read_prop_vector_keyframe :: proc(reader: ^Reader) -> (v: PropVectorKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_VECTOR_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = u64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }
  if isset(flags, 4) {
    v.s = read_vector3(reader) or_return
  }
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_vector :: proc(reader: ^Reader) -> (v: PropVector, err: ReaderError) {
  #assert(PROP_VECTOR_ANIM_FIELDS == PROP_VECTOR_SINGLE_FIELDS, "why not equal?")
  flags := read_flags(reader, PROP_VECTOR_SINGLE_FIELDS) or_return
  if isset(flags, 1) {
    // Animated
    vec_anim := PropVectorAnim{}
    if isset(flags, 0) do vec_anim.sid = read_string(reader) or_return
    vec_anim.a = true
    keyframe_len := read_varint(reader) or_return
    keyframes := make([]PropVectorKeyframe, keyframe_len, reader.allocator)
    for i in 0 ..< keyframe_len {
      keyframes[i] = read_prop_vector_keyframe(reader) or_return
    }
    vec_anim.k = keyframes[:]
    vec_anim._flags = transmute(u64)flags
    return vec_anim, .None
  } else {
    // Not-animated
    vec_single := PropVectorSingle{}
    truncated_to_vec2 := false
    if isset(flags, PROP_VECTOR_SINGLE_FIELDS) do truncated_to_vec2 = true
    if isset(flags, 0) do vec_single.sid = read_string(reader) or_return
    vec_single.a = false
    if truncated_to_vec2 {
      vec_single.k.xy = cast([2]f64)read_vector2(reader) or_return
    } else {
      vec_single.k = read_vector3(reader) or_return
    }
    vec_single._flags = transmute(u64)flags
    return vec_single, .None
  }
}

read_scalar_value :: proc(reader: ^Reader) -> (v: f64, err: ReaderError) {
  scalar := [1]f64{}
  read_vector_intern(reader, &scalar) or_return
  return scalar.x, .None
}

read_prop_scalar_keyframe :: proc(reader: ^Reader) -> (v: PropScalarKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_VECTOR_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = i64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }
  if isset(flags, 4) {
    v.s = read_scalar_value(reader) or_return
  }
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_scalar :: proc(reader: ^Reader) -> (v: PropScalar, err: ReaderError) {
  #assert(PROP_SCALAR_ANIM_FIELDS == PROP_SCALAR_SINGLE_FIELDS, "why not equal?")
  flags := read_flags(reader, PROP_SCALAR_SINGLE_FIELDS) or_return
  if isset(flags, 1) {
    // Animated
    scalar_anim := PropScalarAnim{}
    if isset(flags, 0) do scalar_anim.sid = read_string(reader) or_return
    scalar_anim.a = true
    keyframe_len := read_varint(reader) or_return
    keyframes := make([]PropScalarKeyframe, keyframe_len, reader.allocator)
    for i in 0 ..< keyframe_len {
      keyframes[i] = read_prop_scalar_keyframe(reader) or_return
    }
    scalar_anim.k = keyframes[:]
    scalar_anim._flags = transmute(u64)flags
    return scalar_anim, .None
  } else {
    // Not-animated
    vec_single := PropScalarSingle{}
    if isset(flags, 0) do vec_single.sid = read_string(reader) or_return
    vec_single.a = false
    if isset(flags, 2) do vec_single.k = read_scalar_value(reader) or_return
    vec_single._flags = transmute(u64)flags
    return vec_single, .None
  }
}

read_prop_position_keyframe :: proc(reader: ^Reader) -> (v: PropPositionKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_POSITION_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = u64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }
  if isset(flags, 4) {
    v.s.xy = cast([2]f64)read_vector2(reader) or_return
  }
  if isset(flags, 5) {
    v.ti.xy = cast([2]f64)read_vector2(reader) or_return
  }
  if isset(flags, 6) {
    v.to.xy = cast([2]f64)read_vector2(reader) or_return
  }
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_position :: proc(reader: ^Reader) -> (v: PropPosition, err: ReaderError) {
  union_tag := read_enum(reader, PROP_POSITION_UNION_TAG_BITS) or_return
  position_type := PropPositionUnionTag(union_tag)
  switch position_type {
  case .PropPositionSingle:
    {
      flags := read_flags(reader, PROP_VECTOR_SINGLE_FIELDS) or_return
      pos_single := PropPositionSingle{}
      pos_single._flags = transmute(u64)flags
      if isset(flags, 0) do pos_single.sid = read_string(reader) or_return
      pos_single.a = false
      if isset(flags, 2) {
        vec2 := read_vector2(reader) or_return
        pos_single.k.xy = vec2.xy
      }
      return pos_single, .None
    }
  case .PropPositionAnim:
    {
      pos_anim := PropPositionAnim{}
      flags := read_flags(reader, PROP_POSITION_ANIM_FIELDS) or_return
      if isset(flags, 0) do pos_anim.sid = read_string(reader) or_return
      pos_anim.a = true
      keyframe_len := read_varint(reader) or_return
      keyframes := make([]PropPositionKeyframe, keyframe_len, reader.allocator)
      for i in 0 ..< keyframe_len {
        keyframes[i] = read_prop_position_keyframe(reader) or_return
      }
      pos_anim.k = keyframes[:]
      pos_anim._flags = transmute(u64)flags
      return pos_anim, .None
    }
  case .PropSplitPosition:
    {
      pos_split := PropSplitPosition{}
      flags := read_flags(reader, PROP_SPLIT_POSITION_FIELDS) or_return
      if isset(flags, 0) do pos_split.s = read_bool(reader) or_return
      if isset(flags, 1) do pos_split.x = read_prop_scalar(reader) or_return
      if isset(flags, 2) do pos_split.y = read_prop_scalar(reader) or_return
      pos_split._flags = transmute(u64)flags
    }
  }
  return v, .InvalidPositionUnionTag
}

read_prop_bezier_keyframe :: proc(reader: ^Reader) -> (v: PropBezierKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_BEZIER_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = u64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }
  bezier_array_len := read_varint(reader) or_return
  beziers := make([]BezierShapeValue, bezier_array_len, reader.allocator)
  for idx in 0 ..< bezier_array_len {
    beziers[idx] = read_bezier(reader, reader.allocator) or_return
  }
  v.s = beziers
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_bezier :: proc(reader: ^Reader) -> (v: PropBezier, err: ReaderError) {
  #assert(PROP_BEZIER_SINGLE_FIELDS == PROP_BEZIER_ANIM_FIELDS, "why not equal?")
  flags := read_flags(reader, PROP_BEZIER_SINGLE_FIELDS) or_return
  if isset(flags, 0) {
    bezier_anim := PropBezierAnim{}
    bezier_anim.a = true
    keyframes_len := read_varint(reader) or_return
    keyframes := make([]PropBezierKeyframe, keyframes_len, reader.allocator)
    for idx in 0 ..< keyframes_len {
      keyframes[idx] = read_prop_bezier_keyframe(reader) or_return
    }
    bezier_anim.k = keyframes
    bezier_anim._flags = transmute(u64)flags
    return bezier_anim, .None
  } else {
    bezier_single := PropBezierSingle{}
    bezier_single.a = false
    bezier_single.k = read_bezier(reader) or_return
    bezier_single._flags = transmute(u64)flags
    return bezier_single, .None
  }
}

read_prop_color_keyframe :: proc(reader: ^Reader) -> (v: PropColorKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_COLOR_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = u64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }

  v.s = read_color4(reader) or_return
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_color :: proc(reader: ^Reader) -> (v: PropColor, err: ReaderError) {
  #assert(PROP_COLOR_SINGLE_FIELDS == PROP_COLOR_ANIM_FIELDS, "why not equal?")
  flags := read_flags(reader, PROP_BEZIER_SINGLE_FIELDS) or_return
  if isset(flags, 0) {
    color_anim := PropColorAnim{}
    color_anim.a = true
    keyframes_len := read_varint(reader) or_return
    keyframes := make([]PropColorKeyframe, keyframes_len, reader.allocator)
    for idx in 0 ..< keyframes_len {
      keyframes[idx] = read_prop_color_keyframe(reader) or_return
    }
    color_anim.k = keyframes
    color_anim._flags = transmute(u64)flags
    return color_anim, .None
  } else {
    color_single := PropColorSingle{}
    color_single.a = false
    color_single.k = read_color4(reader) or_return
    color_single._flags = transmute(u64)flags
    return color_single, .None
  }
}

read_prop_gradient_keyframe :: proc(reader: ^Reader) -> (v: GradientKeyframe, err: ReaderError) {
  flags := read_flags(reader, PROP_GRADIENT_KEYFRAME_FIELDS) or_return
  if isset(flags, 0) {
    t := read_varint(reader) or_return
    v.t = i64(t)
  }
  if isset(flags, 1) {
    h := read_varint(reader) or_return
    v.h = i64(h)
  }
  if isset(flags, 2) && isset(flags, 3) {
    p0, p1 := read_easing_curve(reader) or_return
    v.o = p0
    v.i = p1
  }

  v.s = read_gradient(reader) or_return
  v._flags = transmute(u64)flags

  return v, .None
}

read_prop_gradient :: proc(reader: ^Reader) -> (v: PropGradient, err: ReaderError) {
  p := read_varint(reader) or_return
  a := read_bool(reader) or_return
  if a {
    grad_stop_anim := v.k.(GradientStopAnim)
    grad_stop_anim.a = a
    keyframes_len := read_varint(reader) or_return
    keyframes := make([]GradientKeyframe, keyframes_len, reader.allocator)
    for idx in 0 ..< keyframes_len {
      keyframes[idx] = read_prop_gradient_keyframe(reader) or_return
    }
    grad_stop_anim.k = keyframes
    v.p = u64(p)
    v.k = grad_stop_anim
    return v, .None
  } else {
    grad_stop_single := v.k.(GradientStopSingle)
    grad_stop_single.a = a
    grad_stop_single.k = read_gradient(reader) or_return
    v.p = u64(p)
    v.k = grad_stop_single
    return v, .None
  }
}

read_transform :: proc(reader: ^Reader) -> (v: Transform, err: ReaderError) {
  flags := read_flags(reader, TRANSFORM_FIELDS) or_return
  if isset(flags, 0) do v.a = read_prop_position(reader) or_return
  if isset(flags, 1) do v.p = read_prop_position(reader) or_return
  if isset(flags, 2) do v.r = read_prop_scalar(reader) or_return
  if isset(flags, 3) do v.s = read_prop_vector(reader) or_return
  if isset(flags, 4) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 5) do v.sk = read_prop_scalar(reader) or_return
  if isset(flags, 6) do v.sa = read_prop_scalar(reader) or_return
  v._flags = transmute(u64)flags
  return v, .None
}

conv_enum_val_to_graphic_elem_type_str :: proc(type: i8) -> (str: string, err: ReaderError) {
  if type < 0 && type >= i8(GraphicElemType.Size) {
    return "", .InvalidGraphicElemEnum
  } else {
    enum_type := GraphicElemType(type)
    switch enum_type {
    case .el:
      return "el", .None
    case .fl:
      return "fl", .None
    case .gf:
      return "gf", .None
    case .gs:
      return "gs", .None
    case .gr:
      return "gr", .None
    case .sh:
      return "sh", .None
    case .sr:
      return "sr", .None
    case .rc:
      return "rc", .None
    case .st:
      return "st", .None
    case .tr:
      return "tr", .None
    case .tm:
      return "tm", .None
    case .Size, .Error:
      return "", .InvalidGraphicElemEnum
    case:
      return "", .InvalidGraphicElemEnum
    }
  }
}

read_shape_direction_enum :: proc(reader: ^Reader) -> (v: ShapeDirection, err: ReaderError) {
  d := ShapeDirection(read_enum(reader) or_return)
  switch d {
  case .Normal:
    v = .Normal
  case .Reversed:
    v = .Reversed
  case:
    return v, .InvalidShapeDirection
  }
  return v, .None
}

read_ellipse :: proc(reader: ^Reader) -> (v: Ellipse, err: ReaderError) {
  flags := read_flags(reader, ELLIPSE_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return
  if isset(flags, 3) do v.d = read_shape_direction_enum(reader) or_return
  if isset(flags, 4) do v.p = read_prop_position(reader) or_return
  if isset(flags, 5) do v.s = read_prop_vector(reader) or_return
  v._flags = transmute(u64)flags

  return v, .None
}

read_rectangle :: proc(reader: ^Reader) -> (v: Rectangle, err: ReaderError) {
  flags := read_flags(reader, RECTANGLE_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return
  if isset(flags, 3) do v.d = read_shape_direction_enum(reader) or_return
  if isset(flags, 4) do v.p = read_prop_position(reader) or_return
  if isset(flags, 5) do v.s = read_prop_vector(reader) or_return
  if isset(flags, 6) do v.r = read_prop_scalar(reader) or_return
  v._flags = transmute(u64)flags

  return v, .None
}

read_path :: proc(reader: ^Reader) -> (v: Path, err: ReaderError) {
  flags := read_flags(reader, PATH_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return
  if isset(flags, 3) do v.d = read_shape_direction_enum(reader) or_return
  if isset(flags, 4) do v.ks = read_prop_bezier(reader) or_return
  v._flags = transmute(u64)flags

  return v, .None
}

read_polystar :: proc(reader: ^Reader) -> (v: Polystar, err: ReaderError) {
  flags := read_flags(reader, POLYSTAR_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return
  if isset(flags, 3) do v.d = read_shape_direction_enum(reader) or_return
  if isset(flags, 4) do v.p = read_prop_position(reader) or_return
  if isset(flags, 5) do v.or = read_prop_scalar(reader) or_return
  if isset(flags, 6) do v.os = read_prop_scalar(reader) or_return
  if isset(flags, 7) do v.r = read_prop_scalar(reader) or_return
  if isset(flags, 8) do v.pt = read_prop_scalar(reader) or_return
  if isset(flags, 9) {
    sy := StarType(read_enum(reader) or_return)
    switch sy {
    case .Star:
      v.sy = .Star
    case .Polygon:
      v.sy = .Polygon
    case:
      return v, .InvalidStarType
    }
  }
  if isset(flags, 10) do v.ir = read_prop_scalar(reader) or_return
  if isset(flags, 11) do v.is = read_prop_scalar(reader) or_return

  v._flags = transmute(u64)flags

  return v, .None
}

read_group :: proc(reader: ^Reader) -> (v: Group, err: ReaderError) {
  flags := read_flags(reader, GROUP_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return
  if isset(flags, 3) do v.np = i64(read_varint(reader) or_return)

  graphic_arr_len := u64(read_varint(reader) or_return)
  for i in 0 ..< graphic_arr_len {
    // TODO: Need to write the proper graphic elem
  }

  v._flags = transmute(u64)flags

  return v, .None
}

read_transform_shape :: proc(reader: ^Reader) -> (v: TransformShape, err: ReaderError) {
  flags := read_flags(reader, TRANSFORM_SHAPE_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.a = read_prop_position(reader) or_return
  if isset(flags, 4) do v.p = read_prop_position(reader) or_return
  if isset(flags, 5) do v.r = read_prop_scalar(reader) or_return
  if isset(flags, 6) do v.s = read_prop_vector(reader) or_return
  if isset(flags, 7) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 8) do v.sk = read_prop_scalar(reader) or_return
  if isset(flags, 9) do v.sa = read_prop_scalar(reader) or_return

  v._flags = transmute(u64)flags
  return v, .None
}

read_fill :: proc(reader: ^Reader) -> (v: Fill, err: ReaderError) {
  flags := read_flags(reader, FILL_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 4) do v.c = read_prop_color(reader) or_return
  if isset(flags, 5) {
    // TODO(iyaan): Change this pattern of simply casting an unknown
    // read value into an enum. Should check value and the range
    fill_rule := FillRule(read_enum(reader, FILL_RULE_BITS) or_return)
    v.r = fill_rule
  }

  v._flags = transmute(u64)flags
  return v, .None
}

read_stroke_dash :: proc(reader: ^Reader) -> (v: StrokeDash, err: ReaderError) {
  flags := read_flags(reader, STROKE_DASH_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) {
    enum_val := read_enum(reader, STROKE_DASH_TYPE_BITS) or_return
    if enum_val == 0 {
      v.n = .Dash
    } else if enum_val == 1 {
      v.n = .Gap
    } else if enum_val == 2 {
      v.n = .Offset
    } else {
      return v, .InvalidStrokeDashType
    }
  }

  if isset(flags, 2) do v.v = read_prop_scalar(reader) or_return

  v._flags = transmute(u64)flags
  return v, .None
}

read_stroke :: proc(reader: ^Reader) -> (v: Stroke, err: ReaderError) {
  flags := read_flags(reader, STROKE_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 4) {
    lc := LineCap(read_enum(reader, LINE_CAP_BITS) or_return)
    v.lc = lc
  }
  if isset(flags, 5) {
    lj := LineJoin(read_enum(reader, LINE_JOIN_BITS) or_return)
    v.lj = lj
  }
  if isset(flags, 6) do v.ml = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ml2 = read_prop_scalar(reader) or_return
  if isset(flags, 8) do v.w = read_prop_scalar(reader) or_return
  if isset(flags, 9) {
    stroke_dash_len := u64(read_varint(reader) or_return)
    stroke_dash_arr := make([]StrokeDash, stroke_dash_len, reader.allocator)
    for i in 0 ..< stroke_dash_len {
      dash := read_stroke_dash(reader) or_return
      stroke_dash_arr[i] = dash
    }
    v.d = stroke_dash_arr
  }
  if isset(flags, 10) do v.c = read_prop_color(reader) or_return
  v._flags = transmute(u64)flags
  return v, .None
}

read_gradient_fill :: proc(reader: ^Reader) -> (v: GradientFill, err: ReaderError) {
  flags := read_flags(reader, GRADIENT_FILL_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 4) do v.g = read_prop_gradient(reader) or_return
  if isset(flags, 5) do v.s = read_prop_position(reader) or_return
  if isset(flags, 6) do v.e = read_prop_position(reader) or_return
  if isset(flags, 7) {
    v.t = GradientType(read_enum(reader, GRADIENT_TYPE_BITS) or_return)
  }
  if isset(flags, 8) do v.h = read_prop_scalar(reader) or_return
  if isset(flags, 9) do v.a = read_prop_scalar(reader) or_return
  if isset(flags, 10) do v.r = FillRule(read_enum(reader, FILL_RULE_BITS) or_return)

  v._flags = transmute(u64)flags
  return v, .None
}

read_gradient_stroke :: proc(reader: ^Reader) -> (v: GradientStroke, err: ReaderError) {
  flags := read_flags(reader, GRADIENT_STROKE_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 4) do v.lc = LineCap(read_enum(reader, LINE_CAP_BITS) or_return)
  if isset(flags, 5) do v.lj = LineJoin(read_enum(reader, LINE_JOIN_BITS) or_return)
  if isset(flags, 6) do v.ml = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ml2 = read_prop_scalar(reader) or_return
  if isset(flags, 8) do v.w = read_prop_scalar(reader) or_return
  if isset(flags, 9) {
    stroke_dash_len := u64(read_varint(reader) or_return)
    stroke_dash_arr := make([]StrokeDash, stroke_dash_len, reader.allocator)
    for i in 0 ..< stroke_dash_len {
      dash := read_stroke_dash(reader) or_return
      stroke_dash_arr[i] = dash
    }
    v.d = stroke_dash_arr
  }
  if isset(flags, 10) do v.g = read_prop_gradient(reader) or_return
  if isset(flags, 11) do v.s = read_prop_position(reader) or_return
  if isset(flags, 12) do v.e = read_prop_position(reader) or_return
  if isset(flags, 13) do v.t = GradientType(read_enum(reader, GRADIENT_TYPE_BITS) or_return)
  if isset(flags, 14) do v.h = read_prop_scalar(reader) or_return
  if isset(flags, 15) do v.a = read_prop_scalar(reader) or_return

  v._flags = transmute(u64)flags
  return v, .None
}

read_trim_path :: proc(reader: ^Reader) -> (v: TrimPath, err: ReaderError) {
  flags := read_flags(reader, TRIM_PATH_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  ty := read_enum(reader, GRAPHIC_ELEM_TYPE_BITS) or_return
  v.ty = conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  if isset(flags, 3) do v.s = read_prop_scalar(reader) or_return
  if isset(flags, 4) do v.e = read_prop_scalar(reader) or_return
  if isset(flags, 5) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 6) do v.m = TrimMultipleShapes(read_enum(reader, TRIM_MULTIPLE_SHAPES_BITS) or_return)

  v._flags = transmute(u64)flags
  return v, .None
}

read_graphic_elem :: proc(reader: ^Reader) -> (v: GraphicElement, err: ReaderError) {
  old_pos, old_bits := reader_get_cur_pos(reader)
  nm: string
  hd: bool
  ty: u8
  // note(iyaan): Read the fields to get the type of graphic element
  // TODO: Maybe we can have the encoder encode a tag after the flag for each graphic elem.
  flags := read_flags(reader, POLYSTAR_FIELDS) or_return
  if isset(flags, 0) do nm = read_string(reader) or_return
  if isset(flags, 1) do hd = read_bool(reader) or_return
  ty = read_enum(reader) or_return
  ty_str := conv_enum_val_to_graphic_elem_type_str(i8(ty)) or_return

  reader_set_cur_pos(reader, old_pos, old_bits)

  graphic_elem_type := GraphicElemType(ty)
  switch graphic_elem_type {
  case .el:
    v = read_ellipse(reader) or_return
  case .fl:
    v = read_fill(reader) or_return
  case .gf:
    v = read_gradient_fill(reader) or_return
  case .gs:
    v = read_gradient_stroke(reader) or_return
  case .gr:
    v = read_group(reader) or_return
  case .sh:
    v = read_path(reader) or_return
  case .sr:
    v = read_polystar(reader) or_return
  case .rc:
    v = read_rectangle(reader) or_return
  case .st:
    v = read_stroke(reader) or_return
  case .tr:
    v = read_transform_shape(reader) or_return
  case .tm:
    v = read_trim_path(reader) or_return
  case .Size, .Error:
    return v, .InvalidGraphicElemEnum
  case:
    return v, .InvalidGraphicElemEnum
  }

  return v, .None
}

read_mask :: proc(reader: ^Reader) -> (v: Mask, err: ReaderError) {
  flags := read_flags(reader, MASK_FIELDS) or_return
  if isset(flags, 0) {
    enum_val := read_enum(reader, MASK_MODE_BITS) or_return
    if enum_val == 0 {
      v.mode = .None
    } else if  enum_val == 1 {
      v.mode = .Add
    } else if enum_val == 2 {
      v.mode = .Subtract
    } else if enum_val == 3 {
      v.mode = .Intersect
    } else {
      return v, .InvalidMaskModeEnum
    }
  }

  if isset(flags, 1) do v.o = read_prop_scalar(reader) or_return
  if isset(flags, 2) do v.pt = read_prop_bezier(reader) or_return
 
  v._flags = transmute(u64)flags
  return v, .None
}

read_shape_layer :: proc(reader: ^Reader) -> (v: ShapeLayer, err: ReaderError) {
  flags := read_flags(reader, SHAPE_LAYER_FIELDS) or_return

  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  if isset(flags, 3) do v.ind = i64(read_varint(reader) or_return)
  if isset(flags, 4) do v.parent = i64(read_varint(reader) or_return)
  if isset(flags, 5) do v.ip = i64(read_varint(reader) or_return)
  if isset(flags, 6) do v.op = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ks = read_transform(reader) or_return
  if isset(flags, 8) do v.ao = i64(read_varint(reader) or_return)
  if isset(flags, 9) do v.tt = MatteMode(read_enum(reader, MATTE_MODE_BITS) or_return)
  if isset(flags, 10) do v.tp = i64(read_varint(reader) or_return)
  
  if isset(flags, 11) {
    no_of_masks := read_varint(reader) or_return
    masks := make([]Mask, no_of_masks, reader.allocator)
    for i in 0..<no_of_masks {
      masks[i] = read_mask(reader) or_return
    }
    v.masksProperties = masks
  }

  if isset(flags, 12) {
    no_of_shapes := read_varint(reader) or_return
    shapes := make([]GraphicElement, no_of_shapes, reader.allocator)
    for i in 0..<no_of_shapes {
      shapes[i] = read_graphic_elem(reader) or_return
    }
    v.shapes = shapes
  }

  v._flags = transmute(u64)flags
  return v, .None
}

read_image_layer :: proc(reader: ^Reader) -> (v: ImageLayer, err: ReaderError) {
  flags := read_flags(reader, IMAGE_LAYER_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  if isset(flags, 3) do v.ind = i64(read_varint(reader) or_return)
  if isset(flags, 4) do v.parent = i64(read_varint(reader) or_return)
  if isset(flags, 5) do v.ip = i64(read_varint(reader) or_return)
  if isset(flags, 6) do v.op = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ks = read_transform(reader) or_return
  if isset(flags, 8) do v.ao = i64(read_varint(reader) or_return)
  if isset(flags, 9) do v.tt = MatteMode(read_enum(reader, MATTE_MODE_BITS) or_return)
  if isset(flags, 10) do v.tp = i64(read_varint(reader) or_return)

  if isset(flags, 11) {
    no_of_masks := read_varint(reader) or_return
    masks := make([]Mask, no_of_masks, reader.allocator)
    for i in 0..<no_of_masks {
      masks[i] = read_mask(reader) or_return
    }
    v.masksProperties = masks
  }

  if isset(flags, 12) do v.refId = read_string(reader) or_return

  v._flags = transmute(u64)flags
  return v, .None
}

read_null_layer :: proc(reader: ^Reader) -> (v: NullLayer, err: ReaderError) {
  flags := read_flags(reader, NULL_LAYER_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  if isset(flags, 3) do v.ind = i64(read_varint(reader) or_return)
  if isset(flags, 4) do v.parent = i64(read_varint(reader) or_return)
  if isset(flags, 5) do v.ip = i64(read_varint(reader) or_return)
  if isset(flags, 6) do v.op = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ks = read_transform(reader) or_return
  if isset(flags, 8) do v.ao = i64(read_varint(reader) or_return)
  if isset(flags, 9) do v.tt = MatteMode(read_enum(reader, MATTE_MODE_BITS) or_return)
  if isset(flags, 10) do v.tp = i64(read_varint(reader) or_return)

  if isset(flags, 11) {
    no_of_masks := read_varint(reader) or_return
    masks := make([]Mask, no_of_masks, reader.allocator)
    for i in 0..<no_of_masks {
      masks[i] = read_mask(reader) or_return
    }
    v.masksProperties = masks

  }

  v._flags = transmute(u64)flags
  return v, .None
}

read_solid_layer :: proc(reader: ^Reader) -> (v: SolidLayer, err: ReaderError) {
  flags := read_flags(reader, SOLID_LAYER_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  if isset(flags, 3) do v.ind = i64(read_varint(reader) or_return)
  if isset(flags, 4) do v.parent = i64(read_varint(reader) or_return)
  if isset(flags, 5) do v.ip = i64(read_varint(reader) or_return)
  if isset(flags, 6) do v.op = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ks = read_transform(reader) or_return
  if isset(flags, 8) do v.ao = i64(read_varint(reader) or_return)
  if isset(flags, 9) do v.tt = MatteMode(read_enum(reader, MATTE_MODE_BITS) or_return)
  if isset(flags, 10) do v.tp = i64(read_varint(reader) or_return)

  if isset(flags, 11) {
    no_of_masks := read_varint(reader) or_return
    masks := make([]Mask, no_of_masks, reader.allocator)
    for i in 0..<no_of_masks {
      masks[i] = read_mask(reader) or_return
    }
    v.masksProperties = masks
  }

  if isset(flags, 12) do v.sw = i64(read_varint(reader) or_return)
  if isset(flags, 13) do v.sh = i64(read_varint(reader) or_return)
  if isset(flags, 14) do v.sc = read_hexcolor(reader) or_return

  v._flags = transmute(u64)flags
  return v, .None
}

read_precomp_layer :: proc(reader: ^Reader) -> (v: PrecompLayer, err: ReaderError) {
  flags := read_flags(reader, PRECOMP_LAYER_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.hd = read_bool(reader) or_return
  if isset(flags, 3) do v.ind = i64(read_varint(reader) or_return)
  if isset(flags, 4) do v.parent = i64(read_varint(reader) or_return)
  if isset(flags, 5) do v.ip = i64(read_varint(reader) or_return)
  if isset(flags, 6) do v.op = i64(read_varint(reader) or_return)
  if isset(flags, 7) do v.ks = read_transform(reader) or_return
  if isset(flags, 8) do v.ao = i64(read_varint(reader) or_return)
  if isset(flags, 9) do v.tt = MatteMode(read_enum(reader, MATTE_MODE_BITS) or_return)
  if isset(flags, 10) do v.tp = i64(read_varint(reader) or_return)

  if isset(flags, 11) {
    no_of_masks := read_varint(reader) or_return
    masks := make([]Mask, no_of_masks, reader.allocator)
    for i in 0..<no_of_masks {
      masks[i] = read_mask(reader) or_return
    }
    v.masksProperties = masks
  }

  if isset(flags, 12) do v.refId = read_string(reader) or_return
  if isset(flags, 13) do v.w = i64(read_varint(reader) or_return)
  if isset(flags, 14) do v.h = i64(read_varint(reader) or_return)
  if isset(flags, 15) do v.sr = i64(read_varint(reader) or_return)
  if isset(flags, 16) do v.st = i64(read_varint(reader) or_return)

  v._flags = transmute(u64)flags
  return v, .None
}

read_layer :: proc(reader: ^Reader) -> (v: Layer, err: ReaderError) {
  layer_type := LayerType(read_enum(reader, LAYER_TYPE_BITS) or_return)
  
  switch layer_type {
  case .PrecompLayer:
    v1 := read_precomp_layer(reader) or_return
    v1.ty = .PrecompLayer
    v = v1
  case .ImageLayer:
    v1 := read_image_layer(reader) or_return
    v1.ty = .ImageLayer
    v = v1
  case .NullLayer:
    v1 := read_null_layer(reader) or_return
    v1.ty = .NullLayer
    v = v1
  case .SoildLayer:
    v1 := read_solid_layer(reader) or_return
    v1.ty = .SoildLayer
    v = v1
  case .ShapeLayer:
    v1 := read_shape_layer(reader) or_return
    v1.ty = .ShapeLayer
    v = v1
  case:
    return v, .InvalidLayerType
  }
  
  return v, .None
}

read_precomp_asset :: proc(reader: ^Reader) -> (v: PrecompAsset, err: ReaderError) {
  flags := read_flags(reader, PRECOMP_ASSET_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.id = read_string(reader) or_return
  if isset(flags, 2) {
    no_of_layers := read_varint(reader) or_return
    layers := make([]Layer, no_of_layers, reader.allocator)
    for i in 0..<no_of_layers {
      layers[i] = read_layer(reader) or_return
    }
    v.layers = layers
  }

  v._flags = transmute(u64)flags
  return v, .None
}

read_image_asset :: proc(reader: ^Reader) -> (v: ImageAsset, err: ReaderError) {
  flags := read_flags(reader, IMAGE_ASSET_FIELDS) or_return
  if isset(flags, 0) do v.nm = read_string(reader) or_return
  if isset(flags, 1) do v.id = read_string(reader) or_return
  if isset(flags, 2) do v.sid = read_string(reader) or_return
  if isset(flags, 3) do v.w = i64(read_uint32(reader) or_return)
  if isset(flags, 4) do v.h = i64(read_uint32(reader) or_return)
  if isset(flags, 5) do v.p = read_string(reader) or_return
  if isset(flags, 6) do v.u = read_string(reader) or_return
  if isset(flags, 7) do v.e = i64(read_bool(reader) or_return)

  v._flags = transmute(u64)flags
  return v, .None
}

read_asset :: proc(reader: ^Reader) -> (v: Asset, err: ReaderError) {
  asset_type := AssetType(read_enum(reader, ASSET_TYPE_BITS) or_return)
  if asset_type == .PrecompAsset {
    v = read_precomp_asset(reader) or_return
  } else if  asset_type == .ImageAsset {
    v = read_image_asset(reader) or_return
  } else {
    return v, .InvalidAssetType
  }

  return v, .None
}

read_animation :: proc(reader: ^Reader) -> (v: Animation, err: ReaderError) {
  v.nm = read_string(reader) or_return
  v.ver = i64(read_varint(reader) or_return)
  v.fr = i64(read_varint(reader) or_return)
  v.ip = i64(read_varint(reader) or_return)
  v.op = i64(read_varint(reader) or_return)
  v.w = i64(read_varint(reader) or_return)
  v.h = i64(read_varint(reader) or_return)

  no_of_layers := i64(read_varint(reader) or_return)
  layers := make([]Layer, no_of_layers, reader.allocator)
  for i in 0..<no_of_layers {
    layers[i] = read_layer(reader) or_return
  }
  v.layers = layers

  no_of_assets := read_varint(reader) or_return
  assets := make([]Asset, no_of_assets, reader.allocator)
  for i in 0..<no_of_assets {
    assets[i] = read_asset(reader) or_return
  }
  v.assets = assets

  no_of_markers := read_varint(reader) or_return
  markers := make([]Marker, no_of_markers, reader.allocator)
  for i in 0..<no_of_markers {
    // TODO:
  }
  v.markers = markers

  return v, .None
}