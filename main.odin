package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"

JsonLottie_Error :: enum {
	None,
	Missing_Required_Value,
	Outof_Range_Value,
}

Error :: union {
	os.Error,
	JsonLottie_Error,
	json.Unmarshal_Error,
}

JsonLottie_Animation :: struct {
	nm:      string,
	ver:     i64,
	fr:      f64,
	ip:      f64,
	op:      f64,
	w:       i64,
	h:       i64,
	layers:  json.Array,
	assets:  json.Array,
	markers: json.Array,
	slots:   json.Object,
}

JsonLottie :: struct {
	animation: JsonLottie_Animation,
	raw:       []u8,
}

JsonLottie_Core_Types :: enum {
	Null,
	Array,
	Object,
	Float,
	Integer,
	Bool,
	String,
}
json_lottie_check_non_primitive :: proc(root: ^json.Object, key: string) {
	if root[key] == nil {
		fmt.println("nil")
		return
	}
	data := root[key]
	#partial switch type_val in data {
	case json.Null:
		fmt.println("Null")
	case json.Array:
		fmt.println("Array")
	case json.Object:
		fmt.println("Object")
	case json.Float:
		fmt.println("Float")

	}
}

json_lottie_field_is_expected_type :: proc(
	root: ^json.Object,
	key: string,
	expected: JsonLottie_Core_Types,
) -> (
	bool,
	JsonLottie_Core_Types,
) {
	data := root[key]
	union_type := JsonLottie_Core_Types.Null
	switch type_val in data {
	case json.Null:
		union_type = .Null
	case json.Array:
		union_type = .Array
	case json.Object:
		union_type = .Object
	case json.Boolean:
		union_type = .Bool
	case json.Integer:
		union_type = .Integer
	case json.Float:
		union_type = .Float
	case json.String:
		union_type = .String
	}

	if union_type == expected {
		return true, union_type
	} else {
		return false, union_type
	}
}

json_lottie_read_file_handle :: proc(
	fd: os.Handle,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: JsonLottie,
	err: Error,
) {

	data.raw = os.read_entire_file_from_handle_or_err(fd, allocator, loc) or_return
	parsed_json, parse_err := json.parse(data.raw)
	// note(iyaan): Need to call json.destroy_value on parsed_json
	// after we have fully parsed it into the structure
	if parse_err != nil {
		return JsonLottie{}, err
	}

	root := parsed_json.(json.Object)
	if root["h"] == nil ||
	   root["w"] == nil ||
	   root["fr"] == nil ||
	   root["op"] == nil ||
	   root["ip"] == nil {
		return JsonLottie{}, JsonLottie_Error.Missing_Required_Value
	}

	data.animation.nm = root["nm"].(json.String)
	data.animation.fr = root["fr"].(json.Float)
	data.animation.op = root["op"].(json.Float)
	data.animation.ip = root["ip"].(json.Float)
	data.animation.w = i64(root["w"].(json.Float))
	data.animation.h = i64(root["h"].(json.Float))

	if data.animation.h < 0 {
		return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
	}
	if data.animation.w < 0 {
		return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
	}
	if data.animation.fr < 1 {
		return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
	}
	LOTTIE_VERSION_MIN :: 10000
	if root["ver"] != nil && root["ver"].(json.Integer) < LOTTIE_VERSION_MIN {
		return JsonLottie{}, JsonLottie_Error.Outof_Range_Value
	} else if root["ver"] != nil && root["ver"].(json.Integer) > LOTTIE_VERSION_MIN {
		data.animation.ver = root["ver"].(json.Integer)
	}

	layer_ok, _ := json_lottie_field_is_expected_type(&root, "layers", .Array)
	marker_ok, _ := json_lottie_field_is_expected_type(&root, "markers", .Array)
	assets_ok, _ := json_lottie_field_is_expected_type(&root, "assets", .Array)
	slots_ok, _ := json_lottie_field_is_expected_type(&root, "slots", .Object)

	if layer_ok {
		data.animation.layers = root["layers"].(json.Array)
	}
	if marker_ok {
		data.animation.markers = root["markers"].(json.Array)
	}
	if assets_ok {
		data.animation.assets = root["assets"].(json.Array)
	}
	if slots_ok {
		data.animation.slots = root["slots"].(json.Object)
	}
	return data, JsonLottie_Error.None
}

json_lottie_read_file_name :: proc(
	file_name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: JsonLottie,
	err: Error,
) {
	context.allocator = allocator
	fd := os.open(file_name, os.O_RDONLY, 0) or_return
	defer os.close(fd)
	return json_lottie_read_file_handle(fd, allocator, loc)
}

main :: proc() {
	fmt.println("Welcome to tiny lottie project")
	lottie_struct, err := json_lottie_read_file_name("./data/Fire.json")
	fmt.eprintln(lottie_struct.animation)
}
