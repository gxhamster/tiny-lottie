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
    JsonSchema_Validation_Error
}

JsonSchema_Parse_Error :: enum {
	None,
	Invalid_Instance_Type,
}

JsonSchema_Validation_Error :: enum {
    None,
    Clashing_Instance_Type,
}

JsonSchema :: struct {
	schema:              string,
	id:                  string,
	title:               string,
	type:                JsonSchemaInstanceType,
	property:            string, // Used as an internal name, not part of schema
	properties_children: [dynamic]JsonSchema,
	items_children:      [dynamic]JsonSchema,
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
		schema_struct.schema = json_lottie_parse_string(parsed_json["$schema"], true) or_return
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
				schema_struct.properties_children = make(
					[dynamic]JsonSchema,
					no_of_properties,
					allocator,
				)

				if properties_exists && no_of_properties > 0 {
					for prop_field in parsed_json {
						prop_sub_schema, err := json_schema_parse_from_json_value(
							parsed_json[prop_field],
						)
						if err != JsonSchema_Parse_Error.None {
							unreachable()
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

		return schema_struct, (json.Error).None
	case:
		return schema_struct, .Incompatible_Object_Type
	}

	return schema_struct, (json.Error).None

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
	if err != (json.Error.None) {
		panic("Returned an error")
	}
	defer json.destroy_value(parsed_json, allocator)
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
        if schema_type == .Number  || schema_type == .Integer {
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
	parsed_json := json.parse_string(data, spec = json.Specification.JSON5 , parse_integers = true) or_return

	parsed_json_base_type: JsonSchemaInstanceType
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

    if ok := json_schema_check_type_compatibility(schema.type, parsed_json_base_type); !ok {
        log.debug("Incorrect type on data")
        return .Clashing_Instance_Type
    }
	
	return JsonSchema_Validation_Error.None
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

	free_all()
}
