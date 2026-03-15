package sheryl_and_benny

import "vendor:raylib"

// Layout constants
MENU_FLOOR_Y        :: 300   // Y position of the top of the floor platform
MENU_FLOOR_TILES    :: 5     // Number of floor tile rows
MENU_TITLE_TARGET   :: 40.0  // Final Y for the title
MENU_OPTIONS_TARGET :: 420.0 // Final X for menu options
MENU_SLIDE_SPEED    :: 200.0 // Pixels/sec for slide-in animations

// Background layer height (each layer is 640x360 in the spritesheet)
MENU_BG_LAYER_W :: 640
MENU_BG_LAYER_H :: 360

// Character positions on the platform
MENU_SHERYL_X :: 260.0
MENU_BENNY_X  :: 340.0
MENU_CHAR_Y   :: 300.0 // Bottom of sprite (sits on floor)

// Returns 0=none, 1=play, 2=quit
update_main_menu :: proc(gs: ^Game_State) -> i32 {
	dt := raylib.GetFrameTime()

	// Scroll parallax layers: [0]=bg color (static), [1]=clouds, [2]=mountains (closest)
	parallax_speeds := [3]f32{0, 10, 25}
	for i := 0; i < 3; i += 1 {
		gs.menu_scroll_offsets[i] -= parallax_speeds[i] * dt
		if gs.menu_scroll_offsets[i] <= -f32(MENU_BG_LAYER_W) {
			gs.menu_scroll_offsets[i] += f32(MENU_BG_LAYER_W)
		}
	}

	// Animate character sprites
	gs.menu_sprite_timer += dt
	if gs.menu_sprite_timer >= ANIM_FRAME_TIME {
		gs.menu_sprite_timer -= ANIM_FRAME_TIME
		gs.menu_sheryl_frame = (gs.menu_sheryl_frame + 1) % 3
		gs.menu_benny_frame = (gs.menu_benny_frame + 1) % 4
	}

	// Slide title down from top
	if gs.menu_title_y < MENU_TITLE_TARGET {
		gs.menu_title_y += MENU_SLIDE_SPEED * dt
		if gs.menu_title_y > MENU_TITLE_TARGET {
			gs.menu_title_y = MENU_TITLE_TARGET
		}
	}

	// Slide options in from right
	if gs.menu_options_x > MENU_OPTIONS_TARGET {
		gs.menu_options_x -= MENU_SLIDE_SPEED * dt
		if gs.menu_options_x < MENU_OPTIONS_TARGET {
			gs.menu_options_x = MENU_OPTIONS_TARGET
		}
	}

	// Menu input
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.menu_main_selection = 1 - gs.menu_main_selection
	}

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			gs.menu_main_selection = 1 - gs.menu_main_selection
		}
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
	if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
		confirmed = true
	}

	if confirmed {
		if gs.menu_main_selection == 0 {
			return 1 // Play
		} else {
			return 2 // Quit
		}
	}
	return 0
}

draw_main_menu :: proc(gs: ^Game_State) {
	tex := gs.menu_bg_tex
	if tex.id > 0 {
		// Draw 3 layers from the stacked spritesheet (top=bg, middle=clouds, bottom=mountains)
		for i := 0; i < 3; i += 1 {
			src := raylib.Rectangle {
				x      = 0,
				y      = f32(i * MENU_BG_LAYER_H),
				width  = f32(MENU_BG_LAYER_W),
				height = f32(MENU_BG_LAYER_H),
			}
			dst := raylib.Rectangle {
				x      = gs.menu_scroll_offsets[i],
				y      = 0,
				width  = f32(SCREEN_WIDTH),
				height = f32(SCREEN_HEIGHT),
			}
			raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)

			// Second copy for seamless horizontal scrolling
			dst.x += f32(SCREEN_WIDTH)
			raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
		}
	}

	// Draw floor platform
	{
		floor_tex := gs.menu_floor_tex
		if floor_tex.id > 0 {
			tiles_across := SCREEN_WIDTH / TILE_SIZE + 1
			for row := 0; row < MENU_FLOOR_TILES; row += 1 {
				for col := 0; col < tiles_across; col += 1 {
					raylib.DrawTexture(
						floor_tex,
						i32(col * TILE_SIZE),
						i32(MENU_FLOOR_Y + row * TILE_SIZE),
						raylib.WHITE,
					)
				}
			}
		}
	}

	// Draw Sheryl (facing right, running) — 2x scale
	{
		menu_sprite :: SPRITE_DST_SIZE * 2
		src := raylib.Rectangle {
			x      = f32(gs.menu_sheryl_frame * SPRITE_SRC_SIZE),
			y      = 0,
			width  = f32(SPRITE_SRC_SIZE),
			height = f32(SPRITE_SRC_SIZE),
		}
		dst := raylib.Rectangle {
			x      = MENU_SHERYL_X,
			y      = MENU_CHAR_Y,
			width  = f32(menu_sprite),
			height = f32(menu_sprite),
		}
		origin := raylib.Vector2{f32(menu_sprite) / 2, f32(menu_sprite)}
		raylib.DrawTexturePro(gs.sheryl_move_tex, src, dst, origin, 0, raylib.WHITE)
	}

	// Draw Benny (facing right, running) — 2x scale
	{
		menu_sprite :: SPRITE_DST_SIZE * 2
		src := raylib.Rectangle {
			x      = f32(gs.menu_benny_frame * SPRITE_SRC_SIZE),
			y      = 0,
			width  = f32(SPRITE_SRC_SIZE),
			height = f32(SPRITE_SRC_SIZE),
		}
		dst := raylib.Rectangle {
			x      = MENU_BENNY_X,
			y      = MENU_CHAR_Y,
			width  = f32(menu_sprite),
			height = f32(menu_sprite),
		}
		origin := raylib.Vector2{f32(menu_sprite) / 2, f32(menu_sprite)}
		raylib.DrawTexturePro(gs.benny_move_tex, src, dst, origin, 0, raylib.WHITE)
	}

	// Draw title "Sheryl and Benny" sliding in from top
	{
		title_size: f32 = 32
		title_text: cstring = "Sheryl and Benny"
		title_w := raylib.MeasureTextEx(gs.font, title_text, title_size, 1).x
		title_x := (f32(SCREEN_WIDTH) - title_w) / 2
		raylib.DrawTextEx(gs.font, title_text, {title_x, gs.menu_title_y}, title_size, 1, {255, 220, 50, 255})
	}

	// Draw menu options sliding in from right
	{
		option_size: f32 = 22
		options := [2]cstring{"PLAY", "QUIT"}
		for i: i32 = 0; i < 2; i += 1 {
			y: f32 = 200 + f32(i) * 35
			color: raylib.Color = gs.menu_main_selection == i ? {255, 220, 50, 255} : {180, 180, 180, 255}
			if gs.menu_main_selection == i {
				raylib.DrawTextEx(gs.font, ">", {gs.menu_options_x - 18, y}, option_size, 1, color)
			}
			raylib.DrawTextEx(gs.font, options[i], {gs.menu_options_x, y}, option_size, 1, color)
		}
	}
}
