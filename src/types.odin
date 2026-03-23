package main

import "core:os"
import "core:encoding/json"
import "base:intrinsics"

fields :: intrinsics.type_struct_field_count

LottieError :: enum {
  None,
  MissingRequiredValue,
  OutofRangeValue,
  UnmarshalErr,
  IncompatibleVectorType,
  IncompatibleVectorInnerType,
  IncompatibleObjectType,
  IncompatibleScalarType,
  IncompatibleIntegerType,
  IncompatibleArrayType,
  IncompatibleNumberType,
  IncompatibleBooleanType,
  IncompatibleEnumType,
  IncompatibleStringType,
  IncompatiblePositionType,
  IncompatiblePropScalarType,
  IncompatibleTransformType,
  TooLargeVector,
  TooSmallVector,
  UnmarshalUnknownValue_Type,
  UnmarshalUnknownArrayType,
  UnmarshalUnsupportedArrayType,
  UnmarshalUnknownObjectType,
  UnmarshalUnknownArrayInnerType,
  UnmarshalUnknownStructFieldType,
  UnmarshalUnknownUnionFieldType,
  UnmarshalOutOfBoundEnumValue,
  UnmarshalAllocationError,
  UnmarshalDeallocationError,
}

Error :: union {
  os.Error,
  LottieError,
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

// note(iyaan): The structs that are defined here, are in
// a way that allows easy unmarshalling of from their JSON
// counterparts. They are in no way the final encoded data
// layout and can undergo various transformations and will be
// very different from the layout defined here.

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
MATTE_MODE_BITS :: 3
MatteMode :: enum {
  Normal,
  Alpha,
  InvertedAlpha,
  Luma,
  InvertedLuma,
}

KEYFRAME_EASING_UNION_TAG_SIZE :: size_of(intrinsics.type_union_tag_type(PropKeyframeEasing))
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

SCALAR_TAG_SIZE :: size_of(intrinsics.type_union_tag_type(PropScalar))
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
  i: PropKeyframeEasing,
  o: PropKeyframeEasing,
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

PROP_BEZIER_SINGLE_FIELDS :: fields(PropBezierSingle) - 1
PropBezierSingle :: struct {
  a: bool,
  k: BezierShapeValue,
  _flags: u64,
}

PROP_BEZIER_KEYFRAME_FIELDS :: fields(PropBezierKeyframe) - 1
PropBezierKeyframe :: struct {
  t: u64,
  h: i64,
  i: PropKeyframeEasing,
  o: PropKeyframeEasing,
  s: []BezierShapeValue,
  _flags: u64,
}

PROP_BEZIER_ANIM_FIELDS :: fields(PropBezierAnim) - 1
PropBezierAnim :: struct {
  a: bool,
  k: []PropBezierKeyframe,
  _flags: u64,
}

COLOR_UNION_TAG_SIZE :: size_of(intrinsics.type_union_tag_type(PropColor))
PropColor :: union {
  PropColorSingle,
  PropColorAnim,
}

PROP_COLOR_SINGLE_FIELDS :: fields(PropColorSingle) - 1
PropColorSingle :: struct {
  sid: string,
  a:   bool,
  k:   Color4,
  _flags: u64,
}

PROP_COLOR_KEYFRAME_FIELDS :: fields(PropColorKeyframe) - 1
PropColorKeyframe :: struct {
  t: u64,
  h: i64,
  i: PropKeyframeEasing,
  o: PropKeyframeEasing,
  s: Color4,
  _flags: u64,
}

PROP_COLOR_ANIM_FIELDS :: fields(PropColorAnim) - 1
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

PROP_GRADIENT_KEYFRAME_FIELDS :: fields(GradientKeyframe) - 1
GradientKeyframe :: struct {
  t: i64,
  h: i64,
  i: PropKeyframeEasing,
  o: PropKeyframeEasing,
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
  i: PropKeyframeEasing,
  o: PropKeyframeEasing,
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
  i:  PropKeyframeEasing,
  o:  PropKeyframeEasing,
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

PROP_SPLIT_POSITION_FIELDS :: fields(PropSplitPosition) - 1
PropSplitPosition :: struct {
  s: bool,
  x: PropScalar,
  y: PropScalar,
  _flags: u64,
}

// Helpers
TRANSFORM_FIELDS :: fields(Transform) - 1
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

// Shapes
SHAPE_DIR_ENUM_BITS :: 2
ShapeDirection :: enum {
  Normal = 1,
  Reversed = 3,
}

Ellipse :: struct {
  nm: string,
  hd: bool,
  ty: string,
  d: ShapeDirection,
  p: PropPosition,
  s: PropVector,
  _flags: u64,
}

Rectangle :: struct {
  nm: string,
  hd: bool,
  ty: string,
  d: ShapeDirection,
  p: PropPosition,
  s: PropVector,
  r: PropScalar,
  _flags: u64,
}

PATH_FIELDS :: fields(Path) - 1
Path :: struct {
  nm: string,
  hd: bool,
  ty: string,
  d: ShapeDirection,
  ks: PropBezier,
  _flags: u64,
}

STAR_TYPE_BITS :: 2
StarType :: enum {
  Star  = 1,
  Polygon = 2
}

Polystar :: struct {
  nm: string,
  hd: bool,
  ty: string,
  d:  ShapeDirection,
  p:  PropPosition,
  or: PropScalar,
  os: PropScalar,
  r:  PropScalar,
  pt: PropScalar,
  sy: StarType,
  ir: PropScalar,
  is: PropScalar,
  _flags: u64,
}

// Grouping

GROUP_FIELDS :: fields(Group) - 1
Group :: struct {
  nm: string,
  hd: bool,
  ty: string,
  np: i64,
  it: []GraphicElement,
  _flags: u64,
}

TRANSFORM_SHAPE_FIELDS :: fields(TransformShape) - 1
TransformShape :: struct {
  nm: string,
  hd: bool,
  ty: string,
  a:  PropPosition,
  p:  PropPosition,
  r:  PropScalar,
  s:  PropVector,
  o:  PropScalar,
  sk: PropScalar,
  sa: PropScalar,
  _flags: u64,
}

// Style

FILL_RULE_BITS :: 2
FillRule :: enum {
  NonZero = 1,
  EvenOdd = 2
}

FILL_FIELDS :: fields(Fill) - 1
Fill :: struct {
  nm: string,
  hd: bool,
  ty: string,
  o: PropScalar,
  c: PropColor,
  r: FillRule,
  _flags: u64,
}

LINE_CAP_BITS :: 2
LineCap :: enum {
  Butt = 1,
  Round = 2,
  Square = 3
}

LINE_JOIN_BITS :: 2
LineJoin :: enum {
  Miter = 1,
  Round = 2,
  Bevel = 3
}

STROKE_DASH_TYPE_BITS :: 2
StrokeDashType :: enum {
  Dash = 'd',
  Gap = 'g',
  Offset = 'o'
}

STROKE_DASH_FIELDS :: fields(StrokeDash) - 1
StrokeDash :: struct {
  nm: string,
  n: StrokeDashType,
  v: PropScalar,
  _flags: u64,
}

STROKE_FIELDS :: fields(Stroke) - 1
Stroke :: struct {
  nm: string,
  hd: bool,
  ty: string,
  o: PropScalar,
  lc: LineCap,
  lj: LineJoin,
  ml: i64,
  ml2: PropScalar,
  w: PropScalar,
  d: []StrokeDash,
  c: PropColor,
  _flags: u64,
}

GRADIENT_TYPE_BITS :: 2
GradientType :: enum {
  Linear = 1,
  Radial = 2
}

GRADIENT_FILL_FIELDS :: fields(GradientFill) - 1
GradientFill :: struct {
  nm: string,
  hd: bool,
  ty: string,
  o: PropScalar,
  g: PropGradient,
  s: PropPosition,
  e: PropPosition,
  t: GradientType,
  h: PropScalar,
  a: PropScalar,
  r: FillRule,
  _flags: u64,
}

GRADIENT_STROKE_FIELDS :: fields(GradientStroke) - 1
GradientStroke :: struct {
  nm: string,
  hd: bool,
  ty: string,
  o: PropScalar,
  lc: LineCap,
  lj: LineJoin,
  ml: i64,
  ml2: PropScalar,
  w: PropScalar,
  d: []StrokeDash,
  g: PropGradient,
  s: PropPosition,
  e: PropPosition,
  t: GradientType,
  h: PropScalar,
  a: PropScalar,
  _flags: u64,
}

// Modifiers

TRIM_MULTIPLE_SHAPES_BITS :: 2
TrimMultipleShapes :: enum {
  Parallel = 1,
  Sequential = 2
}

TRIM_PATH_FIELDS :: fields(TrimPath) - 1
TrimPath :: struct {
  nm: string,
  hd: bool,
  ty: string,
  s: PropScalar,
  e: PropScalar,
  o: PropScalar,
  m: TrimMultipleShapes,
  _flags: u64,
}

GRAPHIC_ELEM_TYPE_BITS :: 4
GraphicElemType :: enum {
  el = 0,  // Ellipse
  fl = 1,  // Fill
  gf = 2,  // Gradient Fill
  gs = 3,  // Gradient Stroke
  gr = 4,  // Group
  sh = 5,  // Path
  sr = 6,  // PolyStar
  rc = 7,  // Rectangle
  st = 8,  // Stroke
  tr = 9,  // Transform Shape
  tm = 10, // Trim Path
  Error = -1
}

GraphicElement :: union {
  Ellipse,
  Rectangle,
  Path,
  Polystar,
  Group,
  TransformShape,
  Fill,
  Stroke,
  GradientFill,
  GradientStroke,
  TrimPath
}

LAYER_TYPE_BITS :: 3
LayerType :: enum {
  PrecompLayer = 0,
  ImageLayer   = 2,
  NullLayer    = 3,
  SoildLayer   = 1,
  ShapeLayer   = 4,
}

MASK_MODE_BITS :: 2
MaskMode :: enum {
  None      = 'n',
  Add       = 'a',
  Subtract  = 's',
  Intersect = 'i'
}

MASK_FIELDS :: fields(Mask) - 1 
Mask :: struct {
  mode: MaskMode,
  o: PropScalar,
  pt: PropBezier,
  _flags: u64
}

SHAPE_LAYER_FIELDS :: fields(ShapeLayer) - 1
ShapeLayer :: struct {
  nm: string,
  hd: bool,
  ty: LayerType,
  ind: i64,
  parent: i64,
  ip: i64,
  op: i64,
  ks: Transform,
  ao: i64,
  tt: MatteMode,
  tp: i64,
  masksProperties: []Mask,
  shapes: []GraphicElement,
  _flags: u64
}

IMAGE_LAYER_FIELDS :: fields(ImageLayer) - 1
ImageLayer :: struct {
  nm: string,
  hd: bool,
  ty: LayerType,
  ind: i64,
  parent: i64,
  ip: i64,
  op: i64,
  ks: Transform,
  ao: i64,
  tt: MatteMode,
  tp: i64,
  masksProperties: []Mask,
  refId: string,
  _flags: u64
}

NULL_LAYER_FIELDS :: fields(NullLayer) - 1
NullLayer :: struct {
  nm: string,
  hd: bool,
  ty: LayerType,
  ind: i64,
  parent: i64,
  ip: i64,
  op: i64,
  ks: Transform,
  ao: i64,
  tt: MatteMode,
  tp: i64,
  masksProperties: []Mask,
  _flags: u64
}

SOLID_LAYER_FIELDS :: fields(PrecompLayer) - 1
SolidLayer :: struct {
  nm: string,
  hd: bool,
  ty: LayerType,
  ind: i64,
  parent: i64,
  ip: i64,
  op: i64,
  ks: Transform,
  ao: i64,
  tt: MatteMode,
  tp: i64,
  masksProperties: []Mask,
  sw: i64,
  sh: i64,
  sc: HexColor,
  _flags: u64,
}

PRECOMP_LAYER_FIELDS :: fields(PrecompLayer) - 1
PrecompLayer :: struct {
  nm: string,
  hd: bool,
  ty: LayerType,
  ind: i64,
  parent: i64,
  ip: i64,
  op: i64,
  ks: Transform,
  ao: i64,
  tt: MatteMode,
  tp: i64,
  masksProperties: []Mask,
  refId: string,
  w: i64,
  h: i64,
  sr: i64,
  st: i64,
  tm: PropScalar,
  _flags: u64
}

JsonLottie :: struct {
  animation: Animation,
  raw:       []u8,
}