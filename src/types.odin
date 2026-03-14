package main

import "core:os"
import "core:encoding/json"
import "base:intrinsics"

fields :: intrinsics.type_struct_field_count

JL_Error :: enum {
  None,
  Missing_Required_Value,
  Outof_Range_Value,
  Unmarshal_Err,
  Incompatible_Vector_Type,
  Incompatible_Vector_Inner_Type,
  Incompatible_Object_Type,
  Incompatible_Scalar_Type,
  Incompatible_Integer_Type,
  Incompatible_Array_Type,
  Incompatible_Number_Type,
  Incompatible_Boolean_Type,
  Incompatible_String_Type,
  Incompatible_Position_Type,
  Incompatible_Prop_Scalar_Type,
  Incompatible_Transform_Type,
  Too_Large_Vector,
  Too_Small_Vector,
  Unmarshal_Unknown_Value_Type,
  Unmarshal_Unknown_Array_Type,
  Unmarshal_Unsupported_Array_Type,
  Unmarshal_Unknown_Object_Type,
  Unmarshal_Unknown_Array_Inner_Type,
  Unmarshal_Unknown_Struct_Field_Type,
  Unmarshal_Unknown_Union_Field_Type,
  Unmarshal_Out_Of_Bound_Enum_Value,
  Unmarshal_Allocation_Error,
  Unmarshal_Deallocation_Error,
}

Error :: union {
  os.Error,
  JL_Error,
  json.Error,
}

Animation :: struct {
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

// Values
Vec4 :: distinct [4]f64
Vec3 :: distinct [3]f64
Vec2 :: distinct [2]f64

// note(iyaan): sometimes you might find color values
// with 4 components (the 4th being alpha) but most
// players ignore the last component.
Color3 :: Vec3
Color4 :: Vec4
HexColor :: distinct string
Gradient :: distinct []f64

BezierShapeValue :: struct {
  c: bool,
  i: []Vec3,
  o: []Vec3,
  v: []Vec3,
}


// Enumerations
MatteMode :: enum {
  Normal,
  Alpha,
  InvertedAlpha,
  Luma,
  InvertedLuma,
}

PropKeyframeEasing :: union {
  PropKeyframeEasingScalar,
  PropKeyframeEasingVec
}

// Properties
PropKeyframeEasingVec :: struct {
  x: Vec3,
  y: Vec3,
}

PropKeyframeEasingScalar :: struct {
  x: f64,
  y: f64,
}

PropScalar :: union {
  PropScalarSingle,
  PropScalarAnim,
}

PROP_SCALAR_SINGLE_FIELDS :: fields(PropScalarSingle) - 1
PropScalarSingle :: struct {
  sid: string,
  a:   bool,
  k:   f64,
  _flags: u64,
}

PROP_SCALAR_KEYFRAME_FIELDS :: fields(PropScalarKeyframe) - 1
PropScalarKeyframe :: struct {
  t: i64,
  h: i64,
  i: PropKeyframeEasingScalar,
  o: PropKeyframeEasingScalar,
  s: f64,
  _flags: u64,
}

PROP_SCALAR_ANIM_FIELDS :: fields(PropScalarAnim) - 1
PropScalarAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropScalarKeyframe,
  _flags: u64,
}

PropBezier :: union {
  PropBezierSingle,
  PropBezierAnim,
}

PropBezierSingle :: struct {
  a: bool,
  k: BezierShapeValue,
  _flags: u64,
}

PropBezierKeyframe :: struct {
  t: u64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: BezierShapeValue,
  _flags: u64,
}

PropBezierAnim :: struct {
  a: bool,
  k: []PropBezierKeyframe,
  _flags: u64,
}


PropColor :: union {
  PropColorSingle,
  PropColorAnim,
}

PropColorSingle :: struct {
  sid: string,
  a:   bool,
  k:   Color4,
  _flags: u64,
}

PropColorKeyframe :: struct {
  t: u64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: Color4,
  _flags: u64,
}

PropColorAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropColorKeyframe,
  _flags: u64,
}

PropGradient :: struct {
  p: u64,
  k: GradientStop
}

GradientStop :: union {
  GradientStopSingle,
  GradientStopAnim,
}

GradientStopSingle :: struct {
  a: bool,
  k: Gradient,
}

GradientKeyframe :: struct {
  t: i64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: Gradient,
  _flags: u64,
  
}

GradientStopAnim :: struct {
  a: bool,
  k: []GradientKeyframe
}

PropVector :: union {
  PropVectorSingle,
  PropVectorAnim,
}


PROP_VECTOR_SINGLE_FIELDS :: fields(PropVectorSingle) - 1
PropVectorSingle :: struct {
  sid: string,
  a:   bool,
  k:   Vec3,
  _flags: u64,
}

PROP_VECTOR_KEYFRAME_FIELDS :: fields(PropVectorKeyframe) - 1
PropVectorKeyframe :: struct {
  t: u64,
  h: i64,
  i: PropKeyframeEasingVec,
  o: PropKeyframeEasingVec,
  s: Vec3,
  _flags: u64,

}

PROP_VECTOR_ANIM_FIELDS :: fields(PropVectorAnim) - 1
PropVectorAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropVectorKeyframe,
  _flags: u64,

}

// 2D version of a Vector property
PropPosition :: union {
  PropPositionSingle,
  PropPositionAnim,
  PropSplitPosition,
}

PropPositionSingle :: PropVectorSingle
PROP_POSITION_KEYFRAME_FIELDS :: fields(PropPositionKeyframe) - 1
PropPositionKeyframe :: struct {
  t:  u64,
  h:  i64,
  i:  PropKeyframeEasingVec,
  o:  PropKeyframeEasingVec,
  s:  Vec3,
  ti: Vec3,
  to: Vec3,
  _flags: u64,
}

PROP_POSITION_ANIM_FIELDS :: fields(PropPositionAnim) - 1
PropPositionAnim :: struct {
  sid: string,
  a:   bool,
  k:   []PropPositionKeyframe,
  _flags: u64,
}

PropSplitPosition :: struct {
  s: bool,
  x: PropScalar,
  y: PropScalar,
  _flags: u64,
}

// Helpers
Transform :: struct {
  a:  PropPosition,
  p:  PropPosition,
  r:  PropScalar,
  s:  PropVector,
  o:  PropScalar,
  sk: PropScalar,
  sa: PropScalar,
  _flags: u64,
}

Layer :: struct {
  nm:     string,
  hd:     bool,
  ty:     i64,
  ind:    i64,
  parent: i64,
  ip:     f64,
  op:     f64,
}

ShapeLayer :: struct {}

ImageLayer :: struct {}

NullLayer :: struct {}

SolidLayer :: struct {}

PrecompLayer :: struct {}

JsonLottie :: struct {
  animation: Animation,
  raw:       []u8,
}

CoreTypes :: enum {
  Null,
  Array,
  Object,
  Float,
  Integer,
  Bool,
  String,
}
