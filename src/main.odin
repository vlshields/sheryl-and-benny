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
	map_data:      dm.Dot_Map,
	tile_textures: map[u8][dynamic]raylib.Texture2D,
	camera:        raylib.Camera2D,
	players:       [2]Player,
	blaster_tex:   raylib.Texture2D,
	p2_is_ai:      bool,
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

	// Init P1
	gs.players[0] = Player {
		pos          = {spawn_x, spawn_y},
		sprite_sheet = p1_tex,
		frame_count  = 4,
		gamepad_id   = 0,
	}

	// Init P2 - offset slightly from P1
	gs.players[1] = Player {
		pos          = {spawn_x + f32(TILE_SIZE), spawn_y},
		sprite_sheet = p2_tex,
		frame_count  = 2,
		gamepad_id   = 1,
	}

	// P2 AI if no second gamepad
	if !raylib.IsGamepadAvailable(1) {
		gs.players[1].is_ai = true
		gs.p2_is_ai = true
	}

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

		// Update
		get_player_input(&gs.players[0], &gs.players[1], gs.camera)
		get_player_input(&gs.players[1], &gs.players[0], gs.camera)

		move_and_collide(&gs.players[0], &gs.map_data, dt)
		move_and_collide(&gs.players[1], &gs.map_data, dt)

		update_animation(&gs.players[0], dt)
		update_animation(&gs.players[1], dt)

		check_pickup(&gs.players[0], &gs.map_data)
		check_pickup(&gs.players[1], &gs.map_data)

		update_camera(&gs)

		// Draw
		raylib.BeginDrawing()
		raylib.ClearBackground({20, 16, 30, 255})

		raylib.BeginMode2D(gs.camera)
		draw_map(&gs)
		draw_player(&gs.players[0], gs.blaster_tex)
		draw_player(&gs.players[1], gs.blaster_tex)
		raylib.EndMode2D()

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

	dm.destroy_map(&gs.map_data)
}
