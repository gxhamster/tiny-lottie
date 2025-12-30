package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:reflect"


JsonLottie_Error :: enum {
    None,
    Missing_Required_Value,
    Outof_Range_Value,
    Unmarshal_Err,
    Incompatible_Vector_Type,
    Incompatible_Vector_Inner_Type,
    Incompatible_Object_Type,
    Incompatible_Scalar_Type,
    Incompatible_Integer_Type,
    Incompatible_Array_Type,
    Incompatible_Number_Type,
    Incompatible_Boolean_Type,
    Incompatible_String_Type,
    Incompatible_Position_Type,
    Incompatible_Prop_Scalar_Type,
    Incompatible_Transform_Type,
    Too_Large_Vector,
    Too_Small_Vector,
    Unmarshal_Unknown_Value_Type,
    Unmarshal_Unknown_Array_Type,
    Unmarshal_Unknown_Object_Type,
    Unmarshal_Unknown_Array_Inner_Type,
    Unmarshal_Unknown_Struct_Field_Type,
    Unmarshal_Unknown_Union_Field_Type,
    Unmarshal_Allocation_Error,
    Unmarshal_Deallocation_Error,
}

Error :: union {
    os.Error,
    JsonLottie_Error,
    json.Error,
}

JsonLottie_Animation :: struct {
    nm:      string,
    ver:     i64,
    fr:      f64,
    ip:      f64,
    op:      f64,
    w:       i64,
    h:       i64,
    layers:  json.Array,
    assets:  json.Array,
    markers: json.Array,
    slots:   json.Object,
}

// Values
Vec3 :: distinct [3]f64
Vec2 :: distinct [2]f64

// note(iyaan): sometimes you might find color values
// with 4 components (the 4th being alpha) but most
// players ignore the last component.
Color3 :: Vec3
Color4 :: distinct [4]f64
HexColor :: distinct string
Gradient :: distinct []f64

BezierShapeValue :: struct {
    c: bool,
    i: []Vec3,
    o: []Vec3,
    v: []Vec3,
}

// Properties
JsonLottie_Prop_Keyframe_Easing_Vec :: struct {
    x: Vec3,
    y: Vec3,
}

JsonLottie_Prop_Keyframe_Easing_Scalar :: struct {
    x: f64,
    y: f64,
}

JsonLottie_Prop_Scalar :: union {
    JsonLottie_Prop_Scalar_Single,
    JsonLottie_Prop_Scalar_Anim,
}

JsonLottie_Prop_Scalar_Single :: struct {
    sid: string,
    a:   bool,
    k:   f64,
}

JsonLottie_Prop_Scalar_Keyframe :: struct {
    t: f64,
    h: i64,
    i: JsonLottie_Prop_Keyframe_Easing_Scalar,
    o: JsonLottie_Prop_Keyframe_Easing_Scalar,
    s: f64,
}

JsonLottie_Prop_Scalar_Anim :: struct {
    sid: string,
    a:   bool,
    k:   []JsonLottie_Prop_Scalar_Keyframe,
}

JsonLottie_Prop_Bezier :: union {
    JsonLottie_Prop_Bezier_Single,
    JsonLottie_Prop_Bezier_Anim,
}

JsonLottie_Prop_Bezier_Single :: struct {
    a: bool,
    k: BezierShapeValue,
}

JsonLottie_Prop_Bezier_Keyframe :: struct {
    t: f64,
    h: i64,
    i: JsonLottie_Prop_Keyframe_Easing_Vec,
    o: JsonLottie_Prop_Keyframe_Easing_Vec,
    s: BezierShapeValue,
}

JsonLottie_Prop_Bezier_Anim :: struct {
    a: bool,
    k: []JsonLottie_Prop_Bezier_Keyframe,
}


JsonLottie_Prop_Color :: union {
    JsonLottie_Prop_Color_Single,
    JsonLottie_Prop_Color_Anim,
}

JsonLottie_Prop_Color_Single :: struct {
    sid: string,
    a: bool,
    k: Color4,
}

JsonLottie_Prop_Color_Keyframe :: struct {
    t: f64,
    h: i64,
    i: JsonLottie_Prop_Keyframe_Easing_Vec,
    o: JsonLottie_Prop_Keyframe_Easing_Vec,
    s: Color4,
}

JsonLottie_Prop_Color_Anim :: struct {
    sid: string,
    a: bool,
    k: []JsonLottie_Prop_Color_Keyframe,
}

JsonLottie_Prop_Vector :: union {
    JsonLottie_Prop_Vector_Single,
    JsonLottie_Prop_Vector_Anim,
}

JsonLottie_Prop_Vector_Single :: struct {
    sid: string,
    a:   bool,
    k:   Vec3,
}

JsonLottie_Prop_Vector_Keyframe :: struct {
    t: f64,
    h: i64,
    i: JsonLottie_Prop_Keyframe_Easing_Vec,
    o: JsonLottie_Prop_Keyframe_Easing_Vec,
    s: Vec3,
}

JsonLottie_Prop_Vector_Anim :: struct {
    sid: string,
    a:   bool,
    k:   []JsonLottie_Prop_Vector_Keyframe,
}

// 2D version of a Vector property
JsonLottie_Prop_Position :: union {
    JsonLottie_Prop_Position_Single,
    JsonLottie_Prop_Position_Anim,
    JsonLottie_Prop_Split_Position,
}

JsonLottie_Prop_Position_Single :: JsonLottie_Prop_Vector_Single
JsonLottie_Prop_Position_Keyframe :: struct {
    t:  f64,
    h:  i64,
    i:  JsonLottie_Prop_Keyframe_Easing_Vec,
    o:  JsonLottie_Prop_Keyframe_Easing_Vec,
    s:  Vec3,
    ti: Vec3,
    to: Vec3,
}
JsonLottie_Prop_Position_Anim :: struct {
    sid: string,
    a:   bool,
    k:   []JsonLottie_Prop_Position_Keyframe,
}

JsonLottie_Prop_Split_Position :: struct {
    s: bool,
    x: JsonLottie_Prop_Scalar,
    y: JsonLottie_Prop_Scalar,
}

// Helpers
JsonLottie_Transform :: struct {
    a:  JsonLottie_Prop_Position,
    p:  JsonLottie_Prop_Position,
    r:  JsonLottie_Prop_Scalar,
    s:  JsonLottie_Prop_Vector,
    o:  JsonLottie_Prop_Scalar,
    sk: JsonLottie_Prop_Scalar,
    sa: JsonLottie_Prop_Scalar,
}

JsonLottie_Layer :: struct {
    nm:     string,
    hd:     bool,
    ty:     i64,
    ind:    i64,
    parent: i64,
    ip:     f64,
    op:     f64,
}

JsonLottie_Shape_Layer :: struct {}

JsonLottie_Image_Layer :: struct {}

JsonLottie_Null_Layer :: struct {}

JsonLottie_Solid_Layer :: struct {}

JsonLottie_Precomp_Layer :: struct {}

JsonLottie :: struct {
    animation: JsonLottie_Animation,
    raw:       []u8,
}

JsonLottie_Core_Types :: enum {
    Null,
    Array,
    Object,
    Float,
    Integer,
    Bool,
    String,
}

json_obj_val_type :: proc(root: ^json.Object, key: string) -> JsonLottie_Core_Types {
    if root[key] == nil {
        return .Null
    }
    data := root[key]
    #partial switch type_val in data {
    case json.Null:
        return .Null
    case json.Array:
        return .Array
    case json.Object:
        return .Object
    case json.Float:
        return .Float
    case json.Integer:
        return .Integer
    }
    panic("unexpected type")
}

field_expect_type :: proc(
    root: ^json.Object,
    key: string,
    expected: JsonLottie_Core_Types,
) -> bool {
    data := root[key]
    union_type := JsonLottie_Core_Types.Null
    switch type_val in data {
    case json.Null:
        union_type = .Null
    case json.Array:
        union_type = .Array
    case json.Object:
        union_type = .Object
    case json.Boolean:
        union_type = .Bool
    case json.Integer:
        union_type = .Integer
    case json.Float:
        union_type = .Float
    case json.String:
        union_type = .String
    }

    if union_type == expected {
        return true
    } else {
        return false
    }
}

json_lottie_parse_layers :: proc(
    anim: ^JsonLottie_Animation,
    layer_json_array: json.Array,
    allocator := context.allocator,
    loc := #caller_location,
) -> JsonLottie_Error {
    p := (layer_json_array[0].(json.Object)["ks"])

    transform, err := json_lottie_parse_transform(p)
    // if err != .None {
    //      fmt.println(err)
    // } else {
    //      fmt.println(transform)
    // }
    return .None
}

json_lottie_parse_prop_scalar :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    scalar: JsonLottie_Prop_Scalar,
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        obj := value.(json.Object)
        sid_val := json_lottie_parse_string(obj["sid"]) or_return
        animated := json_lottie_parse_integer(obj["a"]) or_return
        if animated == 0 {
            single_scalar := JsonLottie_Prop_Scalar_Single {
                a   = false,
                sid = sid_val,
            }
            single_scalar.k = json_lottie_parse_number(obj["k"]) or_return
            scalar = single_scalar
            return scalar, .None
        } else {
            anim_scalar := JsonLottie_Prop_Scalar_Anim {
                a   = true,
                sid = sid_val,
            }

            #partial switch type in obj["k"] {
            case json.Array:
                arr := obj["k"].(json.Array)
                // warning(iyaan): This allocation needs to be watched out for
                // when using non-arena allocators. Does it matter during pe
                // mode when using tracking allocator
                keyframes := make([dynamic]JsonLottie_Prop_Scalar_Keyframe)
                resize(&keyframes, len(arr))
                for elem in arr {
                    keyframe := json_lottie_parse_scalar_keyframe(elem) or_return
                    append(&keyframes, keyframe)
                }
                anim_scalar.k = keyframes[:]
                return anim_scalar, .None
            case:
                return scalar, .Incompatible_Array_Type
            }
        }
    case:
        return not_required_or_error(required, scalar, .Incompatible_Prop_Scalar_Type)
    }

}

json_lottie_parse_prop_vector :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    vector_prop: JsonLottie_Prop_Vector,
    err: JsonLottie_Error,
) {

    #partial switch type in value {
    case json.Object:
        obj := value.(json.Object)
        sid_val := json_lottie_parse_string(obj["sid"]) or_return
        animated_val := json_lottie_parse_integer(obj["a"]) or_return

        if animated_val == 0 {
            single_vector := JsonLottie_Prop_Vector_Single {
                a   = false,
                sid = sid_val,
            }
            single_vector.k = json_lottie_parse_value_vector(obj["k"]) or_return
            vector_prop = single_vector
            return vector_prop, .None
        } else if animated_val == 1 {
            anim_vector := JsonLottie_Prop_Vector_Anim {
                a = true,
            }
            anim_vector.sid = json_lottie_parse_string(obj["sid"]) or_return

            #partial switch type in obj["k"] {
            case json.Array:
                arr := obj["k"].(json.Array)
                // warning(iyaan): This allocation needs to be watched out for
                // when using non-arena allocators. Does it matter during debug
                // mode when using tracking allocator
                keyframes := make([dynamic]JsonLottie_Prop_Vector_Keyframe)
                resize(&keyframes, len(arr))
                for elem in arr {
                    keyframe := json_lottie_parse_vector_keyframe(elem) or_return
                    append(&keyframes, keyframe)
                }
                anim_vector.k = keyframes[:]
                return anim_vector, .None
            case:
                return vector_prop, .Incompatible_Array_Type
            }
        } else {
            return vector_prop, .Incompatible_Boolean_Type
        }

    case:
        return not_required_or_error(required, vector_prop, .Incompatible_Object_Type)
    }
}

json_lottie_parse_color_keyframe :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    color_keyframe: JsonLottie_Prop_Color_Keyframe,
    err: JsonLottie_Error,
) {

    if err := json_lottie_unmarshal_object(value, color_keyframe); err != .None {
        return not_required_or_error(required, color_keyframe, err)
    } else {
        return color_keyframe, .None
    }
}

json_lottie_parse_prop_color :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    color_prop: JsonLottie_Prop_Color,
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        obj := value.(json.Object)
        animated_val := json_lottie_parse_integer(obj["a"], true) or_return
        sid_val := json_lottie_parse_string(obj["sid"]) or_return

        if animated_val == 0 {
            single_color := JsonLottie_Prop_Color_Single {
                a = false,
                sid = sid_val
            }
            color_value: Color4
            json_lottie_unmarshal_array(obj["k"], color_value) or_return
            single_color.k = color_value
            color_prop = single_color
            return color_prop, .None
        } else if animated_val == 1 {
            anim_color_prop := JsonLottie_Prop_Color_Anim {
                a = true,
                sid = sid_val
            }

            #partial switch type in obj["k"] {
            case json.Array:
                arr := obj["k"].(json.Array)
                // warning(iyaan): This allocation needs to be watched out for
                // when using non-arena allocators. Does it matter during debug
                // mode when using tracking allocator
                keyframes := make([dynamic]JsonLottie_Prop_Color_Keyframe)
                resize(&keyframes, len(arr))
                for elem in arr {
                    keyframe := json_lottie_parse_color_keyframe(elem) or_return
                    append(&keyframes, keyframe)
                }
                anim_color_prop.k = keyframes[:]
                return anim_color_prop, .None
            case:
                return not_required_or_error(required, color_prop, .Incompatible_Array_Type)
            }
        } else {
            return not_required_or_error(required, color_prop, .Incompatible_Boolean_Type)
        }
    case:
        return not_required_or_error(required, color_prop, .Incompatible_Object_Type)
    }
}

json_lottie_parse_bezier_keyframe :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    bezier_keyframe: JsonLottie_Prop_Bezier_Keyframe,
    err: JsonLottie_Error,
) {

    if err := json_lottie_unmarshal_object(value, bezier_keyframe); err != .None {
        return not_required_or_error(required, bezier_keyframe, err)
    } else {
        return bezier_keyframe, .None
    }
}

json_lottie_parse_prop_bezier :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    bezier_prop: JsonLottie_Prop_Bezier,
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        obj := value.(json.Object)
        animated_val := json_lottie_parse_integer(obj["a"], true) or_return

        if animated_val == 0 {
            single_bezier := JsonLottie_Prop_Bezier_Single {
                a = false,
            }
            bezier_shape_struct := BezierShapeValue{}
            json_lottie_unmarshal_object(obj["k"], bezier_shape_struct) or_return
            single_bezier.k = bezier_shape_struct
            bezier_prop = single_bezier
            return bezier_prop, .None
        } else if animated_val == 1 {
            anim_vector := JsonLottie_Prop_Bezier_Anim {
                a = true,
            }

            #partial switch type in obj["k"] {
            case json.Array:
                arr := obj["k"].(json.Array)
                // warning(iyaan): This allocation needs to be watched out for
                // when using non-arena allocators. Does it matter during debug
                // mode when using tracking allocator
                keyframes := make([dynamic]JsonLottie_Prop_Bezier_Keyframe)
                resize(&keyframes, len(arr))
                for elem in arr {
                    keyframe := json_lottie_parse_bezier_keyframe(elem) or_return
                    append(&keyframes, keyframe)
                }
                anim_vector.k = keyframes[:]
                return anim_vector, .None
            case:
                return not_required_or_error(required, bezier_prop, .Incompatible_Array_Type)
            }
        } else {
            return not_required_or_error(required, bezier_prop, .Incompatible_Boolean_Type)
        }
    case:
        return not_required_or_error(required, bezier_prop, .Incompatible_Object_Type)
    }
}


json_lottie_parse_value_vector :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    vec: Vec3,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Array:
        vec: Vec3
        value_as_arr := value.(json.Array)
        if len(value_as_arr) > len(vec) {
            return not_required_or_error(required, Vec3{}, .Too_Large_Vector)
        }

        for idx in 0 ..< len(value_as_arr) {
            float_val := json_lottie_parse_number(value_as_arr[idx]) or_return
            vec[idx] = float_val
        }

        return vec, .None
    case:
        return not_required_or_error(required, Vec3{}, .Incompatible_Vector_Type)
    }

}

json_lottie_parse_string :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    string,
    JsonLottie_Error,
) {
    #partial switch elem_type in value {
    case json.String:
        return value.(json.String), .None
    case:
        return not_required_or_error(required, "", .Incompatible_String_Type)
    }
}


json_lottie_try_float :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    float_val: f64,
    err: JsonLottie_Error,
) {
    #partial switch elem_type in value {
    case json.Float:
        return f64(value.(json.Float)), .None
    case json.Integer:
        return f64(value.(json.Integer)), .None
    case:
        return not_required_or_error(required, f64(0), .Incompatible_Number_Type)
    }
}

json_lottie_parse_number :: json_lottie_try_float

json_lottie_parse_integer :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    i64,
    JsonLottie_Error,
) {
    #partial switch elem_type in value {
    case json.Float:
        return i64(value.(json.Float)), .None
    case json.Integer:
        return i64(value.(json.Integer)), .None
    case:
        return not_required_or_error(required, i64(0), .Incompatible_Integer_Type)
    }
}

// Some conveninent syntax to allow to use or_return
// The calling function will not return the error value
// if the callee function is called as non-required
not_required_or_error :: #force_inline proc(
    required: bool,
    ret_value: $T,
    error_type: JsonLottie_Error,
) -> (
    T,
    JsonLottie_Error,
) {
    if required {
        return ret_value, error_type
    } else {
        return ret_value, .None
    }
}

json_lottie_parse_bool :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    bool,
    JsonLottie_Error,
) {
    #partial switch elem_type in value {
    case json.Boolean:
        return value.(json.Boolean), .None
    case json.Integer:
        int_val := value.(json.Integer)
        if int_val > 0 {
            return true, .None
        } else {
            return false, .None
        }
    case json.Float:
        // note(iyaan): Since json.parse in std library is called without the option
        // of parsing potential numbers as integers, almost all number values will be
        // in floats. Could be handy to have
        float_val := value.(json.Float)
        if float_val > 0.0 {
            return true, .None
        } else {
            return false, .None
        }

    case:
        return not_required_or_error(required, false, .Incompatible_Boolean_Type)
    }
}


json_lottie_parse_keyframe_easing_vec :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    easing_vec: JsonLottie_Prop_Keyframe_Easing_Vec,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Object:
        value_as_obj := value.(json.Object)

        easing_vec.x = json_lottie_parse_value_vector(value_as_obj["x"], true) or_return
        easing_vec.y = json_lottie_parse_value_vector(value_as_obj["y"], true) or_return

        return easing_vec, .None

    case:
        return not_required_or_error(required, easing_vec, .Incompatible_Object_Type)

    }
}

json_lottie_parse_keyframe_easing_scalar :: proc(
    value: json.Value,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    ease_scalar: JsonLottie_Prop_Keyframe_Easing_Scalar,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Object:
        r_keyframe_easing := JsonLottie_Prop_Keyframe_Easing_Scalar{}
        value_as_obj := value.(json.Object)
        required_fields := []string{"x", "y"}
        for field in required_fields {
            if ok := field in value_as_obj; ok == false {
                return JsonLottie_Prop_Keyframe_Easing_Scalar{}, .Missing_Required_Value
            }
        }

        r_keyframe_easing.x = json_lottie_parse_number(value_as_obj["x"], true) or_return
        r_keyframe_easing.x = json_lottie_parse_number(value_as_obj["y"], true) or_return
        return r_keyframe_easing, .None
    case:
        return JsonLottie_Prop_Keyframe_Easing_Scalar{}, .Incompatible_Object_Type

    }
}

// Checks for keys in an json.Object
json_check_missing_required :: proc(
    value: json.Value,
    required_fields: []string,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        value_as_obj := value.(json.Object)
        for field in required_fields {
            if ok := field in value_as_obj; ok == false {
                return .Missing_Required_Value
            }
        }
        return .None
    case:
        return .Incompatible_Object_Type
    }
}


json_lottie_parse_split_position :: proc(
    value: json.Value,
    allocator := context.allocator,
    required := false,
    loc := #caller_location,
) -> (
    pos: JsonLottie_Prop_Position,
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        obj := value.(json.Object)
        if "s" in obj {
            required_fields := [?]string{"s", "x", "y"}
            split_pos := JsonLottie_Prop_Split_Position{}
            json_check_missing_required(value, required_fields[:]) or_return
            split_pos.s = json_lottie_parse_bool(obj["s"]) or_return
            split_pos.x = json_lottie_parse_prop_scalar(obj["x"]) or_return
            split_pos.y = json_lottie_parse_prop_scalar(obj["y"]) or_return
            pos = split_pos
            return pos, .None
        } else {
            normal_pos := json_lottie_parse_position(value) or_return
            pos = normal_pos
            return pos, .None
        }
    case:
        return not_required_or_error(required, pos, .Incompatible_Position_Type)
    }
}

json_lottie_parse_scalar_keyframe :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    scalar_keyframe: JsonLottie_Prop_Scalar_Keyframe,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Object:
        object := value.(json.Object)

        scalar_keyframe.t = json_lottie_parse_number(object["t"]) or_return
        scalar_keyframe.h = json_lottie_parse_integer(object["h"]) or_return
        scalar_keyframe.i = json_lottie_parse_keyframe_easing_scalar(object["i"]) or_return
        scalar_keyframe.o = json_lottie_parse_keyframe_easing_scalar(object["o"]) or_return
        scalar_keyframe.s = json_lottie_parse_number(object["s"]) or_return

        return scalar_keyframe, .None

    case:
        return not_required_or_error(required, scalar_keyframe, .Incompatible_Object_Type)
    }
}


json_lottie_parse_vector_keyframe :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    vec_keyframe: JsonLottie_Prop_Vector_Keyframe,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Object:
        object := value.(json.Object)

        vec_keyframe.t = json_lottie_parse_number(object["t"]) or_return
        vec_keyframe.h = json_lottie_parse_integer(object["h"]) or_return
        vec_keyframe.i = json_lottie_parse_keyframe_easing_vec(object["i"]) or_return
        vec_keyframe.o = json_lottie_parse_keyframe_easing_vec(object["o"]) or_return
        vec_keyframe.s = json_lottie_parse_value_vector(object["s"]) or_return

        return vec_keyframe, .None

    case:
        return not_required_or_error(required, vec_keyframe, .Incompatible_Object_Type)
    }
}

json_lottie_parse_position_keyframe :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    pos_keyframe: JsonLottie_Prop_Position_Keyframe,
    err: JsonLottie_Error,
) {
    #partial switch value_type in value {
    case json.Object:
        object := value.(json.Object)

        pos_keyframe.t = json_lottie_parse_number(object["t"]) or_return
        pos_keyframe.h = json_lottie_parse_integer(object["h"]) or_return
        pos_keyframe.i = json_lottie_parse_keyframe_easing_vec(object["i"]) or_return
        pos_keyframe.o = json_lottie_parse_keyframe_easing_vec(object["o"]) or_return
        pos_keyframe.s = json_lottie_parse_value_vector(object["s"]) or_return
        pos_keyframe.ti = json_lottie_parse_value_vector(object["ti"]) or_return
        pos_keyframe.to = json_lottie_parse_value_vector(object["to"]) or_return

        return pos_keyframe, .None

    case:
        return not_required_or_error(required, pos_keyframe, .Incompatible_Object_Type)
    }
}


json_lottie_parse_position :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    position: JsonLottie_Prop_Position,
    err: JsonLottie_Error,
) {
    #partial switch type in value {
    case json.Object:
        position_obj := value.(json.Object)
        required_fields := []string{"a", "k"}
        json_check_missing_required(value, required_fields) or_return

        animated := json_lottie_parse_integer(position_obj["a"], true) or_return
        if animated == 0 {
            single_pos := JsonLottie_Prop_Position_Single {
                a = false,
            }
            single_pos.k = json_lottie_parse_value_vector(position_obj["k"]) or_return
            return single_pos, .None
        } else {
            position_anim := JsonLottie_Prop_Position_Anim {
                a = true,
            }

            #partial switch type in position_obj["k"] {
            case json.Array:
                arr := position_obj["k"].(json.Array)
                keyframes := make([dynamic]JsonLottie_Prop_Position_Keyframe)
                resize(&keyframes, len(arr))
                for elem in arr {
                    keyframe := json_lottie_parse_position_keyframe(elem) or_return
                    append(&keyframes, keyframe)
                }
                position_anim.k = keyframes[:]
                return position_anim, .None
            case:
                return position_anim, .Incompatible_Array_Type
            }

            return position_anim, .None
        }
    case:
        return position, .None
    }
}

json_lottie_parse_transform :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    transform: JsonLottie_Transform,
    err: JsonLottie_Error,
) {
    transform_struct := JsonLottie_Transform{}
    json_lottie_unmarshal_object(value, transform_struct) or_return
    return transform_struct, .None
}

json_lottie_read_file_handle :: proc(
    fd: os.Handle,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    data: JsonLottie,
    err: Error,
) {

    data.raw = os.read_entire_file_from_handle_or_err(fd, allocator, loc) or_return
    parsed_json, parse_err := json.parse(data.raw)
    if parse_err != nil {
        return JsonLottie{}, parse_err
    }
    // note(iyaan): Need to call json.destroy_value on parsed_json
    // after we have fully parsed it into the structure
    defer delete(data.raw, allocator)
    defer json.destroy_value(parsed_json)

    root := parsed_json.(json.Object)
    if root["h"] == nil ||
       root["w"] == nil ||
       root["fr"] == nil ||
       root["op"] == nil ||
       root["ip"] == nil {
        return JsonLottie{}, JsonLottie_Error.Missing_Required_Value
    }

    data.animation.nm = root["nm"].(json.String)
    data.animation.fr = root["fr"].(json.Float)
    data.animation.op = root["op"].(json.Float)
    data.animation.ip = root["ip"].(json.Float)
    data.animation.w = i64(root["w"].(json.Float))
    data.animation.h = i64(root["h"].(json.Float))

    if data.animation.h < 0 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
    }
    if data.animation.w < 0 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
    }
    if data.animation.fr < 1 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
    }
    LOTTIE_VERSION_MIN :: 10000
    if root["ver"] != nil && root["ver"].(json.Integer) < LOTTIE_VERSION_MIN {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
    } else if root["ver"] != nil && root["ver"].(json.Integer) > LOTTIE_VERSION_MIN {
        data.animation.ver = root["ver"].(json.Integer)
    }

    layer_ok := field_expect_type(&root, "layers", .Array)
    marker_ok := field_expect_type(&root, "markers", .Array)
    assets_ok := field_expect_type(&root, "assets", .Array)
    slots_ok := field_expect_type(&root, "slots", .Object)


    if layer_ok {
        json_lottie_parse_layers(&data.animation, root["layers"].(json.Array))
    }
    if marker_ok {
        data.animation.markers = root["markers"].(json.Array)
    }
    if assets_ok {
        data.animation.assets = root["assets"].(json.Array)
    }
    if slots_ok {
        data.animation.slots = root["slots"].(json.Object)
    }
    return data, JsonLottie_Error.None
}

json_lottie_read_file_name :: proc(
    file_name: string,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    data: JsonLottie,
    err: Error,
) {
    context.allocator = allocator
    fd := os.open(file_name, os.O_RDONLY, 0) or_return
    defer os.close(fd)
    return json_lottie_read_file_handle(fd, allocator, loc)
}

main :: proc() {
    // note(iyaan): For debug mode setup the tracking allocator
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        tracking_allocator := mem.tracking_allocator(&track)
        context.allocator = tracking_allocator

        logger := log.create_console_logger(allocator = tracking_allocator)
        context.logger = logger

        defer {
            log.destroy_console_logger(logger, allocator = tracking_allocator)

            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }

            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    } else {
        // note(iyaan): All allocations related to the JsonLottie struct
        // and all its sub structs would be nice to have in one arena block
        // so that it would be easy to free it all together
        json_lottie_arena: vmem.Arena
        arena_err := vmem.arena_init_growing(&json_lottie_arena)
        ensure(arena_err == nil)
        json_lottie_arena_allocator := vmem.arena_allocator(&json_lottie_arena)

        context.allocator = json_lottie_arena_allocator

        // You free the underlying buffer for the arena. Not the
        // stack allocated arena struct. Hmm very C like!
        defer vmem.arena_destroy(&json_lottie_arena)
    }


    lottie_struct, err := json_lottie_read_file_name("./data/Fire.json", context.allocator)
    if err != nil && err != JsonLottie_Error.None {
        fmt.eprintf("Could not read lottie json file due to %s\n", err)
        panic("Could not read lottie json file")
    }

}


json_lottie_unmarshal_value :: proc(
    val: json.Value,
    p: any,
    allocator := context.allocator,
) -> (
    err: JsonLottie_Error,
) {
    type_info := reflect.type_info_base(type_info_of(p.id))
    ptr := p.data

    #partial switch t in type_info.variant {
    case runtime.Type_Info_String:
        val := json_lottie_parse_string(val) or_return
        field_val_ptr := transmute(^string)ptr
        field_val_ptr^ = val
    case runtime.Type_Info_Boolean:
        val := json_lottie_parse_bool(val) or_return
        field_val_ptr := transmute(^bool)ptr
        field_val_ptr^ = val
    case runtime.Type_Info_Float:
        val := json_lottie_parse_number(val) or_return
        field_val_ptr := transmute(^f64)ptr
        field_val_ptr^ = val
    case runtime.Type_Info_Integer:
        val := json_lottie_parse_integer(val) or_return
        field_val_ptr := transmute(^i64)ptr
        field_val_ptr^ = val
    case:
        return .Unmarshal_Unknown_Value_Type
    }
    return .None
}

json_lottie_unmarshal_array :: proc(
    val: json.Value,
    p: any,
    allocator := context.allocator,
) -> (
    err: JsonLottie_Error,
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
                elem_ptr := rawptr(uintptr(raw.data) + uintptr(idx) * uintptr(internal_elem_size))
                elem_any := any{elem_ptr, internal_elem_type_info.id}
                elem_type_base := reflect.type_info_base(type_info_of(internal_elem_type_info.id))

                #partial switch base_t in elem_type_base.variant {
                case runtime.Type_Info_Struct, runtime.Type_Info_Union:
                    json_lottie_unmarshal_object(elem, elem_any) or_return
                case runtime.Type_Info_Integer,
                     runtime.Type_Info_Float,
                     runtime.Type_Info_Boolean,
                     runtime.Type_Info_String:
                    json_lottie_unmarshal_value(elem, elem_any) or_return
                case runtime.Type_Info_Slice, runtime.Type_Info_Array:
                    json_lottie_unmarshal_array(elem, elem_any) or_return
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
                    json_lottie_unmarshal_value(elem, elem_any) or_return
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

json_lottie_unmarshal_object :: proc(
    val: json.Value,
    p: any,
    allocator := context.allocator,
) -> (
    err: JsonLottie_Error,
) {
    type_info := reflect.type_info_base(type_info_of(p.id))
    ptr := p.data

    #partial switch t in type_info.variant {
    case reflect.Type_Info_Struct:
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
                    json_lottie_unmarshal_value(json_obj[field.name], field_value_any) or_return
                case runtime.Type_Info_Array,
                     runtime.Type_Info_Slice,
                     runtime.Type_Info_Dynamic_Array:
                    field_value_any := any{field_ptr, field.type.id}
                    json_lottie_unmarshal_array(json_obj[field.name], field_value_any) or_return
                case runtime.Type_Info_Struct:
                    field_value_any := any{field_ptr, field.type.id}
                    json_lottie_unmarshal_object(json_obj[field.name], field_value_any) or_return
                case runtime.Type_Info_Union:
                    // TODO(iyaan): Handle some obvious unions (eg: JsonLottie_Prop_Position)
                    // Finding a generic way to handle all cases of unions would be too much
                    switch field.type.id {
                    case JsonLottie_Prop_Position:
                        pos_val := json_lottie_parse_position(json_obj[field.name]) or_return
                        field_ptr_offset := uintptr(ptr) + field.offset
                        field_val_ptr := transmute(^JsonLottie_Prop_Position)field_ptr_offset
                        field_val_ptr^ = pos_val
                    case JsonLottie_Prop_Scalar:
                        scalar_val := json_lottie_parse_prop_scalar(json_obj[field.name]) or_return
                        field_ptr_offset := uintptr(ptr) + field.offset
                        field_val_ptr := transmute(^JsonLottie_Prop_Scalar)field_ptr_offset
                        field_val_ptr^ = scalar_val
                    case JsonLottie_Prop_Vector:
                        vector_val := json_lottie_parse_prop_vector(json_obj[field.name]) or_return
                        field_ptr_offset := uintptr(ptr) + field.offset
                        field_val_ptr := transmute(^JsonLottie_Prop_Vector)field_ptr_offset
                        field_val_ptr^ = vector_val
                    case JsonLottie_Prop_Bezier:
                        bezier_val := json_lottie_parse_prop_bezier(json_obj[field.name]) or_return
                        field_ptr_offset := uintptr(ptr) + field.offset
                        field_val_ptr := transmute(^JsonLottie_Prop_Bezier)field_ptr_offset
                        field_val_ptr^ = bezier_val
                    case JsonLottie_Prop_Color:
                        color_val := json_lottie_parse_prop_color(json_obj[field.name]) or_return
                        field_ptr_offset := uintptr(ptr) + field.offset
                        field_val_ptr := transmute(^JsonLottie_Prop_Color)field_ptr_offset
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
    case:
        return .Incompatible_Object_Type
    }
}
