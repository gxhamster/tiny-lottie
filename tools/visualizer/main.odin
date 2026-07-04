package visualizer

import "core:encoding/hex"
import "core:math"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"
import "vendor:raylib"
import rgl "vendor:raylib/rlgl"
import lottie "src:/"

PADDING_X :: 10
PADDING_Y :: 10
LINE_HEIGHT :: 3
DEFAULT_UI_FONT_SIZE :: 75
GLYPH_SPACING :: DEFAULT_UI_FONT_SIZE / 10
HEX_PAIR_SPACING :: 20

BORDER_WIDTH :: 15
BorderWidthZoomLevel :: enum {
  Default = 15, // > 0.3
  Max     = 25, // <= 0.3
}
TextByteView :: struct {
  data:            []u8,
  hex_data_buffer: []u8,
  content_rect:    raylib.Rectangle,
  border_rect:     raylib.Rectangle,
  padding_rect:    raylib.Rectangle,
  wrapping_width:  int, // Specifies how many byte characters (1 byte = 2 hex char) it should fit in one line
  dragging:        bool,
  drag_offset:     raylib.Vector2,
  font:            raylib.Font,
  camera:          ^raylib.Camera2D,
  allocator:       mem.Allocator,
}

Container :: struct {
  // TODO: Change this to a union of types
  children:     [dynamic]TextByteView,
  content_rect: raylib.Rectangle,
  border_rect:  raylib.Rectangle,
  padding_rect: raylib.Rectangle,
  dragging:     bool,
  drag_offset:  raylib.Vector2,
}

container_view_update :: proc(container: ^Container) {

}

SPACE_BETWEEN_BITS :: 50
FlagView :: struct {
  content_rect: raylib.Rectangle,
  border_rect:  raylib.Rectangle,
  padding_rect: raylib.Rectangle,
  flag_bits: int,
  flags: lottie.Bit64,
  font: raylib.Font,
  camera: raylib.Camera2D,
}

flag_view_init :: proc(view: ^FlagView) {

}

flag_view_update :: proc(view: ^FlagView) {
  // Measure content_rect
  total_content_rect_size : raylib.Vector2
  for bit, idx in 0 ..< view.flag_bits {
    bit_val : cstring = "0"
    if bit in view.flags {
      bit_val = "1"
    }
    glyph_size := raylib.MeasureTextEx(view.font, bit_val, DEFAULT_UI_FONT_SIZE, 0)
    if idx == view.flag_bits - 1 {
      total_content_rect_size.x += glyph_size.x
    } else {
      total_content_rect_size.x += glyph_size.x + SPACE_BETWEEN_BITS
    }
    total_content_rect_size.y = glyph_size.y
  }
  view.content_rect.width = total_content_rect_size.x
  view.content_rect.height = total_content_rect_size.y

  view.padding_rect.x = view.content_rect.x - PADDING_X
  view.padding_rect.y = view.content_rect.y - PADDING_Y
  view.padding_rect.width = view.content_rect.width + PADDING_X * 2
  view.padding_rect.height = view.content_rect.height + PADDING_Y * 2

  border_width: BorderWidthZoomLevel = .Default
  if view.camera.zoom <= 0.3 {
    border_width = .Max
  }
  view.border_rect.x = view.content_rect.x - PADDING_X - f32(border_width)
  view.border_rect.y = view.content_rect.y - PADDING_Y - f32(border_width)
  view.border_rect.width = view.content_rect.width + PADDING_X * 2 + f32(border_width) * 2
  view.border_rect.height = view.content_rect.height + PADDING_Y * 2 + f32(border_width) * 2
}

flag_view_draw :: proc(view: ^FlagView) {
  raylib.DrawRectangleRec(view.border_rect, raylib.Color{42, 59, 0, 255})
  raylib.DrawRectangleRec(view.padding_rect, raylib.Color{238, 255, 198, 255})
  raylib.DrawRectangleLines(
    i32(view.content_rect.x),
    i32(view.content_rect.y),
    i32(view.content_rect.width),
    i32(view.content_rect.height),
    raylib.RED,
  )
  pos : raylib.Vector2 = {view.content_rect.x, view.content_rect.y}
  for bit, idx in 0 ..< view.flag_bits {
    bit_val : cstring = "0"
    if bit in view.flags {
      bit_val = "1"
    }
    glyph_size := raylib.MeasureTextEx(view.font, bit_val, DEFAULT_UI_FONT_SIZE, 0)
    raylib.DrawTextEx(view.font, bit_val, pos, DEFAULT_UI_FONT_SIZE, 0, raylib.BLACK)
    pos.x += glyph_size.x + SPACE_BETWEEN_BITS
  }
}  

// The constraint should be actually trying to fit as many glyphs into
// a fixed size rect instead of setting a fixed number of glyphs

byte_view_compute_text_rect :: proc(view: ^TextByteView) -> (rect: raylib.Rectangle) {
  lines_required := int(math.ceil(f64(len(view.hex_data_buffer)) / (f64(view.wrapping_width) * 2.0)))
  max_line_size: raylib.Vector2 = {}
  for line in 0 ..< lines_required {
    cur_line_width := view.wrapping_width * 2
    slice_start_idx := line * cur_line_width
    slice_end_idx := 0
    if line == lines_required - 1 {
      slice_end_idx = len(view.hex_data_buffer)
    } else {
      slice_end_idx = (line + 1) * cur_line_width
    }

    line_hex_buffer := view.hex_data_buffer[slice_start_idx:slice_end_idx]
    line_size: raylib.Vector2 = {}
    for hex_char_idx := 0; hex_char_idx < len(line_hex_buffer); hex_char_idx += 2 {
      idx := (line * cur_line_width) + hex_char_idx
      byte_pair := []u8{view.hex_data_buffer[idx], view.hex_data_buffer[idx + 1]}
      byte_pair_string := strings.clone_from_bytes(byte_pair, context.temp_allocator)
      byte_pair_cstring := strings.clone_to_cstring(byte_pair_string, context.temp_allocator)
      this_pair_len := raylib.MeasureTextEx(view.font, byte_pair_cstring, DEFAULT_UI_FONT_SIZE, GLYPH_SPACING)
      // If last hex pair dont add the HEX_PAIR_SPACING
      if hex_char_idx == len(line_hex_buffer) - 2 {
        line_size.x += this_pair_len.x
      } else {
        line_size.x += this_pair_len.x + HEX_PAIR_SPACING
      }
      line_size.y = this_pair_len.y
      max_line_size.x = max(line_size.x, max_line_size.x)
      max_line_size.y = max(line_size.y, max_line_size.y)

    }
  }

  rect.x = view.content_rect.x
  rect.y = view.content_rect.y
  rect.width = max_line_size.x
  rect.height = max_line_size.y * f32(lines_required)
  return rect
}

byte_view_compute_text_layout :: proc(view: ^TextByteView) {
  // Find largest line in glyph size
  hex_buffer := hex.encode(view.data, view.allocator)
  view.hex_data_buffer = hex_buffer

  text_rect := byte_view_compute_text_rect(view)
  view.content_rect.width = text_rect.width
  view.content_rect.height = text_rect.height
}


byte_view_update :: proc(view: ^TextByteView) {
  mouseWorldPos := raylib.GetScreenToWorld2D(raylib.GetMousePosition(), view.camera^)

  view.padding_rect.x = view.content_rect.x - PADDING_X
  view.padding_rect.y = view.content_rect.y - PADDING_Y
  view.padding_rect.width = view.content_rect.width + PADDING_X * 2
  view.padding_rect.height = view.content_rect.height + PADDING_Y * 2


  border_width: BorderWidthZoomLevel = .Default
  if view.camera.zoom <= 0.3 {
    border_width = .Max
  }
  view.border_rect.x = view.content_rect.x - PADDING_X - f32(border_width)
  view.border_rect.y = view.content_rect.y - PADDING_Y - f32(border_width)
  view.border_rect.width = view.content_rect.width + PADDING_X * 2 + f32(border_width) * 2
  view.border_rect.height = view.content_rect.height + PADDING_Y * 2 + f32(border_width) * 2

  if raylib.CheckCollisionPointRec(mouseWorldPos, view.border_rect) {
    if !raylib.CheckCollisionPointRec(mouseWorldPos, view.padding_rect) {
      // Allow dragging the Rect
      if raylib.IsMouseButtonPressed(raylib.MouseButton.LEFT) && !view.dragging {
        view.dragging = true
        view.drag_offset = {mouseWorldPos.x - view.content_rect.x, mouseWorldPos.y - view.content_rect.y}
        raylib.SetMouseCursor(raylib.MouseCursor.POINTING_HAND)
      }
    }
  }

  if view.dragging {
    view.content_rect.x = mouseWorldPos.x - view.drag_offset.x
    view.content_rect.y = mouseWorldPos.y - view.drag_offset.y

    if raylib.IsMouseButtonReleased(raylib.MouseButton.LEFT) {
      raylib.SetMouseCursor(raylib.MouseCursor.DEFAULT)
      view.dragging = false
    }
  }

  // Check if any of the hex is hovered on


}

byte_view_draw :: proc(view: ^TextByteView) {
  raylib.DrawRectangleRec(view.border_rect, raylib.Color{68, 95, 71, 255})
  raylib.DrawRectangleRec(view.padding_rect, raylib.Color{149, 190, 126, 255})
  raylib.DrawRectangleLines(
    i32(view.content_rect.x),
    i32(view.content_rect.y),
    i32(view.content_rect.width),
    i32(view.content_rect.height),
    raylib.RED,
  )

  // Get all hex values for a line
  lines_required := int(math.ceil(f64(len(view.hex_data_buffer)) / (f64(view.wrapping_width) * 2.0)))
  for line in 0 ..< lines_required {
    cur_line_width := view.wrapping_width * 2
    slice_start_idx := line * cur_line_width
    slice_end_idx := 0
    if line == lines_required - 1 {
      slice_end_idx = len(view.hex_data_buffer)
    } else {
      slice_end_idx = (line + 1) * cur_line_width
    }

    line_hex_buffer := view.hex_data_buffer[slice_start_idx:slice_end_idx]
    pos: raylib.Vector2 = {view.content_rect.x, view.content_rect.y}
    for hex_char_idx := 0; hex_char_idx < len(line_hex_buffer); hex_char_idx += 2 {
      idx := (line * cur_line_width) + hex_char_idx
      byte_pair := []u8{view.hex_data_buffer[idx], view.hex_data_buffer[idx + 1]}
      byte_pair_string := strings.clone_from_bytes(byte_pair, context.temp_allocator)
      byte_pair_cstring := strings.clone_to_cstring(byte_pair_string, context.temp_allocator)
      this_pair_len := raylib.MeasureTextEx(view.font, byte_pair_cstring, DEFAULT_UI_FONT_SIZE, GLYPH_SPACING)

      pos.y = view.content_rect.y + f32(line * DEFAULT_UI_FONT_SIZE)

      raylib.DrawTextEx(view.font, byte_pair_cstring, pos, DEFAULT_UI_FONT_SIZE, GLYPH_SPACING, raylib.BLACK)
      raylib.DrawRectangleLines(i32(pos.x), i32(pos.y), DEFAULT_UI_FONT_SIZE, DEFAULT_UI_FONT_SIZE, raylib.RED)

      pos.x += this_pair_len.x + HEX_PAIR_SPACING
    }
  }
}

main :: proc() {
  arena: vmem.Arena
  arena_allocator := vmem.arena_allocator(&arena)
  screenWidth: i32 = 1280
  screenHeight: i32 = 720
  // raylib.SetTargetFPS(250)
  raylib.SetConfigFlags({raylib.ConfigFlag.VSYNC_HINT})
  raylib.InitWindow(screenWidth, screenHeight, "raylib [core] example - drop files")
  camera := raylib.Camera2D{}
  camera.zoom = 1.0
  zoom_mode := 0

  sample_buffer := make([dynamic]byte, arena_allocator)
  append_elems(&sample_buffer, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
  byte_view := TextByteView{}
  byte_view.content_rect.x = f32(screenWidth) / 2.0
  byte_view.content_rect.y = f32(screenHeight) / 2.0
  byte_view.wrapping_width = 16
  byte_view.data = sample_buffer[:]
  byte_view.camera = &camera
  byte_view.font = raylib.LoadFontEx("fonts/UbuntuMono-R.ttf", DEFAULT_UI_FONT_SIZE, nil, 0)
  byte_view.allocator = arena_allocator
  byte_view_compute_text_layout(&byte_view)

  flag_view := FlagView{}
  flag_view.flag_bits = 3
  flag_view.font = raylib.LoadFontEx("fonts/UbuntuMono-R.ttf", DEFAULT_UI_FONT_SIZE, nil, 0)
  flag_view.flags = {1, 2, 3}
  flag_view.camera = camera

  for !raylib.WindowShouldClose() {
    if (raylib.IsMouseButtonDown(raylib.MouseButton.RIGHT)) {
      delta := raylib.GetMouseDelta()
      delta = delta * -1.0 / camera.zoom
      camera.target = camera.target + delta
    }

    byte_view_update(&byte_view)
    flag_view_update(&flag_view)

    if (zoom_mode == 0) {
      wheel := raylib.GetMouseWheelMove()
      if (wheel != 0) {
        mouseWorldPos := raylib.GetScreenToWorld2D(raylib.GetMousePosition(), camera)
        camera.offset = raylib.GetMousePosition()
        camera.target = mouseWorldPos

        // Uses log scaling to provide consistent zoom speed
        scale := 0.2 * wheel
        camera.zoom += scale
        camera.zoom = raylib.Clamp(camera.zoom, 0.2, 1.0)

        // camera.zoom = raylib.Clamp(math.exp_f32(math.log_f32(camera.zoom, 10) + scale), 0.00001, 5.0)
      }
    }

    if (raylib.IsKeyDown(raylib.KeyboardKey.UP)) {
      last_elem := sample_buffer[len(sample_buffer) - 1]
      append(&sample_buffer, last_elem + 1)
      byte_view.data = sample_buffer[:]
      byte_view_compute_text_layout(&byte_view)
    }

    raylib.BeginDrawing()
    raylib.ClearBackground(raylib.Color{218, 231, 246, 255})
    raylib.BeginMode2D(camera)
    // Draw the 3d grid, rotated 90 degrees and centered around 0,0
    // just so we have something in the XY plane
    rgl.PushMatrix()
    rgl.Translatef(0, 25 * 50, 0)
    rgl.Rotatef(90, 1, 0, 0)
    // raylib.DrawGrid(50, 50)
    rgl.PopMatrix()
    byte_view_draw(&byte_view)
    flag_view_draw(&flag_view)
    raylib.EndMode2D()

    raylib.DrawFPS(20, 20)
    raylib.EndDrawing()
  }
  free_all(context.temp_allocator)
  raylib.CloseWindow()
}
