package main

import "core:math/bits"
import "core:log"
import "core:testing"

Reader :: struct {
  data: []byte,
  cur_offset: int,
  cur_bits: uint,
  end_offset: int,  // end_offset and end_bits is the byte and bit offset
  end_bits: uint    // at which the writer was at the moment
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
reader_from_writer :: proc(writer: ^Writer) -> Reader {
  reader := Reader{}
  reader.data = writer.data
  reader.end_bits = writer.bits
  reader.end_offset = writer.offset
  reader.cur_bits = 0
  reader.cur_offset = 0

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

  return reader
}

@(test)
read_bits_test :: proc(t: ^testing.T) {
  writer := Writer{}
  writer_init(&writer)
  write_color4(&writer, Color4{1,2,3,4})

  reader := reader_from_writer(&writer)
  v1, r1, e1 := read_bits(&reader, 2)
  v2, r2, e2 := read_bits(&reader, 8)
  v3, r3, e3 := read_bits(&reader, 8)
  v4, r4, e4 := read_bits(&reader, 8)
  v5, r5, e5 := read_bits(&reader, 8)
  testing.expect(t, v1 == 0 && v2 == 1 && v3 == 2 && v4 == 3 && v5 == 4, "not expected color values")
}

ReaderError :: enum {
  None,
  OutofBoundsRead,
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
