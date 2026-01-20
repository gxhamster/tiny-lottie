package main

import "base:runtime"
import "core:encoding/json"
import "core:mem"
import "core:reflect"

// This file contains procedures which are used
// to take json values and convert them or unmarshal
// them into lottie structs as best as possible

unmarshal_value :: proc(
  val: json.Value,
  p: any,
  allocator := context.allocator,
) -> (
  err: JL_Error,
) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  #partial switch t in type_info.variant {
  case runtime.Type_Info_String:
    val := parse_string(val) or_return
    field_val_ptr := transmute(^string)ptr
    field_val_ptr^ = val
  case runtime.Type_Info_Boolean:
    val := parse_bool(val) or_return
    field_val_ptr := transmute(^bool)ptr
    field_val_ptr^ = val
  case runtime.Type_Info_Float:
    val := parse_number(val) or_return
    field_val_ptr := transmute(^f64)ptr
    field_val_ptr^ = val
  case runtime.Type_Info_Integer:
    val := parse_integer(val) or_return
    field_val_ptr := transmute(^i64)ptr
    field_val_ptr^ = val
  case:
    return .Unmarshal_Unknown_Value_Type
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

  #partial switch t in val {
  case json.Array:
    json_array := val.(json.Array)
    json_array_len := len(json_array)

    #partial switch array_type in type_info.variant {
    case runtime.Type_Info_Slice:
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
        case runtime.Type_Info_Struct, runtime.Type_Info_Union:
          unmarshal_object(elem, elem_any) or_return
        case runtime.Type_Info_Integer,
             runtime.Type_Info_Float,
             runtime.Type_Info_Boolean,
             runtime.Type_Info_String:
          unmarshal_value(elem, elem_any) or_return
        case runtime.Type_Info_Slice, runtime.Type_Info_Array:
          unmarshal_array(elem, elem_any) or_return
        case:
          if err := delete(data); err != .None {
            return .Unmarshal_Deallocation_Error
          } else {
            return .Unmarshal_Unknown_Array_Inner_Type
          }
        }
      }
      return .None
    case runtime.Type_Info_Array:
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
    case runtime.Type_Info_Dynamic_Array:
      return .Unmarshal_Unknown_Array_Type
    case:
      return .Unmarshal_Unknown_Array_Type
    }
  case:
    return .Incompatible_Array_Type
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

	if _, ok := type_info.variant.(reflect.Type_Info_Struct); ok {
    fields := reflect.struct_fields_zipped(p.id)

    #partial switch tval in val {
    case json.Object:
      json_obj := val.(json.Object)
      for field in fields {
        field_type_as_base := reflect.type_info_base(field.type)
        field_ptr := rawptr(uintptr(p.data) + field.offset)
        #partial switch struct_type in field_type_as_base.variant {
        case runtime.Type_Info_Integer,
             runtime.Type_Info_Float,
             runtime.Type_Info_String,
             runtime.Type_Info_Boolean:
          field_value_any := any{field_ptr, field.type.id}
          unmarshal_value(
            json_obj[field.name],
            field_value_any,
          ) or_return
        case runtime.Type_Info_Array,
             runtime.Type_Info_Slice,
             runtime.Type_Info_Dynamic_Array:
          field_value_any := any{field_ptr, field.type.id}
          unmarshal_array(
            json_obj[field.name],
            field_value_any,
          ) or_return
        case runtime.Type_Info_Struct:
          field_value_any := any{field_ptr, field.type.id}
          unmarshal_object(
            json_obj[field.name],
            field_value_any,
          ) or_return
        case runtime.Type_Info_Union:
          // TODO(iyaan): Handle some obvious unions (eg: JsonLottie_Prop_Position)
          // Finding a generic way to handle all cases of unions would be too much
          switch field.type.id {
          case PropPosition:
            pos_val := parse_position(
              json_obj[field.name],
            ) or_return
            field_ptr_offset := uintptr(ptr) + field.offset
            field_val_ptr := transmute(^PropPosition)field_ptr_offset
            field_val_ptr^ = pos_val
          case PropScalar:
            scalar_val := parse_prop_scalar(
              json_obj[field.name],
            ) or_return
            field_ptr_offset := uintptr(ptr) + field.offset
            field_val_ptr := transmute(^PropScalar)field_ptr_offset
            field_val_ptr^ = scalar_val
          case PropVector:
            vector_val := parse_prop_vector(
              json_obj[field.name],
            ) or_return
            field_ptr_offset := uintptr(ptr) + field.offset
            field_val_ptr := transmute(^PropVector)field_ptr_offset
            field_val_ptr^ = vector_val
          case PropBezier:
            bezier_val := parse_prop_bezier(
              json_obj[field.name],
            ) or_return
            field_ptr_offset := uintptr(ptr) + field.offset
            field_val_ptr := transmute(^PropBezier)field_ptr_offset
            field_val_ptr^ = bezier_val
          case PropColor:
            color_val := parse_prop_color(
              json_obj[field.name],
            ) or_return
            field_ptr_offset := uintptr(ptr) + field.offset
            field_val_ptr := transmute(^PropColor)field_ptr_offset
            field_val_ptr^ = color_val
          case:
            return .Unmarshal_Unknown_Union_Field_Type
          }

        case:
          return .Unmarshal_Unknown_Struct_Field_Type
        }
      }
      return .None
    case:
      return .Incompatible_Object_Type
    }
  } else {
    return .Incompatible_Object_Type
	}
}
