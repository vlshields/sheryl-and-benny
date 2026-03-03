package sheryl_and_benny

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:math/rand"
import "core:strings"

SCREEN_WIDTH  :: 640
SCREEN_HEIGHT :: 360
TILE_SIZE     :: 16
TARGET_FPS    :: 60
CAMERA_ZOOM   :: 3.0

Game_State :: struct {
	map_data:            dm.Dot_Map,
	tile_textures:       map[u8][dynamic]raylib.Texture2D,
	camera:              raylib.Camera2D,
	players:             [2]Player,
	blaster_tex:         raylib.Texture2D,
	p2_is_ai:            bool,
	projectiles:         [MAX_PROJECTILES]Projectile,
	particles:           [MAX_PARTICLES]Particle,
	enemies:             [MAX_ENEMIES]Enemy,
	slug_move_tex:       raylib.Texture2D,
	slug_dead_tex:       raylib.Texture2D,
	game_over:           bool,
	game_over_selection: i32,
	font:                raylib.Font,
	spawn_pos:           raylib.Vector2,
}

main :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ACJAM")
	defer raylib.CloseWindow()
	raylib.SetTargetFPS(TARGET_FPS)

	gs: Game_State

	// Parse map
	map_data, map_ok := dm.parse_map_file("assets/maps/home_base.map")
	if !map_ok {
		fmt.eprintln("Failed to load map!")
		return
	}
	gs.map_data = map_data

	// Load tile textures
	gs.tile_textures = make(map[u8][dynamic]raylib.Texture2D)
	for sym, td in gs.map_data.metadata {
		textures: [dynamic]raylib.Texture2D
		for path in td.tiles {
			cpath := strings.clone_to_cstring(path)
			defer delete(cpath)
			tex := raylib.LoadTexture(cpath)
			if tex.id > 0 {
				append(&textures, tex)
			} else {
				fmt.eprintln("Failed to load texture:", path)
			}
		}
		gs.tile_textures[sym] = textures
	}

	// Assign random tile variants for 'w' cells
	if w_texs, ok := gs.tile_textures['w']; ok {
		num_variants := len(w_texs)
		if num_variants > 1 {
			for &row in gs.map_data.grid {
				for &cell in row {
					if cell.symbol == 'w' {
						cell.tile_index = rand.int_max(num_variants)
					}
				}
			}
		}
	}

	// Load player sprites
	p1_tex := raylib.LoadTexture("assets/sprites/player_one_move.png")
	p2_tex := raylib.LoadTexture("assets/sprites/player_two_move.png")
	gs.blaster_tex = raylib.LoadTexture("assets/sprites/blaster.png")

	// Load enemy sprites
	gs.slug_move_tex = raylib.LoadTexture("assets/sprites/enemy_slug_move.png")
	gs.slug_dead_tex = raylib.LoadTexture("assets/sprites/enemy_slug_dead.png")

	// Load font
	gs.font = raylib.LoadFontEx("assets/Romulus.ttf", 48, nil, 0)
	raylib.SetTextureFilter(gs.font.texture, .POINT)

	// Find spawn points ('p' tiles)
	spawn_x: f32 = 0
	spawn_y: f32 = 0
	spawn_found := false
	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'p' && !spawn_found {
				spawn_x = f32(x * TILE_SIZE)
				spawn_y = f32(y * TILE_SIZE)
				spawn_found = true
				break
			}
		}
		if spawn_found {
			break
		}
	}

	gs.spawn_pos = {spawn_x, spawn_y}

	// Init P1
	gs.players[0] = Player {
		pos          = {spawn_x, spawn_y},
		sprite_sheet = p1_tex,
		frame_count  = 4,
		gamepad_id   = 0,
		hp           = PLAYER_HP,
	}

	// Init P2 - offset slightly from P1
	gs.players[1] = Player {
		pos          = {spawn_x + f32(TILE_SIZE), spawn_y},
		sprite_sheet = p2_tex,
		frame_count  = 2,
		gamepad_id   = 1,
		hp           = PLAYER_HP,
	}

	// P2 AI if no second gamepad
	if !raylib.IsGamepadAvailable(1) {
		gs.players[1].is_ai = true
		gs.p2_is_ai = true
	}

	// Init enemies
	init_enemies(&gs)

	// Init camera
	update_camera(&gs)

	// Game loop
	for !raylib.WindowShouldClose() {
		dt := raylib.GetFrameTime()

		// Check if P2 gamepad connected mid-game
		if gs.p2_is_ai && raylib.IsGamepadAvailable(1) {
			gs.players[1].is_ai = false
			gs.p2_is_ai = false
		}

		if !gs.game_over {
			// Update
			get_player_input(&gs.players[0], &gs.players[1], &gs)
			get_player_input(&gs.players[1], &gs.players[0], &gs)

			// Decrement fire and invincibility cooldowns
			for &p in gs.players {
				if p.fire_cooldown > 0 {
					p.fire_cooldown -= dt
				}
				if p.invincibility_timer > 0 {
					p.invincibility_timer -= dt
				}
			}

			move_and_collide(&gs.players[0], &gs.map_data, dt)
			move_and_collide(&gs.players[1], &gs.map_data, dt)

			update_projectiles(&gs.projectiles, &gs.particles, &gs.map_data, dt)
			update_particles(&gs.particles, dt)

			update_enemies(&gs, dt)
			check_enemy_player_collision(&gs)
			check_projectile_enemy_collision(&gs)

			update_animation(&gs.players[0], dt)
			update_animation(&gs.players[1], dt)

			check_pickup(&gs.players[0], &gs.map_data)
			check_pickup(&gs.players[1], &gs.map_data)

			// Check game over
			for &p in gs.players {
				if p.hp <= 0 {
					gs.game_over = true
				}
			}

			update_camera(&gs)
		} else {
			action := handle_game_over_input(&gs)
			if action == 1 {
				reset_game(&gs)
			} else if action == 2 {
				break
			}
		}

		// Draw
		raylib.BeginDrawing()
		raylib.ClearBackground({20, 16, 30, 255})

		raylib.BeginMode2D(gs.camera)
		draw_map(&gs)
		draw_enemies(&gs)
		draw_particles(&gs.particles)
		draw_player(&gs.players[0], gs.blaster_tex)
		draw_player(&gs.players[1], gs.blaster_tex)
		draw_projectiles(&gs.projectiles)
		raylib.EndMode2D()

		if gs.game_over {
			draw_game_over(&gs)
		}

		raylib.EndDrawing()
	}

	// Cleanup
	for _, &textures in gs.tile_textures {
		for &tex in textures {
			raylib.UnloadTexture(tex)
		}
		delete(textures)
	}
	delete(gs.tile_textures)

	raylib.UnloadTexture(p1_tex)
	raylib.UnloadTexture(p2_tex)
	raylib.UnloadTexture(gs.blaster_tex)
	raylib.UnloadTexture(gs.slug_move_tex)
	raylib.UnloadTexture(gs.slug_dead_tex)
	raylib.UnloadFont(gs.font)

	dm.destroy_map(&gs.map_data)
}

// Returns 0=none, 1=restart, 2=quit
handle_game_over_input :: proc(gs: ^Game_State) -> i32 {
	// Keyboard navigation
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.game_over_selection = 1 - gs.game_over_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	// Gamepad
	for gp_idx in 0 ..< 2 {
		gp := i32(gp_idx)
		if !raylib.IsGamepadAvailable(gp) {
			continue
		}
		if raylib.IsGamepadButtonPressed(gp, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(gp, .LEFT_FACE_UP) {
			gs.game_over_selection = 1 - gs.game_over_selection
		}
		if raylib.IsGamepadButtonPressed(gp, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		return gs.game_over_selection == 0 ? 1 : 2
	}
	return 0
}

draw_game_over :: proc(gs: ^Game_State) {
	// Dark overlay
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, {0, 0, 0, 150})

	// Panel
	PANEL_W :: 220
	PANEL_H :: 130
	PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
	PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

	raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
	raylib.DrawRectangleLinesEx(
		{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
		2,
		{200, 180, 220, 255},
	)

	// Title
	title_size: f32 = 32
	title_w := raylib.MeasureTextEx(gs.font, "GAME OVER", title_size, 1).x
	title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
	title_y := f32(PANEL_Y) + 15
	raylib.DrawTextEx(gs.font, "GAME OVER", {title_x, title_y}, title_size, 1, {220, 50, 50, 255})

	// Menu options
	option_size: f32 = 20

	// Restart
	restart_w := raylib.MeasureTextEx(gs.font, "RESTART", option_size, 1).x
	restart_x := f32(PANEL_X) + (f32(PANEL_W) - restart_w) / 2
	restart_y := f32(PANEL_Y) + 65
	restart_color: raylib.Color = gs.game_over_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
	if gs.game_over_selection == 0 {
		raylib.DrawTextEx(gs.font, ">", {restart_x - 18, restart_y}, option_size, 1, restart_color)
	}
	raylib.DrawTextEx(gs.font, "RESTART", {restart_x, restart_y}, option_size, 1, restart_color)

	// Quit
	quit_w := raylib.MeasureTextEx(gs.font, "QUIT", option_size, 1).x
	quit_x := f32(PANEL_X) + (f32(PANEL_W) - quit_w) / 2
	quit_y := f32(PANEL_Y) + 95
	quit_color: raylib.Color = gs.game_over_selection == 0 ? {180, 180, 180, 255} : {255, 220, 50, 255}
	if gs.game_over_selection == 1 {
		raylib.DrawTextEx(gs.font, ">", {quit_x - 18, quit_y}, option_size, 1, quit_color)
	}
	raylib.DrawTextEx(gs.font, "QUIT", {quit_x, quit_y}, option_size, 1, quit_color)
}

reset_game :: proc(gs: ^Game_State) {
	// Reset players — preserve identity fields (sprite_sheet, frame_count, gamepad_id, is_ai)
	for i in 0 ..< 2 {
		gs.players[i].pos = i == 0 ? gs.spawn_pos : gs.spawn_pos + {f32(TILE_SIZE), 0}
		gs.players[i].aim_dir = {0, 0}
		gs.players[i].move_dir = {0, 0}
		gs.players[i].current_frame = 0
		gs.players[i].anim_timer = 0
		gs.players[i].facing_left = false
		gs.players[i].weapon = .None
		gs.players[i].blaster_angle = 0
		gs.players[i].fire_cooldown = 0
		gs.players[i].hp = PLAYER_HP
		gs.players[i].invincibility_timer = 0
		gs.players[i].knockback_vel = {0, 0}
	}

	// Clear projectiles and particles
	for &proj in gs.projectiles {
		proj.active = false
	}
	for &part in gs.particles {
		part.active = false
	}

	// Reset map collected state
	for &row in gs.map_data.grid {
		for &cell in row {
			cell.collected = false
		}
	}

	// Re-init enemies
	for &enemy in gs.enemies {
		enemy = {}
	}
	init_enemies(gs)

	gs.game_over = false
	gs.game_over_selection = 0
	update_camera(gs)
}
