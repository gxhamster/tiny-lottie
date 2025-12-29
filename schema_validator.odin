package main

import "core:encoding/json"
import "core:testing"
import "core:fmt"
import "core:log"

JsonSchemaInstanceType :: enum {
    Null = 0,
    Boolean,
    Object,
    Array,
    Number,
    Integer,
    String,

    Not_Provided
}

JsonSchemaError :: union {
    json.Error,
    JsonLottie_Error,
    JsonSchema_Parse_Error
}

JsonSchema_Parse_Error :: enum {
    None,
    Invalid_Instance_Type,
}

JsonSchema :: struct {
    schema: string,
    id: string,
    title: string,
    type: JsonSchemaInstanceType,

    properties_children: []JsonSchema,
    items_children: []JsonSchema,
}

json_schema_parse_from_string :: proc(
    schema: string,
    allocator := context.allocator,
    logger := context.logger
) -> (schema_struct: JsonSchema, err: JsonSchemaError) {
    parsed_json := json.parse_string(schema) or_return

    root: JsonSchema
    #partial switch t in parsed_json {
    case json.Object:
        parsed_json := parsed_json.(json.Object)
        root.schema = json_lottie_parse_string(parsed_json["$schema"], true) or_return
        root.title = json_lottie_parse_string(parsed_json["title"]) or_return
        root.id = json_lottie_parse_string(parsed_json["id"]) or_return
        type := json_lottie_parse_string(parsed_json["type"]) or_return

        switch type {
        case "null":
            root.type = .Null
        case "boolean":
            root.type = .Boolean
        case "object":
            root.type = .Object
        case "array":
            root.type = .Array
        case "number":
            root.type = .Number
        case "integer":
            root.type = .Integer
        case "string":
            root.type = .String
        case:
            return schema_struct, JsonSchema_Parse_Error.Invalid_Instance_Type
        }

        properties_exists := "properties" in parsed_json
        if properties_exists {

        }




        return root, (json.Error).None
    case:
        return schema_struct, .Incompatible_Object_Type
    }

    return schema_struct, (json.Error).None
}

json_schema_validate_string_with_schema :: proc(
    data: string,
    schema: JsonSchema,
    allocator := context.allocator
) -> (JsonSchemaError) {
    parsed_json := json.parse_string(data, parse_integers = true) or_return



    #partial switch t in parsed_json {
    case json.Object:
        parsed_json := parsed_json.(json.Object)
        return json.Error.None
    case json.Float:
        parsed_json := parsed_json.(json.Float)
        log.debug(parsed_json)
        return json.Error.None
    case json.Integer:
        parsed_json := parsed_json.(json.Integer)
        log.debug(parsed_json)
        return json.Error.None
    case:
        return JsonLottie_Error.Incompatible_Object_Type
    }

}

@(test)
json_schema_validator_test :: proc(t: ^testing.T) {
    simple_test_schema := `{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "number"
}`
    simple_test_data1 := `42`
    simple_test_data2 := `foo`

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

    logger := log.create_console_logger()
    context.logger = logger

    schema, err := json_schema_parse_from_string(simple_test_schema)
    json_schema_validate_string_with_schema(simple_test_data1, schema)
    log.destroy_console_logger(logger)
    free_all()
}
