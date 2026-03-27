#+feature dynamic-literals

package main
import "core:encoding/json"
import vmem "core:mem/virtual"
import "core:fmt"
import "core:log"
import "core:testing"
import "core:strings"
import "core:os"

@(test)
json_lottie_unmarshal_test :: proc(t: ^testing.T) {
  test_struct :: struct {
    sid: string,
    a:   bool,
    k:   []f64,
    j:   PropKeyframeEasingScalar,
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

  unmarshal_value(m["sid"], t1.sid)
  testing.expect(t, t1.sid == "1234", "Unmarshal value correctly")


  unmarshal_object(m, t1)
  testing.expect_value(t, t1.sid, "1234")
  testing.expect_value(t, t1.a, true)
  for elem, idx in a {
    testing.expect_value(t, t1.k[idx], elem.(json.Float))
  }
  testing.expect_value(t, t1.j, PropKeyframeEasingScalar{1, 2})
  testing.expect_value(t, t1.v, Vec3{5, 5, 6})

  test_struct2 :: struct {
    j: []PropKeyframeEasingScalar,
  }
  t2 := test_struct2{}

  m1 := json.Object {
    "j" = json.Array {
      json.Object{"x" = 1, "y" = 2},
      json.Object{"x" = 3, "y" = 4},
    },
  }
  unmarshal_object(m1, t2)
  testing.expect(t, len(t2.j) == 2, "Length should be 2")
  testing.expect_value(t, t2.j[0], PropKeyframeEasingScalar{1, 2})
  testing.expect_value(t, t2.j[1], PropKeyframeEasingScalar{3, 4})
}

@(test)
json_lottie_gradient_test :: proc(t: ^testing.T) {
  json_arr := json.Array {
    0.0,
    0.161,
    0.184,
    0.459,
    0.5,
    0.196,
    0.314,
    0.69,
    1.0,
    0.769,
    0.851,
    0.961,
  }
  defer free_all()
  p: Gradient
  unmarshal_array(json_arr, p)

  testing.expect(t, len(json_arr) == len(p), "Both lengths should be same")

  for elem, idx in json_arr {
    elem_float := elem.(json.Float)
    testing.expect_value(t, elem_float, p[idx])
  }
}

@(test)
json_lottie_bezier_shape_test :: proc(t: ^testing.T) {
  logger := log.create_console_logger()
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
  p := BezierShapeValue{}
  if err := unmarshal_object(json_obj, p); err != .None {
    err_str := fmt.tprintf("Unmarshal returned an error: %v", err)
    testing.expect(t, err == .None, err_str)
  }
  // log.info("=== Bezier Shape === ", p)

  testing.expect(t, p.c == true, "c is true")
  for elem, idx in json_obj["v"].(json.Array) {
    for x, idx1 in elem.(json.Array) {
      testing.expect_value(t, x.(json.Float), p.v[idx][idx1])
    }
  }

  log.destroy_console_logger(logger)
}

@(test)
lottie_enum_unmarshal_test :: proc(t: ^testing.T) {
  m := json.Object {
    "sid" = "2",
    "id"  = 2,
    "id1" = 5,
  }

  defer free_all()

  mm: MatteMode

  //testing.expect(
  //  t,
  //  unmarshal_value(m["sid"], mm) == LottieError.IncompatibleIntegerType,
  //  "Cannot convert non-integer value to enum",
  //)
  testing.expect(
    t,
    unmarshal_value(m["id"], mm) == LottieError.None,
    "Corrrect value for MatteMode enum",
  )
  testing.expect(
    t,
    unmarshal_value(m["id1"], mm) ==
    LottieError.UnmarshalOutOfBoundEnumValue,
    "An integer value that is not an enumeration for MatteMode",
  )

}

@(test)
json_lottie_test_prop_position_keyframe :: proc(t: ^testing.T) {
  m := json.Object{
    "t" = 23,
    "h" = 2,
    "i" = json.Object{
        "x" = json.Array{1, 2, 3},
        "y" = json.Array{1, 2, 3}
    },
    "o" = json.Object{
        "x" = json.Array{2, 3, 4},
        "y" = json.Array{2, 3, 4}
    },
    "s"  = json.Array{5, 6},
    "ti" = json.Array{8, 9, 10},
    "to" = json.Array{11, 12, 13},
  }

  defer free_all()
  keyframe := PropPositionKeyframe{}
  err := unmarshal_object(m, keyframe)
  log.debug(keyframe)
}

@(test)
json_lottie_parse_transform_test :: proc(t: ^testing.T) {
  source := `{
"a": {
    "sid": "this is heck of a long string that is going to occupy more than the viewport space, i think",
    "a": 0,
    "k": [
        256.245,
        256
    ]
},
"p": {
    "a": 0,
    "k": [
        23.525,
        256
    ]
},
"s": {
    "a": 0,
    "k": [
        100,
        100,
        562356.252
    ]
},
"r": {
    "a": 0,
    "k": 300
},
"o": {
    "a": 0,
    "k": 100
},
"sk": {
    "a": 0,
    "k": 0
},
"sa": {
    "a": 0,
    "k": 0
}
}`
 
 value, err := json.parse_string(source, parse_integers = true, allocator = context.temp_allocator)
 if err != .None {
  log.fatalf("json.parse returned error = %v", err)
 } else {
   tr := Transform{}
   err := unmarshal_object(value, tr)
   if err != .None {
    log.fatalf("parse_transform returned error = %v, %v", err, tr)
   } else {
     writer := Writer{}
     writer_init(&writer, allocator = context.temp_allocator)
     write_transform(&writer, tr)
     log.debug(writer.data[:10])
     total_bits := 0
     for d, idx in writer.debug {
      bits := (d.end_byte - d.start_byte) * 8 + int(d.end_bit - d.start_bit)
      total_bits += bits
      // log.debug(idx, d, "SIZE:", bits) 
     }
     // log.debugf("OFFSET: %v, BIT_OFFSET: %v\n", writer.offset, writer.bits)
     // log.debug(tr)
     builder := gen_html(&writer)
     builder_str := strings.to_string(builder)
     // log.debug(builder_str)
     FILE_NAME :: "data.debug"
     succ := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
     if !succ {
      panic("something went very wrong while file writing") 
     }
   }
 }
}

@(test)
path_unmarshal_test :: proc(t: ^testing.T) {
  source := `{
    "nm": "path",
    "hd": true,
    "ty": "sh",
    "d": 1,
    "ks": {
        "a": 0,
        "k": {
            "c": true,
            "v": [
                [
                    253,
                    147
                ],
                [
                    56,
                    153
                ],
                [
                    253,
                    440
                ],
                [
                    450,
                    153
                ]
            ],
            "i": [
                [
                    12,
                    -57
                ],
                [
                    42,
                    -112
                ],
                [
                    -32,
                    -114
                ],
                [
                    46,
                    123
                ]
            ],
            "o": [
                [
                    -17,
                    -61
                ],
                [
                    -46,
                    125
                ],
                [
                    32,
                    -114
                ],
                [
                    -43,
                    -115
                ]
            ]
        }
    }
}`
 value, err := json.parse_string(source, parse_integers = true, allocator = context.temp_allocator)
 if err != .None {
  log.fatalf("json.parse returned error = %v", err)
 } else {
   path := Path{}
   err := unmarshal_object(value, path)
   if err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", err, path)
   } else {
     log.debug(path)
     writer := Writer{}
     writer_init(&writer, allocator = context.temp_allocator)
     write_path(&writer, path)
     total_bits := 0
     for d, idx in writer.debug {
      bits := (d.end_byte - d.start_byte) * 8 + int(d.end_bit - d.start_bit)
      total_bits += bits
      log.debug(idx, d, "SIZE:", bits) 
     }
     builder := gen_html(&writer)
     builder_str := strings.to_string(builder)
     FILE_NAME :: "data.debug"
     succ := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
     if !succ {
      panic("something went very wrong while file writing") 
     }
   }
 }
}


@(test)
gradient_stroke_unmarshal_test :: proc(t: ^testing.T) {
  source := `{"ty":"gs","nm":"Stroke","o":{"a":0,"k":100},"c":{"a":0,"k":[1,0.98,0.28]},"lc":2,"lj":2,"ml":3,"w":{"a":0,"k":30},"d":[{"n":"d","nm":"dash","v":{"a":0,"k":100}},{"n":"g","nm":"gap","v":{"a":0,"k":0}},{"n":"o","nm":"offset","v":{"a":0,"k":0}}],"r":1,"s":{"a":0,"k":[256,496]},"e":{"a":0,"k":[256,16]},"t":1,"g":{"p":3,"k":{"a":0,"k":[0,0.7686274509803922,0.8509803921568627,0.9607843137254902,0.5,0.19600213626306554,0.31400015259021896,0.6899977111467155,1,0.16099794003204396,0.18399328603036547,0.45900663767452504,0,1,0.5,1,1,1]}}}`

 value, err := json.parse_string(source, parse_integers = true, allocator = context.temp_allocator)
 if err != .None {
  log.fatalf("json.parse returned error = %v", err)
 } else {
   gradient := GradientStroke{}
   err := unmarshal_object(value, gradient)
   if err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", err, gradient)
   } else {
     log.debug(gradient)
     writer := Writer{}
     writer_init(&writer, allocator = context.temp_allocator)
     write_gradient_stroke(&writer, gradient)
     total_bits := 0
     for d, idx in writer.debug {
      bits := (d.end_byte - d.start_byte) * 8 + int(d.end_bit - d.start_bit)
      total_bits += bits
      log.debug(idx, d, "SIZE:", bits) 
     }
     builder := gen_html(&writer)
     builder_str := strings.to_string(builder)
     FILE_NAME :: "data.debug"
     succ := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
     if !succ {
      panic("something went very wrong while file writing") 
     }
   }
 }
}

@(test)
group_unmarshal_test :: proc(t: ^testing.T) {
  source := `{"ty":"gr","it":[{"ind":0,"ty":"sh","ks":{"a":1,"k":[{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":60,"s":[{"i":[[51.25,10.429],[47.25,35.25]],"o":[[5.5,-8.321],[29,7.5]],"v":[[-49.75,163],[-79.75,106.179]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":74,"s":[{"i":[[51.983,10.645],[36.75,139.5]],"o":[[-1,14.429],[-14.517,22.717]],"v":[[-77.983,110.033],[-31.233,57.212]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":75,"s":[{"i":[[52.25,9.179],[36.75,139.5]],"o":[[-1,14.429],[-11.25,22]],"v":[[-80,106.25],[-34.25,64.429]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":89,"s":[{"i":[[2.5,5.429],[36.75,139.5]],"o":[[-1,14.429],[-1,5.5]],"v":[[-35.5,58.5],[-29.25,57.679]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":90,"s":[{"i":[[51.25,10.429],[47.25,35.25]],"o":[[5.5,-8.321],[29,7.5]],"v":[[-49.75,163],[-79.75,106.179]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":104,"s":[{"i":[[51.983,10.645],[36.75,139.5]],"o":[[-1,14.429],[-14.517,22.717]],"v":[[-77.983,110.033],[-31.233,57.212]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":105,"s":[{"i":[[52.25,9.179],[36.75,139.5]],"o":[[-1,14.429],[-11.25,22]],"v":[[-80,106.25],[-34.25,64.429]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":119,"s":[{"i":[[2.5,5.429],[36.75,139.5]],"o":[[-1,14.429],[-1,5.5]],"v":[[-35.5,58.5],[-29.25,57.679]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":120,"s":[{"i":[[51.25,10.429],[47.25,35.25]],"o":[[5.5,-8.321],[29,7.5]],"v":[[-49.75,163],[-79.75,106.179]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":134,"s":[{"i":[[51.983,10.645],[36.75,139.5]],"o":[[-1,14.429],[-14.517,22.717]],"v":[[-77.983,110.033],[-31.233,57.212]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":135,"s":[{"i":[[52.25,9.179],[36.75,139.5]],"o":[[-1,14.429],[-11.25,22]],"v":[[-80,106.25],[-34.25,64.429]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":149,"s":[{"i":[[2.5,5.429],[36.75,139.5]],"o":[[-1,14.429],[-1,5.5]],"v":[[-35.5,58.5],[-29.25,57.679]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":150,"s":[{"i":[[51.25,10.429],[47.25,35.25]],"o":[[5.5,-8.321],[29,7.5]],"v":[[-49.75,163],[-79.75,106.179]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":164,"s":[{"i":[[51.983,10.645],[36.75,139.5]],"o":[[-1,14.429],[-14.517,22.717]],"v":[[-77.983,110.033],[-31.233,57.212]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":165,"s":[{"i":[[52.25,9.179],[36.75,139.5]],"o":[[-1,14.429],[-11.25,22]],"v":[[-80,106.25],[-34.25,64.429]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":179,"s":[{"i":[[2.5,5.429],[36.75,139.5]],"o":[[-1,14.429],[-1,5.5]],"v":[[-35.5,58.5],[-29.25,57.679]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":180,"s":[{"i":[[51.25,10.429],[47.25,35.25]],"o":[[5.5,-8.321],[29,7.5]],"v":[[-49.75,163],[-79.75,106.179]],"c":true}]},{"i":{"x":0.833,"y":0.833},"o":{"x":0.167,"y":0.167},"t":198,"s":[{"i":[[51.983,10.645],[36.75,139.5]],"o":[[-1,14.429],[-14.517,22.717]],"v":[[-77.983,110.033],[-31.233,57.212]],"c":true}]},{"i":{"x":0.156,"y":1},"o":{"x":0.167,"y":0.167},"t":199,"s":[{"i":[[52.25,9.179],[36.75,139.5]],"o":[[-1,14.429],[-11.25,22]],"v":[[-80,106.25],[-34.25,64.429]],"c":true}]},{"t":240,"s":[{"i":[[2.5,5.429],[36.75,139.5]],"o":[[-1,14.429],[-1,5.5]],"v":[[-35.5,58.5],[-29.25,57.679]],"c":true}]}]},"nm":"prov left2","hd":false},{"ty":"gf","o":{"a":0,"k":100},"r":1,"bm":0,"g":{"p":3,"k":{"a":0,"k":[0.121,0.996,0.996,0.898,0.54,0.998,0.951,0.598,0.808,1,0.906,0.298]}},"s":{"a":0,"k":[-6.123,134.654]},"e":{"a":1,"k":[{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":60,"s":[-4.994,35.327],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":75,"s":[-5.994,-4.673],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":90,"s":[-4.994,35.327],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":105,"s":[-5.994,-4.673],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":120,"s":[-4.994,35.327],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":135,"s":[-5.994,-4.673],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":150,"s":[-4.994,35.327],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":165,"s":[-5.994,-4.673],"to":[0,0],"ti":[0,0]},{"i":{"x":0.667,"y":1},"o":{"x":0.333,"y":0},"t":180,"s":[-4.994,35.327],"to":[0,0],"ti":[0,0]},{"i":{"x":0.156,"y":1},"o":{"x":0.333,"y":0},"t":199,"s":[-5.994,-4.673],"to":[0,0],"ti":[0,0]},{"t":240,"s":[-4.994,35.327]}]},"t":2,"h":{"a":0,"k":0},"a":{"a":0,"k":0},"nm":"Gradient Fill 4","hd":false},{"ty":"tr","p":{"a":0,"k":[-27.257,83.339]},"a":{"a":0,"k":[-27.257,83.339]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100},"sk":{"a":0,"k":0},"sa":{"a":0,"k":0},"nm":"Transform"}],"nm":"Group 13","bm":0,"hd":false}`

 value, err := json.parse_string(source, parse_integers = true, allocator = context.temp_allocator)
 if err != .None {
  log.fatalf("json.parse returned error = %v", err)
 } else {
   group := Group{}
   err := unmarshal_object(value, group)
   if err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", err, group)
   } else {
     log.debug(group)
     writer := Writer{}
     writer_init(&writer, data_len = 1 << 32, allocator = context.temp_allocator)
     write_group(&writer, group)
     total_bits := 0
     for d, idx in writer.debug {
      bits := (d.end_byte - d.start_byte) * 8 + int(d.end_bit - d.start_bit)
      total_bits += bits
      log.debug(idx, d, "SIZE:", bits) 
     }
     builder := gen_html(&writer)
     builder_str := strings.to_string(builder)
     FILE_NAME :: "data.debug"
     succ := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
     if !succ {
      panic("something went very wrong while file writing") 
     }
   }
 }
}

@(test)
animation_unmarshal_test :: proc(t: ^testing.T) {
  arena: vmem.Arena
	arena_allocator := vmem.arena_allocator(&arena)

  data, ok := os.read_entire_file_from_filename("./data/Fire.json")
  
  defer delete(data)

  if !ok {
    log.fatalf("could not read from file")
  }

  value, err := json.parse(data, parse_integers = true)
  if err != .None {
    log.fatalf("could not parse json due to %v", err)
  }

  defer json.destroy_value(value)


  anim := Animation{}
  unmarshal_err := unmarshal_object(value, anim, allocator = arena_allocator)
  if unmarshal_err != .None {
    log.fatalf("unmarshal_object returned error = %v, %v", unmarshal_err, anim)
  }
  // log.debug(anim)
  writer := Writer{}
  writer_init(&writer, data_len = 1 << 32, allocator = arena_allocator)
  write_animation(&writer, anim)
  total_bits := 0
  for d, idx in writer.debug {
  bits := (d.end_byte - d.start_byte) * 8 + int(d.end_bit - d.start_bit)
  total_bits += bits
  log.debug(idx, d, "SIZE:", bits) 
  }
  builder := gen_html(&writer)
  builder_str := strings.to_string(builder)
  FILE_NAME :: "data.debug"
  succ := os.write_entire_file(FILE_NAME, transmute([]u8)builder_str)
  if !succ {
    panic("something went very wrong while file writing") 
  }

  vmem.arena_destroy(&arena)

}