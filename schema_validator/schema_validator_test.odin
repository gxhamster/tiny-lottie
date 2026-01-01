package schema_validator

import "core:encoding/json"
import "core:log"
import "core:testing"


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
    testing.expect_value(
        t,
        err,
        JsonSchema_Validation_Error.Type_Validation_Failed,
    )
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
    "minimum": 21
}
}
}`
    test_schema_data1 := `{
"firstName": "John",
"lastName": "Doe",
"age": 21
}`
    test_schema_data2 := `{
"firstName": "John",
"lastName": "Doe",
"age": 20
}`

    defer free_all()
    schema, parse_err := json_schema_parse_from_string(test_schema2)
    testing.expect_value(t, parse_err, JsonSchema_Parse_Error.None)
    valid_err := json_schema_validate_string_with_schema(
        test_schema_data1,
        schema,
    )
    testing.expect_value(t, valid_err, JsonSchema_Validation_Error.None)
    valid_err1 := json_schema_validate_string_with_schema(
        test_schema_data2,
        schema,
    )
    testing.expect_value(
        t,
        valid_err1,
        JsonSchema_Validation_Error.Minimum_Validation_Failed,
    )

}

@(test)
schema_valid_nested_property_test :: proc(t: ^testing.T) {
    test_schema2 := `{
"$id": "https://example.com/person.schema.json",
"$schema": "https://json-schema.org/draft/2020-12/schema",
"title": "Person",
"type": "object",
"properties": {
    "name": {
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
                "minimum": 21
            }
        }
    }
}
}`
    test_schema_data1 := `{
"name": {
    "firstName": "John",
    "lastName": "Doe",
    "age": 21
}}`
    test_schema_data2 := `{
"name": {
    "firstName": "John",
    "lastName": "Doe",
}}`

    test_schema_data3 := `{}`

    defer free_all()
    schema, parse_err := json_schema_parse_from_string(test_schema2)
    testing.expect_value(t, parse_err, JsonSchema_Parse_Error.None)
    valid_err := json_schema_validate_string_with_schema(
        test_schema_data1,
        schema,
    )
    testing.expect_value(t, valid_err, JsonSchema_Validation_Error.None)

    valid_err1 := json_schema_validate_string_with_schema(
        test_schema_data2,
        schema,
    )
    testing.expect_value(t, valid_err1, JsonSchema_Validation_Error.None)

    valid_err2 := json_schema_validate_string_with_schema(
        test_schema_data3,
        schema,
    )
    testing.expect_value(t, valid_err2, JsonSchema_Validation_Error.None)
}

@(test)
check_if_array_match_test :: proc(t: ^testing.T) {

}

@(test)
check_if_primitive_type_match_test :: proc(t: ^testing.T) {
    data1: json.String = "hello"
    data2: json.Integer = 2345
    data3: json.Float = 2.345

    testing.expect_value(t, check_if_match_base(data1, "hello"), true)
    testing.expect_value(t, check_if_match_base(data1, "helloo"), false)
    testing.expect_value(t, check_if_match_base(data1, 123), false)

    testing.expect_value(t, check_if_match_base(data2, 2345), true)
    testing.expect_value(t, check_if_match_base(data2, 23445), false)
    testing.expect_value(t, check_if_match_base(data2, nil), false)
    // note(iyaan): Should we allow interpreting float values with
    // zero decimal part to be equivalent to an integer. I say yes
    testing.expect_value(t, check_if_match_base(data2, 2345.00000), true)
    testing.expect_value(t, check_if_match_base(data2, 2345.00002), false)


    testing.expect_value(t, check_if_match_base(data3, 2.345), true)
    testing.expect_value(t, check_if_match_base(data3, 23445), false)
    testing.expect_value(t, check_if_match_base(data3, nil), false)
    testing.expect_value(t, check_if_match_base(data3, "foo"), false)
    testing.expect_value(t, check_if_match_base(2345.0, 2345), true)

}

@(test)
check_if_object_type_match_test :: proc(t: ^testing.T) {


}
