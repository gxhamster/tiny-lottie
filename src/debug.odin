package main

import str "core:strings"
import "core:math/bits"
import "core:encoding/hex"
import "core:log"
import "core:slice"


gen_html :: proc(writer: ^Writer, allocator := context.allocator) {
  infos := writer.debug
  end_tag_idxs := make([dynamic]int, 0, len(infos))
  builder := str.builder_make(allocator = allocator)
  for info, cur_idx in infos {
    if info.end_idx != cur_idx {
      append(&end_tag_idxs, info.end_idx)
    }   
    gen_html_for_info(&builder, info, writer)

    // Insert closing tags for all those that need closing
    for {
      found_idx, found := slice.linear_search(end_tag_idxs[:], cur_idx)
      if found {
        str.write_string(&builder, "</div></div>") 
        unordered_remove(&end_tag_idxs, found_idx)
      } else {
        break
      }
    }
  }

  log.debug(str.to_string(builder))
  delete(end_tag_idxs)
}

gen_html_for_info :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, allocator := context.allocator) {
  gen_prim_div_tag_for_type :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, class_name: string, $T: typeid, allocator := context.temp_allocator) {
    str.write_string(builder, "<div class=\"")
    str.write_string(builder, class_name)
    str.write_string(builder, "\">")
    ptr := cast(^int)raw_data(writer.data[info.start_byte:])
    count := info.end_bit - info.start_bit
    int_val := bits.bitfield_extract_int(ptr^, info.start_bit, count)
    // Kinda hacky but its ok -_-
    T_val_bytes := transmute([size_of(T)]byte)((^T)(&int_val))^
    hexes := hex.encode(T_val_bytes[:], allocator)
    for b, idx in hexes {
      str.write_byte(builder, b)
      if idx != len(hexes) - 1 do str.write_string(builder, " ")
    }
    str.write_string(builder, "</div>")
  }

  switch info.type {
  case .meta:
  {
    str.write_string(builder, "<div class=\"meta\">")
    str.write_string(builder, "<div class=\"meta_title\">")
    str.write_string(builder, info.name)
    str.write_string(builder, "</div>")
    str.write_string(builder, "<div class=\"meta_content\">")
    // note(iyaan): Remeber that closing </div> needs to be inserted
    // after all the child debug info has been written
  }
  case .flags:
  {
    str.write_string(builder, "<div class=\"flags\">")
    ptr := cast(^int)raw_data(writer.data[info.start_byte:])
    flag_bits := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
    flags := bits.bitfield_extract_int(ptr^, info.start_bit, uint(flag_bits))
    flags_bitset := transmute(Bit64)flags
    for bit in 0..<flag_bits {
      if int(bit) in flags_bitset {
        str.write_string(builder, "<span>")
        str.write_int(builder, 1)   
        str.write_string(builder, "</span>")
      } else {
        str.write_string(builder, "<span>")
        str.write_int(builder, 0)   
        str.write_string(builder, "</span>")
      }
    }
    str.write_string(builder, "</div>") 
  }
  case .f16:
    gen_prim_div_tag_for_type(builder, info, writer, "float16", f16)
  case .f32:
    gen_prim_div_tag_for_type(builder, info, writer, "float32", f32)
  case .f64:
    gen_prim_div_tag_for_type(builder, info, writer, "float64", f64)
  case .i8:
    gen_prim_div_tag_for_type(builder, info, writer, "int8", i8)
  case .i16:
    gen_prim_div_tag_for_type(builder, info, writer, "int16", i16)
  case .i32:
    gen_prim_div_tag_for_type(builder, info, writer, "int32", i32)
  case .i64:
    gen_prim_div_tag_for_type(builder, info, writer, "int64", i64)
  case .u8:
    gen_prim_div_tag_for_type(builder, info, writer, "uint8", u8)
  case .u16:
    gen_prim_div_tag_for_type(builder, info, writer, "uint16", u16)
  case .u32:
    gen_prim_div_tag_for_type(builder, info, writer, "uint32", u32)
  case .u64:
    gen_prim_div_tag_for_type(builder, info, writer, "uint64", u64)
  case .varint:
  case .bool:
    gen_prim_div_tag_for_type(builder, info, writer, "bool", bool)
  case .string:
  {

  }
  case .Enum:
  case:

  }

}
