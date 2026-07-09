package main

import "core:strconv"
import "core:fmt"
import "core:encoding/json"
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
  builder:   strings.Builder,
  depth:     int,
  schemas:   [dynamic]Schema,
}

SchemaError :: enum {
  None,
  NotAnObject,
  PathPartNotExist,
  NotFragmentPath,
  EOF, // Not necessarily an error
  // Tokenizing Errors
  Illegal_Character,
  Invalid_Number,
  String_Not_Terminated,
  Invalid_String,
  Invalid_Rune,
  Unquote_Failed,

  // Parser Errors
  Unexpected_Token,
  Expected_Colon_After_Key,
  Expected_String_For_Object_Key,

  // Allocating Errors
  Invalid_Allocator,
  Out_Of_Memory,
}

SchemaFields :: enum {
  Field_Schema,
  Field_Id,
  Field_Def,
  Field_Version,
  Field_Type,
  Field_Title,
  Field_Description,
  Field_AllOf,
  Field_OneOf,
  Field_Properties,
  Field_Ref,
  Field_Items,
  FieldCount,
}

Schema :: struct {
  key:         string,
  schema_uri:  string,
  id:          string,
  version:     i64,
  type:        DataTypes,
  title:       string,
  description: string,
  allOf:       [dynamic]Schema,
  oneOf:       [dynamic]Schema,
  properties:  map[string]Schema,
  items:       ^Schema,
  ref:         string, // Only stores the path
  required:    [dynamic]string,
  _flags:      bit_set[SchemaFields],
}

SchemaParser :: struct {
  tok:        json.Tokenizer,
  prev_token: json.Token,
  curr_token: json.Token,
  allocator:  mem.Allocator,
}

make_schema_parser :: proc(data: []byte, allocator := context.allocator) -> SchemaParser {
  return make_schema_parser_from_string(string(data), allocator)
}

make_schema_parser_from_string :: proc(data: string, allocator := context.allocator) -> SchemaParser {
  p: SchemaParser
  p.tok = json.make_tokenizer(data)
  p.allocator = allocator
  assert(p.allocator.procedure != nil)
  advance_token(&p)
  return p
}

parse :: proc(data: []byte, allocator: mem.Allocator, loc := #caller_location) -> (Schema, SchemaError) {
  return parse_from_string(string(data), allocator, loc)
}

parse_from_string :: proc(data: string, allocator: mem.Allocator, loc := #caller_location) -> (Schema, SchemaError) {
  p := make_schema_parser_from_string(data, allocator)
  return parse_subschema(&p, loc)
}

advance_token :: proc(p: ^SchemaParser) -> (tok: json.Token, err: SchemaError) {
  error: json.Error
  p.prev_token = p.curr_token
  p.curr_token, error = json.get_token(&p.tok)
  // Map errors from JSON package into this one
  #partial switch error {
  case .Illegal_Character:
    err = .Illegal_Character
  case .Invalid_Number:
    err = .Invalid_Number
  case .String_Not_Terminated:
    err = .String_Not_Terminated
  case .Invalid_String:
    err = .Invalid_String
  case .Invalid_Rune:
    err = .Invalid_Rune
  }
  return p.prev_token, err
}

allow_token :: proc(p: ^SchemaParser, kind: json.Token_Kind) -> bool {
  if p.curr_token.kind == kind {
    advance_token(p)
    return true
  }
  return false
}

expect_token :: proc(p: ^SchemaParser, kind: json.Token_Kind) -> SchemaError {
  prev := p.curr_token
  advance_token(p)
  if prev.kind == kind {
    return nil
  }
  return .Unexpected_Token
}

parse_colon :: proc(p: ^SchemaParser) -> (err: SchemaError) {
  colon_err := expect_token(p, .Colon)
  if colon_err == nil {
    return nil
  }
  return .Expected_Colon_After_Key
}

parse_comma :: proc(p: ^SchemaParser) -> (do_break: bool) {
  if allow_token(p, .Comma) {
    return false
  }
  return false
}

parse_object_key :: proc(
  p: ^SchemaParser,
  key_allocator: mem.Allocator,
  loc := #caller_location,
) -> (
  key: string,
  err: SchemaError,
) {
  tok := p.curr_token
  
  if tok_err := expect_token(p, .String); tok_err != nil {
		err = .Expected_String_For_Object_Key
		return
	} else {
    key, key_err := json.unquote_string(tok, json.DEFAULT_SPECIFICATION, key_allocator, loc)
    if key_err != nil {
      err = .Unquote_Failed
      return
    }
    return key, .None
  }
}

@(private = "file")
parse_string :: proc(p: ^SchemaParser, loc := #caller_location) -> (value: string, err: SchemaError) {
  advance_token(p)
  val, unqoute_err := json.unquote_string(p.curr_token, json.Specification.JSON5, p.allocator, loc)
  if unqoute_err != nil {
    return value, .Unquote_Failed
  }
  return val, .None
}

@(private = "file")
parse_integer :: proc(p: ^SchemaParser, loc := #caller_location) -> (value: i64, err: SchemaError) {
  advance_token(p)
  i, _ := strconv.parse_i64(p.curr_token.text)
  value = i64(i)
  return
}

parse_array_of_schemas :: proc(p: ^SchemaParser, loc := #caller_location) -> (value: [dynamic]Schema, err: SchemaError) {
  err = .None
  expect_token(p, .Open_Bracket) or_return

  array: [dynamic]Schema
  array.allocator = p.allocator

  for p.curr_token.kind != .Close_Bracket {
    elem := parse_subschema(p, loc) or_return
    append(&array, elem)

    if parse_comma(p) {
      break
    }
  }

  expect_token(p, .Close_Bracket) or_return
  value = array
  return
}

parse_subschema_body :: proc(
  p: ^SchemaParser,
  end_token: json.Token_Kind,
  loc := #caller_location,
) -> (
  schema: Schema,
  err: SchemaError,
) {
  for p.curr_token.kind != end_token {
    token := p.curr_token
    field_key := parse_object_key(p, p.allocator, loc) or_return
    parse_colon(p) or_return

    if field_key == "$schema" {
      if token.kind == .String {
        schema.schema_uri = parse_string(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "$id" {
      if token.kind == .String {
        schema.id = parse_string(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "$version" {
      if token.kind == .String {
        schema.version = parse_integer(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "$ref" {
      if token.kind == .String {
        schema.ref = parse_string(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "type" {
      if token.kind == .String {
        type_str := parse_string(p, loc) or_return
        if type_str == "null" do schema.type = .Null
        if type_str == "boolean" do schema.type = .Boolean
        if type_str == "object" do schema.type = .Object
        if type_str == "array" do schema.type = .Array
        if type_str == "number" do schema.type = .Number
        if type_str == "string" do schema.type = .String
        if type_str == "integer" do schema.type = .Integer
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "title" {
      if token.kind == .String {
        schema.title = parse_string(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "description" {
      if token.kind == .String {
        schema.description = parse_string(p, loc) or_return
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "allOf" {
      if token.kind == .Open_Bracket {
        allof_array := parse_array_of_schemas(p, loc) or_return
        schema.allOf = allof_array
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "oneOf" {
      if token.kind == .Open_Bracket {
        oneof_array := parse_array_of_schemas(p, loc) or_return
        schema.oneOf = oneof_array
      } else {
        err = .Unexpected_Token
        return
      }
    } else if field_key == "items" {
      items_schema := parse_subschema(p, loc) or_return
      items_alloc := new(Schema, p.allocator)
      items_alloc^ = items_schema
      schema.items = items_alloc
    } else {
      // Not accepted field
      err_msg := fmt.tprintfln("not an accepted field, %v", field_key)
      panic(err_msg)
    }

    if parse_comma(p) {
			break
		}

  }
  return
}

// In this implementation of JSON parser each object needs to be
// a valid schema
parse_subschema :: proc(p: ^SchemaParser, loc := #caller_location) -> (schema: Schema, err: SchemaError) {
  expect_token(p, .Open_Brace) or_return
  // Parse the body of the schema (object)
  obj := parse_subschema_body(p, .Close_Brace, loc) or_return
  expect_token(p, .Close_Brace) or_return
  return obj, .None
}

get_json_value_from_path :: proc(
  root: json.Value,
  path: string,
  state: State,
) -> (
  value: json.Value,
  err: SchemaError,
) {
  if len(path) > 1 && path[0] == '#' && path[1] == '/' {
    full_path_parts := slashpath.split_elements(path, state.allocator)
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


/*
parse_schema :: proc(
  json_schema: json.Value,
  state: ^State,
  loc := #caller_location,
) -> (
  schema: Schema,
  err: SchemaError,
) {
  if object, ok := json_schema.(json.Object); ok {
    state.depth += 1
    if state.depth > 90 {
      fmt.println(json_schema)
      // panic("Too deep")
    }


    fmt.println(state.depth)
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

    if "allOf" in object {
      if all_of_array, ok := object["allOf"].(json.Array); ok {
        schema._flags += {.Field_AllOf}
        schema.allOf = make_dynamic_array([dynamic]Schema, state.allocator)
        for cur_all_of_schema in all_of_array {
          sub_all_of_schema, _ := parse_schema(cur_all_of_schema, state)
          append(&schema.allOf, sub_all_of_schema)
        }
      }
    }

    if "oneOf" in object {
      if one_of_array, ok := object["oneOf"].(json.Array); ok {
        schema._flags += {.Field_OneOf}
        schema.oneOf = make_dynamic_array([dynamic]Schema, state.allocator)
        for cur_one_of_array in one_of_array {
          sub_one_of_schema, _ := parse_schema(cur_one_of_array, state)
          append(&schema.oneOf, sub_one_of_schema)
        }
      }
    }

    if "items" in object {
      if items_schema, ok := object["items"].(json.Object); ok {
        schema._flags += {.Field_Items}
        allocated_schema, alloc_err := new(Schema, state.allocator)
        if alloc_err != .None {
          panic("could not allocate for `items`")
        }

        parsed_item_schema, _ := parse_schema(items_schema, state)
        allocated_schema^ = parsed_item_schema
        schema.items = allocated_schema
      }
    }

    if "properties" in object {
      if properties, ok := object["properties"].(json.Object); ok {
        schema._flags += {.Field_Properties}
        schema.properties = make_map(map[string]Schema, state.allocator)
        for key, value in properties {
          sc, _ := parse_schema(value, state)
          sc.key = key
          schema.properties[key] = sc
        }
      }
    }


    if requried_fields_array, ok := object["required"].(json.Array); ok {
      schema.required = make_dynamic_array([dynamic]string, state.allocator)
      for field in requried_fields_array {
        if field_as_string, ok := field.(json.String); ok {
          append(&schema.required, field_as_string)
        }
      }
    }

    if "$ref" in object {
      if ref, ok := object["$ref"].(json.String); ok {
        // if the schema is just a $ref to another schema
        // no need to further schema parsing
        // Need to walk the original parsed JSON according
        // to the $ref
        schema._flags += {.Field_Ref}
        schema.ref = ref

        ref_schema_json_value, path_err := get_json_value_from_path(state.root, ref, state^)
        if path_err != .None {
          panic_msg := fmt.tprintfln("cannot get $ref path, %v", path_err)
          panic(panic_msg)
        }

        // TODO: Need to handle the error returned from here
        ref_schema, ref_schema_err := parse_schema(ref_schema_json_value, state)
        if ref_schema_err != .None {
          panic("error in $ref schema parsing")
        }

        // Make the the last path component in the $ref path
        // the new name of the schema
        path_parts := slashpath.split_elements(ref, state.allocator)
        last_idx := len(path_parts) - 1
        schema.key = path_parts[last_idx]

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
          case .Field_Items:
            schema.items = ref_schema.items
          case .Field_OneOf:
            schema.oneOf = ref_schema.oneOf
          case .FieldCount:
            panic("what the hell")
          }
        }
      }
    }

  }

  state.depth -= 1
  return schema, err
}

// Basically try to expand the schema into its struct form
// In the future generate formatted code
gen_struct_for_schema :: proc(schema: ^Schema, state: ^State) {
  builder := &state.builder

  enter_struct :: proc(builder: ^strings.Builder, struct_name: string) {
    struct_head := fmt.tprintf("struct %s ", len(struct_name) > 0 ? struct_name : "nil")
    strings.write_string(builder, struct_head)
    strings.write_string(builder, "{\n")
  }

  end_struct :: proc(builder: ^strings.Builder) {
    strings.write_string(builder, "}\n")
  }

  gen_number_field :: proc(builder: ^strings.Builder, field_name: string) {
    field_format := fmt.tprintfln("%s: f64,\n", field_name)
    strings.write_string(builder, field_format)
  }


  switch schema.type {
  case .Number:
    if len(schema.key) == 0 {
      panic("a number field name is missing")
    }
    gen_number_field(builder, schema.key)
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
      enter_struct(builder, schema.key)
      for property, value in schema.properties {
        gen_struct_for_schema(schema, state)
      }
      end_struct(builder)
    }
  case .String:
  // TODO
  case .Array:
  // TODO
  }


}
*/