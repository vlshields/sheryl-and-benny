package sheryl_and_benny

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"

SCREEN_WIDTH      :: 640
SCREEN_HEIGHT     :: 360
TILE_SIZE         :: 16
TARGET_FPS        :: 60
CAMERA_ZOOM       :: 3.0
MAX_DAMAGE_TEXTS  :: 8
MAX_HEALTH_CRATES :: 8
HEALTH_CRATE_HEAL :: 15
DAMAGE_TEXT_SPEED      :: 20.0
DAMAGE_TEXT_TIME       :: 0.8
DOOR_ANIM_FRAME_TIME   :: 0.2

Game_Phase :: enum {
	Character_Select,
	Playing,
}

Damage_Text :: struct {
	active: bool,
	pos:    raylib.Vector2,
	timer:  f32,
	damage: i32,
}

Health_Crate :: struct {
	pos:    raylib.Vector2,
	active: bool,
}

Game_State :: struct {
	map_data:            dm.Dot_Map,
	tile_textures:       map[u8][dynamic]raylib.Texture2D,
	camera:              raylib.Camera2D,
	player:              Player,
	blaster_tex:         raylib.Texture2D,
	slinger_tex:         raylib.Texture2D,
	flamethrower_tex:    raylib.Texture2D,
	flame_particles:     [MAX_FLAME_PARTICLES]Flame_Particle,
	projectiles:         [MAX_PROJECTILES]Projectile,
	particles:           [MAX_PARTICLES]Particle,
	enemies:             [MAX_ENEMIES]Enemy,
	slug_move_tex:       raylib.Texture2D,
	slug_dead_tex:       raylib.Texture2D,
	fly_move_tex:        raylib.Texture2D,
	fly_dead_tex:        raylib.Texture2D,
	bunny_move_tex:      raylib.Texture2D,
	bunny_dead_tex:      raylib.Texture2D,
	enemies_cleared:     bool,
	game_over:           bool,
	game_over_selection: i32,
	font:                raylib.Font,
	spawn_pos:           raylib.Vector2,
	white_flash_shader:  raylib.Shader,
	damage_texts:        [MAX_DAMAGE_TEXTS]Damage_Text,
	health_crates:       [MAX_HEALTH_CRATES]Health_Crate,
	health_crate_tex:    raylib.Texture2D,
	reticle_tex:         raylib.Texture2D,
	ammo_tex:            raylib.Texture2D,
	phase:               Game_Phase,
	menu_selection:      i32,
	door_locked_msg_timer: f32,
	door_unlocked:       bool,
	door_anim_timer:     f32,
	door_anim_frame:     i32,
	benny_move_tex:      raylib.Texture2D,
	benny_idle_tex:      raylib.Texture2D,
	sheryl_move_tex:     raylib.Texture2D,
	sheryl_idle_tex:     raylib.Texture2D,
	boss_move_tex:       raylib.Texture2D,
	arena:               Arena_State,
	boss_victory:        bool,
	boss_victory_selection: i32,
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

	// Load character sprites
	gs.benny_move_tex = raylib.LoadTexture("assets/sprites/player_one_move.png")
	gs.benny_idle_tex = raylib.LoadTexture("assets/sprites/player_one_idle.png")
	gs.sheryl_move_tex = raylib.LoadTexture("assets/sprites/player_two_move.png")
	gs.sheryl_idle_tex = raylib.LoadTexture("assets/sprites/player_two_idle.png")
	gs.blaster_tex = raylib.LoadTexture("assets/sprites/blaster.png")
	gs.slinger_tex = raylib.LoadTexture("assets/sprites/slinger.png")
	gs.flamethrower_tex = raylib.LoadTexture("assets/sprites/flamethrower.png")

	// Load enemy sprites
	gs.slug_move_tex = raylib.LoadTexture("assets/sprites/enemy_slug_move.png")
	gs.slug_dead_tex = raylib.LoadTexture("assets/sprites/enemy_slug_dead.png")
	gs.fly_move_tex = raylib.LoadTexture("assets/sprites/enemy_fly_move.png")
	gs.fly_dead_tex = raylib.LoadTexture("assets/sprites/enemy_fly_dead.png")
	gs.bunny_move_tex = raylib.LoadTexture("assets/sprites/enemy_crazy_bunny_move.png")
	gs.bunny_dead_tex = raylib.LoadTexture("assets/sprites/enemy_crazy_bunny_dead.png")
	gs.boss_move_tex = raylib.LoadTexture("assets/sprites/enemy_boss.png")
	gs.health_crate_tex = raylib.LoadTexture("assets/sprites/health_pickup.png")

	// Load reticle cursor
	gs.reticle_tex = raylib.LoadTexture("assets/sprites/reticle.png")
	gs.ammo_tex = raylib.LoadTexture("assets/sprites/ammo.png")
	raylib.HideCursor()

	// Load font
	gs.font = raylib.LoadFontEx("assets/Romulus.ttf", 48, nil, 0)
	raylib.SetTextureFilter(gs.font.texture, .POINT)

	// Load white flash shader (turns all visible pixels white)
	WHITE_FLASH_FS :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
    vec4 texColor = texture(texture0, fragTexCoord);
    finalColor = vec4(1.0, 1.0, 1.0, texColor.a);
}
`
	gs.white_flash_shader = raylib.LoadShaderFromMemory(nil, WHITE_FLASH_FS)

	// Find spawn point
	spawn_x: f32 = 0
	spawn_y: f32 = 0
	spawn_found := false
	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'p' && !spawn_found {
				spawn_x = f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2
				spawn_y = f32(y * TILE_SIZE) + f32(TILE_SIZE)
				spawn_found = true
				break
			}
		}
		if spawn_found {
			break
		}
	}

	gs.spawn_pos = {spawn_x, spawn_y}

	// Init enemies
	init_enemies(&gs)
	init_arena(&gs)

	// Init camera centered on spawn
	gs.camera.zoom = CAMERA_ZOOM
	gs.camera.offset = {f32(SCREEN_WIDTH) / 2, f32(SCREEN_HEIGHT) / 2}
	gs.camera.target = {gs.spawn_pos.x, gs.spawn_pos.y - f32(SPRITE_DST_SIZE) / 2}

	// Game loop
	game_loop: for !raylib.WindowShouldClose() {
		dt := raylib.GetFrameTime()

		switch gs.phase {
		case .Character_Select:
			handle_menu_input(&gs)

		case .Playing:
			if !gs.game_over && !gs.boss_victory {
				get_player_input(&gs.player, &gs)

				if gs.player.fire_cooldown > 0 {
					gs.player.fire_cooldown -= dt
				}
				if gs.player.invincibility_timer > 0 {
					gs.player.invincibility_timer -= dt
				}

				update_arena_waves(&gs, dt)

				if gs.arena.active {
					gs.enemies_cleared = gs.arena.boss_defeated
				} else {
					gs.enemies_cleared = are_enemies_cleared(&gs)
				}

				move_and_collide(&gs.player, &gs.map_data, dt, gs.enemies_cleared)

				update_projectiles(&gs.projectiles, &gs.particles, &gs.map_data, dt)
				update_particles(&gs.particles, dt)
				update_flame_particles(&gs.flame_particles, dt)

				update_enemies(&gs, dt)
				check_enemy_player_collision(&gs)
				check_projectile_enemy_collision(&gs)
				check_flame_enemy_collision(&gs)
				check_enemy_projectile_player_collision(&gs)

				update_animation(&gs.player, dt)

				check_pickup(&gs.player, &gs.map_data)
				check_health_crate_pickup(&gs)

				update_damage_texts(&gs.damage_texts, dt)

				// Check if player is bumping into a locked door
				if check_door_blocked(&gs.player, &gs.map_data) {
					gs.door_locked_msg_timer = 2.0
				}
				if gs.door_locked_msg_timer > 0 {
					gs.door_locked_msg_timer -= dt
				}

				// Unlock door when player reaches it with key and enemies cleared
				if !gs.door_unlocked && gs.enemies_cleared && gs.player.has_key {
					if player_near_door(&gs.player, &gs.map_data) {
						gs.door_unlocked = true
						gs.door_anim_timer = 0
						gs.door_anim_frame = 0
					}
				}

				// Update door open animation
				if gs.door_unlocked && gs.door_anim_frame < 2 {
					gs.door_anim_timer += dt
					if gs.door_anim_timer >= DOOR_ANIM_FRAME_TIME {
						gs.door_anim_timer -= DOOR_ANIM_FRAME_TIME
						gs.door_anim_frame += 1
					}
				}

				// Check door transition (only after animation completes)
				next_map := check_door_transition(&gs)
				if len(next_map) > 0 {
					transition_to_map(&gs, next_map)
				}

				if gs.player.hp <= 0 {
					gs.game_over = true
				}

				if gs.arena.boss_defeated && !gs.boss_victory {
					gs.boss_victory = true
					gs.boss_victory_selection = 0
				}

				update_camera(&gs)
			} else if gs.boss_victory {
				action := handle_boss_victory_input(&gs)
				if action == 1 {
					reset_game(&gs)
				} else if action == 2 {
					break game_loop
				}
			} else {
				action := handle_game_over_input(&gs)
				if action == 1 {
					reset_game(&gs)
				} else if action == 2 {
					break game_loop
				}
			}
		}

		// Draw
		raylib.BeginDrawing()
		raylib.ClearBackground({20, 16, 30, 255})

		switch gs.phase {
		case .Character_Select:
			draw_character_select(&gs)

		case .Playing:
			raylib.BeginMode2D(gs.camera)
			draw_map(&gs)
			draw_enemies(&gs)
			draw_health_crates(&gs)
			draw_particles(&gs.particles)
			draw_flame_particles(&gs.flame_particles)
			draw_player(&gs.player, gs.blaster_tex, gs.slinger_tex, gs.flamethrower_tex)
			draw_projectiles(&gs.projectiles)
			draw_damage_texts(&gs.damage_texts, gs.font)
			raylib.EndMode2D()

			draw_hp_bar(&gs.player)
			draw_ammo_display(&gs.player, gs.ammo_tex)
			draw_boss_hp_bar(&gs)

			// Arena objective text with subtle pulse
			if gs.arena.active && !gs.arena.boss_defeated {
				pulse := 1.0 + 0.05 * math.sin(f32(raylib.GetTime()) * 3.0)
				base_size: f32 = 10
				text_size := base_size * pulse
				text_alpha := u8(200 + 55 * math.sin(f32(raylib.GetTime()) * 2.0))
				raylib.DrawTextEx(
					gs.font,
					"Survive the enemy waves!",
					{8, 8},
					text_size,
					1,
					{255, 220, 50, text_alpha},
				)
			}

			if gs.door_locked_msg_timer > 0 {
				msg :: "Find the key to unlock"
				msg_size: f32 = 14
				msg_w := raylib.MeasureTextEx(gs.font, msg, msg_size, 1).x
				msg_x := (f32(SCREEN_WIDTH) - msg_w) / 2
				msg_y: f32 = f32(SCREEN_HEIGHT) - 50
				raylib.DrawTextEx(gs.font, msg, {msg_x, msg_y}, msg_size, 1, {255, 220, 50, 255})
			}

			if gs.boss_victory {
				draw_boss_victory(&gs)
			} else if gs.game_over {
				draw_game_over(&gs)
			}
		}

		// Draw reticle cursor
		{
			RETICLE_SIZE :: 18
			mouse := raylib.GetMousePosition()
			src := raylib.Rectangle{0, 0, f32(gs.reticle_tex.width), f32(gs.reticle_tex.height)}
			dst := raylib.Rectangle{mouse.x - RETICLE_SIZE / 2, mouse.y - RETICLE_SIZE / 2, RETICLE_SIZE, RETICLE_SIZE}
			raylib.DrawTexturePro(gs.reticle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
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

	raylib.UnloadTexture(gs.benny_move_tex)
	raylib.UnloadTexture(gs.benny_idle_tex)
	raylib.UnloadTexture(gs.sheryl_move_tex)
	raylib.UnloadTexture(gs.sheryl_idle_tex)
	raylib.UnloadTexture(gs.blaster_tex)
	raylib.UnloadTexture(gs.slinger_tex)
	raylib.UnloadTexture(gs.flamethrower_tex)
	raylib.UnloadTexture(gs.slug_move_tex)
	raylib.UnloadTexture(gs.slug_dead_tex)
	raylib.UnloadTexture(gs.fly_move_tex)
	raylib.UnloadTexture(gs.fly_dead_tex)
	raylib.UnloadTexture(gs.bunny_move_tex)
	raylib.UnloadTexture(gs.bunny_dead_tex)
	raylib.UnloadTexture(gs.boss_move_tex)
	raylib.UnloadTexture(gs.health_crate_tex)
	raylib.UnloadTexture(gs.reticle_tex)
	raylib.UnloadTexture(gs.ammo_tex)
	raylib.UnloadFont(gs.font)
	raylib.UnloadShader(gs.white_flash_shader)

	dm.destroy_map(&gs.map_data)
}

handle_menu_input :: proc(gs: ^Game_State) {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.menu_selection = 1 - gs.menu_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			gs.menu_selection = 1 - gs.menu_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		init_player(gs)
		update_camera(gs)
		gs.phase = .Playing
	}
}

init_player :: proc(gs: ^Game_State) {
	if gs.menu_selection == 0 {
		// Sheryl
		gs.player = Player {
			pos              = gs.spawn_pos,
			sprite_sheet     = gs.sheryl_move_tex,
			idle_sheet       = gs.sheryl_idle_tex,
			frame_count      = 3,
			idle_frame_count = 4,
			hp               = PLAYER_HP,
		}
	} else {
		// Benny
		gs.player = Player {
			pos              = gs.spawn_pos,
			sprite_sheet     = gs.benny_move_tex,
			idle_sheet       = gs.benny_idle_tex,
			frame_count      = 4,
			idle_frame_count = 5,
			hp               = PLAYER_HP,
		}
	}
}

draw_character_select :: proc(gs: ^Game_State) {
	// Title
	title_size: f32 = 28
	title_w := raylib.MeasureTextEx(gs.font, "CHOOSE YOUR CHARACTER", title_size, 1).x
	title_x := (f32(SCREEN_WIDTH) - title_w) / 2
	raylib.DrawTextEx(gs.font, "CHOOSE YOUR CHARACTER", {title_x, 60}, title_size, 1, {220, 210, 240, 255})

	option_size: f32 = 22
	PREVIEW_SIZE :: 48

	// Sheryl
	{
		y: f32 = 140
		color: raylib.Color = gs.menu_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		preview_x := f32(SCREEN_WIDTH) / 2 - 60
		src := raylib.Rectangle{0, 0, f32(SPRITE_SRC_SIZE), f32(SPRITE_SRC_SIZE)}
		dst := raylib.Rectangle{preview_x, y - 14, PREVIEW_SIZE, PREVIEW_SIZE}
		raylib.DrawTexturePro(gs.sheryl_idle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		name_x := preview_x + PREVIEW_SIZE + 12
		if gs.menu_selection == 0 {
			raylib.DrawTextEx(gs.font, ">", {name_x - 18, y}, option_size, 1, color)
		}
		raylib.DrawTextEx(gs.font, "SHERYL", {name_x, y}, option_size, 1, color)
	}

	// Benny
	{
		y: f32 = 210
		color: raylib.Color = gs.menu_selection == 1 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		preview_x := f32(SCREEN_WIDTH) / 2 - 60
		src := raylib.Rectangle{0, 0, f32(SPRITE_SRC_SIZE), f32(SPRITE_SRC_SIZE)}
		dst := raylib.Rectangle{preview_x, y - 14, PREVIEW_SIZE, PREVIEW_SIZE}
		raylib.DrawTexturePro(gs.benny_idle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		name_x := preview_x + PREVIEW_SIZE + 12
		if gs.menu_selection == 1 {
			raylib.DrawTextEx(gs.font, ">", {name_x - 18, y}, option_size, 1, color)
		}
		raylib.DrawTextEx(gs.font, "BENNY", {name_x, y}, option_size, 1, color)
	}
}

// Returns 0=none, 1=restart, 2=quit
handle_game_over_input :: proc(gs: ^Game_State) -> i32 {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.game_over_selection = 1 - gs.game_over_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			gs.game_over_selection = 1 - gs.game_over_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
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

// Returns 0=none, 1=continue(restart), 2=quit
handle_boss_victory_input :: proc(gs: ^Game_State) -> i32 {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.boss_victory_selection = 1 - gs.boss_victory_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			gs.boss_victory_selection = 1 - gs.boss_victory_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		return gs.boss_victory_selection == 0 ? 1 : 2
	}
	return 0
}

draw_boss_victory :: proc(gs: ^Game_State) {
	// Dark overlay
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, {0, 0, 0, 150})

	// Panel
	PANEL_W :: 260
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
	title_size: f32 = 22
	title_w := raylib.MeasureTextEx(gs.font, "You captured Monroe!", title_size, 1).x
	title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
	title_y := f32(PANEL_Y) + 15
	raylib.DrawTextEx(gs.font, "You captured Monroe!", {title_x, title_y}, title_size, 1, {255, 220, 50, 255})

	// Menu options
	option_size: f32 = 20

	// Continue
	continue_w := raylib.MeasureTextEx(gs.font, "CONTINUE", option_size, 1).x
	continue_x := f32(PANEL_X) + (f32(PANEL_W) - continue_w) / 2
	continue_y := f32(PANEL_Y) + 65
	continue_color: raylib.Color = gs.boss_victory_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
	if gs.boss_victory_selection == 0 {
		raylib.DrawTextEx(gs.font, ">", {continue_x - 18, continue_y}, option_size, 1, continue_color)
	}
	raylib.DrawTextEx(gs.font, "CONTINUE", {continue_x, continue_y}, option_size, 1, continue_color)

	// Quit
	quit_w := raylib.MeasureTextEx(gs.font, "QUIT", option_size, 1).x
	quit_x := f32(PANEL_X) + (f32(PANEL_W) - quit_w) / 2
	quit_y := f32(PANEL_Y) + 95
	quit_color: raylib.Color = gs.boss_victory_selection == 0 ? {180, 180, 180, 255} : {255, 220, 50, 255}
	if gs.boss_victory_selection == 1 {
		raylib.DrawTextEx(gs.font, ">", {quit_x - 18, quit_y}, option_size, 1, quit_color)
	}
	raylib.DrawTextEx(gs.font, "QUIT", {quit_x, quit_y}, option_size, 1, quit_color)
}

reset_game :: proc(gs: ^Game_State) {
	// Reset player — preserve identity fields (sprite_sheet, frame_count, etc.)
	gs.player.pos = gs.spawn_pos
	gs.player.aim_dir = {0, 0}
	gs.player.move_dir = {0, 0}
	gs.player.current_frame = 0
	gs.player.anim_timer = 0
	gs.player.facing_left = false
	gs.player.weapon = .None
	gs.player.ammo = 0
	gs.player.blaster_angle = 0
	gs.player.fire_cooldown = 0
	gs.player.hp = PLAYER_HP
	gs.player.invincibility_timer = 0
	gs.player.knockback_vel = {0, 0}
	gs.player.blaster_recoil = 0

	// Clear projectiles and particles
	for &proj in gs.projectiles {
		proj.active = false
	}
	for &part in gs.particles {
		part.active = false
	}
	for &fp in gs.flame_particles {
		fp.active = false
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
	init_arena(gs)

	for &dt_text in gs.damage_texts {
		dt_text.active = false
	}
	for &crate in gs.health_crates {
		crate.active = false
	}

	gs.enemies_cleared = false
	gs.game_over = false
	gs.game_over_selection = 0
	gs.boss_victory = false
	gs.boss_victory_selection = 0
	gs.door_locked_msg_timer = 0
	gs.door_unlocked = false
	gs.door_anim_timer = 0
	gs.door_anim_frame = 0
	update_camera(gs)
}

spawn_damage_text :: proc(gs: ^Game_State, pos: raylib.Vector2, damage: i32) {
	for &dt_text in gs.damage_texts {
		if !dt_text.active {
			dt_text = Damage_Text {
				active = true,
				pos    = pos,
				timer  = DAMAGE_TEXT_TIME,
				damage = damage,
			}
			return
		}
	}
}

update_damage_texts :: proc(texts: ^[MAX_DAMAGE_TEXTS]Damage_Text, frame_dt: f32) {
	for &dt_text in texts {
		if !dt_text.active {
			continue
		}
		dt_text.timer -= frame_dt
		dt_text.pos.y -= DAMAGE_TEXT_SPEED * frame_dt
		if dt_text.timer <= 0 {
			dt_text.active = false
		}
	}
}

check_door_transition :: proc(gs: ^Game_State) -> string {
	if !gs.enemies_cleared {
		return ""
	}

	center_x := int(gs.player.pos.x) / TILE_SIZE
	center_y := int(gs.player.pos.y - f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE

	if center_y < 0 || center_y >= gs.map_data.height {
		return ""
	}
	if center_x < 0 || center_x >= len(gs.map_data.grid[center_y]) {
		return ""
	}

	cell := gs.map_data.grid[center_y][center_x]
	if td, ok := gs.map_data.metadata[cell.symbol]; ok {
		if len(td.to_room) > 0 {
			// Check all conditions before allowing transition
			if strings.contains(td.condition, "has_key") && !gs.player.has_key {
				return ""
			}
			// Wait for door animation to finish
			if gs.door_unlocked && gs.door_anim_frame < 2 {
				return ""
			}
			return td.to_room
		}
	}

	return ""
}

transition_to_map :: proc(gs: ^Game_State, map_name: string) {
	// Build path relative to current map directory
	map_path := strings.concatenate({"assets/maps/", map_name})
	defer delete(map_path)

	new_map, map_ok := dm.parse_map_file(map_path)
	if !map_ok {
		fmt.eprintln("Failed to load map:", map_path)
		return
	}

	// Unload old tile textures
	for _, &textures in gs.tile_textures {
		for &tex in textures {
			raylib.UnloadTexture(tex)
		}
		delete(textures)
	}
	delete(gs.tile_textures)

	// Destroy old map
	dm.destroy_map(&gs.map_data)
	gs.map_data = new_map

	// Load new tile textures
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

	// Find spawn point
	spawn_x: f32 = 0
	spawn_y: f32 = 0
	spawn_found := false
	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'p' && !spawn_found {
				spawn_x = f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2
				spawn_y = f32(y * TILE_SIZE) + f32(TILE_SIZE)
				spawn_found = true
				break
			}
		}
		if spawn_found {
			break
		}
	}

	gs.spawn_pos = {spawn_x, spawn_y}

	// Reset player to new spawn
	gs.player.pos = gs.spawn_pos
	gs.player.move_dir = {0, 0}
	gs.player.current_frame = 0
	gs.player.anim_timer = 0
	gs.player.knockback_vel = {0, 0}

	// Clear projectiles and particles
	for &proj in gs.projectiles {
		proj.active = false
	}
	for &part in gs.particles {
		part.active = false
	}
	for &fp in gs.flame_particles {
		fp.active = false
	}
	for &dt_text in gs.damage_texts {
		dt_text.active = false
	}
	for &crate in gs.health_crates {
		crate.active = false
	}

	// Re-init enemies
	for &enemy in gs.enemies {
		enemy = {}
	}
	init_enemies(gs)
	init_arena(gs)

	gs.enemies_cleared = false
	gs.door_locked_msg_timer = 0
	gs.door_unlocked = false
	gs.door_anim_timer = 0
	gs.door_anim_frame = 0
	gs.player.has_key = false
	update_camera(gs)
}

spawn_health_crate :: proc(gs: ^Game_State, pos: raylib.Vector2) {
	for &crate in gs.health_crates {
		if !crate.active {
			crate = Health_Crate {
				pos    = pos,
				active = true,
			}
			return
		}
	}
}

check_health_crate_pickup :: proc(gs: ^Game_State) {
	px := gs.player.pos.x - f32(PLAYER_HITBOX) / 2
	py := gs.player.pos.y - f32(PLAYER_HITBOX) / 2
	ps := f32(PLAYER_HITBOX)

	for &crate in gs.health_crates {
		if !crate.active {
			continue
		}

		cs := f32(SPRITE_DST_SIZE)
		if px < crate.pos.x + cs && px + ps > crate.pos.x &&
		   py < crate.pos.y + cs && py + ps > crate.pos.y {
			gs.player.hp = min(gs.player.hp + HEALTH_CRATE_HEAL, PLAYER_HP)
			crate.active = false
		}
	}
}

draw_health_crates :: proc(gs: ^Game_State) {
	for &crate in gs.health_crates {
		if !crate.active {
			continue
		}

		src := raylib.Rectangle {
			x      = 0,
			y      = 0,
			width  = f32(gs.health_crate_tex.width),
			height = f32(gs.health_crate_tex.height),
		}
		dst := raylib.Rectangle {
			x      = crate.pos.x,
			y      = crate.pos.y,
			width  = f32(SPRITE_DST_SIZE),
			height = f32(SPRITE_DST_SIZE),
		}
		raylib.DrawTexturePro(gs.health_crate_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	}
}

draw_damage_texts :: proc(texts: ^[MAX_DAMAGE_TEXTS]Damage_Text, font: raylib.Font) {
	buf: [16]u8
	for &dt_text in texts {
		if !dt_text.active {
			continue
		}
		alpha := u8(255 * (dt_text.timer / DAMAGE_TEXT_TIME))
		text := fmt.bprintf(buf[:], "{}", dt_text.damage)
		ctext := strings.clone_to_cstring(text, context.temp_allocator)
		text_size: f32 = 6
		text_w := raylib.MeasureTextEx(font, ctext, text_size, 0.5).x
		x := dt_text.pos.x - text_w / 2
		raylib.DrawTextEx(font, ctext, {x, dt_text.pos.y}, text_size, 0.5, {255, 80, 80, alpha})
	}
}
