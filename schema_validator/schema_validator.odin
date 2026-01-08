package schema_validator

import "core:encoding/json"
import "core:log"
import "core:math"
import "core:path/slashpath"
import "core:strings"


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
					log.debugf("Parsing properties failed (field=%v) : %v", prop_field, err)
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
	log.debug("Appending ref info:", ref_info)
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
		for keyword_info, idx in keywords_parse_table {
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
					// TODO: Remove this in time
					panic("Could not parse a validation keyword field")
				}
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
			for info in keywords_parse_table {
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
	case:
		return .Invalid_Integer_Type
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
        return .None
    } else {
        return .Invalid_Integer_Type
    }
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
        return .None
    } else {
        return .Invalid_Integer_Type
    }
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
        return .None
    } else {
        return .Invalid_Integer_Type
    }
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
        return .None
    } else {
        return .Invalid_Integer_Type
    }
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

parse_schema_from_string :: proc(
	schema: string,
	schema_context: ^Context,
	allocator := context.allocator,
) -> (
	schema_struct: ^Schema,
	pool_idx: PoolIndex,
	err: Error,
) {
	parsed_json, parsed_json_err := json.parse_string(schema)
	if parsed_json_err != .None {
		log.debugf("json.parse_string returned error (%v)", parsed_json_err)
		return schema_struct, pool_idx, .Json_Parse_Error
	}

	schema_struct, pool_idx, err = parse_schema_from_json_value(
		parsed_json,
		schema_context,
		allocator,
	)
	if err != (.None) {
		log.debugf("_parse_from_json_value() returned %v\n", err)
		panic("Returned an error")
	}

	for v in schema_context.refs_to_resolve {
		log.debugf("Resolving ref (%v)\n", v.ref)
	}

	return schema_struct, pool_idx, .None
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
		log.debugf("json.parse_string returned error (%v)", ok)
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
	log.debug("JSON Value:", json_value_as_obj)
	for prop in subschema.properties_children {
		prop_schema := &ctx.schema_pool[prop]
		val := json_value_as_obj[prop_schema.name]
		log.debug("Value:", val, ", Prop:", prop)
		if val != nil {
			val_type := get_json_value_type(val)
			prop_valid_err := validate_json_value_with_subschema(val, prop_schema, ctx)
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
	subschema: ^Schema,
	ctx: ^Context,
) -> Error {
	subschema_copy := subschema

	for validation_keyword in subschema.validation_flags {
		log.debugf("Performing validation (%v) on (%v)", validation_keyword, json_value)
		validation_keyword_info := keywords_validation_table[validation_keyword]
		validation_proc := validation_keyword_info.validation_proc
		if validation_proc != nil {
			validation_err := validation_proc(json_value, subschema, ctx)
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
validate_type :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
	parsed_json_base_type := get_json_value_type(json_value)
	if ok := json_schema_check_type_compatibility(subschema.type, parsed_json_base_type); !ok {
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
validate_min_length :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

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
validate_multipleof :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {

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
validate_max_properties :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
	if json_value_object, ok := json_value.(json.Object); ok {
        if len(json_value_object) > subschema.max_properties {
            return .Max_Properties_Validation_Failed
        }
	}
    return .None
}

@(private)
validate_min_properties :: proc(json_value: json.Value, subschema: ^Schema, ctx: ^Context) -> Error {
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
        if len(json_value_array) > subschema.min_items {
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
	for subschema_idx in subschema.allof {
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
	for subschema_idx in subschema.allof {
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
    if_err := validate_json_value_with_subschema(json_value, subschema, ctx)
    then_exists := SchemaKeywords.Then in subschema.validation_flags
    else_exists := SchemaKeywords.Else in subschema.validation_flags
    if then_exists {
        then_schema := get_schema(ctx, subschema.then)
        then_err := validate_json_value_with_subschema(json_value, then_schema, ctx)
        if if_err == .None && then_err == .None {
            return .None
        } else {
            return .If_Then_Validation_Failed
        }
    }

    if else_exists {
        else_schema := get_schema(ctx, subschema.then)
        else_err := validate_json_value_with_subschema(json_value, else_schema, ctx)

        if if_err != .None && else_err == .None {
            return .None
        } else {
            return .If_Else_Validation_Failed
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
				target_schema := search_defs(&cur_schema.defs, paths[2:], ctx) or_return
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
			log.debugf("Could not resolve ref (%v) : %v", ref_info.ref, err)
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
