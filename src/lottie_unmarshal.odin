package main

import "base:runtime"
import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:reflect"
import "base:intrinsics"

// This file contains procedures which are used
// to take json values and convert them or unmarshal
// them into lottie structs as best as possible


_parse_enum_internal :: proc(
  value: json.Value,
  loc := #caller_location,
) -> (
  i64,
  JL_Error,
) {
  #partial switch elem_type in value {
  case json.Float:
    return i64(value.(json.Float)), .None
  case json.Integer:
    return i64(value.(json.Integer)), .None
  case json.String:
  {
    str := value.(json.String)
    if len(str) == 1 {
      return i64(str[0]), .None
    } else {
      return 0, .Incompatible_Enum_Type
    }
  }
  case:
    return 0, .Incompatible_Enum_Type
  }
}

// Takes a json value and try to convert it into
// a primitive type given in `p`. Can support converting
// arbitary values into enum values if possible
unmarshal_value :: proc(
  val: json.Value,
  p: any,
  allocator := context.allocator,
  loc := #caller_location,
) -> (
  err: JL_Error,
) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  #partial switch t in type_info.variant {
  case runtime.Type_Info_String:
  {
    val := parse_string(val) or_return
    field_val_ptr := transmute(^string)ptr
    field_val_ptr^ = val
  }
  case runtime.Type_Info_Boolean:
  {
    val := parse_bool(val) or_return
    field_val_ptr := transmute(^bool)ptr
    field_val_ptr^ = val
  }
  case runtime.Type_Info_Float:
  {
    val := parse_number(val) or_return
    field_val_ptr := transmute(^f64)ptr
    field_val_ptr^ = val
  }
  case runtime.Type_Info_Integer:
  {
    val := parse_integer(val) or_return
    field_val_ptr := transmute(^i64)ptr
    field_val_ptr^ = val
  }
  case runtime.Type_Info_Enum:
  {
    // note(iyaan): Internally odin treats the enum value
    // as an i64 by default. The internal backing type can
    // be found from Type_Info_Enum (t) t.base. Ofcourse have
    // to make sure whatever json value we are receiving does
    // not exceed the size limits of the backing type
    val, enum_parse_err := _parse_enum_internal(val)
    if enum_parse_err != .None {
      log.fatalf("could not parse enum")
    }
    val_in_enum := false
    for enum_val in t.values {
      if val == i64(enum_val) {
        mem.copy(ptr, &val, t.base.size)
        val_in_enum = true
      }
    }

    if !val_in_enum {
      return .Unmarshal_Out_Of_Bound_Enum_Value
    }
  }
  case:
  {
    log.fatalf("unknown type: %v, called from %v", t, loc)
    return .Unmarshal_Unknown_Value_Type
  }
  }
  return .None
}

unmarshal_array :: proc(
  val: json.Value,
  p: any,
  allocator := context.allocator,
) -> (
  err: JL_Error,
) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data
  
  if _, ok := val.(json.Array); !ok {
    return .Incompatible_Array_Type
  }

  json_array := val.(json.Array)
  json_array_len := len(json_array)

  #partial switch array_type in type_info.variant {
  case runtime.Type_Info_Slice:
  {
    internal_elem_type_info := array_type.elem
    internal_elem_size := internal_elem_type_info.size
    internal_elem_alignment := internal_elem_type_info.align
    raw := (^mem.Raw_Slice)(p.data)

    // note(iyaan): This memory will be tricky to free
    // in a normal heap allocator. Maybe everything related
    // to JsonLottie_* structs should be in one memory space,
    // that will be freed together (arena)
    data, alloc_err := mem.alloc_bytes(
      internal_elem_size * int(json_array_len),
      internal_elem_alignment,
      allocator,
    )

    if alloc_err != .None {
      return .Unmarshal_Allocation_Error
    }

    raw.data = raw_data(data)
    raw.len = int(json_array_len)
    for elem, idx in json_array {
      elem_ptr := rawptr(
        uintptr(raw.data) + uintptr(idx) * uintptr(internal_elem_size),
      )
      elem_any := any{elem_ptr, internal_elem_type_info.id}
      elem_type_base := reflect.type_info_base(
        type_info_of(internal_elem_type_info.id),
      )

      #partial switch base_t in elem_type_base.variant {
      case runtime.Type_Info_Struct, runtime.Type_Info_Union: unmarshal_object(elem, elem_any) or_return
      case runtime.Type_Info_Integer,
           runtime.Type_Info_Float,
           runtime.Type_Info_Boolean,
           runtime.Type_Info_String,
           runtime.Type_Info_Enum: unmarshal_value(elem, elem_any) or_return
      case runtime.Type_Info_Slice, runtime.Type_Info_Array: unmarshal_array(elem, elem_any) or_return
      case:
      {
        if err := delete(data); err != .None {
          return .Unmarshal_Deallocation_Error
        } else {
          return .Unmarshal_Unknown_Array_Inner_Type
        }
      }
      }
    }
    return .None
  }
  case runtime.Type_Info_Array:
  {
    if json_array_len <= array_type.count {
      internal_elem_type_info := array_type.elem
      internal_elem_size := internal_elem_type_info.size
      for elem, idx in json_array {
        elem_ptr := rawptr(
          uintptr(p.data) + uintptr(idx) * uintptr(internal_elem_size),
        )
        elem_any := any{elem_ptr, internal_elem_type_info.id}
        unmarshal_value(elem, elem_any) or_return
      }
    } else {
      return .Too_Large_Vector
    }
  }
  case runtime.Type_Info_Dynamic_Array: 
    return .Unmarshal_Unsupported_Array_Type
  case: 
    return .Unmarshal_Unknown_Array_Type
  }

  return .None
}



_unmarshal_prop_union :: proc(object: json.Object, field_ptr: rawptr, $union_type, $single_variant, $anim_variant: typeid) -> (err: JL_Error){
  animated := parse_bool(object["a"]) or_return
  field_val_ptr := transmute(^union_type)field_ptr
  if animated {
    // note(iyaan): It important to initialize that union field location
    // with its expected type before you set it to the correct
    // variant. This is true for all the cases of this switch statement
    field_val_ptr^ = anim_variant{}
    field_value_any := any{field_ptr, typeid_of(anim_variant)}
    unmarshal_object(object, field_value_any) or_return
  } else {
    field_val_ptr^ = single_variant{}
    field_value_any := any{field_ptr, typeid_of(single_variant)}
    unmarshal_object(object, field_value_any)
  }

  return .None
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

_unmarshal_graphic_elem_internal :: proc(object: json.Object, field_ptr: rawptr, $intern_type: typeid) -> (err: JL_Error) {
  field_val_ptr := transmute(^GraphicElement)field_ptr
  field_val_ptr^ = intern_type{}
  field_value_any := any{field_ptr, typeid_of(intern_type)}
  unmarshal_object(object, field_value_any) or_return
  return .None
}


_unmarshal_graphic_element_union :: proc(object: json.Object, field_ptr: rawptr) -> (err: JL_Error) {
  graphic_elem_type_str := parse_string(object["ty"]) or_return
  // Map the string `type` to an enum
  graphic_elem_type := conv_graphic_elem_type_to_enum(graphic_elem_type_str)
  switch graphic_elem_type {
  case .el: _unmarshal_graphic_elem_internal(object, field_ptr, Ellipse)
  case .fl: _unmarshal_graphic_elem_internal(object, field_ptr, Fill)
  case .gf: _unmarshal_graphic_elem_internal(object, field_ptr, GradientFill)
  case .gs: _unmarshal_graphic_elem_internal(object, field_ptr, GradientStroke)
  case .gr: _unmarshal_graphic_elem_internal(object, field_ptr, Group)
  case .sh: _unmarshal_graphic_elem_internal(object, field_ptr, Path)
  case .sr: _unmarshal_graphic_elem_internal(object, field_ptr, Polystar)
  case .rc: _unmarshal_graphic_elem_internal(object, field_ptr, Rectangle)
  case .st: _unmarshal_graphic_elem_internal(object, field_ptr, Stroke)
  case .tr: _unmarshal_graphic_elem_internal(object, field_ptr, TransformShape)
  case .tm: _unmarshal_graphic_elem_internal(object, field_ptr, TrimPath)
  case .Error:
    panic("unknown graphic element type")
  }

  return .None
}

unmarshal_object :: proc(
  val: json.Value,
  p: any,
  allocator := context.allocator,
) -> (
  err: JL_Error,
) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  if _, ok := type_info.variant.(reflect.Type_Info_Struct); !ok {
    return .Incompatible_Object_Type
  }

  if _, ok := val.(json.Object); !ok {
    return .Incompatible_Object_Type
  }

  fields := reflect.struct_fields_zipped(p.id)
  json_obj := val.(json.Object)
  flags : Bit64
  flags_field_exists: = false
  flags_field_ptr : rawptr
  for field, idx in fields {
    field_type_as_base := reflect.type_info_base(field.type)
    field_ptr := rawptr(uintptr(p.data) + field.offset)
    if field.name == "_flags" {
      flags_field_exists = true
      flags_field_ptr = field_ptr
      continue
    }
    if _, field_exists := json_obj[field.name]; field_exists {
      flags += {idx}
    }
    
    field_value_any := any{field_ptr, field.type.id}
    #partial switch struct_type in field_type_as_base.variant {
    case runtime.Type_Info_Integer,
         runtime.Type_Info_Float,
         runtime.Type_Info_String,
         runtime.Type_Info_Boolean,
         runtime.Type_Info_Enum:   unmarshal_value(json_obj[field.name], field_value_any) or_return
    case runtime.Type_Info_Dynamic_Array,
         runtime.Type_Info_Array,
         runtime.Type_Info_Slice : unmarshal_array(json_obj[field.name], field_value_any) or_return
    case runtime.Type_Info_Struct: unmarshal_object(json_obj[field.name], field_value_any) or_return
    case runtime.Type_Info_Union:
    {
      if _, ok := json_obj[field.name].(json.Object); !ok {
        continue
      }
      object := json_obj[field.name].(json.Object)
      switch field.type.id {
      case PropScalar:     _unmarshal_prop_union(object, field_ptr, PropScalar, PropScalarSingle, PropScalarAnim)
      case PropVector:     _unmarshal_prop_union(object, field_ptr, PropVector, PropVectorSingle, PropVectorAnim)
      case PropBezier:     _unmarshal_prop_union(object, field_ptr, PropBezier, PropBezierSingle, PropBezierAnim)
      case PropPosition:   _unmarshal_prop_union(object, field_ptr, PropPosition, PropPositionSingle, PropPositionAnim)
      case PropColor:      _unmarshal_prop_union(object, field_ptr, PropColor, PropColorSingle, PropColorAnim)
      case GradientStop:   _unmarshal_prop_union(object, field_ptr, GradientStop, GradientStopSingle, GradientStopAnim)
      case GraphicElement: _unmarshal_graphic_element_union(object, field_ptr)
      case:
        log.fatalf("unknown union type encountered for field = %v, type = %v", field.name, field.type.id)
      }
    } 
    case:
      return .Unmarshal_Unknown_Struct_Field_Type
    }
  }
  // Set the flags of the struct as a mask
  // which will tell which fields of the struct
  // were set
  if flags_field_exists {
    field_val_ptr := transmute(^Bit64)flags_field_ptr
    field_val_ptr^ = flags
  }
  return .None
}
