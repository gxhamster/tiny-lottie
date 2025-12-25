package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:reflect"


JsonLottie_Error :: enum {
	None,
	Missing_Required_Value,
	Outof_Range_Value,
	Incompatible_Vector_Type,
	Incompatible_Vector_Inner_Type,
	Too_Large_Vector,
}

Error :: union {
	os.Error,
	JsonLottie_Error,
	json.Error,
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

// Base types
Vec3 :: distinct [3]f64
Vec2 :: distinct [2]f64


// Properties
JsonLottie_Prop_Keyframe_Easing :: struct {
	x: []f64,
	y: []f64,
}

JsonLottie_Prop_Scalar :: union {
	JsonLottie_Prop_Scalar_Single,
	JsonLottie_Prop_Scalar_Anim,
}

JsonLottie_Prop_Scalar_Single :: struct {
	sid: string,
	a:   bool,
	k:   f64,
}

JsonLottie_Prop_Scalar_Anim :: struct {
	sid: string,
	a:   bool,
	k:   []struct {
		t: f64,
		h: i64,
		i: JsonLottie_Prop_Keyframe_Easing,
		o: JsonLottie_Prop_Keyframe_Easing,
		s: f64,
	},
}

JsonLottie_Prop_Vector :: union {
	JsonLottie_Prop_Vector_Single,
	JsonLottie_Prop_Vector_Anim,
}

JsonLottie_Prop_Vector_Single :: struct {
	sid: string,
	a:   bool,
	k:   Vec3,
}
JsonLottie_Prop_Vector_Anim :: struct {
	sid: string,
	a:   bool,
	k:   []struct {
		t: f64,
		h: i64,
		i: JsonLottie_Prop_Keyframe_Easing,
		o: JsonLottie_Prop_Keyframe_Easing,
		s: Vec3,
	},
}

// 2D version of a Vector property
JsonLottie_Prop_Position :: union {
	JsonLottie_Prop_Position_Single,
	JsonLottie_Prop_Position_Anim,
}

JsonLottie_Prop_Position_Single :: JsonLottie_Prop_Vector_Single

JsonLottie_Prop_Position_Anim :: struct {
	sid: string,
	a:   bool,
	k:   []struct {
		t:  f64,
		h:  i64,
		i:  JsonLottie_Prop_Keyframe_Easing,
		o:  JsonLottie_Prop_Keyframe_Easing,
		s:  []Vec3,
		ti: []Vec3,
		to: []Vec3,
	},
}

JsonLottie_Prop_Split_Position :: struct {
	s: bool,
	x: JsonLottie_Prop_Scalar,
	y: JsonLottie_Prop_Scalar,
}

// Helpers
JsonLottie_Transform :: struct {
	a:  JsonLottie_Prop_Position,
	p:  JsonLottie_Prop_Split_Position,
	r:  JsonLottie_Prop_Scalar,
	s:  JsonLottie_Prop_Vector,
	o:  JsonLottie_Prop_Scalar,
	sk: JsonLottie_Prop_Scalar,
	sa: JsonLottie_Prop_Scalar,
}

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
json_obj_val_type :: proc(root: ^json.Object, key: string) -> JsonLottie_Core_Types {
	if root[key] == nil {
		return .Null
	}
	data := root[key]
	#partial switch type_val in data {
	case json.Null:
		return .Null
	case json.Array:
		return .Array
	case json.Object:
		return .Object
	case json.Float:
		return .Float
	case json.Integer:
		return .Integer
	}
	panic("unexpected type")
}

json_lottie_field_is_expected_type :: proc(
	root: ^json.Object,
	key: string,
	expected: JsonLottie_Core_Types,
) -> bool {
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
		return true
	} else {
		return false
	}
}

json_lottie_parse_layers :: proc(
	anim: ^JsonLottie_Animation,
	layer_json_array: json.Array,
	allocator := context.allocator,
	loc := #caller_location,
) -> JsonLottie_Error {
	p := (layer_json_array[0].(json.Object)["ks"].(json.Object))

	json_lottie_parse_transform(&p)
	return .None
}

json_lottie_parse_vec :: proc(
	value: ^json.Value,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	Vec3,
	JsonLottie_Error,
) {
	#partial switch value_type in value {
		case json.Array:
			vec: Vec3
			value_as_arr := &value.(json.Array)
			if len(value_as_arr) > len(vec) {
				return Vec3{}, .Too_Large_Vector
			}
			
			for idx in 0..<len(value_as_arr) {
				fmt.println(typeid_of(type_of(value_as_arr[idx])))
				// note(iyaan): Check float similarity of Value
				#partial switch elem_type in value_as_arr[idx] {
					case json.Float:
						vec[idx] = f64(value_as_arr[idx].(json.Float))
					case json.Integer:
						vec[idx] = f64(value_as_arr[idx].(json.Integer))
					case:
						return Vec3{}, .Incompatible_Vector_Inner_Type
				}
			}
			
			return vec, .None
	}
	return Vec3{}, .Incompatible_Vector_Type
}

json_lottie_parse_position :: proc(
	position_obj: ^json.Object,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	position: JsonLottie_Prop_Position,
	err: JsonLottie_Error,
) {
	required_fields := []string{"a", "k"}
	for field in required_fields {
		if ok := field in position_obj; ok == false {
			return position, .Missing_Required_Value
		}
	}

	animated := i64(position_obj["a"].(json.Float))
	if animated == 0 {
		if json_lottie_field_is_expected_type(position_obj, "k", .Array) {
			single_pos := JsonLottie_Prop_Position_Single {
				a = false,
			}
			k_vec, vec_err := json_lottie_parse_vec(&position_obj["k"])
			single_pos.k = k_vec
			return single_pos, vec_err
		}
	} else {
		position_anim := JsonLottie_Prop_Position_Anim {
			a = true,
		}

		return position_anim, .None
	}
	return position, .None
}

json_lottie_parse_transform :: proc(
	transform_obj: ^json.Object,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	transform: JsonLottie_Transform,
) {
	// note(iyaan): Not required fields in a transform
	// just fill the struct with whatever available
	a := transform_obj["a"]
	p := transform_obj["p"]
	r := transform_obj["r"]
	s := transform_obj["s"]
	o := transform_obj["o"]
	sk := transform_obj["sk"]
	sa := transform_obj["sa"]

	pos, pos_err := json_lottie_parse_position(&(a.(json.Object)))
	fmt.println("Pos:", pos, "A:", a, "Err:", pos_err)

	return transform
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
		return JsonLottie{}, parse_err
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

	layer_ok := json_lottie_field_is_expected_type(&root, "layers", .Array)
	marker_ok := json_lottie_field_is_expected_type(&root, "markers", .Array)
	assets_ok := json_lottie_field_is_expected_type(&root, "assets", .Array)
	slots_ok := json_lottie_field_is_expected_type(&root, "slots", .Object)


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
	json_lottie_arena: vmem.Arena
	arena_err := vmem.arena_init_growing(&json_lottie_arena)
	ensure(arena_err == nil)
	json_lottie_arena_allocator := vmem.arena_allocator(&json_lottie_arena)


	lottie_struct, err := json_lottie_read_file_name(
		"./data/Fire.json",
		json_lottie_arena_allocator,
	)

	if err != nil && err != JsonLottie_Error.None {
		fmt.eprintf("Could not read lottie json file due to %s\n", err)
		panic("Could not read lottie json file")
	}

	fmt.eprintln(lottie_struct.animation)


	// You free the underlying buffer for the arena. Not the
	// stack allocated arena struct. Hmm very C like!
	vmem.arena_destroy(&json_lottie_arena)
}
