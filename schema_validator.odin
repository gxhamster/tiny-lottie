package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:testing"

JsonSchemaInstanceType :: enum {
	Null = 0,
	Boolean,
	Object,
	Array,
	Number,
	Integer,
	String,
	Not_Provided,
}

JsonSchemaError :: union {
	json.Error,
	JsonLottie_Error,
	JsonSchema_Parse_Error,
	JsonSchema_Validation_Error,
}

JsonSchema_Parse_Error :: enum {
	None,
	Invalid_Instance_Type,
}

JsonSchema_Validation_Error :: enum {
	None,
	Clashing_Instance_Type,
	Clashing_Property_Type,
}

// Takes a pointer to the schema to set the correct parameter
// to the parsed value
parse_validation_proc :: proc(value: json.Value, schema: ^JsonSchema) -> JsonSchema_Parse_Error

ValidationKeywordInfo :: struct {
	keyword:    string,
	type:       JsonSchemaValidationKeyword,
	parse_proc: parse_validation_proc,
}

validation_keywords_map := [?]ValidationKeywordInfo {
	{"type", .Type, nil},
	{"enum", .Enum, nil},
	{"const", .Const, nil},
	{"maxLength", .MaxLength, nil},
	{"minLength", .MinLength, nil},
	{"pattern", .Pattern, nil},
	{"exclusiveMaximum", .ExclusiveMaximum, nil},
	{"exclusiveMinimum", .ExclusiveMinimum, nil},
	{"maximum", .Maximum, nil},
	{"minimum", .Minimum, parse_minimum},
	{"multipleOf", .MultipleOf, nil},
	{"dependentRequired", .DependentRequired, nil},
	{"maxProperties", .MaxProperties, nil},
	{"minProperties", .MinProperties, nil},
	{"required", .Required, nil},
	{"maxItems", .MaxItems, nil},
	{"minItems", .MinItems, nil},
	{"maxContains", .MaxContains, nil},
	{"minContains", .MinContains, nil},
	{"uniqueItems", .UniqueItems, nil},
}

JsonSchemaValidationKeyword :: enum {
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
	schema:              string,
	id:                  string,
	title:               string,
	property:            string, // Used as an internal name, not part of schema

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
	validation_flags:    bit_set[JsonSchemaValidationKeyword],
	type:                JsonSchemaInstanceType,
	minimum:             f64,
	maximum:             f64,
}

json_schema_parse_from_json_value :: proc(
	value: json.Value,
	allocator := context.allocator,
	logger := context.logger,
) -> (
	schema_struct: JsonSchema,
	err: JsonSchemaError,
) {
	#partial switch t in value {
	case json.Object:
		parsed_json := value.(json.Object)
		schema_struct.schema = json_lottie_parse_string(parsed_json["$schema"]) or_return
		schema_struct.title = json_lottie_parse_string(parsed_json["title"]) or_return
		schema_struct.id = json_lottie_parse_string(parsed_json["id"]) or_return
		type := json_lottie_parse_string(parsed_json["type"]) or_return

		if strings.compare(type, "null") == 0 {
			schema_struct.type = .Null
		} else if strings.compare(type, "boolean") == 0 {
			schema_struct.type = .Boolean
		} else if strings.compare(type, "object") == 0 {
			schema_struct.type = .Object
		} else if strings.compare(type, "array") == 0 {
			schema_struct.type = .Array
		} else if strings.compare(type, "number") == 0 {
			schema_struct.type = .Number
		} else if strings.compare(type, "integer") == 0 {
			schema_struct.type = .Integer
		} else if strings.compare(type, "string") == 0 {
			schema_struct.type = .String
		} else {
			return schema_struct, JsonSchema_Parse_Error.Invalid_Instance_Type
		}

		properties_exists := "properties" in parsed_json
		if properties_exists {
			if _, ok := parsed_json["properties"].(json.Object); ok {
				no_of_properties := len(parsed_json["properties"].(json.Object))
				// note(iyaan): I dont think the properties are likely to change for a schema after
				// it has already been parsed.
				schema_struct.properties_children = make([dynamic]JsonSchema, 0, allocator)
				reserve(&schema_struct.properties_children, no_of_properties)

				if properties_exists && no_of_properties > 0 {
					schema_struct.type = .Object
					properties_obj := parsed_json["properties"].(json.Object)
					for prop_field in properties_obj {
						prop_sub_schema, err := json_schema_parse_from_json_value(
							properties_obj[prop_field],
						)
						if err != JsonSchema_Parse_Error.None {
							panic("Could not parse properties schema")
						}
						prop_sub_schema.property = prop_field
						append(&schema_struct.properties_children, prop_sub_schema)
					}
				}
			} else {
				// note(iyaan): No need for any action if no properties
				// are found
			}
		}

		// Parse any validation keywords existing and set appropriate
		// flags for the validation stage
		for keyword_info, idx in validation_keywords_map {
			val := parsed_json[keyword_info.keyword]
			parse_proc := keyword_info.parse_proc
			if parse_proc != nil {
                parse_err := parse_proc(val, &schema_struct)
                if parse_err == .None {
                    schema_struct.validation_flags += {keyword_info.type}
                } else {
                    // TODO: Remove this in time
                    panic("Could not parse a validation keyword field")
                }
            } else {
                panic("Validation keyword not implemented yet")
            }
            
		}

		return schema_struct, JsonSchema_Parse_Error.None
	case:
		return schema_struct, .Incompatible_Object_Type
	}

	return schema_struct, JsonSchema_Parse_Error.None

}


parse_minimum :: proc(value: json.Value, schema: ^JsonSchema) -> JsonSchema_Parse_Error {
	return .None
}

json_schema_parse_from_string :: proc(
	schema: string,
	allocator := context.allocator,
	logger := context.logger,
) -> (
	schema_struct: JsonSchema,
	err: JsonSchemaError,
) {
	parsed_json := json.parse_string(schema) or_return
	schema_struct, err = json_schema_parse_from_json_value(parsed_json, allocator)
	if err != (JsonSchema_Parse_Error.None) {
		panic("Returned an error")
	}
	return schema_struct, JsonSchema_Parse_Error.None
}

json_schema_check_type_compatibility :: proc(
	schema_type: JsonSchemaInstanceType,
	parsed_data_type: JsonSchemaInstanceType,
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

json_schema_validate_string_with_schema :: proc(
	data: string,
	schema: JsonSchema,
	allocator := context.allocator,
) -> JsonSchemaError {
	// note(iyaan): In odin parsing without JSON5 spec will
	// not work for single data at root level that is not
	// enclosed in a top-level object
	parsed_json := json.parse_string(
		data,
		spec = json.Specification.JSON5,
		parse_integers = true,
	) or_return


	return JsonSchema_Validation_Error.None
}

@(private = "file")
validate_json_value_with_subschema :: proc(
	json_value: json.Value,
	subschema: JsonSchema,
) -> JsonSchema_Validation_Error {
	parsed_json_base_type := get_json_value_type(json_value)
	if ok := json_schema_check_type_compatibility(subschema.type, parsed_json_base_type); !ok {
		return .Clashing_Instance_Type
	}

	validate_properties(subschema, json_value) or_return

	return .None
}

@(private = "file")
validation_minimum :: proc(
	json_value: json.Value,
	subschema: JsonSchema,
) -> JsonSchema_Validation_Error {
	return .None
}

@(private = "file")
get_json_value_type :: proc(json_value: json.Value) -> JsonSchemaInstanceType {
	parsed_json_base_type: JsonSchemaInstanceType
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


@(private = "file")
// json_value is the parent object which contains the
// properties, not the actual property value itself
validate_properties :: proc(
	schema: JsonSchema,
	json_value: json.Value,
) -> JsonSchema_Validation_Error {
	// If the data is not an object it does not need to check
	// the properties
	if _, ok := json_value.(json.Object); !ok {
		return .None
	}
	json_value_as_obj := json_value.(json.Object)
	for prop in schema.properties_children {
		val := json_value_as_obj[prop.property]
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

@(test)
schema_valid_number_test :: proc(t: ^testing.T) {
	simple_test_schema := `{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "number"
}`
	simple_test_data1 := `42`
	simple_test_data2 := `"foo"`
	schema, _ := json_schema_parse_from_string(simple_test_schema)
	err := json_schema_validate_string_with_schema(simple_test_data1, schema)
	testing.expect_value(t, err, JsonSchema_Validation_Error.None)

	err = json_schema_validate_string_with_schema(simple_test_data2, schema)
	testing.expect_value(t, err, JsonSchema_Validation_Error.Clashing_Instance_Type)

	free_all()
}

@(test)
schema_valid_property_test :: proc(t: ^testing.T) {
	test_schema2 := `{
"$id": "https://example.com/person.schema.json",
"$schema": "https://json-schema.org/draft/2020-12/schema",
"title": "Person",
"type": "object",
"properties": {
"firstName": {
    "type": "string",
    "description": "The person's first name."
},
"lastName": {
    "type": "string",
    "description": "The person's last name."
},
"age": {
    "description": "Age in years which must be equal to or greater than zero.",
    "type": "integer",
    "minimum": 0
}
}
}`
	test_schema2_data := `{
"firstName": "John",
"lastName": "Doe",
"age": 21
}`

	schema, _ := json_schema_parse_from_string(test_schema2)


	free_all()
}
