package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:path/slashpath"
import "core:strings"

// The idea is to take a JSON schema file which contains some version
// of a lottie schema and create the neccessary structs for all things other
// than the primitive values.

DataTypes :: enum {
  Null,
  Boolean,
  Object,
  Array,
  Number,
  Integer,
  String,
}

State :: struct {
  allocator: mem.Allocator,
  root:      json.Value,
}

SchemaError :: enum {
  None,
  NotAnObject,
  PathPartNotExist,
  NotFragmentPath,
}

SchemaFields :: enum {
  Field_Type,
  Field_Title,
  Field_Description,
  Field_AllOf,
  Field_Properties,
  Field_Ref,
  FieldCount,
}

Schema :: struct {
  key:         string,
  type:        DataTypes,
  title:       string,
  description: string,
  allOf:       [dynamic]Schema,
  properties:  map[string]Schema,
  ref:         string, // Only stores the path
  required:    [dynamic]string,
  _flags:      bit_set[SchemaFields],
}

get_json_value_from_path :: proc(root: json.Value, path: string) -> (value: json.Value, err: SchemaError) {
  if len(path) > 1 && strings.compare(path[0:1], "#/") == 0 {
    full_path_parts := slashpath.split_elements(path)
    idx := 1
    path_parts := full_path_parts[1:]
    cur_json_value := root
    for part in path_parts {
      if cur_json_value_object, ok := cur_json_value.(json.Object); ok {
        if part in cur_json_value_object {
          cur_json_value = cur_json_value_object[part]
        } else {
          err = .PathPartNotExist
          return
        }
      } else {
        err = .NotAnObject
        return
      }
    }
    return cur_json_value, .None
  } else {
    err = .NotFragmentPath
    return
  }
}

parse_schema :: proc(
  json_schema: json.Value,
  state: State,
  loc := #caller_location,
) -> (
  schema: Schema,
  err: SchemaError,
) {
  if object, ok := json_schema.(json.Object); ok {
    if type, ok := object["type"].(json.String); ok {
      if type == "null" do schema.type = .Null
      if type == "boolean" do schema.type = .Boolean
      if type == "object" do schema.type = .Object
      if type == "array" do schema.type = .Array
      if type == "number" do schema.type = .Number
      if type == "string" do schema.type = .String
      if type == "integer" do schema.type = .Integer
      schema._flags += {.Field_Type}
    }
    if title, ok := object["title"].(json.String); ok {
      schema._flags += {.Field_Title}
      schema.title = title
    }

    if description, ok := object["description"].(json.String); ok {
      schema._flags += {.Field_Description}
      schema.description = description
    }

    if all_of_array, ok := object["allOf"].(json.Array); ok {
      schema._flags += {.Field_AllOf}
      for cur_all_of_schema in all_of_array {
        sub_all_of_schema, _ := parse_schema(cur_all_of_schema, state)
        append(&schema.allOf, sub_all_of_schema)
      }
    }

    if properties, ok := object["properties"].(json.Object); ok {
      schema._flags += {.Field_Properties}
      for key, value in properties {
        sc, _ := parse_schema(value, state)
        sc.key = key
        schema.properties[key] = sc
      }
    }

    if requried_fields_array, ok := object["required"].(json.Array); ok {
      for field in requried_fields_array {
        if field_as_string, ok := field.(json.String); ok {
          append(&schema.required, field_as_string)
        }
      }
    }

    if ref, ok := object["$ref"].(json.String); ok {
      // if the schema is just a $ref to another schema
      // no need to further schema parsing
      // Need to walk the original parsed JSON according
      // to the $ref
      schema._flags += {.Field_Ref}
      schema.ref = ref

      ref_schema_json_value, path_err := get_json_value_from_path(state.root, ref)
      if path_err != .None {
        panic("cannot get $ref path")
      }

      // TODO: Need to handle the error returned from here
      ref_schema, _ := parse_schema(ref_schema_json_value, state)

      // note(iyaan): Only set fields in the current schema on the fields
      // that are not already set

      to_replace_fields := ref_schema._flags - schema._flags

      for flag in to_replace_fields {
        switch flag {
        case .Field_Type:
          schema.type = ref_schema.type
        case .Field_Title:
          schema.title = ref_schema.title
        case .Field_Description:
          schema.description = ref_schema.description
        case .Field_AllOf:
          schema.allOf = ref_schema.allOf
        case .Field_Properties:
          schema.properties = ref_schema.properties
        case .Field_Ref:
          schema.ref = ref_schema.ref
        case .FieldCount:
        }
      }


    }


  }

  return schema, err
}

// Basically try to expand the schema into its struct form
gen_struct_for_schema :: proc(schema: Schema, state: State) {
  builder := strings.builder_make(state.allocator)

  enter_struct :: proc(builder: ^strings.Builder, struct_name: string) {
    struct_head := fmt.tprintfln("struct %s {", struct_name)
    strings.write_string(builder, struct_head)
  }

  gen_number_field :: proc(builder: ^strings.Builder, field_name: string) {
    field_format := fmt.tprintfln("%s: f64", field_name)
    strings.write_string(builder, field_format)
  }


  switch schema.type {
  case .Number:
    if len(schema.key) == 0 {
      panic("a number field name is missing")
    }
    gen_number_field(&builder, schema.key)
  case .Integer:
  // TODO
  case .Null:
  // TODO
  case .Boolean:
  // TODO
  case .Object:
    {
      // If a schema is of type object it should have atleast
      // a properties or a subschema that has the fields
      for property, value in schema.properties {
        enter_struct(&builder, schema.key)
        
      }
    }

  }


}
