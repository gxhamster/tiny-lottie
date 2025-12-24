package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:thread"

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

JsonLottie_Transform :: struct {}

JsonLottie_Layer :: struct {
	nm:     string,
	hd:     bool,
	ty:     i64,
	ind:    i64,
	parent: i64,
	ip:     f64,
	op:     f64,
}

JsonLottie_Visual_Layer :: struct {}

JsonLottie_Shape_Layer :: struct {}

JsonLottie_Image_Layer :: struct {}

JsonLottie_Null_Layer :: struct {}

JsonLottie_Solid_Layer :: struct {}

JsonLottie_Precomp_Layer :: struct {}

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

json_lottie_parse_layers :: proc(
	anim: ^JsonLottie_Animation,
	layer_json_array: json.Array,
) -> JsonLottie_Error {
	return .None
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

	defer json.destroy_value(parsed_json)

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
		json_lottie_parse_layers(&data.animation, root["layers"].(json.Array))
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
	// note(iyaan): For debug mode setup the tracking allocator
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}

			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// note(iyaan): All allocations related to the JsonLottie struct
	// and all its sub structs would be nice to have in one arena block
	// so that it would be easy to free it all together
	json_lottie_arena_mem := make([]byte, 1 * mem.Megabyte)
	json_lottie_arena: mem.Arena
	mem.arena_init(&json_lottie_arena, json_lottie_arena_mem)
	json_lottie_arena_allocator := mem.arena_allocator(&json_lottie_arena)


	fmt.println("Welcome to tiny lottie project")
	lottie_struct, err := json_lottie_read_file_name(
		"./data/Fire.json",
		json_lottie_arena_allocator,
	)
	fmt.eprintln(lottie_struct.animation)

	// You free the underlying buffer for the arena. Not the
	// stack allocated arena struct. Hmm very C like!
	if arena_delete_err := delete(json_lottie_arena_mem); arena_delete_err != .None {
		panic("Could not deallocate arena for JsonLottie struct")
	}
}
