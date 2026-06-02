package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:reflect"

// This file contains procedures which are used
// to take json values and convert them or unmarshal
// them into lottie structs as best as possible


_parse_enum_internal :: proc(value: json.Value, loc := #caller_location) -> (i64, LottieError) {
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
        return 0, .IncompatibleEnumType
      }
    }
  case:
    return 0, .IncompatibleEnumType
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
  err: LottieError,
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
        return .UnmarshalOutOfBoundEnumValue
      }
    }
  case:
    {
      log.fatalf("unknown type: %v, called from %v", t, loc)
      return .UnmarshalUnknownValue_Type
    }
  }
  return .None
}

unmarshal_array :: proc(val: json.Value, p: any, allocator := context.allocator) -> (err: LottieError) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  if _, ok := val.(json.Array); !ok {
    return .IncompatibleArrayType
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
      data, alloc_err := mem.alloc_bytes(internal_elem_size * int(json_array_len), internal_elem_alignment, allocator)

      if alloc_err != .None {
        return .UnmarshalAllocationError
      }

      raw.data = raw_data(data)
      raw.len = int(json_array_len)
      for elem, idx in json_array {
        elem_ptr := rawptr(uintptr(raw.data) + uintptr(idx) * uintptr(internal_elem_size))
        elem_any := any{elem_ptr, internal_elem_type_info.id}
        elem_type_base := reflect.type_info_base(type_info_of(internal_elem_type_info.id))

        #partial switch base_t in elem_type_base.variant {
        case runtime.Type_Info_Struct:
          err := unmarshal_object(elem, elem_any, allocator = allocator)
          if err != .None {
            log.fatalf("unmarshal_object returned error %v for %v %v", err, elem, internal_elem_type_info.id)
          }
        case runtime.Type_Info_Union:
          unmarshal_union(elem, elem_any, allocator = allocator) or_return
        case runtime.Type_Info_Integer,
             runtime.Type_Info_Float,
             runtime.Type_Info_Boolean,
             runtime.Type_Info_String,
             runtime.Type_Info_Enum:
          unmarshal_value(elem, elem_any, allocator = allocator) or_return
        case runtime.Type_Info_Slice, runtime.Type_Info_Array:
          unmarshal_array(elem, elem_any, allocator = allocator) or_return
        case:
          {
            if err := delete(data); err != .None {
              return .UnmarshalDeallocationError
            } else {
              return .UnmarshalUnknownArrayInnerType
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
          elem_ptr := rawptr(uintptr(p.data) + uintptr(idx) * uintptr(internal_elem_size))
          elem_any := any{elem_ptr, internal_elem_type_info.id}
          unmarshal_value(elem, elem_any) or_return
        }
      } else {
        return .TooLargeVector
      }
    }
  case runtime.Type_Info_Dynamic_Array:
    return .UnmarshalUnsupportedArrayType
  case:
    return .UnmarshalUnknownArrayType
  }

  return .None
}


_unmarshal_prop_union :: proc(
  object: json.Object,
  field_ptr: rawptr,
  $union_type, $single_variant, $anim_variant: typeid,
) -> (
  err: LottieError,
) {
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

_unmarshal_graphic_elem_internal :: proc(
  object: json.Object,
  field_ptr: rawptr,
  $intern_type: typeid,
) -> (
  err: LottieError,
) {
  field_val_ptr := transmute(^GraphicElement)field_ptr
  field_val_ptr^ = intern_type{}
  field_value_any := any{field_ptr, typeid_of(intern_type)}
  unmarshal_object(object, field_value_any) or_return
  return .None
}


_unmarshal_graphic_element_union :: proc(object: json.Object, field_ptr: rawptr) -> (err: LottieError) {
  graphic_elem_type_str := parse_string(object["ty"]) or_return
  // Map the string `type` to an enum
  graphic_elem_type := conv_graphic_elem_type_to_enum(graphic_elem_type_str)
  switch graphic_elem_type {
  case .el:
    _unmarshal_graphic_elem_internal(object, field_ptr, Ellipse) or_return
  case .fl:
    _unmarshal_graphic_elem_internal(object, field_ptr, Fill) or_return
  case .gf:
    _unmarshal_graphic_elem_internal(object, field_ptr, GradientFill) or_return
  case .gs:
    _unmarshal_graphic_elem_internal(object, field_ptr, GradientStroke) or_return
  case .gr:
    _unmarshal_graphic_elem_internal(object, field_ptr, Group) or_return
  case .sh:
    _unmarshal_graphic_elem_internal(object, field_ptr, Path) or_return
  case .sr:
    _unmarshal_graphic_elem_internal(object, field_ptr, Polystar) or_return
  case .rc:
    _unmarshal_graphic_elem_internal(object, field_ptr, Rectangle) or_return
  case .st:
    _unmarshal_graphic_elem_internal(object, field_ptr, Stroke) or_return
  case .tr:
    _unmarshal_graphic_elem_internal(object, field_ptr, TransformShape) or_return
  case .tm:
    _unmarshal_graphic_elem_internal(object, field_ptr, TrimPath) or_return
  case .Error:
    fmt.println(graphic_elem_type_str)
    panic("unknown graphic element type")
  }

  return .None
}

unmarshal_union :: proc(val: json.Value, p: any, allocator := context.allocator) -> (err: LottieError) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  if _, ok := type_info.variant.(reflect.Type_Info_Union); !ok {
    return .IncompatibleObjectType
  }

  if _, ok := val.(json.Object); !ok {
    return .IncompatibleObjectType
  }

  object := val.(json.Object)
  switch p.id {
  case PropScalar:
    _unmarshal_prop_union(object, ptr, PropScalar, PropScalarSingle, PropScalarAnim) or_return
  case PropVector:
    _unmarshal_prop_union(object, ptr, PropVector, PropVectorSingle, PropVectorAnim) or_return
  case PropBezier:
    _unmarshal_prop_union(object, ptr, PropBezier, PropBezierSingle, PropBezierAnim) or_return
  case PropPosition:
    _unmarshal_prop_union(object, ptr, PropPosition, PropPositionSingle, PropPositionAnim) or_return
  case PropColor:
    _unmarshal_prop_union(object, ptr, PropColor, PropColorSingle, PropColorAnim) or_return
  case GradientStop:
    _unmarshal_prop_union(object, ptr, GradientStop, GradientStopSingle, GradientStopAnim) or_return
  case PropKeyframeEasing:
    {
      is_vector_type := false
      _, okX := object["x"].(json.Array)
      _, okY := object["y"].(json.Array)
      if okX && okY do is_vector_type = true
      if is_vector_type {
        easing_ptr := transmute(^PropKeyframeEasing)ptr
        easing_ptr^ = PropKeyframeEasingVec{}
        easing_vector := any{ptr, typeid_of(PropKeyframeEasingVec)}
        unmarshal_object(object, easing_vector, allocator = allocator) or_return
      } else {
        easing_ptr := transmute(^PropKeyframeEasing)ptr
        easing_ptr^ = PropKeyframeEasingScalar{}
        easing_scalar := any{ptr, typeid_of(PropKeyframeEasingScalar)}
        unmarshal_object(object, easing_scalar, allocator = allocator) or_return
      }
    }
  case GraphicElement:
    {
      if "ty" in object {
        _unmarshal_graphic_element_union(object, ptr) or_return
      }
    }
  case Layer:
    {
      if "ty" in object {
        if ty, ok := object["ty"].(json.Integer); ok {
          enum_ty := LayerType(ty)
          if enum_ty >= LayerType.PrecompLayer && enum_ty <= LayerType.ShapeLayer {
            layer_ptr := transmute(^Layer)ptr
            switch enum_ty {
            case .PrecompLayer:
              {
                layer_ptr^ = PrecompLayer{}
                layer_any := any{ptr, typeid_of(PrecompLayer)}
                unmarshal_object(object, layer_any, allocator = allocator) or_return
              }
            case .ImageLayer:
              {
                layer_ptr^ = ImageLayer{}
                layer_any := any{ptr, typeid_of(ImageLayer)}
                unmarshal_object(object, layer_any, allocator = allocator) or_return
              }
            case .NullLayer:
              {
                layer_ptr^ = NullLayer{}
                layer_any := any{ptr, typeid_of(NullLayer)}
                unmarshal_object(object, layer_any, allocator = allocator) or_return
              }
            case .SoildLayer:
              {
                layer_ptr^ = SolidLayer{}
                layer_any := any{ptr, typeid_of(SolidLayer)}
                unmarshal_object(object, layer_any, allocator = allocator) or_return
              }
            case .ShapeLayer:
              {
                layer_ptr^ = ShapeLayer{}
                layer_any := any{ptr, typeid_of(ShapeLayer)}
                unmarshal_object(object, layer_any, allocator = allocator) or_return
              }
            }
          }

        } else {

        }
      }
    }
  case:
    log.fatalf("unknown union type encountered %v", p.id)
  }

  return .None
}

unmarshal_object :: proc(val: json.Value, p: any, allocator := context.allocator) -> (err: LottieError) {
  type_info := reflect.type_info_base(type_info_of(p.id))
  ptr := p.data

  if _, ok := type_info.variant.(reflect.Type_Info_Struct); !ok {
    return .IncompatibleObjectType
  }

  if _, ok := val.(json.Object); !ok {
    return .IncompatibleObjectType
  }

  fields := reflect.struct_fields_zipped(p.id)
  json_obj := val.(json.Object)
  flags: Bit64
  flags_field_exists := false
  flags_field_ptr: rawptr
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
    } else {
      continue
    }

    field_value_any := any{field_ptr, field.type.id}
    #partial switch struct_type in field_type_as_base.variant {
    case runtime.Type_Info_Integer,
         runtime.Type_Info_Float,
         runtime.Type_Info_String,
         runtime.Type_Info_Boolean,
         runtime.Type_Info_Enum:
      unmarshal_value(json_obj[field.name], field_value_any, allocator = allocator) or_return
    case runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Array, runtime.Type_Info_Slice:
      unmarshal_array(json_obj[field.name], field_value_any, allocator = allocator) or_return
    case runtime.Type_Info_Struct:
      unmarshal_object(json_obj[field.name], field_value_any, allocator = allocator) or_return
    case runtime.Type_Info_Union:
      {
        // note(iyaan): Are we deadass ignoring any union which has no struct variants
        if _, ok := json_obj[field.name].(json.Object); !ok {
          continue
        }
        unmarshal_union(json_obj[field.name], field_value_any, allocator = allocator) or_return
      }
    case:
      return .UnmarshalUnknownStructFieldType
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
