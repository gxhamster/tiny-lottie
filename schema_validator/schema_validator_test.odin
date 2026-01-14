#+feature dynamic-literals
package schema_validator

import "core:encoding/json"
import "core:log"
import "core:math"
import "core:testing"


@(test)
schema_valid_number_test :: proc(t: ^testing.T) {
  simple_test_schema := `{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "number"
}`
  simple_test_data1 := `42`
  simple_test_data2 := `"foo"`
  ctx := Context{}
  init_context(&ctx, 100, context.allocator)
  schema, idx, _ := parse_schema_from_string(simple_test_schema, &ctx)
  err := validate_string_with_schema(simple_test_data1, schema, &ctx)
  testing.expect_value(t, err, Error.None)

  err = validate_string_with_schema(simple_test_data2, schema, &ctx)
  testing.expect_value(t, err, Error.Type_Validation_Failed)
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
  ctx := Context{}
  init_context(&ctx, 100, context.allocator)
  schema, _, parse_err := parse_schema_from_string(test_schema2, &ctx)
  testing.expect_value(t, parse_err, Error.None)
  valid_err := validate_string_with_schema(test_schema_data1, schema, &ctx)
  testing.expect_value(t, valid_err, Error.None)
  valid_err1 := validate_string_with_schema(test_schema_data2, schema, &ctx)
  testing.expect_value(t, valid_err1, Error.Minimum_Validation_Failed)

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
  ctx := Context{}
  init_context(&ctx, 100, context.allocator)
  schema, _, parse_err := parse_schema_from_string(test_schema2, &ctx)
  testing.expect_value(t, parse_err, Error.None)
  valid_err := validate_string_with_schema(test_schema_data1, schema, &ctx)
  testing.expect_value(t, valid_err, Error.None)

  valid_err1 := validate_string_with_schema(test_schema_data2, schema, &ctx)
  testing.expect_value(t, valid_err1, Error.None)

  valid_err2 := validate_string_with_schema(test_schema_data3, schema, &ctx)
  testing.expect_value(t, valid_err2, Error.None)
}

@(test)
check_if_array_match_test :: proc(t: ^testing.T) {
  defer free_all()
  data1: json.Array = {1, 2, 3}
  data2: json.Array = {1, 2, json.Array{1, 2}}
  data3: json.Array = {1, 2, json.Array{1, 2, json.Array{3, 4}}}
  data4: json.Array = {1, 2, json.Object{"foo" = "name"}}


  testing.expect_value(t, check_if_match_array(data1, {1, 2, 3}), true)
  testing.expect_value(t, check_if_match_array(data1, {1, 3, 2}), false)
  testing.expect_value(t, check_if_match_array(data1, {1, 2, 3.2}), false)

  testing.expect_value(
    t,
    check_if_match_array(data2, {1, 2, json.Array{1, 2}}),
    true,
  )
  testing.expect_value(
    t,
    check_if_match_array(data2, {1, 3, json.Array{1, 2}}),
    false,
  )
  testing.expect_value(
    t,
    check_if_match_array(data2, {1, 2, json.Array{1, 2}, 4}),
    false,
  )

  testing.expect_value(
    t,
    check_if_match_array(data3, {1, 2, json.Array{1, 2, json.Array{3, 4}}}),
    true,
  )
  testing.expect_value(
    t,
    check_if_match_array(data3, {1, 2, json.Array{1, 2, json.Array{3, 5}}}),
    false,
  )

  testing.expect_value(
    t,
    check_if_match_array(data4, {1, 2, json.Object{"foo" = "name"}}),
    true,
  )
  testing.expect_value(
    t,
    check_if_match_array(data4, {1, 2, json.Object{"foo" = "name1"}}),
    false,
  )
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

  defer free_all()
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
    "age": 21
}}`

  test_schema_data3 := `{
"name": {
    "firstName": "John",
    "lastName": "Doe",
    "age": 22
}}`

  test_schema_data4 := `{
"name": {
    "firstName": "John",
    "lastName": "Doe",
    "age": 22,
    "dob": "1/1/2026"
}}`
  test_schema_data5 := `{
"name": {
    "age": 21
    "firstName": "John",
    "lastName": "Doe",
}}`
  test_nested1 := `{
"name": {
    "age": 21
    "firstName": "John",
    "lastName": "Doe",
    "address": {
         "street": "Main",
         "city": "London"
    }
}}`
  test_nested2 := `{
"name": {
    "age": 21
    "firstName": "John",
    "lastName": "Doe",
    "address": {
         "street": "Main",
         "city": "UK"
    }
}}`

  data1_0, _ := json.parse_string(test_schema_data1)
  data1_1, _ := json.parse_string(test_schema_data2)
  data1_2, _ := json.parse_string(test_schema_data3)
  data1_3, _ := json.parse_string(test_schema_data4)
  data1_4, _ := json.parse_string(test_schema_data5)

  data2_0, _ := json.parse_string(test_nested1)
  data2_1, _ := json.parse_string(test_nested2)

  testing.expect_value(
    t,
    check_if_match_object(data1_0.(json.Object), data1_1.(json.Object)),
    true,
  )
  testing.expect_value(
    t,
    check_if_match_object(data1_0.(json.Object), data1_2.(json.Object)),
    false,
  )
  testing.expect_value(
    t,
    check_if_match_object(data1_0.(json.Object), data1_3.(json.Object)),
    false,
  )
  testing.expect_value(
    t,
    check_if_match_object(data1_0.(json.Object), data1_4.(json.Object)),
    true,
  )

  testing.expect_value(
    t,
    check_if_match_object(data2_0.(json.Object), data2_1.(json.Object)),
    false,
  )
}

@(test)
ref_path_test :: proc(t: ^testing.T) {
  defer free_all()
  schema := Schema {
    ref = "#/$defs/helper",
  }

  test_schema0 := `{
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
            },
            "address": {
                "$ref": "#/$defs/personal/address"
            }
        }
    }
},
"$defs": {
    "personal": {
        "address": {
            "type": "object",
            "properties": {
                "street": {
                    "type": "string",
                }
            }
        }
    }
}
}`
  ctx := Context{}
  init_context(&ctx, 100, context.allocator)
  data0, idx, err := parse_schema_from_string(test_schema0, &ctx)
  log.debug(data0)
  resolve_refs_to_schemas(data0, &ctx)
}
