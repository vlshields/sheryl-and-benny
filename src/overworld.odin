package sheryl_and_benny

import "vendor:raylib"



draw_map :: proc(gs: ^Game_State) {
	map_data := &gs.map_data
	cam := gs.camera

	// Calculate visible tile range based on camera
	left := int(cam.target.x - cam.offset.x / cam.zoom) / TILE_SIZE - 1
	right := int(cam.target.x + cam.offset.x / cam.zoom) / TILE_SIZE + 2
	top := int(cam.target.y - cam.offset.y / cam.zoom) / TILE_SIZE - 1
	bottom := int(cam.target.y + cam.offset.y / cam.zoom) / TILE_SIZE + 2

	if left < 0 {
		left = 0
	}
	if top < 0 {
		top = 0
	}
	if bottom > map_data.height {
		bottom = map_data.height
	}

	// Get floor textures for drawing under spawn points and collected tiles
	floor_textures: ^[dynamic]raylib.Texture2D
	if texs, ok := &gs.tile_textures['w']; ok {
		floor_textures = texs
	}

	for y in top ..< bottom {
		row := map_data.grid[y]
		row_right := right < len(row) ? right : len(row)
		for x in left ..< row_right {
			cell := row[x]
			sym := cell.symbol

			// Spawn points and enemy spawns: draw floor tile instead
			if sym == 'p' || sym == 'e' || sym == 'f' {
				if floor_textures != nil && len(floor_textures) > 0 {
					raylib.DrawTexture(floor_textures[0], i32(x * TILE_SIZE), i32(y * TILE_SIZE), raylib.WHITE)
				}
				continue
			}

			// Collected tiles: draw floor instead
			if cell.collected {
				if floor_textures != nil && len(floor_textures) > 0 {
					raylib.DrawTexture(floor_textures[0], i32(x * TILE_SIZE), i32(y * TILE_SIZE), raylib.WHITE)
				}
				continue
			}

			// Draw the actual tile
			if texs, ok := &gs.tile_textures[sym]; ok {
				if len(texs) > 0 {
					idx := cell.tile_index % len(texs)
					raylib.DrawTexture(texs[idx], i32(x * TILE_SIZE), i32(y * TILE_SIZE), raylib.WHITE)
				}
			} else {
				// Fallback: draw a colored rect for unknown tiles
				raylib.DrawRectangle(i32(f32(x * TILE_SIZE)), i32(f32(y * TILE_SIZE)), TILE_SIZE, TILE_SIZE, raylib.MAGENTA)
			}
		}
	}
}

update_camera :: proc(gs: ^Game_State) {
	map_height_px := f32(gs.map_data.height * TILE_SIZE)
	map_width_px := f32(gs.map_data.width * TILE_SIZE)

	gs.camera.zoom = CAMERA_ZOOM
	gs.camera.offset = {f32(SCREEN_WIDTH) / 2, f32(SCREEN_HEIGHT) / 2}

	// Visible half-extents in world space
	half_view_w := f32(SCREEN_WIDTH) / (2 * CAMERA_ZOOM)
	half_view_h := f32(SCREEN_HEIGHT) / (2 * CAMERA_ZOOM)

	// Follow P1
	target_x := gs.players[0].pos.x + f32(SPRITE_DST_SIZE) / 2
	target_y := gs.players[0].pos.y + f32(SPRITE_DST_SIZE) / 2

	// Clamp to map edges
	if target_x < half_view_w {
		target_x = half_view_w
	}
	if target_x > map_width_px - half_view_w {
		target_x = map_width_px - half_view_w
	}
	if target_y < half_view_h {
		target_y = half_view_h
	}
	if target_y > map_height_px - half_view_h {
		target_y = map_height_px - half_view_h
	}

	gs.camera.target = {target_x, target_y}
}
