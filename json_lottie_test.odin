#+feature dynamic-literals

package main
import "core:testing"
import "core:encoding/json"
import "core:fmt"


@(test)
json_lottie_unmarshal_test :: proc(t: ^testing.T) {
	test_struct :: struct {
		sid: string,
		a:   bool,
		k:   []f64,
		j:   JsonLottie_Prop_Keyframe_Easing_Scalar,
		v:   Vec3,
	}

	a := json.Array{1.2, 1.3, 1.4, 1.5, 16.2}

	m := json.Object {
		"sid" = "1234",
		"a" = true,
		"k" = a,
		"j" = json.Object{"x" = 1, "y" = 2},
		"v" = json.Array{5, 5, 6},
	}

	defer free_all()

	t1 := test_struct {
		k = {1.1, 1.2, 1.3},
	}

	json_lottie_unmarshal_value(m["sid"], t1.sid)
	testing.expect(t, t1.sid == "1234", "Unmarshal value correctly")


	json_lottie_unmarshal_object(m, t1)
	testing.expect_value(t, t1.sid, "1234")
	testing.expect_value(t, t1.a, true)
	for elem, idx in a {
		testing.expect_value(t, t1.k[idx], elem.(json.Float))
	}
	testing.expect_value(t, t1.j, JsonLottie_Prop_Keyframe_Easing_Scalar{1, 2})
	testing.expect_value(t, t1.v, Vec3{5, 5, 6})

	test_struct2 :: struct {
		j: []JsonLottie_Prop_Keyframe_Easing_Scalar,
	}
	t2 := test_struct2{}

	m1 := json.Object {
		"j" = json.Array{json.Object{"x" = 1, "y" = 2}, json.Object{"x" = 3, "y" = 4}},
	}
	json_lottie_unmarshal_object(m1, t2)
	testing.expect(t, len(t2.j) == 2, "Length should be 2")
	testing.expect_value(t, t2.j[0], JsonLottie_Prop_Keyframe_Easing_Scalar{1, 2})
	testing.expect_value(t, t2.j[1], JsonLottie_Prop_Keyframe_Easing_Scalar{3, 4})
}

@(test)
json_lottie_gradient_test :: proc(t: ^testing.T) {
	json_arr := json.Array{0.0, 0.161, 0.184, 0.459, 0.5, 0.196, 0.314, 0.69, 1.0, 0.769, 0.851, 0.961}
	defer free_all()
	p: Gradient
	json_lottie_unmarshal_array(json_arr, p)

	testing.expect(t, len(json_arr) == len(p), "Both lengths should be same")

	for elem, idx in json_arr {
		elem_float := elem.(json.Float)
		testing.expect_value(t, elem_float, p[idx])
	}
}

@(test)
json_lottie_bezier_shape_test :: proc(t: ^testing.T) {
	json_obj := json.Object {
		"c" = true,
		"v" = json.Array {
			json.Array{194.591, 155.276},
			json.Array{181.683, 163.021},
			json.Array{21.625, 364.386},
			json.Array{450.0, 153.0},
		},
		"i" = json.Array {
			json.Array{-33.883, -127.257},
			json.Array{42.0, -112.0},
			json.Array{-32.0, -114.0},
			json.Array{-181.833, 66.816},
		},
		"o" = json.Array {
			json.Array{-17.0, -61.0},
			json.Array{-46.0, 125.1},
			json.Array{32.0, -114.1},
			json.Array{-43.0, -115.1},
		},
	}
	defer free_all()
	p := BezierShape{}
	json_lottie_unmarshal_object(json_obj, p)
	fmt.println(p)
	testing.expect(t, p.c == true, "c is true")
	for elem, idx in json_obj["v"].(json.Array) {
		for x, idx1 in elem.(json.Array) {
			testing.expect_value(t, x.(json.Float), p.v[idx][idx1])
		}
	}
}