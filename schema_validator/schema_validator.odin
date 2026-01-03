package schema_validator

import "core:encoding/json"
import "core:log"
import "core:math"
import "core:path/slashpath"
import "core:strings"

InstanceTypes :: enum {
    Null,
    Boolean,
    Object,
    Array,
    Number,
    Integer,
    String,
}

Error :: enum {
    None,

    // JSON Errors
    Json_Parse_Error,

    // Parsing Errors
    Invalid_Instance_Type,
    Invalid_Number_Type,
    Invalid_Integer_Type,
    Invalid_Enum_Type,
    Invalid_Object_Type,
    Invalid_String_Type,
    Invalid_Array_Type,

    // Validation Errors
    Type_Validation_Failed,
    Enum_Validation_Failed,
    Clashing_Property_Type,
    Minimum_Validation_Failed,
    Maximum_Validation_Failed,
    Required_Validation_Failed,
    Const_Validation_Failed,
    Maxlength_Validation_Failed,
    Minlength_Validation_Failed,
    Exclusive_Minimum_Validation_Failed,
    Exclusive_Maximum_Validation_Failed,
    Multiple_Of_Validation_Failed,

    // Allocation Errors
    Allocation_Error,
}

// Takes a pointer to the schema to set the correct parameter
// to the parsed value
@(private)
ParseProc :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error
// No need to take a pointer since it does not need to set any
// state in the schema. It just needs to read in the correct
// field in the schema struct
@(private)
ValidationProc :: proc(value: json.Value, schema: JsonSchema) -> Error

@(private)
KeywordValidationInfo :: struct {
    keyword:         string,
    type:            SchemaKeywords,
    validation_proc: ValidationProc,
}

@(private)
KeywordParseInfo :: struct {
    keyword:    string,
    type:       SchemaKeywords,
    parse_proc: ParseProc,
}

// TODO: Implement parsing procedure for each of the keywords -_-
@(private)
keywords_parse_table := [?]KeywordParseInfo {
    // Applicators
    {"allOf", .AllOf, nil},
    {"anyOf", .AnyOf, nil},
    {"oneOf", .OneOf, nil},
    {"if", .If, nil},
    {"then", .Then, nil},
    {"else", .Else, nil},
    {"not", .Not, nil},
    {"properties", .Properties, parse_properties},
    {"additionalProperties", .AdditionalProperties, nil},
    {"patternProperties", .PatternProperties, nil},
    {"dependentSchemas", .DependentSchemas, nil},
    {"propertyNames", .PropertyNames, nil},
    {"contains", .Contains, nil},
    {"items", .Items, nil},
    {"prefixItems", .PrefixItems, nil},

    // Validators
    {"type", .Type, parse_type},
    {"enum", .Enum, parse_enum},
    {"const", .Const, parse_const},
    {"maxLength", .MaxLength, parse_max_length},
    {"minLength", .MinLength, parse_min_length},
    {"pattern", .Pattern, nil},
    {"exclusiveMaximum", .ExclusiveMaximum, parse_exclusive_max},
    {"exclusiveMinimum", .ExclusiveMinimum, parse_exclusive_min},
    {"maximum", .Maximum, parse_maximum},
    {"minimum", .Minimum, parse_minimum},
    {"multipleOf", .MultipleOf, parse_multipleof},
    {"dependentRequired", .DependentRequired, nil},
    {"maxProperties", .MaxProperties, nil},
    {"minProperties", .MinProperties, nil},
    {"required", .Required, parse_required},
    {"maxItems", .MaxItems, nil},
    {"minItems", .MinItems, nil},
    {"maxContains", .MaxContains, nil},
    {"minContains", .MinContains, nil},
    {"uniqueItems", .UniqueItems, nil},
}

// TODO: Implement validation procedure for each of the keywords -_-
@(private)
keywords_validation_table := [?]KeywordValidationInfo {
    // Applicators
    {"allOf", .AllOf, nil},
    {"anyOf", .AnyOf, nil},
    {"oneOf", .OneOf, nil},
    {"if", .If, nil},
    {"then", .Then, nil},
    {"else", .Else, nil},
    {"not", .Not, nil},
    {"properties", .Properties, validate_properties},
    {"additionalProperties", .AdditionalProperties, nil},
    {"patternProperties", .PatternProperties, nil},
    {"dependentSchemas", .DependentSchemas, nil},
    {"propertyNames", .PropertyNames, nil},
    {"contains", .Contains, nil},
    {"items", .Items, nil},
    {"prefixItems", .PrefixItems, nil},

    // Validators
    {"type", .Type, validate_type},
    {"enum", .Enum, validate_enum},
    {"const", .Const, validate_const},
    {"maxLength", .MaxLength, validate_max_length},
    {"minLength", .MinLength, validate_min_length},
    {"pattern", .Pattern, nil},
    {"exclusiveMaximum", .ExclusiveMaximum, validate_exclusive_max},
    {"exclusiveMinimum", .ExclusiveMinimum, validate_exclusive_min},
    {"maximum", .Maximum, validate_maximum},
    {"minimum", .Minimum, validate_minimum},
    {"multipleOf", .MultipleOf, validate_multipleof},
    {"dependentRequired", .DependentRequired, nil},
    {"maxProperties", .MaxProperties, nil},
    {"minProperties", .MinProperties, nil},
    {"required", .Required, validate_required},
    {"maxItems", .MaxItems, nil},
    {"minItems", .MinItems, nil},
    {"maxContains", .MaxContains, nil},
    {"minContains", .MinContains, nil},
    {"uniqueItems", .UniqueItems, nil},
}

SchemaKeywords :: enum {
    // Applicators
    AllOf,
    AnyOf,
    OneOf,
    If,
    Then,
    Else,
    Not,
    Properties,
    AdditionalProperties,
    PatternProperties,
    DependentSchemas,
    PropertyNames,
    Contains,
    Items,
    PrefixItems,

    // Validators
    Type,
    Enum,
    Const,
    MaxLength,
    MinLength,
    Pattern,
    ExclusiveMaximum,
    ExclusiveMinimum,
    Maximum,
    Minimum,
    MultipleOf,
    DependentRequired,
    MaxProperties,
    MinProperties,
    Required,
    MaxItems,
    MinItems,
    MaxContains,
    MinContains,
    UniqueItems,
}

JsonSchema :: struct {
    // Core stuff of the schema
    schema:              string,
    id:                  string,
    title:               string,
    // note(iyaan): I dont know whether I will be able to implement
    // fully URI path support
    ref:                 string,
    defs:                map[string]JsonSchema,

    // Internal stuff
    // Used to create paths and for holding the name of
    // a property
    property:            string,

    // Used to denote whether this schema is used to just
    // as a holder for another schema. Used by $ref when
    // referencing embedded sub-schemas
    is_empty_container:  bool,

    // Applicator keywords
    properties_children: [dynamic]JsonSchema,
    items_children:      [dynamic]JsonSchema,

    // Validation keywords
    // note(iyaan): We need a way to know whether a schema has defined
    // a validation keyword. Struct would default these to zero. This means
    // we wont know really if that has been defined and the validation logic
    // might run for that keyword. For `minimum` this means for each schema
    // it will check whether a value is min zero, which is not the behaviour
    // that we want. We need a sort of flag set for each defined validation
    // keyword
    validation_flags:    bit_set[SchemaKeywords],
    type:                InstanceTypes,
    const:               json.Value,
    min_length:          int,
    max_length:          int,
    exclusive_max:       f64,
    exclusive_min:       f64,
    multipleof:          f64,
    enums:               []json.Value,
    minimum:             f64,
    maximum:             f64,
    required:            []string,
}

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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {

    if properties_as_object, ok := value.(json.Object); ok {
        no_of_properties := len(properties_as_object)
        // note(iyaan): I dont think the properties are likely to change for a schema after
        // it has already been parsed.
        schema.properties_children = make(
            [dynamic]JsonSchema,
            0,
            allocator,
        )
        reserve(&schema.properties_children, no_of_properties)

        if no_of_properties > 0 {
            schema.type = .Object
            for prop_field in properties_as_object {
                prop_sub_schema, err := parse_schema_from_json_value(
                    properties_as_object[prop_field],
                )
                if err != .None {
                    panic("Could not parse properties schema")
                }
                prop_sub_schema.property = prop_field
                append(&schema.properties_children, prop_sub_schema)
            }
        }
    } else {
        return .Invalid_Object_Type
    }

    return .None
}

parse_schema_from_json_value :: proc(
    value: json.Value,
    allocator := context.allocator,
    logger := context.logger,
) -> (
    schema_struct: JsonSchema,
    err: Error,
) {
    #partial switch t in value {
    case json.Object:
        parsed_json := value.(json.Object)
        schema_struct.schema = json_parse_string(
            parsed_json["$schema"],
        ) or_return
        schema_struct.title = json_parse_string(parsed_json["title"]) or_return
        schema_struct.id = json_parse_string(parsed_json["id"]) or_return

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
        // I think we can have a single map and each value in
        // the map will have the full path to the schema instead of
        // the value having sub-schemas. In the above case for the root
        // $defs map it will contain only '#/$defs/foo1/foo2'. Here foo1
        // is just a container to hold the real schema foo2
        if "$defs" in parsed_json {
            if defs_object, ok := parsed_json["$defs"].(json.Object); ok {
                for key in defs_object {
                    // def_value := defs_object[key]

                }
            } else {
                return schema_struct, .Invalid_Object_Type
            }
        }

        // Parse any keywords existing and set appropriate
        // flags for the validation stage. Will parse both
        // the applicators and the valiators keywords
        for keyword_info, idx in keywords_parse_table {
            val := parsed_json[keyword_info.keyword]
            parse_proc := keyword_info.parse_proc
            if val != nil && parse_proc != nil {
                parse_err := parse_proc(val, &schema_struct, allocator)
                if parse_err == .None {
                    schema_struct.validation_flags += {keyword_info.type}
                } else {
                    // TODO: Remove this in time
                    panic("Could not parse a validation keyword field")
                }
            }
        }
        return schema_struct, .None
    case:
        return schema_struct, .Invalid_Object_Type
    }

    return schema_struct, .None

}

@(private)
parse_type :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
    type, ok := value.(json.String)
    if !ok {
        return .Invalid_String_Type
    }

    if strings.compare(type, "null") == 0 {
        schema.type = .Null
    } else if strings.compare(type, "boolean") == 0 {
        schema.type = .Boolean
    } else if strings.compare(type, "object") == 0 {
        schema.type = .Object
    } else if strings.compare(type, "array") == 0 {
        schema.type = .Array
    } else if strings.compare(type, "number") == 0 {
        schema.type = .Number
    } else if strings.compare(type, "integer") == 0 {
        schema.type = .Integer
    } else if strings.compare(type, "string") == 0 {
        schema.type = .String
    } else {
        return .Invalid_Instance_Type
    }

    return .None
}

@(private)
parse_enum :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
    schema.const = value
    return .None
}

@(private)
parse_min_length :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
    #partial switch type in value {
    case json.Integer:
        schema.min_length = int(value.(json.Integer))
    case:
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_max_length :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
    #partial switch type in value {
    case json.Integer:
        schema.max_length = int(value.(json.Integer))
    case:
        return .Invalid_Integer_Type
    }
    return .None
}

@(private)
parse_exclusive_max :: proc(
    value: json.Value,
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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
    schema: ^JsonSchema,
    allocator := context.allocator,
) -> Error {
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

parse_schema_from_string :: proc(
    schema: string,
    allocator := context.allocator,
    logger := context.logger,
) -> (
    schema_struct: JsonSchema,
    err: Error,
) {
    parsed_json, parsed_json_err := json.parse_string(schema)
    if parsed_json_err != .None {
        log.debugf("json.parse_string returned error (%v)", parsed_json_err)
        return schema_struct, .Json_Parse_Error
    }
    schema_struct, err = parse_schema_from_json_value(parsed_json, allocator)
    if err != (.None) {
        log.debugf("json_schema_parse_from_json_value() returned %v\n", err)
        panic("Returned an error")
    }
    return schema_struct, .None
}

@(private)
json_schema_check_type_compatibility :: proc(
    schema_type: InstanceTypes,
    parsed_data_type: InstanceTypes,
) -> bool {
    // note(iyaan): Note that while the JSON grammar does not distinguish
    // between integer and real numbers, JSON Schema provides the integer
    // logical type that matches either integers (such as 2), or real numbers
    // where the fractional part is zero (such as 2.0)
    if parsed_data_type == .Integer {
        if schema_type == .Number || schema_type == .Integer {
            return true
        } else {
            return false
        }
    }
    if parsed_data_type == schema_type {
        return true
    } else {
        return false
    }
}

validate_string_with_schema :: proc(
    data: string,
    schema: JsonSchema,
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
        log.debugf("json.parse_string returned error (%v)", ok)
        return .Json_Parse_Error
    }

    validate_json_value_with_subschema(parsed_json, schema) or_return

    return .None
}

@(private)
// json_value is the parent object which contains the
// properties, not the actual property value itself
validate_properties :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {
    // If the data is not an object it does not need to check
    // the properties
    if _, ok := json_value.(json.Object); !ok {
        return .None
    }
    json_value_as_obj := json_value.(json.Object)
    log.debug("JSON Value:", json_value_as_obj)
    for prop in subschema.properties_children {
        val := json_value_as_obj[prop.property]
        log.debug("Value:", val, ", Prop:", prop)
        if val != nil {
            val_type := get_json_value_type(val)
            prop_valid_err := validate_json_value_with_subschema(val, prop)
            if prop_valid_err != .None {
                return prop_valid_err
            }
        }
    }
    return .None
}

@(private)
validate_json_value_with_subschema :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {
    subschema_copy := subschema

    for validation_keyword in subschema.validation_flags {
        log.debugf(
            "Performing validation (%v) on (%v)",
            validation_keyword,
            json_value,
        )
        validation_keyword_info :=
            keywords_validation_table[validation_keyword]
        validation_proc := validation_keyword_info.validation_proc
        if validation_proc != nil {
            validation_err := validation_proc(json_value, subschema)
            if validation_err != .None {
                log.debugf(
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

@(private)
validate_type :: proc(json_value: json.Value, subschema: JsonSchema) -> Error {
    parsed_json_base_type := get_json_value_type(json_value)
    if ok := json_schema_check_type_compatibility(
        subschema.type,
        parsed_json_base_type,
    ); !ok {
        return .Type_Validation_Failed
    }

    return .None
}

@(private)
validate_minimum :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {

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
validate_maximum :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {

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
    subschema: JsonSchema,
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
    subschema: JsonSchema,
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
validate_max_length :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {

    #partial switch type in json_value {
    case json.String:
        if len(json_value.(json.String)) > subschema.max_length {
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
validate_min_length :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {

    #partial switch type in json_value {
    case json.String:
        if len(json_value.(json.String)) < subschema.min_length {
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
validate_multipleof :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {

    float_is_multiple :: proc(n1: f64, n2: f64) -> Error {
        // note(iyaan): This is a such a dumb way to overcome
        // float precision errors when trying to find if mod
        // is zero
        MANTISSA_THRESHOLD :: 1e-15
        mod := math.mod_f64(n1, n2)
        if mod == 0 {
            return .None
        } else if mod < MANTISSA_THRESHOLD {
            return .None
        } else {
            return .Multiple_Of_Validation_Failed
        }
    }

    #partial switch type in json_value {
    case json.Float:
        return float_is_multiple(json_value.(json.Float), subschema.multipleof)
    case json.Integer:
        return float_is_multiple(
            f64(json_value.(json.Integer)),
            subschema.multipleof,
        )
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
check_if_match_object :: proc(
    enum_val: json.Object,
    data_json_object: json.Object,
) -> bool {
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
            if data_json_object_arr_val, ok := data_json_object[key].(json.Array);
               ok {
                if !check_if_match_array(
                    obj_val.(json.Array),
                    data_json_object_arr_val,
                ) {
                    return false
                }
            } else {
                return false
            }

        case json.Object:
            if data_json_object_obj_val, ok := data_json_object[key].(json.Object);
               ok {
                if !check_if_match_object(
                    obj_val.(json.Object),
                    data_json_object_obj_val,
                ) {
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
check_if_match_array :: proc(
    enum_val: json.Array,
    data_json_array: json.Array,
) -> bool {
    if len(enum_val) != len(data_json_array) {
        return false
    }
    for val, idx in enum_val {
        switch val_type in val {
        case json.Integer, json.Float, json.Boolean, json.String, json.Null:
            check_if_match_base(val, data_json_array[idx]) or_return
        case json.Array:
            if data_json_array_val, ok := data_json_array[idx].(json.Array);
               ok {
                check_if_match_array(
                    val.(json.Array),
                    data_json_array_val,
                ) or_return
            } else {
                return false
            }
        case json.Object:
            if data_json_object_val, ok := data_json_array[idx].(json.Object);
               ok {
                check_if_match_object(
                    val.(json.Object),
                    data_json_object_val,
                ) or_return
            } else {
                return false
            }
        }
    }
    return true
}

@(private)
validate_enum :: proc(json_value: json.Value, subschema: JsonSchema) -> Error {

    // Check if the json_value is one of the values in subschema.enum
    for enum_val in subschema.enums {
        switch enum_type in enum_val {
        case json.Integer:
        case json.Float:
        case json.Boolean:
        case json.String:
        case json.Null:
            if check_if_match_base(enum_val, json_value) {
                return .None
            }
        case json.Array:
            if arr_json_value, ok := json_value.(json.Array); ok {
                if check_if_match_array(
                    enum_val.(json.Array),
                    arr_json_value,
                ) {
                    return .None
                }
            }
        case json.Object:
            if obj_json_value, ok := json_value.(json.Object); ok {
                if check_if_match_object(
                    enum_val.(json.Object),
                    obj_json_value,
                ) {
                    return .None
                }
            }
        }
    }
    return .Enum_Validation_Failed
}

@(private)
validate_required :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {
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
validate_const :: proc(
    json_value: json.Value,
    subschema: JsonSchema,
) -> Error {
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
            if check_if_match_array(
                subschema.const.(json.Array),
                json_value_as_array,
            ) {
                return .None
            } else {
                return .Const_Validation_Failed
            }
        } else {
            return .Const_Validation_Failed
        }
    case json.Object:
        if json_value_as_object, ok := json_value.(json.Object); ok {
            if check_if_match_object(
                subschema.const.(json.Object),
                json_value_as_object,
            ) {
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

@(private)
get_json_value_type :: proc(json_value: json.Value) -> InstanceTypes {
    parsed_json_base_type: InstanceTypes
    parsed_json := json_value
    switch t in parsed_json {
    case json.Object:
        parsed_json := parsed_json.(json.Object)
        parsed_json_base_type = .Object
    case json.Float:
        parsed_json := parsed_json.(json.Float)
        parsed_json_base_type = .Number
    case json.Integer:
        parsed_json := parsed_json.(json.Integer)
        parsed_json_base_type = .Integer
    case json.Array:
        parsed_json := parsed_json.(json.Array)
        parsed_json_base_type = .Array
    case json.Null:
        parsed_json := parsed_json.(json.Null)
        parsed_json_base_type = .Null
    case json.Boolean:
        parsed_json := parsed_json.(json.Boolean)
        parsed_json_base_type = .Boolean
    case json.String:
        parsed_json := parsed_json.(json.String)
        parsed_json_base_type = .String
    case:
        panic("Not a json type")
    }
    return parsed_json_base_type
}

// For now will only support finding
// schemas through relative fragment
// pointers
get_schema_from_ref_path :: proc(
    ref_path: string,
    root_schema: JsonSchema,
    allocator := context.allocator,
) -> (
    JsonSchema,
    Error,
) {
    // "$ref": "#/$defs/helper"
    //   "$defs": {
    //     "helper": {
    //     "$id": "my-helper",
    //     "type": "string"
    //     }
    //    }

    cur_schema := root_schema
    target_schema_path := ref_path
    paths := slashpath.split_elements(target_schema_path, allocator)
    assert(paths[0] == "#", "Ref path needs a relative fragment path")
    for path in paths[1:] {
        log.debug(path)
    }
    return root_schema, .None
}
