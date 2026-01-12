package schema_validator

import "base:runtime"
import "core:encoding/json"
import "core:log"
import "core:math"
import "core:math/bits"
import "core:path/slashpath"
import "core:strings"
import "core:text/regex"
import regex_common "core:text/regex/common"
import regex_compiler "core:text/regex/compiler"
import regex_parser "core:text/regex/parser"


@(private)
json_parse_string :: proc(
    value: json.Value,
    required := false,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    string,
    Error,
) {
    #partial switch elem_type in value {
    case json.String:
        return value.(json.String), .None
    case:
        return "", .None
    }
}

@(private)
parse_properties :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {

    if properties_as_object, ok := value.(json.Object); ok {
        schema := get_schema(schema_context, schema_idx)
        no_of_properties := len(properties_as_object)
        // note(iyaan): I dont think the properties are likely to change for a schema after
        // it has already been parsed.
        schema.properties_children = make([dynamic]PoolIndex, 0, allocator)
        reserve(&schema.properties_children, no_of_properties)

        if no_of_properties > 0 {
            schema.type = .Object
            for prop_field in properties_as_object {
                prop_sub_schema, schema_idx, err := parse_schema_from_json_value(
                    properties_as_object[prop_field],
                    schema_context,
                )
                if err != .None {
                    log.infof("Parsing properties failed (field=%v) : %v", prop_field, err)
                    panic("Could not parse properties schema")
                }
                prop_sub_schema.name = prop_field
                append(&schema.properties_children, schema_idx)
            }
        }
    } else {
        return .Invalid_Object_Type
    }

    return .None
}

@(private)
parse_pattern_properties :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {

    if properties_as_object, ok := value.(json.Object); ok {
        schema := get_schema(schema_context, schema_idx)
        // note(iyaan): Allocate for the regular expressions
        no_of_properties := len(properties_as_object)
        schema.pattern_regex = make([dynamic]regex.Regular_Expression, 0, allocator)
        schema.pattern_properties = make([dynamic]PoolIndex, 0, allocator)
        reserve(&schema.pattern_properties, no_of_properties)
        reserve(&schema.pattern_regex, no_of_properties)

        for prop_field in properties_as_object {
            prop_sub_schema, schema_idx, err := parse_schema_from_json_value(
                properties_as_object[prop_field],
                schema_context,
            )
            prop_sub_schema.name = prop_field
            if err != .None {
                log.infof("Parsing prefix properties failed (field=%v) : %v", prop_field, err)
                return err
            }
            prop_sub_schema.name = prop_field
            r_regex, regex_create_err := regex.create(
                prop_field,
                // note(iyaan): I have seen some spec tests like
                // in additionalProperties.json where the pattern
                // had non-ascii characters, so i am adding the unicode
                // flag here
                {regex_common.Flag.No_Capture, regex_common.Flag.Unicode},
                allocator,
            )

            switch error_type in regex_create_err {
            case regex_parser.Error:
                log.infof("Regex parser error (%v)", regex_create_err.(regex_parser.Error))
                return .Regex_Parser_Error
            case regex_compiler.Error:
                if val, ok := regex_create_err.(regex_compiler.Error); val != .None {
                    return .Regex_Compiler_Error
                }
            case regex.Creation_Error:
                if val, ok := regex_create_err.(regex.Creation_Error); val != .None {
                    log.infof("Regex creation for pattern failed (%v)", regex_create_err)
                    return .Regex_Creation_Failed
                }
            }

            append(&schema.pattern_regex, r_regex)
            append(&schema.pattern_properties, schema_idx)
            assert(
                len(schema.pattern_regex) == len(schema.pattern_properties),
                "Regex and properties array mismatch",
            )
        }
    } else {
        return .Invalid_Object_Type
    }

    return .None
}

parse_additional_properties :: proc (
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
    
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.additional_properties = idx
    return .None
}

@(private)
parse_property_names :: proc (
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
    
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.property_names = idx
    return .None
}

@(private)
parse_schema_field :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.schema = json_parse_string(value) or_return
    return .None
}

@(private)
parse_title :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.title = json_parse_string(value) or_return
    return .None
}

@(private)
parse_id :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.id = json_parse_string(value) or_return
    return .None
}

@(private)
parse_comment :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.comment = json_parse_string(value) or_return
    return .None
}

@(private)
parse_description :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.description = json_parse_string(value) or_return
    return .None
}

parse_ref :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.ref = json_parse_string(value) or_return
    assert(schema_context.refs_to_resolve != nil)

    ref_info := RefsToResolve {
        ref           = schema.ref,
        source_schema = schema_idx,
    }
    append(&schema_context.refs_to_resolve, ref_info)

    return .None
}

@(private)
parse_defs :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    // note(iyaan): Parse any of $defs defined in a schema
    // From what I have seen $defs allow schemas nested
    // under keywords. e.g,
    // "$defs": {
    //     "foo1": {
    //         "foo2": {
    //             "type": number
    //         }
    //     }
    // }
    schema := get_schema(schema_context, schema_idx)
    if defs_object, ok := value.(json.Object); ok {
        for key in defs_object {
            def_value := defs_object[key]
            subschema, idx, def_subschema_err := parse_schema_from_json_value(
                def_value,
                schema_context,
                allocator,
            )
            if def_subschema_err != .None {
                // TODO: Remove this panic in time
                panic("Could not parse subschema inside $defs")
            }
            schema.defs[key] = idx
        }
    } else {
        return .Invalid_Object_Type
    }

    return .None
}

parse_schema_from_json_value :: proc(
    value: json.Value,
    schema_context: ^Context,
    allocator := context.allocator,
    logger := context.logger,
) -> (
    schema_struct: ^Schema,
    schema_idx: PoolIndex,
    err: Error,
) {
    if parsed_json, ok := value.(json.Object); ok {
        append(&schema_context.schema_pool, Schema{})
        schema_struct = &schema_context.schema_pool[len(schema_context.schema_pool) - 1]
        schema_idx = PoolIndex(len(schema_context.schema_pool) - 1)

        // Parse any keywords existing and set appropriate
        // flags for the validation stage. Will parse both
        // the applicators and the valiators keywords
        any_keywords_existed := false
        for keyword_info, idx in keywords_table {
            val := parsed_json[keyword_info.keyword]
            parse_proc := keyword_info.parse_proc
            if val != nil && parse_proc != nil {
                any_keywords_existed = true
                parse_err := parse_proc(val, schema_idx, schema_context, allocator)
                if parse_err == .None {
                    // Setting the bit on keywords that needs
                    // to be validated
                    schema_struct.validation_flags += {keyword_info.type}
                } else {
                    log.infof("Could not parse (%v), returned (%v)", val, parse_err)
                    return schema_struct, schema_idx, parse_err
                }
            }

            // note(iyaan): Keeping this until all keywords
            // have been properly implemented
            if val != nil && parse_proc == nil {
                log.errorf("(%v) cannot parse yet", keyword_info.keyword)
            }
        }


        // Determine whether this current schema is just a bogus
        // container
        schema_struct.is_empty_container = !any_keywords_existed


        // Here we need to gather all the keys that are not
        // keywords belonging to either applicator or validator or
        // any of the other keywords. This needs to be recursive.
        for key in parsed_json {
            is_key_vocabulary := false
            for info in keywords_table {
                if strings.compare(info.keyword, key) == 0 {
                    is_key_vocabulary = true
                }
            }

            if !is_key_vocabulary {
                bogus_schema, schema_idx := parse_schema_from_json_value(
                    parsed_json[key],
                    schema_context,
                    allocator,
                ) or_return
                bogus_schema.name = key
                schema_struct.other_keys[key] = schema_idx
            }
        }


        return schema_struct, schema_idx, .None
    } else if parsed_json, ok := value.(json.Boolean); ok {
        // note(iyaan): Handle just boolean value schemas
        append(&schema_context.schema_pool, Schema{})
        schema_idx = PoolIndex(len(schema_context.schema_pool) - 1)
        schema_struct = &schema_context.schema_pool[len(schema_context.schema_pool) - 1]
        if parsed_json {
            schema_struct.is_bool_schema = true
            schema_struct.bool_schema_val = true
            return schema_struct, schema_idx, .None
        } else {
            schema_struct.is_bool_schema = true
            schema_struct.bool_schema_val = false
            return schema_struct, schema_idx, .None
        }
    } else {
        return schema_struct, schema_idx, .Invalid_Object_Type
    }
}

@(private)
parse_type :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    // note(iyaan): type can be either a string or a value
    // of strings that specify that an elem can be multiple types

    get_type :: proc(type_str: string) -> InstanceTypes {
        if strings.compare(type_str, "null") == 0 {
            return .Null
        } else if strings.compare(type_str, "boolean") == 0 {
            return .Boolean
        } else if strings.compare(type_str, "object") == 0 {
            return .Object
        } else if strings.compare(type_str, "array") == 0 {
            return .Array
        } else if strings.compare(type_str, "number") == 0 {
            return .Number
        } else if strings.compare(type_str, "integer") == 0 {
            return .Integer
        } else if strings.compare(type_str, "string") == 0 {
            return .String
        } else {
            return .Invalid
        }

    }

    if array_type, ok := value.(json.Array); ok {
        types_slice := make(CompositeTypes, len(array_type), allocator)

        for type_val_elem, idx in array_type {
            if type_val_elem_str, ok := type_val_elem.(json.String); ok {
                type_val := get_type(type_val_elem_str)
                if type_val != .Invalid {
                    types_slice[idx] = type_val
                } else {
                    return .Invalid_Instance_Type
                }
            } else {
                return .Invalid_String_Type
            }
        }

        schema.type = types_slice
    } else if string_type, ok := value.(json.String); ok {
        type_val := get_type(string_type)
        if type_val != .Invalid {
            schema.type = type_val
        } else {
            return .Invalid_Instance_Type
        }
    } else {
        return .Expected_Array_Or_String
    }


    return .None
}

@(private)
parse_enum :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Array:
        as_array_val := value.(json.Array)
        // note(iyaan): Here the enum values are just are slice
        // of the original values parsed from the json module
        // We need to keep the json value around until we have
        // parsed and validated using a schema as values inside the
        // schema are referencing non-owned values
        schema.enums = as_array_val[:]
    case:
        return .Invalid_Enum_Type
    }
    return .None
}

@(private)
parse_const :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    schema.const = value
    return .None
}

@(private)
parse_min_length :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Integer:
        schema.min_length = int(value.(json.Integer))
    case json.Float:
        if can_float_be_int(value.(json.Float)) {
            schema.min_length = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    case:
        return .Invalid_Integer_Type
    }
    return .None
}

@(private = "file")
// Just output project related errors from
// the union type error of the regex package
get_regex_err :: proc(regex_err: regex.Error) -> Error {
    switch error_type in regex_err {
    case regex_parser.Error:
        log.infof("regex parser error (%v)", regex_err.(regex_parser.Error))
        return .Regex_Parser_Error
    case regex_compiler.Error:
        if val, ok := regex_err.(regex_compiler.Error); val != .None {
            log.infof("regex compiler (%v)", regex_err)
            return .Regex_Compiler_Error
        }
    case regex.Creation_Error:
        if val, ok := regex_err.(regex.Creation_Error); val != .None {
            log.infof("regex creation for pattern failed (%v)", regex_err)
            return .Regex_Creation_Failed
        }
    }
    return .None
}

@(private)
parse_pattern :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.String:
        // note(iyaan): Compile the string
        // pattern to a regex
        r_regex, regex_create_err := regex.create(
            value.(json.String),
            {regex_common.Flag.No_Capture, regex_common.Flag.Unicode},
            allocator,
        )
        get_regex_err(regex_create_err) or_return

        schema.pattern = r_regex
    case:
        return .Invalid_String_Type
    }
    return .None
}

@(private)
parse_max_length :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Integer:
        schema.max_length = int(value.(json.Integer))
    case json.Float:
        if can_float_be_int(value.(json.Float)) {
            schema.max_length = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    case:
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_exclusive_max :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Float:
        schema.exclusive_max = value.(json.Float)
    case json.Integer:
        schema.exclusive_max = f64(value.(json.Integer))
    case:
        return .Invalid_Number_Type
    }
    return .None
}

@(private)
parse_exclusive_min :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Float:
        schema.exclusive_min = value.(json.Float)
    case json.Integer:
        schema.exclusive_min = f64(value.(json.Integer))
    case:
        return .Invalid_Number_Type
    }
    return .None
}

@(private)
parse_minimum :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Float:
        schema.minimum = value.(json.Float)
    case json.Integer:
        schema.minimum = f64(value.(json.Integer))
    case:
        return .Invalid_Number_Type
    }
    return .None
}

@(private)
parse_maximum :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Float:
        schema.maximum = value.(json.Float)
    case json.Integer:
        schema.maximum = f64(value.(json.Integer))
    case:
        return .Invalid_Number_Type
    }
    return .None
}

@(private)
parse_multipleof :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    #partial switch type in value {
    case json.Float:
        schema.multipleof = value.(json.Float)
    case json.Integer:
        schema.multipleof = f64(value.(json.Integer))
    case:
        return .Invalid_Number_Type
    }
    return .None
}

@(private)
parse_required :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if array_value, ok := value.(json.Array); ok {
        // note(iyaan): Do i need a cloned slice here really?
        // I mean i cant just assign the array_value here
        // to the slice since its internal values are json.Values
        // but the slice is []string. Maybe I can just set the internal
        // data of the slice to it.
        new_slice := make([]string, len(array_value), allocator)
        for val, idx in array_value {
            if str_val, ok := val.(json.String); ok {
                new_slice[idx] = str_val
            } else {
                return .Invalid_String_Type
            }
        }
        schema.required = new_slice
        return .None
    } else {
        return .Invalid_Array_Type
    }
}

@(private)
parse_max_items :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        assert(value_as_int >= 0, "maxItems should be positive")
        schema.max_items = int(value_as_int)
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value_as_float) {
            schema.max_items = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_min_items :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        assert(value_as_int >= 0, "minItems should be positive")
        schema.min_items = int(value_as_int)
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value_as_float) {
            schema.min_items = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_max_properties :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        value_as_int := int(value_as_int)
        assert(value_as_int >= 0, "maxProperties should be positive (I think)")
        schema.max_properties = value_as_int
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value.(json.Float)) {
            schema.max_properties = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_min_properties :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        value_as_int := int(value_as_int)
        assert(value_as_int >= 0, "minProperties should be positive (I think)")
        schema.min_properties = value_as_int
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value.(json.Float)) {
            schema.min_properties = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_max_contains :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        value_as_int := int(value_as_int)
        assert(value_as_int >= 0, "maxContains should be positive")
        schema.max_contains = value_as_int
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value.(json.Float)) {
            schema.max_contains = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_min_contains :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_int, ok := value.(json.Integer); ok {
        value_as_int := int(value_as_int)
        assert(value_as_int >= 0, "minContains should be positive")
        schema.min_contains = value_as_int
    } else if value_as_float, ok := value.(json.Float); ok {
        if can_float_be_int(value.(json.Float)) {
            schema.min_contains = int(value.(json.Float))
        } else {
            return .Invalid_Integer_Type
        }
    } else {
        return .Invalid_Integer_Type
    }
    return .None
}

parse_allof :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    if value_as_array, ok := value.(json.Array); ok {
        schema := get_schema(schema_context, schema_idx)
        no_of_subschemas := len(value_as_array)
        for subschema_val in value_as_array {
            _, idx, _ := parse_schema_from_json_value(subschema_val, schema_context, allocator)
            // note(iyaan): Has to make sure that allof field
            // dynamic array is inititalized with the allocator
            // we need
            append(&schema.allof, idx)
        }

        return .None
    }

    return .Invalid_Array_Type
}

parse_anyof :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    if value_as_array, ok := value.(json.Array); ok {
        schema := get_schema(schema_context, schema_idx)
        no_of_subschemas := len(value_as_array)
        for subschema_val in value_as_array {
            _, idx, _ := parse_schema_from_json_value(subschema_val, schema_context, allocator)
            // note(iyaan): Has to make sure that allof field
            // dynamic array is inititalized with the allocator
            // we need
            append(&schema.anyof, idx)
        }

        return .None
    }

    return .Invalid_Array_Type
}

parse_oneof :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    if value_as_array, ok := value.(json.Array); ok {
        schema := get_schema(schema_context, schema_idx)
        no_of_subschemas := len(value_as_array)
        for subschema_val in value_as_array {
            _, idx, _ := parse_schema_from_json_value(subschema_val, schema_context, allocator)
            // note(iyaan): Has to make sure that allof field
            // dynamic array is inititalized with the allocator
            // we need
            append(&schema.oneof, idx)
        }

        return .None
    }

    return .Invalid_Array_Type
}

parse_if :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema._if = idx
    return .None
}

parse_then :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.then = idx
    return .None
}

@(private)
parse_else :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema._else = idx
    return .None
}

@(private)
parse_not :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.not = idx
    return .None
}

@(private)
parse_contains :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.contains = idx
    return .None
}

@(private)
parse_items :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    _, idx := parse_schema_from_json_value(value, schema_context, allocator) or_return
    schema.items = idx
    return .None
}

@(private)
parse_prefix_items :: proc(
    value: json.Value,
    schema_idx: PoolIndex,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    schema := get_schema(schema_context, schema_idx)
    if value_as_array, ok := value.(json.Array); ok {
        for schema_elem in value_as_array {
            _, idx := parse_schema_from_json_value(
                schema_elem,
                schema_context,
                allocator,
            ) or_return
            append(&schema.prefix_items, idx)
        }
        return .None
    } else {
        return .Invalid_Array_Type
    }
}

parse_schema_from_string :: proc(
    schema: string,
    schema_context: ^Context,
    allocator := context.allocator,
) -> (
    schema_struct: ^Schema,
    pool_idx: PoolIndex,
    err: Error,
) {
    parsed_json, parsed_json_err := json.parse_string(schema, json.DEFAULT_SPECIFICATION, true)
    if parsed_json_err != .None {
        log.infof("json.parse_string returned error (%v)", parsed_json_err)
        return schema_struct, pool_idx, .Json_Parse_Error
    }

    schema_struct, pool_idx, err = parse_schema_from_json_value(
        parsed_json,
        schema_context,
        allocator,
    )
    if err != (.None) {
        log.infof("_parse_from_json_value() returned %v\n", err)
        return schema_struct, pool_idx, err
    }

    return schema_struct, pool_idx, .None
}

validate_string_with_schema :: proc(
    data: string,
    schema: ^Schema,
    ctx: ^Context,
    allocator := context.allocator,
) -> Error {
    // note(iyaan): In odin parsing without JSON5 spec will
    // not work for single data at root level that is not
    // enclosed in a top-level object
    parsed_json, ok := json.parse_string(
        data,
        spec = json.Specification.JSON5,
        parse_integers = true,
    )
    if ok != .None {
        log.infof("json.parse_string returned error (%v)", ok)
        return .Json_Parse_Error
    }

    validate_json_value_with_subschema(parsed_json, schema, ctx) or_return

    return .None
}

@(private)
// json_value is the parent object which contains the
// properties, not the actual property value itself
validate_properties :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    // If the data is not an object it does not need to check
    // the properties
    if _, ok := json_value.(json.Object); !ok {
        return .None
    }
    json_value_as_obj := json_value.(json.Object)
    for prop in subschema.properties_children {
        prop_schema := &ctx.schema_pool[prop]
        val := json_value_as_obj[prop_schema.name]
        if val != nil {
            prop_valid_err := validate_json_value_with_subschema(val, prop_schema, ctx)
            if prop_valid_err != .None {
                return prop_valid_err
            }
        }
    }
    return .None
}

@(private)
// json_value is the parent object which contains the
// properties, not the actual property value itself
// patternProperties: {
// }
validate_pattern_properties :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if _, ok := json_value.(json.Object); !ok {
        return .None
    }
    json_value_as_obj := json_value.(json.Object)
    for obj_prop in json_value_as_obj {
        for prop_schema_idx, _idx in subschema.pattern_properties {
            // note(iyaan): Check if the current property name matches
            // any of the patterns stored in the schema
            prop_regex := subschema.pattern_regex[_idx]
            prop_schema := get_schema(ctx, prop_schema_idx)
            val := json_value_as_obj[obj_prop]

            capture, ok := regex.match_and_allocate_capture(prop_regex, obj_prop)
            // note(iyaan): This constant allocation and deallocation is bad. Fix
            // this later
            regex.destroy_capture(capture)

            // If the property of the object is match with
            // the regex in the schema
            if ok && val != nil {
                prop_valid_err := validate_json_value_with_subschema(val, prop_schema, ctx)
                if prop_valid_err != .None {
                    return prop_valid_err
                }
            }
        }
    }

    return .None
}

@(private)
// Validation succeeds if the schema validates
// against each value not matched by other object
// applicators in this vocabulary.
validate_additional_properties :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if _, ok := json_value.(json.Object); !ok {
        return .None
    }
    json_value_as_obj := json_value.(json.Object)

    for obj_prop in json_value_as_obj {
        // note(iyaan): Check if the property matches
        // against any `properties`
        matches_properties := false
        for prop_idx in subschema.properties_children {
            prop_schema := get_schema(ctx, prop_idx)
            assert(prop_schema.name != "", "Property name not set in schema")
            if strings.compare(obj_prop, prop_schema.name) == 0 {
                matches_properties = true
            }
        }

        // note(iyaan): Check if the property matches against
        // any `patternProperties`
        matches_pattern_properties := false
        for prop_idx, _idx in subschema.pattern_properties {
            prop_schema := get_schema(ctx, prop_idx)
            prop_regex := subschema.pattern_regex[_idx]
            assert(prop_schema.name != "", "Property name not set in schema")
            
            capture, ok := regex.match_and_allocate_capture(prop_regex, obj_prop)
            // TODO: Too much allocation in a loop for my taste
            regex.destroy_capture(capture)

            if ok {
                matches_pattern_properties = true
            }
        }

        if !matches_properties && !matches_pattern_properties {
            val := json_value_as_obj[obj_prop]
            additional_properties_schema := get_schema(ctx, subschema.additional_properties)
            additional_prop_err := validate_json_value_with_subschema(val, additional_properties_schema, ctx)
            if additional_prop_err != .None {
                log.infof("additional_properties validation failed (%v)", additional_prop_err)
                return additional_prop_err
            }
        }
        
    }

    return .None
}

@(private)
// Validation succeeds if the schema validates
// against every property name in the instance.
validate_property_names :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if _, ok := json_value.(json.Object); !ok {
        return .None
    }
    json_value_as_obj := json_value.(json.Object)
    property_name_schema := get_schema(ctx, subschema.property_names)
    for prop_name in json_value_as_obj {
        // note(iyaan): Validate the property name
        // not the contents
        prop_name_err := validate_json_value_with_subschema(
            prop_name,
            property_name_schema,
            ctx
        )
        if prop_name_err != .None {
            log.infof("propertyNames validation failed (%v)",
                      prop_name_err
                     )
            return prop_name_err
        }
    }

    return .None
}

validate_json_value_with_subschema :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if subschema.is_bool_schema {
        return subschema.bool_schema_val ? .None : .Bool_Schema_False
    }

    for validation_keyword in subschema.validation_flags {
        log.debugf("Performing validation (%v) on (%v)", validation_keyword, json_value)
        validation_keyword_info := keywords_table[validation_keyword]
        validation_proc := validation_keyword_info.validation_proc
        if validation_proc != nil {
            validation_err := validation_proc(json_value, subschema, ctx)
            if validation_err != .None {
                log.infof(
                    "Validation (%v) failed with error (%v)",
                    validation_keyword,
                    validation_err,
                )
                return validation_err
            } else {
                log.debugf("Validation (%v) succesful", validation_keyword)
            }
        }
    }

    return .None
}

@(private = "file")
can_float_be_int :: proc(f: f64) -> bool {
    _, frac_part := math.modf_f64(f)
    if frac_part == 0.0 {
        return true
    } else {
        return false
    }
}

@(private)
validate_type :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    check_against_type_val :: proc(value: json.Value, t: InstanceTypes) -> bool {
        // Check if data value is compatible with a given type (t)
        switch t {
        case .Integer:
            if int_json_val, ok := value.(json.Integer); ok {
                return true
            } else if float_json_val, ok := value.(json.Float); ok {
                // Check if float value is an equivalent integer
                return can_float_be_int(float_json_val)
            }
        case .Number:
            if float_json_val, ok := value.(json.Float); ok {
                return true
            } else if int_json_val, ok := value.(json.Integer); ok {
                // An integer is a valid expected data type
                // for an type of number
                return true
            }
        case .Boolean:
            if _, ok := value.(json.Boolean); ok {
                return true
            }
        case .String:
            if _, ok := value.(json.String); ok {
                return true
            }
        case .Null:
            if _, ok := value.(json.Null); ok {
                return true
            }
        case .Array:
            if _, ok := value.(json.Array); ok {
                return true
            }
        case .Object:
            if _, ok := value.(json.Object); ok {
                return true
            }
        case .Invalid:
            return false
        }
        return false
    }

    switch t in subschema.type {
    case InstanceTypes:
        // Single type
        ok := check_against_type_val(json_value, subschema.type.(InstanceTypes))
        if !ok {
            return .Type_Validation_Failed
        }
    case CompositeTypes:
        // Multiple type possibilities to check. Only has to match
        // one to pass
        matched_once := false
        for type in subschema.type.(CompositeTypes) {
            if check_against_type_val(json_value, type) {
                matched_once = true
                break
            }
        }
        if !matched_once {
            return .Type_Validation_Failed
        }
    case:
        return .Type_Validation_Failed
    }

    return .None
}

@(private)
validate_minimum :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    #partial switch type in json_value {
    case json.Float:
        num_val := json_value.(json.Float)
        if num_val < subschema.minimum {
            return .Minimum_Validation_Failed
        }
    case json.Integer:
        num_val := f64(json_value.(json.Integer))
        if num_val < subschema.minimum {
            return .Minimum_Validation_Failed
        }
    case:
        return .None
    }

    return .None
}

@(private)
validate_maximum :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    #partial switch type in json_value {
    case json.Float:
        num_val := json_value.(json.Float)
        if num_val > subschema.maximum {
            return .Maximum_Validation_Failed
        }
    case json.Integer:
        num_val := f64(json_value.(json.Integer))
        if num_val > subschema.maximum {
            return .Maximum_Validation_Failed
        }
    case:
        return .None
    }

    return .None
}

@(private)
validate_exclusive_max :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {

    #partial switch type in json_value {
    case json.Float:
        num_val := json_value.(json.Float)
        if num_val >= subschema.exclusive_max {
            return .Exclusive_Maximum_Validation_Failed
        }
    case json.Integer:
        num_val := f64(json_value.(json.Integer))
        if num_val >= subschema.exclusive_max {
            return .Exclusive_Maximum_Validation_Failed
        }
    case:
        return .None
    }

    return .None
}

@(private)
validate_exclusive_min :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {

    #partial switch type in json_value {
    case json.Float:
        num_val := json_value.(json.Float)
        if num_val <= subschema.exclusive_min {
            return .Exclusive_Minimum_Validation_Failed
        }
    case json.Integer:
        num_val := f64(json_value.(json.Integer))
        if num_val <= subschema.exclusive_min {
            return .Exclusive_Minimum_Validation_Failed
        }
    case:
        return .None
    }

    return .None
}

@(private)
validate_max_length :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    #partial switch type in json_value {
    case json.String:
        // note(iyaan): Spec expects strings to be utf-8
        // encoded. Cannot just retreive the raw byte length
        // of a string. Need logical length of graphemes
        rune_len := 0
        for r in json_value.(json.String) {
            rune_len += 1
        }

        if rune_len > subschema.max_length {
            return .Maxlength_Validation_Failed
        } else {
            return .None
        }
    case:
        // A non-string value is valid
        return .None
    }
}

@(private)
validate_min_length :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    #partial switch type in json_value {
    case json.String:
        rune_len := 0
        for r in json_value.(json.String) {
            rune_len += 1
        }

        if rune_len < subschema.min_length {
            return .Minlength_Validation_Failed
        } else {
            return .None
        }
    case:
        // A non-string value is valid
        return .None
    }
}

@(private)
validate_pattern :: proc (json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    if str_value, ok := json_value.(json.String); ok {
        re := subschema.pattern
        capture, ok := regex.match_and_allocate_capture(re, str_value)
        regex.destroy_capture(capture)

        if ok {
            return .None
        } else {
            return .Pattern_Validation_Failed
        }

    } else {
        // Does not apply to non-strings
        return .None
    }
}

@(private)
validate_multipleof :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    float_is_multiple :: proc(n1: f64, n2: f64) -> Error {
        // note(iyaan): Perform the float division
        // and then look at the fractional part of the result
        // to determine if divisible
        n := n1 / n2
        _, frac := math.modf_f64(n)
        if frac == 0.0 {
            return .None
        } else {
            return .Multiple_Of_Validation_Failed
        }
    }

    #partial switch type in json_value {
    case json.Float:
        return float_is_multiple(json_value.(json.Float), subschema.multipleof)
    case json.Integer:
        return float_is_multiple(f64(json_value.(json.Integer)), subschema.multipleof)
    case:
        // A non-number value is valid
        return .None
    }
}

// Checks whether the type of val1 and its
// value is equal to that of val2
@(private)
check_if_match_base :: proc(val1: json.Value, val2: json.Value) -> bool {
    #partial switch val1_type in val1 {
    case json.Integer:
        if int_json_val, ok := val2.(json.Integer); ok {
            if int_json_val == val1.(json.Integer) {
                return true
            }
        } else if float_json_val, ok := val2.(json.Float); ok {
            if float_json_val == f64(val1.(json.Integer)) {
                return true
            }
        } else {
            return false
        }
    case json.Float:
        if float_json_val, ok := val2.(json.Float); ok {
            if float_json_val == val1.(json.Float) {
                return true
            }
        } else if int_json_val, ok := val2.(json.Integer); ok {
            if int_json_val == i64(val1.(json.Float)) {
                return true
            }
        } else {
            return false
        }
    case json.Boolean:
        if bool_json_val, ok := val2.(json.Boolean); ok {
            if bool_json_val == val1.(json.Boolean) {
                return true
            }
        }
    case json.String:
        if str_json_val, ok := val2.(json.String); ok {
            if str_json_val == val1.(json.String) {
                return true
            }
        }
    case json.Null:
        if null_json_val, ok := val2.(json.Null); ok {
            if null_json_val == val1.(json.Null) {
                return true
            }
        }
    }

    return false
}

@(private)
check_if_match_object :: proc(enum_val: json.Object, data_json_object: json.Object) -> bool {
    if len(enum_val) != len(data_json_object) {
        return false
    }
    for key in enum_val {
        obj_val := enum_val[key]
        switch obj_val_type in obj_val {
        case json.Integer, json.Float, json.Boolean, json.String, json.Null:
            if !check_if_match_base(obj_val, data_json_object[key]) {
                return false
            }
        case json.Array:
            if data_json_object_arr_val, ok := data_json_object[key].(json.Array); ok {
                if !check_if_match_array(obj_val.(json.Array), data_json_object_arr_val) {
                    return false
                }
            } else {
                return false
            }

        case json.Object:
            if data_json_object_obj_val, ok := data_json_object[key].(json.Object); ok {
                if !check_if_match_object(obj_val.(json.Object), data_json_object_obj_val) {
                    return false
                }
            } else {
                return false
            }
        }
    }
    return true
}

@(private)
check_if_match_array :: proc(enum_val: json.Array, data_json_array: json.Array) -> bool {
    if len(enum_val) != len(data_json_array) {
        return false
    }
    for val, idx in enum_val {
        switch val_type in val {
        case json.Integer, json.Float, json.Boolean, json.String, json.Null:
            check_if_match_base(val, data_json_array[idx]) or_return
        case json.Array:
            if data_json_array_val, ok := data_json_array[idx].(json.Array); ok {
                check_if_match_array(val.(json.Array), data_json_array_val) or_return
            } else {
                return false
            }
        case json.Object:
            if data_json_object_val, ok := data_json_array[idx].(json.Object); ok {
                check_if_match_object(val.(json.Object), data_json_object_val) or_return
            } else {
                return false
            }
        }
    }
    return true
}

@(private)
validate_enum :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

    // Check if the json_value is one of the values in subschema.enum
    for enum_val in subschema.enums {
        switch enum_type in enum_val {
        case json.Integer, json.Float, json.Boolean, json.String, json.Null:
            if check_if_match_base(enum_val, json_value) {
                return .None
            }
        case json.Array:
            if arr_json_value, ok := json_value.(json.Array); ok {
                if check_if_match_array(enum_val.(json.Array), arr_json_value) {
                    return .None
                }
            }
        case json.Object:
            if obj_json_value, ok := json_value.(json.Object); ok {
                if check_if_match_object(enum_val.(json.Object), obj_json_value) {
                    return .None
                }
            }
        }
    }
    return .Enum_Validation_Failed
}

@(private)
validate_required :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    if json_value_object, ok := json_value.(json.Object); ok {
        for required_key in subschema.required {
            if required_key in json_value_object {
                continue
            } else {
                return .Required_Validation_Failed
            }
        }
        return .None
    } else {
        // If not an object no need to check required fields
        return .None
    }
}

@(private)
validate_max_properties :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if json_value_object, ok := json_value.(json.Object); ok {
        if len(json_value_object) > subschema.max_properties {
            return .Max_Properties_Validation_Failed
        }
    }
    return .None
}

@(private)
validate_min_properties :: proc(
    json_value: json.Value,
    subschema: ^Schema,
    ctx: ^Context,
) -> Error {
    if json_value_object, ok := json_value.(json.Object); ok {
        if len(json_value_object) < subschema.min_properties {
            return .Min_Properties_Validation_Failed
        }
    }
    return .None
}

@(private)
validate_max_items :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    if json_value_array, ok := json_value.(json.Array); ok {
        if len(json_value_array) > subschema.max_items {
            return .Max_Items_Validation_Failed
        }
    }
    return .None
}

@(private)
validate_min_items :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    if json_value_array, ok := json_value.(json.Array); ok {
        if len(json_value_array) < subschema.min_items {
            return .Min_Items_Validation_Failed
        }
    }
    return .None
}

@(private)
validate_const :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    // Basically a watered down version of validate_enum
    // but you only have to compare against one thing
    switch const_type in subschema.const {
    case json.Integer, json.Float, json.Boolean, json.String, json.Null:
        if check_if_match_base(subschema.const, json_value) {
            return .None
        } else {
            return .Const_Validation_Failed
        }
    case json.Array:
        if json_value_as_array, ok := json_value.(json.Array); ok {
            if check_if_match_array(subschema.const.(json.Array), json_value_as_array) {
                return .None
            } else {
                return .Const_Validation_Failed
            }
        } else {
            return .Const_Validation_Failed
        }
    case json.Object:
        if json_value_as_object, ok := json_value.(json.Object); ok {
            if check_if_match_object(subschema.const.(json.Object), json_value_as_object) {
                return .None
            } else {
                return .Const_Validation_Failed
            }
        } else {
            return .Const_Validation_Failed
        }
    case:
        unreachable()
    }
}

validate_allof :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    for subschema_idx in subschema.allof {
        subschema := get_schema(ctx, subschema_idx)
        validate_json_value_with_subschema(json_value, subschema, ctx) or_return
    }
    return .None
}

validate_anyof :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    at_least_one_validated := false
    for subschema_idx in subschema.anyof {
        subschema := get_schema(ctx, subschema_idx)
        if err := validate_json_value_with_subschema(json_value, subschema, ctx); err == .None {
            at_least_one_validated = true
        }
    }
    if at_least_one_validated {
        return .None
    } else {
        return .Anyof_Validation_Failed
    }
}

validate_oneof :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    validated_schema_count := 0
    for subschema_idx in subschema.oneof {
        subschema := get_schema(ctx, subschema_idx)
        if err := validate_json_value_with_subschema(json_value, subschema, ctx); err == .None {
            validated_schema_count += 1
        }
    }
    if validated_schema_count == 1 {
        return .None
    } else {
        return .Oneof_Validation_Failed
    }
}

validate_if_then_else :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    // Will be checking the validity of the else and then schemas
    // based on the value of the if schema
    if_schema := get_schema(ctx, subschema._if)
    if_err := validate_json_value_with_subschema(json_value, if_schema, ctx)
    then_exists := SchemaKeywords.Then in subschema.validation_flags
    else_exists := SchemaKeywords.Else in subschema.validation_flags
    if then_exists {
        then_schema := get_schema(ctx, subschema.then)
        then_err := validate_json_value_with_subschema(json_value, then_schema, ctx)
        // note(iyaan): Check then schema only if passes otherwise
        // dont
        if if_err == .None {
            if then_err == .None {
                return .None
            } else {
                return .If_Then_Validation_Failed
            }
        }
    }

    if else_exists {
        else_schema := get_schema(ctx, subschema._else)
        else_err := validate_json_value_with_subschema(json_value, else_schema, ctx)

        // note(iyaan): Check then schema only if not passes otherwise
        // dont
        if if_err != .None {
            if else_err == .None {
                return .None
            } else {
                return .If_Else_Validation_Failed
            }
        }
    }

    // note(iyaan): Case where `if` exists by itself
    return .None
}

validate_not :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    not_schema := get_schema(ctx, subschema.not)
    validation_err := validate_json_value_with_subschema(json_value, not_schema, ctx)
    if validation_err != .None {
        return .None
    } else {
        return .Not_Validation_Failed
    }
}

// note(iyaan): Will also handle minContains and maxContains
// Those keywords by themselves has no effect without
// a `contain` applicator
validate_contains :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    schema_of_contains := get_schema(ctx, subschema.contains)

    min_contains_defined := SchemaKeywords.MinContains in subschema.validation_flags
    max_contains_defined := SchemaKeywords.MaxContains in subschema.validation_flags

    min := min_contains_defined ? subschema.min_contains : 1
    max := max_contains_defined ? subschema.max_contains : bits.INT_MAX

    contains_count := 0
    if value_as_array, ok := json_value.(json.Array); ok {
        for val in value_as_array {
            err := validate_json_value_with_subschema(val, schema_of_contains, ctx)
            if err == .None {
                contains_count += 1

                // Early exit for case when no max
                // contraint defined
                if min_contains_defined {
                    is_min_satisfied := contains_count >= subschema.min_contains
                    if !max_contains_defined && is_min_satisfied {
                        break
                    }
                }
            }
        }

        // Edge case min and max are set to zero. The data instance
        // is an empty array

        if contains_count < min {
            return .Min_Contains_Validation_Failed
        }

        if contains_count > max {
            return .Max_Contains_Validation_Failed
        }
    }

    return .None
}

@(private)
validate_items :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
    items_schema := get_schema(ctx, subschema.items)
    // note(iyaan): Validate prefixItems first. Things covered by
    // the prefixItems does need to have items schema validated against
    // them
    if json_value_array, ok := json_value.(json.Array); ok {
        // How many values in the data array to skip to perform the
        // items validation
        rest_start_idx: int = 0
        if SchemaKeywords.PrefixItems in subschema.validation_flags {
            for elem, idx in json_value_array {
                if idx < len(subschema.prefix_items) {
                    prefix_elem_schema := get_schema(ctx, PoolIndex(subschema.prefix_items[idx]))
                    rest_start_idx = idx
                    err := validate_json_value_with_subschema(elem, prefix_elem_schema, ctx)
                    if err != .None {
                        log.infof("prefix item schema failed (%v)", err)
                        return .Prefix_Items_Validation_Failed
                    }
                }

            }
            rest_start_idx += 1
        }
        if rest_start_idx < len(json_value_array) {
            // note(iyaan): Perform items validation here
            for idx in rest_start_idx ..< len(json_value_array) {
                err := validate_json_value_with_subschema(json_value_array[idx], items_schema, ctx)
                if err != .None {
                    log.infof("item schema failed (%v)", err)
                    return .Items_Validation_Failed
                }

            }
        }

        // note(iyaan): If the data has no more elems after checking
        // prefixItems no need to care
    }

    return .None
}

// For now will only support finding
// schemas through relative fragment
// pointers. Any URI path in $ref actually needs
// to do proper resolving of that URI path to whatever
// schema it is pointing to
get_schema_from_ref_path :: proc(
    ref_path: string,
    root_schema: ^Schema,
    ctx: ^Context,
    allocator := context.allocator,
) -> (
    schema: ^Schema,
    err: Error,
) {
    DEFS_KEYWORDS :: "$defs"

    // Pass the path after the $defs part
    // e.g: Given a full path like this
    // $defs/personal/address -> personal/address
    search_defs :: proc(
        root_schema: ^Schema,
        defs: ^map[string]PoolIndex,
        path: []string,
        ctx: ^Context,
    ) -> (
        target_schema: ^Schema,
        err: Error,
    ) {
        if len(path) == 0 {
            return target_schema, .Ref_Schema_Not_Found
        }

        if path[0] in defs {
            cur_schema: ^Schema = get_schema(ctx, defs[path[0]])
            if len(path) > 1 {
                for pt in path[1:] {
                    if pt in cur_schema.other_keys {
                        cur_schema = get_schema(ctx, cur_schema.other_keys[pt])
                    } else {
                        return target_schema, .Ref_Schema_Not_Found
                    }
                }
            }
            return cur_schema, .None
        }
        return target_schema, .Ref_Path_Not_Found_In_Defs
    }

    target_schema_path := ref_path
    cur_schema: ^Schema = root_schema
    paths := slashpath.split_elements(target_schema_path, allocator)
    assert(paths[0] == "#", "Ref path needs a relative fragment path")
    if len(paths[1:]) > 0 {
        if strings.compare(paths[1], DEFS_KEYWORDS) == 0 {
            if len(paths[2:]) == 0 {
                return schema, .Ref_Non_Schema
            } else {
                // Go down the $defs route
                target_schema := search_defs(
                    cur_schema,
                    &cur_schema.defs,
                    paths[2:],
                    ctx,
                ) or_return
                return target_schema, .None
            }
        } else {
            assert(1 == 0, "Referencing schemas not inside $defs not implemented")
        }
    }

    return cur_schema, .None
}

// note(iyaan): Make sure that this is called
// before validation has been called
resolve_refs_to_schemas :: proc(
    root_schema: ^Schema,
    schema_context: ^Context,
    allocator := context.allocator,
) -> Error {
    for ref_info in schema_context.refs_to_resolve {
        target_schema, err := get_schema_from_ref_path(
            ref_info.ref,
            root_schema,
            schema_context,
            allocator,
        )

        if err != .None {
            log.infof("Could not resolve ref (%v) : %v", ref_info.ref, err)
            return err
        } else {
            // note(iyaan): Replace the schema in which $ref field was in
            // with the resolved schema
            // ref_info.source_schema^ = target_schema^
            source_schema := get_schema(schema_context, ref_info.source_schema)
            source_schema^ = target_schema^
        }
    }
    return .None
}
