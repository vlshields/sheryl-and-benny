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
CAMERA_ZOOM       :: 2.85
MAX_DAMAGE_TEXTS  :: 8
MAX_HEALTH_CRATES :: 8
MAX_NPCS          :: 8
NPC_ANIM_FRAME_TIME :: 0.2
HEALTH_CRATE_HEAL :: 15
DAMAGE_TEXT_SPEED      :: 20.0
DAMAGE_TEXT_TIME       :: 0.8
DOOR_ANIM_FRAME_TIME   :: 0.2

Game_Phase :: enum {
	Main_Menu,
	Character_Select,
	Playing,
}

Pause_Submenu :: enum {
	None,
	Controls,
	Quit_Confirm,
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

NPC :: struct {
	pos:           raylib.Vector2,
	active:        bool,
	sprite_sheet:  raylib.Texture2D,
	frame_count:   i32,
	current_frame: i32,
	anim_timer:    f32,
	facing_left:   bool,
}

Game_State :: struct {
	map_data:            dm.Dot_Map,
	tile_textures:       map[u8][dynamic]raylib.Texture2D,
	camera:              raylib.Camera2D,
	player:              Player,
	blaster_tex:         raylib.Texture2D,
	slinger_tex:         raylib.Texture2D,
	flamethrower_tex:    raylib.Texture2D,
	lasergun_tex:        raylib.Texture2D,
	laser_beams:         [MAX_LASER_BEAMS]Laser_Beam,
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
	npcs:                [MAX_NPCS]NPC,
	npc_bunny_tex:       raylib.Texture2D,
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
	paused:              bool,
	pause_selection:     i32,
	pause_submenu:       Pause_Submenu,
	pause_confirm_selection: i32,
	render_target:         raylib.RenderTexture2D,
	screen_scale:          f32,
	screen_offset:         raylib.Vector2,
	menu_bg_tex:           raylib.Texture2D,
	menu_scroll_offsets:   [3]f32,
	menu_floor_tex:        raylib.Texture2D,
	menu_title_y:          f32,
	menu_options_x:        f32,
	menu_main_selection:   i32,
	menu_sheryl_frame:     i32,
	menu_benny_frame:      i32,
	menu_sprite_timer:     f32,
}

get_virtual_mouse :: proc(gs: ^Game_State) -> raylib.Vector2 {
	mouse := raylib.GetMousePosition()
	return {
		(mouse.x - gs.screen_offset.x) / gs.screen_scale,
		(mouse.y - gs.screen_offset.y) / gs.screen_scale,
	}
}

main :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ACJAM")
	defer raylib.CloseWindow()

	monitor := raylib.GetCurrentMonitor()
	screen_w := raylib.GetMonitorWidth(monitor)
	screen_h := raylib.GetMonitorHeight(monitor)
	raylib.SetWindowSize(screen_w, screen_h)
	raylib.ToggleFullscreen()
	raylib.SetTargetFPS(TARGET_FPS)

	gs: Game_State

	// Setup render target for virtual resolution scaling
	gs.render_target = raylib.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	raylib.SetTextureFilter(gs.render_target.texture, .POINT)
	scale_x := f32(screen_w) / f32(SCREEN_WIDTH)
	scale_y := f32(screen_h) / f32(SCREEN_HEIGHT)
	gs.screen_scale = min(scale_x, scale_y)
	gs.screen_offset = {
		(f32(screen_w) - f32(SCREEN_WIDTH) * gs.screen_scale) / 2,
		(f32(screen_h) - f32(SCREEN_HEIGHT) * gs.screen_scale) / 2,
	}

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
	gs.lasergun_tex = raylib.LoadTexture("assets/sprites/laser_gun.png")

	// Load enemy sprites
	gs.slug_move_tex = raylib.LoadTexture("assets/sprites/enemy_slug_move.png")
	gs.slug_dead_tex = raylib.LoadTexture("assets/sprites/enemy_slug_dead.png")
	gs.fly_move_tex = raylib.LoadTexture("assets/sprites/enemy_fly_move.png")
	gs.fly_dead_tex = raylib.LoadTexture("assets/sprites/enemy_fly_dead.png")
	gs.bunny_move_tex = raylib.LoadTexture("assets/sprites/enemy_crazy_bunny_move.png")
	gs.bunny_dead_tex = raylib.LoadTexture("assets/sprites/enemy_crazy_bunny_dead.png")
	gs.boss_move_tex = raylib.LoadTexture("assets/sprites/enemy_boss.png")
	gs.health_crate_tex = raylib.LoadTexture("assets/sprites/health_pickup_arena.png")
	gs.npc_bunny_tex = raylib.LoadTexture("assets/sprites/npc_bunny_idle.png")

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

	// Load main menu background (3 layers stacked vertically in one image)
	gs.menu_bg_tex = raylib.LoadTexture("assets/sprites/background.png")
	gs.menu_floor_tex = raylib.LoadTexture("assets/tiles/arena_floor.png")

	// Init main menu animation state
	gs.menu_title_y = -60
	gs.menu_options_x = f32(SCREEN_WIDTH) + 100

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

	// Init enemies and NPCs
	init_enemies(&gs)
	init_npcs(&gs)
	init_arena(&gs)

	// Init camera centered on spawn
	gs.camera.zoom = CAMERA_ZOOM
	gs.camera.offset = {f32(SCREEN_WIDTH) / 2, f32(SCREEN_HEIGHT) / 2}
	gs.camera.target = {gs.spawn_pos.x, gs.spawn_pos.y - f32(SPRITE_DST_SIZE) / 2}

	// Game loop
	game_loop: for !raylib.WindowShouldClose() {
		dt := raylib.GetFrameTime()

		switch gs.phase {
		case .Main_Menu:
			action := update_main_menu(&gs)
			if action == 1 {
				gs.phase = .Character_Select
				gs.menu_selection = 0
			} else if action == 2 {
				break game_loop
			}

		case .Character_Select:
			handle_menu_input(&gs)

		case .Playing:
			// Pause toggle
			if raylib.IsKeyPressed(.P) && !gs.game_over && !gs.boss_victory {
				if gs.paused {
					gs.paused = false
					gs.pause_submenu = .None
				} else {
					gs.paused = true
					gs.pause_selection = 0
					gs.pause_submenu = .None
					gs.pause_confirm_selection = 0
				}
			}

			if gs.paused {
				action := handle_pause_input(&gs)
				if action == 1 {
					gs.paused = false
					gs.pause_submenu = .None
				} else if action == 2 {
					break game_loop
				}
			} else if !gs.game_over && !gs.boss_victory {
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
				update_laser_beams(&gs.laser_beams, dt)

				update_enemies(&gs, dt)
				check_enemy_player_collision(&gs)
				check_projectile_enemy_collision(&gs)
				check_flame_enemy_collision(&gs)
				check_enemy_projectile_player_collision(&gs)

				update_animation(&gs.player, dt)

				check_pickup(&gs.player, &gs.map_data)
				check_health_crate_pickup(&gs)

				update_npcs(&gs, dt)
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

		// Draw to virtual render target
		raylib.BeginTextureMode(gs.render_target)
		raylib.ClearBackground({20, 16, 30, 255})

		switch gs.phase {
		case .Main_Menu:
			draw_main_menu(&gs)

		case .Character_Select:
			draw_character_select(&gs)

		case .Playing:
			raylib.BeginMode2D(gs.camera)
			draw_map(&gs)
			draw_enemies(&gs)
			draw_npcs(&gs)
			draw_health_crates(&gs)
			draw_particles(&gs.particles)
			draw_flame_particles(&gs.flame_particles)
			draw_laser_beams(&gs.laser_beams)
			draw_player(&gs.player, gs.blaster_tex, gs.slinger_tex, gs.flamethrower_tex, gs.lasergun_tex)
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

			if gs.paused {
				draw_pause_menu(&gs)
			} else if gs.boss_victory {
				draw_boss_victory(&gs)
			} else if gs.game_over {
				draw_game_over(&gs)
			}
		}

		// Draw reticle cursor in virtual space
		{
			RETICLE_SIZE :: 18
			mouse := get_virtual_mouse(&gs)
			src := raylib.Rectangle{0, 0, f32(gs.reticle_tex.width), f32(gs.reticle_tex.height)}
			dst := raylib.Rectangle{mouse.x - RETICLE_SIZE / 2, mouse.y - RETICLE_SIZE / 2, RETICLE_SIZE, RETICLE_SIZE}
			raylib.DrawTexturePro(gs.reticle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		}

		raylib.EndTextureMode()

		// Blit render target scaled to fullscreen
		raylib.BeginDrawing()
		raylib.ClearBackground(raylib.BLACK)
		src := raylib.Rectangle{0, 0, f32(SCREEN_WIDTH), -f32(SCREEN_HEIGHT)}
		dst := raylib.Rectangle{gs.screen_offset.x, gs.screen_offset.y, f32(SCREEN_WIDTH) * gs.screen_scale, f32(SCREEN_HEIGHT) * gs.screen_scale}
		raylib.DrawTexturePro(gs.render_target.texture, src, dst, {0, 0}, 0, raylib.WHITE)
		raylib.EndDrawing()
	}

	// Cleanup
	raylib.UnloadRenderTexture(gs.render_target)
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
	raylib.UnloadTexture(gs.lasergun_tex)
	raylib.UnloadTexture(gs.slug_move_tex)
	raylib.UnloadTexture(gs.slug_dead_tex)
	raylib.UnloadTexture(gs.fly_move_tex)
	raylib.UnloadTexture(gs.fly_dead_tex)
	raylib.UnloadTexture(gs.bunny_move_tex)
	raylib.UnloadTexture(gs.bunny_dead_tex)
	raylib.UnloadTexture(gs.boss_move_tex)
	raylib.UnloadTexture(gs.health_crate_tex)
	raylib.UnloadTexture(gs.npc_bunny_tex)
	raylib.UnloadTexture(gs.reticle_tex)
	raylib.UnloadTexture(gs.ammo_tex)
	raylib.UnloadFont(gs.font)
	raylib.UnloadShader(gs.white_flash_shader)

	raylib.UnloadTexture(gs.menu_bg_tex)
	raylib.UnloadTexture(gs.menu_floor_tex)

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
			weapon           = .Blaster,
			ammo             = BLASTER_MAX_AMMO,
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
			weapon           = .Blaster,
			ammo             = BLASTER_MAX_AMMO,
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

// Returns 0=none, 1=continue, 2=quit
handle_pause_input :: proc(gs: ^Game_State) -> i32 {
	switch gs.pause_submenu {
	case .None:
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
			gs.pause_selection = (gs.pause_selection + 1) % 3
		}
		if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
			gs.pause_selection = (gs.pause_selection + 2) % 3
		}

		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
				gs.pause_selection = (gs.pause_selection + 1) % 3
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
				gs.pause_selection = (gs.pause_selection + 2) % 3
			}
		}

		confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}

		if confirmed {
			switch gs.pause_selection {
			case 0:
				return 1 // Continue
			case 1:
				gs.pause_submenu = .Controls
			case 2:
				gs.pause_submenu = .Quit_Confirm
				gs.pause_confirm_selection = 1 // Default to "No"
			}
		}

	case .Controls:
		back := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE) || raylib.IsKeyPressed(.ESCAPE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			back = true
		}
		if back {
			gs.pause_submenu = .None
		}

	case .Quit_Confirm:
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
			gs.pause_confirm_selection = 1 - gs.pause_confirm_selection
		}
		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
				gs.pause_confirm_selection = 1 - gs.pause_confirm_selection
			}
		}

		back := raylib.IsKeyPressed(.ESCAPE)
		if back {
			gs.pause_submenu = .None
			return 0
		}

		confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
		if confirmed {
			if gs.pause_confirm_selection == 0 {
				return 2 // Quit
			} else {
				gs.pause_submenu = .None
			}
		}
	}
	return 0
}

draw_pause_menu :: proc(gs: ^Game_State) {
	// Dark overlay
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, {0, 0, 0, 150})

	switch gs.pause_submenu {
	case .None:
		PANEL_W :: 220
		PANEL_H :: 160
		PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
		PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

		raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
		raylib.DrawRectangleLinesEx(
			{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
			2,
			{200, 180, 220, 255},
		)

		// Title
		title_size: f32 = 28
		title_w := raylib.MeasureTextEx(gs.font, "PAUSED", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 12
		raylib.DrawTextEx(gs.font, "PAUSED", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		option_size: f32 = 20
		options := [3]cstring{"CONTINUE", "CONTROLS", "QUIT"}

		for i: i32 = 0; i < 3; i += 1 {
			opt_w := raylib.MeasureTextEx(gs.font, options[i], option_size, 1).x
			opt_x := f32(PANEL_X) + (f32(PANEL_W) - opt_w) / 2
			opt_y := f32(PANEL_Y) + 55 + f32(i) * 30
			color: raylib.Color = gs.pause_selection == i ? {255, 220, 50, 255} : {180, 180, 180, 255}
			if gs.pause_selection == i {
				raylib.DrawTextEx(gs.font, ">", {opt_x - 18, opt_y}, option_size, 1, color)
			}
			raylib.DrawTextEx(gs.font, options[i], {opt_x, opt_y}, option_size, 1, color)
		}

	case .Controls:
		PANEL_W :: 280
		PANEL_H :: 200
		PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
		PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

		raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
		raylib.DrawRectangleLinesEx(
			{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
			2,
			{200, 180, 220, 255},
		)

		title_size: f32 = 22
		title_w := raylib.MeasureTextEx(gs.font, "CONTROLS", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 10
		raylib.DrawTextEx(gs.font, "CONTROLS", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		label_size: f32 = 12
		lx: f32 = f32(PANEL_X) + 20
		ly: f32 = f32(PANEL_Y) + 42
		line_h: f32 = 18
		label_color := raylib.Color{180, 180, 180, 255}
		value_color := raylib.Color{255, 220, 50, 255}

		controls := [5][2]cstring{
			{"MOVE", "WASD"},
			{"AIM", "MOUSE"},
			{"SHOOT", "LEFT CLICK"},
			{"RELOAD", "RIGHT CLICK"},
			{"PAUSE", "P"},
		}

		for i := 0; i < 5; i += 1 {
			y := ly + f32(i) * line_h
			raylib.DrawTextEx(gs.font, controls[i][0], {lx, y}, label_size, 1, label_color)
			raylib.DrawTextEx(gs.font, controls[i][1], {lx + 130, y}, label_size, 1, value_color)
		}

		// Back button
		back_size: f32 = 16
		back_w := raylib.MeasureTextEx(gs.font, "BACK", back_size, 1).x
		back_x := f32(PANEL_X) + (f32(PANEL_W) - back_w) / 2
		back_y := f32(PANEL_Y) + f32(PANEL_H) - 32
		raylib.DrawTextEx(gs.font, "> BACK", {back_x - 18, back_y}, back_size, 1, {255, 220, 50, 255})

	case .Quit_Confirm:
		PANEL_W :: 240
		PANEL_H :: 130
		PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
		PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

		raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
		raylib.DrawRectangleLinesEx(
			{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
			2,
			{200, 180, 220, 255},
		)

		title_size: f32 = 20
		title_w := raylib.MeasureTextEx(gs.font, "ARE YOU SURE?", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 15
		raylib.DrawTextEx(gs.font, "ARE YOU SURE?", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		option_size: f32 = 20

		// Yes
		yes_w := raylib.MeasureTextEx(gs.font, "YES", option_size, 1).x
		yes_x := f32(PANEL_X) + (f32(PANEL_W) - yes_w) / 2
		yes_y := f32(PANEL_Y) + 60
		yes_color: raylib.Color = gs.pause_confirm_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		if gs.pause_confirm_selection == 0 {
			raylib.DrawTextEx(gs.font, ">", {yes_x - 18, yes_y}, option_size, 1, yes_color)
		}
		raylib.DrawTextEx(gs.font, "YES", {yes_x, yes_y}, option_size, 1, yes_color)

		// No
		no_w := raylib.MeasureTextEx(gs.font, "NO", option_size, 1).x
		no_x := f32(PANEL_X) + (f32(PANEL_W) - no_w) / 2
		no_y := f32(PANEL_Y) + 90
		no_color: raylib.Color = gs.pause_confirm_selection == 1 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		if gs.pause_confirm_selection == 1 {
			raylib.DrawTextEx(gs.font, ">", {no_x - 18, no_y}, option_size, 1, no_color)
		}
		raylib.DrawTextEx(gs.font, "NO", {no_x, no_y}, option_size, 1, no_color)
	}
}

reset_game :: proc(gs: ^Game_State) {
	// Reset player — preserve identity fields (sprite_sheet, frame_count, etc.)
	gs.player.pos = gs.spawn_pos
	gs.player.aim_dir = {0, 0}
	gs.player.move_dir = {0, 0}
	gs.player.current_frame = 0
	gs.player.anim_timer = 0
	gs.player.facing_left = false
	gs.player.weapon = .Blaster
	gs.player.ammo = BLASTER_MAX_AMMO
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
	for &beam in gs.laser_beams {
		beam.active = false
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
	init_npcs(gs)
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
	gs.paused = false
	gs.pause_submenu = .None
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
	for &beam in gs.laser_beams {
		beam.active = false
	}
	for &dt_text in gs.damage_texts {
		dt_text.active = false
	}
	for &crate in gs.health_crates {
		crate.active = false
	}

	// Re-init enemies and NPCs
	for &enemy in gs.enemies {
		enemy = {}
	}
	for &npc in gs.npcs {
		npc = {}
	}
	init_enemies(gs)
	init_npcs(gs)
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
	py := gs.player.pos.y - f32(PLAYER_HITBOX)
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

init_npcs :: proc(gs: ^Game_State) {
	npc_idx := 0
	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'n' && npc_idx < MAX_NPCS {
				gs.npcs[npc_idx] = NPC {
					pos          = {f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2, f32(y * TILE_SIZE) + f32(TILE_SIZE)},
					active       = true,
					sprite_sheet = gs.npc_bunny_tex,
					frame_count  = 3,
				}
				npc_idx += 1
			}
		}
	}
}

update_npcs :: proc(gs: ^Game_State, dt: f32) {
	for &npc in gs.npcs {
		if !npc.active {
			continue
		}
		npc.anim_timer += dt
		if npc.anim_timer >= NPC_ANIM_FRAME_TIME {
			npc.anim_timer -= NPC_ANIM_FRAME_TIME
			npc.current_frame = (npc.current_frame + 1) % npc.frame_count
		}

		// Face the player
		if gs.player.pos.x < npc.pos.x {
			npc.facing_left = true
		} else {
			npc.facing_left = false
		}
	}
}

draw_npcs :: proc(gs: ^Game_State) {
	for &npc in gs.npcs {
		if !npc.active {
			continue
		}

		src_w := f32(SPRITE_SRC_SIZE)
		if npc.facing_left {
			src_w = -src_w
		}

		src := raylib.Rectangle {
			x      = f32(npc.current_frame * SPRITE_SRC_SIZE),
			y      = 0,
			width  = src_w,
			height = f32(SPRITE_SRC_SIZE),
		}

		dst := raylib.Rectangle {
			x      = npc.pos.x,
			y      = npc.pos.y,
			width  = f32(SPRITE_DST_SIZE),
			height = f32(SPRITE_DST_SIZE),
		}

		origin := raylib.Vector2{f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE)}
		raylib.DrawTexturePro(npc.sprite_sheet, src, dst, origin, 0, raylib.WHITE)
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
