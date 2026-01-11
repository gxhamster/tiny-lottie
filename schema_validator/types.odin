package schema_validator

import "base:runtime"
import "core:encoding/json"
import "core:text/regex"

CompositeTypes :: []InstanceTypes

// Holding single types and combination of types
InstanceType :: union {
	InstanceTypes,
	CompositeTypes,
}

InstanceTypes :: enum {
	Null,
	Boolean,
	Object,
	Array,
	Number,
	Integer,
	String,
	Invalid,
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
	Expected_Array_Or_String,
	Regex_Creation_Failed,
	Regex_Parser_Error,
	Regex_Compiler_Error,


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
	Allof_Validation_Failed,
	Oneof_Validation_Failed,
	Anyof_Validation_Failed,
	If_Then_Validation_Failed,
	If_Else_Validation_Failed,
	Not_Validation_Failed,
	Max_Properties_Validation_Failed,
	Min_Properties_Validation_Failed,
	Max_Items_Validation_Failed,
	Min_Items_Validation_Failed,
	Contains_Validation_Failed,
	Max_Contains_Validation_Failed,
	Min_Contains_Validation_Failed,
	Items_Validation_Failed,
	Prefix_Items_Validation_Failed,
    Pattern_Validation_Failed,
	Bool_Schema_False,


	// Allocation Errors
	Allocation_Error,

	// Referencing Errors
	Ref_Non_Schema,
	Ref_Schema_Not_Found,
	Ref_Path_Not_Found_In_Defs,
}

// Takes a pointer to the schema to set the correct parameter
// to the parsed value
@(private)
ParseProc :: proc(
	value: json.Value,
	schema_idx: PoolIndex,
	schema_context: ^Context,
	allocator := context.allocator,
) -> Error
// No need to take a pointer since it does not need to set any
// state in the schema. It just needs to read in the correct
// field in the schema struct
@(private)
ValidationProc :: proc(value: json.Value, schema: ^Schema, ctx: ^Context) -> Error

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
	// Core vocabulary
	{"$id", .Id, parse_id},
	{"$schema", .Schema, parse_schema_field},
	{"$ref", .Ref, parse_ref},
	{"$comment", .Comment, parse_comment},
	{"$defs", .Defs, parse_defs},
	{"$anchor", .Anchor, nil},
	{"$dynamicAnchor", .DynamicAnchor, nil},
	{"$dynamicRef", .DynamicRef, nil},
	{"$vocabulary", .Vocabulary, nil},

	// Applicators
	{"allOf", .AllOf, parse_allof},
	{"anyOf", .AnyOf, parse_anyof},
	{"oneOf", .OneOf, parse_oneof},
	{"if", .If, parse_if},
	{"then", .Then, parse_then},
	{"else", .Else, parse_else},
	{"not", .Not, parse_not},
	{"properties", .Properties, parse_properties},
	{"additionalProperties", .AdditionalProperties, parse_additional_properties},
	{"patternProperties", .PatternProperties, parse_pattern_properties},
	{"dependentSchemas", .DependentSchemas, nil},
	{"propertyNames", .PropertyNames, parse_property_names},
	{"contains", .Contains, parse_contains},
	{"items", .Items, parse_items},
	{"prefixItems", .PrefixItems, parse_prefix_items},

	// Validators
	{"type", .Type, parse_type},
	{"enum", .Enum, parse_enum},
	{"const", .Const, parse_const},
	{"maxLength", .MaxLength, parse_max_length},
	{"minLength", .MinLength, parse_min_length},
	{"pattern", .Pattern, parse_pattern},
	{"exclusiveMaximum", .ExclusiveMaximum, parse_exclusive_max},
	{"exclusiveMinimum", .ExclusiveMinimum, parse_exclusive_min},
	{"maximum", .Maximum, parse_maximum},
	{"minimum", .Minimum, parse_minimum},
	{"multipleOf", .MultipleOf, parse_multipleof},
	{"dependentRequired", .DependentRequired, nil},
	{"maxProperties", .MaxProperties, parse_max_properties},
	{"minProperties", .MinProperties, parse_min_properties},
	{"required", .Required, parse_required},
	{"maxItems", .MaxItems, parse_max_items},
	{"minItems", .MinItems, parse_min_items},
	{"maxContains", .MaxContains, parse_max_contains},
	{"minContains", .MinContains, parse_min_contains},
	{"uniqueItems", .UniqueItems, nil},

	// Metadata
	{"title", .Title, parse_title},
	{"description", .Description, parse_description},
	{"default", .Default, nil},
	{"deprecated", .Deprecated, nil},
	{"examples", .Examples, nil},
	{"readOnly", .ReadOnly, nil},
	{"writeOnly", .WriteOnly, nil},

	// Unevaluated
	{"unevaluatedItems", .UnevaluatedItems, nil},
	{"unevaluatedProperties", .UnevaluatedProperties, nil},
}

// TODO: Implement validation procedure for each of the keywords -_-
@(private)
keywords_validation_table := [?]KeywordValidationInfo {
	// Core vocabulary //
	// These do not have any validation
	// to do. Just here to preserve the order of the enums
	{"$id", .Id, nil},
	{"$schema", .Schema, nil},
	{"$ref", .Ref, nil},
	{"$comment", .Comment, nil},
	{"$defs", .Defs, nil},
	{"$anchor", .Anchor, nil},
	{"$dynamicAnchor", .DynamicAnchor, nil},
	{"$dynamicRef", .DynamicRef, nil},
	{"$vocabulary", .Vocabulary, nil},

	// Applicators //
	{"allOf", .AllOf, validate_allof},
	{"anyOf", .AnyOf, validate_anyof},
	{"oneOf", .OneOf, validate_oneof},
	{"if", .If, validate_if_then_else},
	// note(iyaan): Leave `then` and `else` empty
	{"then", .Then, nil},
	{"else", .Else, nil},
	{"not", .Not, validate_not},
	{"properties", .Properties, validate_properties},
	{"additionalProperties", .AdditionalProperties, validate_additional_properties},
	{"patternProperties", .PatternProperties, validate_pattern_properties},
	{"dependentSchemas", .DependentSchemas, nil},
	{"propertyNames", .PropertyNames, validate_property_names},
	{"contains", .Contains, validate_contains},
	// note(iyaan): `items` and `prefixItems` validated
	// together. Keep `prefixItems` nil
	{"items", .Items, validate_items},
	{"prefixItems", .PrefixItems, nil},

	// Validators //
	{"type", .Type, validate_type},
	{"enum", .Enum, validate_enum},
	{"const", .Const, validate_const},
	{"maxLength", .MaxLength, validate_max_length},
	{"minLength", .MinLength, validate_min_length},
	{"pattern", .Pattern, validate_pattern},
	{"exclusiveMaximum", .ExclusiveMaximum, validate_exclusive_max},
	{"exclusiveMinimum", .ExclusiveMinimum, validate_exclusive_min},
	{"maximum", .Maximum, validate_maximum},
	{"minimum", .Minimum, validate_minimum},
	{"multipleOf", .MultipleOf, validate_multipleof},
	{"dependentRequired", .DependentRequired, nil},
	{"maxProperties", .MaxProperties, validate_max_properties},
	{"minProperties", .MinProperties, validate_min_properties},
	{"required", .Required, validate_required},
	{"maxItems", .MaxItems, validate_max_items},
	{"minItems", .MinItems, validate_min_items},
	// note(iyaan): Validated inside `contains` so leave
	// `maxContains` and `minContains` empty
	{"maxContains", .MaxContains, nil},
	{"minContains", .MinContains, nil},
	{"uniqueItems", .UniqueItems, nil},

	// Metadata //
	{"title", .Title, nil},
	{"description", .Description, nil},
	{"default", .Default, nil},
	{"deprecated", .Deprecated, nil},
	{"examples", .Examples, nil},
	{"readOnly", .ReadOnly, nil},
	{"writeOnly", .WriteOnly, nil},

	// Unevaluated //
	{"unevaluatedItems", .UnevaluatedItems, nil},
	{"unevaluatedProperties", .UnevaluatedProperties, nil},
}

// note(iyaan): Values of this enum will be used to
// lookup the correct parse and validate
// function from the tables above. So make sure
// the entries are in order of this enum.
SchemaKeywords :: enum {
	// Core vocabulary. There are no validation
	// procedures for these. In the validation table
	// there procedure will be kept nil. But they will
	// be parsed
	Id,
	Schema,
	Ref,
	Comment,
	Defs,
	Anchor,
	DynamicAnchor,
	DynamicRef,
	Vocabulary,

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

	// Metadata
	Title,
	Description,
	Default,
	Deprecated,
	Examples,
	ReadOnly,
	WriteOnly,

	// Unevaluated
	UnevaluatedItems,
	UnevaluatedProperties,

	// TODO: Add all other keywords in schema specfification
}

Schema :: struct {
	// Core stuff of the schema
	schema:              string,
	id:                  string,
	title:               string,
	comment:             string,
	description:         string,
	// note(iyaan): I dont know whether I will be able to implement
	// fully URI path support for refs
	ref:                 string,
	defs:                map[string]PoolIndex,

	// Internal stuff
	// Used for holding the name of a property
	name:                string,
	is_bool_schema:      bool,
	bool_schema_val:     bool,

	// Used to denote whether this schema is used to just
	// as a holder for another schema. Used by $ref when
	// referencing embedded sub-schemas
	is_empty_container:  bool,
	other_keys:          map[string]PoolIndex,


	// Applicator keywords
	properties_children: [dynamic]PoolIndex,
	items_children:      [dynamic]PoolIndex,
    additional_properties: PoolIndex, 
    property_names:        PoolIndex, 
	allof:               [dynamic]PoolIndex,
	anyof:               [dynamic]PoolIndex,
	oneof:               [dynamic]PoolIndex,
	// note(iyaan): Regular_Expression allocates things
	// Each refex in `pattern_regex` corresponds to a
	// property in `pattern_properties`
	pattern_regex:       [dynamic]regex.Regular_Expression,
	pattern_properties:  [dynamic]PoolIndex,
	// note(iyaan): During validation probably we can just
	// have a procedure just for if. `then` and `else` by themselves
	// does not have meaning without the `if` condition schema. So checking
	// of those fields could be done in the `if` validation proc..
	_if:                 PoolIndex,
	then:                PoolIndex,
	_else:               PoolIndex,
	not:                 PoolIndex,
	contains:            PoolIndex,
	items:               PoolIndex,
	prefix_items:        [dynamic]PoolIndex,


	// Validation keywords
	// note(iyaan): We need a way to know whether a schema has defined
	// a validation keyword. Struct would default these to zero. This means
	// we wont know really if that has been defined and the validation logic
	// might run for that keyword. For `minimum` this means for each schema
	// it will check whether a value is min zero, which is not the behaviour
	// that we want. We need a sort of flag set for each defined validation
	// keyword
	validation_flags:    bit_set[SchemaKeywords],
	type:                InstanceType,
	const:               json.Value,
	min_length:          int,
	max_length:          int,
    pattern:             regex.Regular_Expression,
	exclusive_max:       f64,
	exclusive_min:       f64,
	multipleof:          f64,
	enums:               []json.Value,
	minimum:             f64,
	maximum:             f64,
	required:            []string,
	max_items:           int,
	min_items:           int,
	max_properties:      int,
	min_properties:      int,
	max_contains:        int,
	min_contains:        int,
}

// Just a neat little to hold store related stuff
RefsToResolve :: struct {
	ref:           string,
	// note(iyaan): This is just where the ref path
	// string has been found in. Useful when we need to
	// set the ref_as_schema after the target schema pointed
	// to by the $ref has been found
	source_schema: PoolIndex,
}

// note(iyaan): Dynamic arrays are likely to get
// reallocated which would invalidate pointers to any
// schemas in it. So for long term references using and index
PoolIndex :: distinct int

Context :: struct {
	refs_to_resolve: [dynamic]RefsToResolve,
	// note(iyaan): I can sleep better knowing that
	// schemas are pooled and not allocated one by one
	// still all the internal strigs and maps are still
	// dependent on whatever allocator is used
	schema_pool:     [dynamic]Schema,
}

POOL_INIT_CAPACITY :: 128
init_context :: proc(
	ctx: ^Context,
	pool_init_cap := POOL_INIT_CAPACITY,
	allocator := context.allocator,
) -> runtime.Allocator_Error {
	ctx.refs_to_resolve = make([dynamic]RefsToResolve, 0, allocator) or_return
	ctx.schema_pool = make([dynamic]Schema, 0, allocator) or_return

	reserve(&ctx.schema_pool, pool_init_cap) or_return
	reserve(&ctx.refs_to_resolve, pool_init_cap) or_return

	return .None
}

get_schema :: #force_inline proc(ctx: ^Context, idx: PoolIndex) -> ^Schema {
	assert(ctx.schema_pool != nil, "Schema pool is not initialized")
	assert(int(idx) < len(ctx.schema_pool), "Out of bounds index")

	return &ctx.schema_pool[idx]
}
