package main

import str "core:strings"
import "core:math/bits"
import "core:encoding/hex"
import "core:encoding/endian"
import "core:log"
import "core:slice"
import "core:os"


gen_html_alt :: proc(writer: ^Writer, allocator := context.allocator) -> str.Builder {
  infos := writer.debug
  builder := str.builder_make(allocator = allocator)
  end_tag_idxs := make([dynamic]int, 0, len(infos))
  start_tag_idxs := make([dynamic]int, 0, len(infos))

  // Add the styles and preamble
  str.write_string(&builder, INJECTED_HTML_HEADER_ALT)

  for info, cur_idx in infos {
    if info.end_idx != cur_idx {
      append(&end_tag_idxs, info.end_idx)
      append(&start_tag_idxs, cur_idx)
    }   
    gen_html_for_info_alt(&builder, info, writer, cur_idx, allocator)

    // Insert the closing meta identifier
    for {
      found_idx, found := slice.linear_search_reverse(end_tag_idxs[:], cur_idx)
      if found {
        str.write_string(&builder, "<div class=\"meta_closing\">") 
        start_idx := start_tag_idxs[found_idx]
        str.write_string(&builder, infos[start_idx].name)
        str.write_string(&builder, " (")
        str.write_int(&builder, start_idx)
        str.write_string(&builder, ")")
        str.write_string(&builder, "</div>") 

        unordered_remove(&end_tag_idxs, found_idx)
        unordered_remove(&start_tag_idxs, found_idx)
      } else {
        break
      }
    }
  }

  str.write_string(&builder, "</div></body></html>")
  delete(end_tag_idxs)
  return builder
}


gen_html :: proc(writer: ^Writer, allocator := context.allocator) -> str.Builder {
  infos := writer.debug
  end_tag_idxs := make([dynamic]int, 0, len(infos))
  builder := str.builder_make(allocator = allocator)

  // Add the styles and preamble
  str.write_string(&builder, INJECTED_HTML_HEADER)

  for info, cur_idx in infos {
    if info.end_idx != cur_idx {
      append(&end_tag_idxs, info.end_idx)
    }   
    gen_html_for_info(&builder, info, writer, allocator)

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

  str.write_string(&builder, "</body></html>")
  delete(end_tag_idxs)
  return builder
}

gen_prim_div_tag_for_type :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, class_name: string, $T: typeid, allocator := context.temp_allocator) {
  count := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
  str.write_string(builder, "<div class=\"")
  str.write_string(builder, class_name)
  str.write_string(builder, "\" title=\"")
  str.write_int(builder, count)
  str.write_string(builder, " bits\">")
  ptr := cast(^int)raw_data(writer.data[info.start_byte:])
  assert(count > 0, "count of bits is probably incorrect")
  int_val := bits.bitfield_extract_int(ptr^, info.start_bit, uint(count))

  // TODO(iyaan): For display purposes I think big-endian is nicer
  // maybe I should make this configurable
  MAX_BYTE_BUF_SIZE :: size_of(u64)
  T_val_bytes := [MAX_BYTE_BUF_SIZE]byte{}
  ok := endian.put_u64(T_val_bytes[:], .Big, u64(int_val))
  range_start := MAX_BYTE_BUF_SIZE - size_of(T)
  hexes := hex.encode(T_val_bytes[range_start:], allocator)

  if len(hexes) <= 0 || len(hexes) % 2 != 0 {
    panic("cannot output hex string to html")
  }
  for idx := 0; idx < len(hexes); idx += 2 {
    str.write_byte(builder, hexes[idx])
    str.write_byte(builder, hexes[idx + 1])
    if idx + 1 != len(hexes) - 1 do str.write_string(builder, " ")
  }
  str.write_string(builder, "</div>")
}

// For types such as varint or strings which have byte sequences
gen_html_for_byte_sequence_types :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, class_name: string, allocator := context.temp_allocator) {
  count := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
  bit_offset := info.start_bit
  str.write_string(builder, "<div class=\"")
  str.write_string(builder, class_name)
  str.write_string(builder, "\" title=\"")
  str.write_int(builder, count)
  str.write_string(builder, " bits\">")

  end := int(count / BYTE_BITS)
  for cur_byte := 0; cur_byte < end; cur_byte += 1 {
    ptr := cast(^int)raw_data(writer.data[info.start_byte + cur_byte:])
    int_val := bits.bitfield_extract_int(ptr^, bit_offset, BYTE_BITS)
    varint_bytes := [?]byte{byte(int_val)}
    hexes := hex.encode(varint_bytes[:], context.temp_allocator)
    
    assert(len(hexes) == 2, "one byte has two hex characters")
    str.write_byte(builder, hexes[0])
    str.write_byte(builder, hexes[1])
    
    if cur_byte < end - 1 do str.write_string(builder, " ")
  }
  str.write_string(builder, "</div>")
}

gen_html_for_enum :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer) {
  ptr := cast(^int)raw_data(writer.data[info.start_byte:])
  enum_bits := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
  str.write_string(builder, "<div class=\"enum\"")
  str.write_string(builder, " title=\"")
  str.write_int(builder, enum_bits)
  str.write_string(builder, " bits\">")
  enum_val := bits.bitfield_extract_int(ptr^, info.start_bit, uint(enum_bits))
  enum_bitset := transmute(Bit64)enum_val
  for bit in 0..<enum_bits {
    str.write_string(builder, "<span>")
    if int(bit) in enum_bitset {
      str.write_int(builder, 1)   
    } else {
      str.write_int(builder, 0)   
    }
    str.write_string(builder, "</span>")
  }
  str.write_string(builder, "</div>") 
}

gen_html_for_bool :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer) {
  ptr := cast(^byte)raw_data(writer.data[info.start_byte:])
  bool_bits := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
  str.write_string(builder, "<div class=\"bool\"")
  str.write_string(builder, " title=\"")
  str.write_int(builder, bool_bits)
  str.write_string(builder, " bits\">")
  bool_val := bits.bitfield_extract_u8(ptr^, info.start_bit, uint(bool_bits))
  assert(bool_val == 0 || bool_val == 1, "bool has only two possibiilites")
  assert(bool_bits == 1, "why is a bool more than 1 bit") 
  str.write_int(builder, int(bool_val))
  str.write_string(builder, "</div>") 
}

gen_html_for_info_alt :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, debug_count: int, allocator := context.allocator) {
  #partial switch info.type {
  case .meta:
  {
    // note(iyaan): Wull only change the meta type rendering
    // others are just the same

    str.write_string(builder, "<div class=\"meta\">")
    str.write_string(builder, "<span class=\"bit_count\">")
    str.write_int(builder, calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit))
    str.write_string(builder, " bits</span>")
    str.write_string(builder, info.name)
    str.write_string(builder, " (")
    str.write_int(builder, debug_count)
    str.write_string(builder, ")")
    str.write_string(builder, "</div>")
  }
  case:
    gen_html_for_info(builder, info, writer, allocator)
  } 
}

gen_html_for_info :: proc(builder: ^str.Builder, info: DebugInfo, writer: ^Writer, allocator := context.allocator) {

  switch info.type {
  case .meta:
  {
    bits := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
    str.write_string(builder, "<div class=\"meta\"")
    str.write_string(builder, " title=\"")
    str.write_int(builder, bits)
    str.write_string(builder, " bits\">")
    str.write_string(builder, "<div class=\"meta_title\">")
    str.write_string(builder, "<span>")
    str.write_string(builder, info.name)
    str.write_string(builder, "</span>")
    str.write_string(builder, "<span class=\"bit_count\">")
    str.write_int(builder, bits)
    str.write_string(builder, " bits</span>")
    str.write_string(builder, "</div>")
    str.write_string(builder, "<div class=\"meta_content\">")
    // note(iyaan): Remeber that closing </div> needs to be inserted
    // after all the child debug info has been written
  }
  case .flags:
  {
    ptr := cast(^int)raw_data(writer.data[info.start_byte:])
    flag_bits := calc_bits_from(info.start_byte, info.end_byte, info.start_bit, info.end_bit)
    str.write_string(builder, "<div class=\"flags\"")
    str.write_string(builder, " title=\"")
    str.write_int(builder, flag_bits)
    str.write_string(builder, " bits\">")
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
  case .f16:    gen_prim_div_tag_for_type(builder, info, writer, "float16", f16)
  case .f32:    gen_prim_div_tag_for_type(builder, info, writer, "float32", f32)
  case .f64:    gen_prim_div_tag_for_type(builder, info, writer, "float64", f64)
  case .i8:     gen_prim_div_tag_for_type(builder, info, writer, "int8", i8)
  case .i16:    gen_prim_div_tag_for_type(builder, info, writer, "int16", i16)
  case .i32:    gen_prim_div_tag_for_type(builder, info, writer, "int32", i32)
  case .i64:    gen_prim_div_tag_for_type(builder, info, writer, "int64", i64)
  case .u8:     gen_prim_div_tag_for_type(builder, info, writer, "uint8", u8)
  case .u16:    gen_prim_div_tag_for_type(builder, info, writer, "uint16", u16)
  case .u32:    gen_prim_div_tag_for_type(builder, info, writer, "uint32", u32)
  case .u64:    gen_prim_div_tag_for_type(builder, info, writer, "uint64", u64)
  case .bool:   gen_html_for_bool(builder, info, writer)
  case .varint: gen_html_for_byte_sequence_types(builder, info, writer, "varint") 
  case .string: gen_html_for_byte_sequence_types(builder, info, writer, "string") 
  case .Enum:   gen_html_for_enum(builder, info, writer)
  case:

  }
}

INJECTED_HTML_HEADER :: `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tiny Lottie Debug Export</title>
  <link rel="stylesheet" href="style.css">
  <style>
    :root {
      --meta-padding: 0.5em;
      --meta-background-color: #FFFDF5;
      
      --type-text-bottom: -1.1em;
      --type-text-right:  0.5em;
        
      --prim-height: 35px;
      --float16-background: #ffbbc2;
      --float32-background: #bc99f9;
      --float64-background: #d791fd;
      --uint8-background:   #fb95cd;
      --uint16-background:  #FCB6C1;
      --uint32-background:  #fcb0ab;
      --uint64-background:  #fabca1;
      --int8-background:    #fcc494;
      --int16-background:   #fccf85;
      --int32-background:   #fdee74;
      --int64-background:   #CBDEA3;
      --flags-background:   #eeffc6;
      --bool-background:    #ebf577;
      --string-background:  #b4acf8;
      --enum-background:    #DEADB2;
      --varint-background:  #DEADB2;

      --float16-border-color: red;
      --float32-border-color: #520ccd;
      --float64-border-color: #8504cc;
      --uint8-border-color:   #CA0872;
      --uint16-border-color:  #F62E4C;
      --uint32-border-color:  #F7271A;
      --uint64-border-color:  #E44D0C;
      --int8-border-color:    #F98B2C;
      --int16-border-color:   #F9A51A;
      --int32-border-color:   #D4BD03;
      --int64-border-color:   #84A83B;
      --flags-border-color:   #2a3b00;
      --bool-border-color:    #9CA80C;
      --string-border-color:  #2110b6;
      --enum-border-color:    #BD5C66;
      --varint-border-color:  #BD5C66;
    }
    body {
      font-family: 'Courier New', monospace;
    }

    #root {
      padding: 2em;
      display: flex;
      max-width: 100vw;
      gap: 25px;
      flex-wrap: wrap;
    }

    .meta_content {
      display: flex;
      gap: 20px 10px;
      flex-wrap: wrap;
    }
    .meta_title {
      text-transform: uppercase;
      display: flex;
      letter-spacing: 1px;
      gap: 2em;
      justify-content: space-between;
      margin-bottom: 1px;
    }
    .meta_title .bit_count {
      text-transform: uppercase;
      font-size: x-small;
      font-weight: bold;
    }
    .meta {
      align-self: flex-start;
      position: relative;
      background-color: var(--meta-background-color);
      display: flex;
      flex-direction: column;
      padding: var(--meta-padding);
      border: 3.0px solid #575349;
    }

    .varint {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      min-width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--varint-border-color);
      text-transform: lowercase;
      background-color: var(--varint-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .varint::after {
      content: "varint";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .flags {
      text-align: center;
      position: relative;
      padding: 0.5em;
      height: var(--prim-height);
      border: 3px solid var(--flags-border-color);
      background-color: var(--flags-background);
      display: flex;
      gap: 15px;
      line-height: var(--prim-height);
      font-size: large;
    }
    .flags::after {
      content: "flags";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .enum {
      text-align: center;
      position: relative;
      padding: 0.5em;
      height: var(--prim-height);
      border: 3px solid var(--enum-border-color);
      background-color: var(--enum-background);
      min-width: var(--prim-height);
      display: flex;
      justify-content: center;
      gap: 5px;
      line-height: var(--prim-height);
      font-size: large;
    }
    .enum::after {
      content: "enum";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float16-border-color);
      text-transform: lowercase;
      background-color: var(--float16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float16::after {
      content: "f16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float32 {
      padding: 0.5em;
      position: relative;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float32-border-color);
      text-transform: lowercase;
      background-color: var(--float32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float32::after {
      content: "f32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float64 {
      padding: 0.5em;
      position: relative;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float64-border-color);
      text-transform: lowercase;
      background-color: var(--float64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float64::after {
      content: "f64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint8 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint8-border-color);
      text-transform: lowercase;
      background-color: var(--uint8-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint8::after {
      content: "u8";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint16-border-color);
      text-transform: lowercase;
      background-color: var(--uint16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint16::after {
      content: "u16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint32 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint32-border-color);
      text-transform: lowercase;
      background-color: var(--uint32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint32::after {
      content: "u32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint64 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint64-border-color);
      text-transform: lowercase;
      background-color: var(--uint64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint64::after {
      content: "u64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int8 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int8-border-color);
      text-transform: lowercase;
      background-color: var(--int8-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int8::after {
      content: "i8";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int16-border-color);
      text-transform: lowercase;
      background-color: var(--int16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int16::after {
      content: "i16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int32 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int32-border-color);
      text-transform: lowercase;
      background-color: var(--int32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int32::after {
      content: "i32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int64 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int64-border-color);
      text-transform: lowercase;
      background-color: var(--int64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int64::after {
      content: "i64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }
    .bool {
      padding: 0.5em;
      position: relative;
      text-align: center;
      height: var(--prim-height);
      line-height: var(--prim-height);
      width: var(--prim-height);
      border: 3px solid var(--bool-border-color);
      background-color: var(--bool-background);
      font-size: large;
    }
    .bool::after {
      content: "bool";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .string {
      padding: 0.5em;
      position: relative;
      text-align: left;
      line-height: var(--prim-height);
      min-height: var(--prim-height);
      border: 3px solid var(--string-border-color);
      background-color: var(--string-background);
      font-size: large;
    }
    .string::after {
      content: "string";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

  </style>
</head>
<body>
`

INJECTED_HTML_HEADER_ALT :: `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tiny Lottie Debug Export</title>
  <link rel="stylesheet" href="style.css">
  <style>
    :root {
      --meta-padding: 0.5em;
      --meta-background-color: #FFFDF5;
      
      --type-text-bottom: -1.1em;
      --type-text-right:  0.5em;
        
      --prim-height: 35px;
      --float16-background: #ffbbc2;
      --float32-background: #bc99f9;
      --float64-background: #d791fd;
      --uint8-background:   #fb95cd;
      --uint16-background:  #FCB6C1;
      --uint32-background:  #fcb0ab;
      --uint64-background:  #fabca1;
      --int8-background:    #fcc494;
      --int16-background:   #fccf85;
      --int32-background:   #fdee74;
      --int64-background:   #CBDEA3;
      --flags-background:   #eeffc6;
      --bool-background:    #ebf577;
      --string-background:  #b4acf8;
      --enum-background:    #DEADB2;
      --varint-background:  #DEADB2;

      --float16-border-color: red;
      --float32-border-color: #520ccd;
      --float64-border-color: #8504cc;
      --uint8-border-color:   #CA0872;
      --uint16-border-color:  #F62E4C;
      --uint32-border-color:  #F7271A;
      --uint64-border-color:  #E44D0C;
      --int8-border-color:    #F98B2C;
      --int16-border-color:   #F9A51A;
      --int32-border-color:   #D4BD03;
      --int64-border-color:   #84A83B;
      --flags-border-color:   #2a3b00;
      --bool-border-color:    #9CA80C;
      --string-border-color:  #2110b6;
      --enum-border-color:    #BD5C66;
      --varint-border-color:  #BD5C66;
    }
    body {
      font-family: 'Courier New', monospace;
    }

    #root {
      padding: 2em;
      display: flex;
      max-width: 100vw;
      gap: 10px;
      flex-wrap: wrap;
    }

    .bit_count {
      text-transform: uppercase;
      font-size: x-small;
      font-weight: bold;
    }
    .meta_closing {
      text-transform: uppercase;
      text-align: center;
      position: relative;
      background-color: var(--meta-background-color);
      display: flex;
      height: var(--prim-height);
      min-width: calc(var(--prim-height) + 2em);
      line-height: var(--prim-height);
      flex-direction: column;
      padding: 0.5em;
      font-size: large;
      border: 3.0px solid #575349;
    }
    .meta_closing::after {
      content: "end";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }
    .meta {
      text-transform: uppercase;
      text-align: center;
      position: relative;
      background-color: var(--meta-background-color);
      display: flex;
      height: var(--prim-height);
      min-width: calc(var(--prim-height) + 2em);
      flex-direction: column;
      padding: 0.5em;
      font-size: large;
      border: 3.0px solid #575349;
    }
    .meta::after {
      content: "start";
      font-size: x-small;
      position: absolute;
      bottom: 0px;
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .varint {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      min-width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--varint-border-color);
      text-transform: lowercase;
      background-color: var(--varint-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .varint::after {
      content: "varint";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .flags {
      text-align: center;
      position: relative;
      padding: 0.5em;
      height: var(--prim-height);
      border: 3px solid var(--flags-border-color);
      background-color: var(--flags-background);
      display: flex;
      gap: 15px;
      line-height: var(--prim-height);
      font-size: large;
    }
    .flags::after {
      content: "flags";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .enum {
      text-align: center;
      position: relative;
      padding: 0.5em;
      height: var(--prim-height);
      border: 3px solid var(--enum-border-color);
      background-color: var(--enum-background);
      min-width: var(--prim-height);
      display: flex;
      justify-content: center;
      gap: 5px;
      line-height: var(--prim-height);
      font-size: large;
    }
    .enum::after {
      content: "enum";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float16-border-color);
      text-transform: lowercase;
      background-color: var(--float16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float16::after {
      content: "f16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float32 {
      padding: 0.5em;
      position: relative;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float32-border-color);
      text-transform: lowercase;
      background-color: var(--float32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float32::after {
      content: "f32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .float64 {
      padding: 0.5em;
      position: relative;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--float64-border-color);
      text-transform: lowercase;
      background-color: var(--float64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .float64::after {
      content: "f64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint8 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint8-border-color);
      text-transform: lowercase;
      background-color: var(--uint8-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint8::after {
      content: "u8";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint16-border-color);
      text-transform: lowercase;
      background-color: var(--uint16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint16::after {
      content: "u16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint32 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint32-border-color);
      text-transform: lowercase;
      background-color: var(--uint32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint32::after {
      content: "u32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .uint64 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--uint64-border-color);
      text-transform: lowercase;
      background-color: var(--uint64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .uint64::after {
      content: "u64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int8 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      width: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int8-border-color);
      text-transform: lowercase;
      background-color: var(--int8-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int8::after {
      content: "i8";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int16 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int16-border-color);
      text-transform: lowercase;
      background-color: var(--int16-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int16::after {
      content: "i16";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int32 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int32-border-color);
      text-transform: lowercase;
      background-color: var(--int32-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int32::after {
      content: "i32";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .int64 {
      position: relative;
      padding: 0.5em;
      text-align: center;
      line-height: var(--prim-height);
      height: var(--prim-height);
      border: 3px solid var(--int64-border-color);
      text-transform: lowercase;
      background-color: var(--int64-background);
      letter-spacing: -0.5px;
      font-size: large;
    }
    .int64::after {
      content: "i64";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }
    .bool {
      padding: 0.5em;
      position: relative;
      text-align: center;
      height: var(--prim-height);
      line-height: var(--prim-height);
      width: var(--prim-height);
      border: 3px solid var(--bool-border-color);
      background-color: var(--bool-background);
      font-size: large;
    }
    .bool::after {
      content: "bool";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

    .string {
      padding: 0.5em;
      position: relative;
      text-align: left;
      line-height: var(--prim-height);
      min-height: var(--prim-height);
      border: 3px solid var(--string-border-color);
      background-color: var(--string-background);
      font-size: large;
    }
    .string::after {
      content: "string";
      font-size: x-small;
      position: absolute;
      bottom: var(--type-text-bottom);
      font-weight: bold;
      text-transform: uppercase;
      left: var(--type-text-right);
    }

  </style>
</head>
<body>
<div id="root">
`
