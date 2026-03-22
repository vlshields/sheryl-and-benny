package sheryl_and_benny

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"


Game_Phase :: enum {
	Main_Menu,
	Character_Select,
	Playing,
}

Pause_Submenu :: enum {
	None,
	Controls,
	Audio,
	Quit_Confirm,
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

Sign :: struct {
	pos:    raylib.Vector2,
	active: bool,
}

Game_State :: struct {
	map_data:               dm.Dot_Map,
	tile_textures:          map[u8][dynamic]raylib.Texture2D,
	camera:                 raylib.Camera2D,
	player:                 Player,
	blaster_tex:            raylib.Texture2D,
	slinger_tex:            raylib.Texture2D,
	flamethrower_tex:       raylib.Texture2D,
	lasergun_tex:           raylib.Texture2D,
	laser_beams:            [MAX_LASER_BEAMS]Laser_Beam,
	flame_particles:        [MAX_FLAME_PARTICLES]Flame_Particle,
	projectiles:            [MAX_PROJECTILES]Projectile,
	particles:              [MAX_PARTICLES]Particle,
	enemies:                [MAX_ENEMIES]Enemy,
	slug_move_tex:          raylib.Texture2D,
	slug_dead_tex:          raylib.Texture2D,
	fly_move_tex:           raylib.Texture2D,
	fly_dead_tex:           raylib.Texture2D,
	bunny_move_tex:         raylib.Texture2D,
	bunny_dead_tex:         raylib.Texture2D,
	enemies_cleared:        bool,
	game_over:              bool,
	game_over_selection:    i32,
	font:                   raylib.Font,
	spawn_pos:              raylib.Vector2,
	white_flash_shader:     raylib.Shader,
	health_crates:          [MAX_HEALTH_CRATES]Health_Crate,
	health_crate_tex:       raylib.Texture2D,
	npcs:                   [MAX_NPCS]NPC,
	npc_bunny_tex:          raylib.Texture2D,
	reticle_tex:            raylib.Texture2D,
	ammo_tex:               raylib.Texture2D,
	phase:                  Game_Phase,
	menu_selection:         i32,
	door_locked_msg_timer:  f32,
	door_unlocked:          bool,
	door_anim_timer:        f32,
	door_anim_frame:        i32,
	benny_move_tex:         raylib.Texture2D,
	benny_idle_tex:         raylib.Texture2D,
	sheryl_move_tex:        raylib.Texture2D,
	sheryl_idle_tex:        raylib.Texture2D,
	boss_move_tex:          raylib.Texture2D,
	arena:                  Arena_State,
	boss_victory:           bool,
	boss_victory_selection: i32,
	paused:                 bool,
	pause_selection:        i32,
	pause_submenu:          Pause_Submenu,
	pause_confirm_selection: i32,
	pause_audio_selection:  i32,
	audio:                  Audio_State,
	dialogue:               Dialogue_State,
	door_dialogue:          Dialogue_State,
	sign_dialogue:          Dialogue_State,
	signs:                  [MAX_SIGNS]Sign,
	current_map_name:       string,
	exit_door_pos:          raylib.Vector2,
	has_exit_door:          bool,
	compass_arrow_tex:      raylib.Texture2D,
	render_target:          raylib.RenderTexture2D,
	screen_scale:           f32,
	screen_offset:          raylib.Vector2,
	window_w:               i32,
	window_h:               i32,
	menu_bg_tex:            raylib.Texture2D,
	menu_scroll_offsets:    [3]f32,
	menu_floor_tex:         raylib.Texture2D,
	menu_title_y:           f32,
	menu_options_x:         f32,
	menu_main_selection:    i32,
	menu_sheryl_frame:      i32,
	menu_benny_frame:       i32,
	menu_sprite_timer:      f32,
	should_quit:            bool,
}

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	WHITE_FLASH_FS :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
void main() {
    vec4 texColor = texture2D(texture0, fragTexCoord);
    gl_FragColor = vec4(1.0, 1.0, 1.0, texColor.a);
}
`
} else {
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
}

get_virtual_mouse :: proc(state: ^Game_State) -> raylib.Vector2 {
	mouse: raylib.Vector2
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		mouse = web_mouse_pos
	} else {
		mouse = raylib.GetMousePosition()
	}
	return {
		(mouse.x - state.screen_offset.x) / state.screen_scale,
		(mouse.y - state.screen_offset.y) / state.screen_scale,
	}
}

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	web_mouse_pos: raylib.Vector2
	web_mouse_down: bool
}

set_web_mouse_pos :: proc(x, y: int) {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		web_mouse_pos = {f32(x), f32(y)}
	}
}

set_web_mouse_down :: proc(down: bool) {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		web_mouse_down = down
	}
}

@(private = "file")
gs: Game_State

@(private = "file")
update_screen_scale :: proc() {
	win_w := gs.window_w
	win_h := gs.window_h
	if win_w <= 0 || win_h <= 0 {
		win_w = raylib.GetScreenWidth()
		win_h = raylib.GetScreenHeight()
	}
	scale_x := f32(win_w) / f32(SCREEN_WIDTH)
	scale_y := f32(win_h) / f32(SCREEN_HEIGHT)
	gs.screen_scale = min(scale_x, scale_y)
	gs.screen_offset = {
		(f32(win_w) - f32(SCREEN_WIDTH) * gs.screen_scale) / 2,
		(f32(win_h) - f32(SCREEN_HEIGHT) * gs.screen_scale) / 2,
	}
}

init :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Sheryl and Benny")

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		monitor := raylib.GetCurrentMonitor()
		screen_w := raylib.GetMonitorWidth(monitor)
		screen_h := raylib.GetMonitorHeight(monitor)
		raylib.SetWindowSize(screen_w, screen_h)
		raylib.ToggleFullscreen()
		raylib.SetTargetFPS(TARGET_FPS)
	}

	init_audio(&gs.audio)

	// Setup render target for virtual resolution scaling
	gs.render_target = raylib.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	raylib.SetTextureFilter(gs.render_target.texture, .POINT)
	update_screen_scale()

	// Parse map
	map_bytes, map_read_ok := read_entire_file("assets/maps/home_base.map")
	if !map_read_ok {
		fmt.eprintln("Failed to load map file!")
		gs.should_quit = true
		return
	}
	map_data, map_ok := dm.parse_map(string(map_bytes))
	delete(map_bytes)
	if !map_ok {
		fmt.eprintln("Failed to parse map!")
		gs.should_quit = true
		return
	}
	gs.map_data = map_data
	gs.current_map_name = "home_base.map"
	find_exit_door(&gs)

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
	gs.compass_arrow_tex = raylib.LoadTexture("assets/sprites/compass_arrow.png")
	raylib.HideCursor()

	// Use the default raylib font
	gs.font = raylib.GetFontDefault()

	// Load white flash shader
	gs.white_flash_shader = raylib.LoadShaderFromMemory(nil, WHITE_FLASH_FS)

	// Load main menu background
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

	// Init enemies, NPCs, and signs
	init_enemies(&gs)
	init_npcs(&gs)
	init_signs(&gs)
	init_arena(&gs)

	// Load dialogues
	dialogue, dialogue_ok := parse_dialogue_file("assets/dialogue/player_and_bozzo.dialg")
	if dialogue_ok {
		gs.dialogue = dialogue
	}
	door_dlg, door_dlg_ok := parse_dialogue_file("assets/dialogue/player_and_homebase_door.dialg")
	if door_dlg_ok {
		gs.door_dialogue = door_dlg
	}
	sign_dlg, sign_dlg_ok := parse_dialogue_file("assets/dialogue/sign_find_the_key.dialg")
	if sign_dlg_ok {
		gs.sign_dialogue = sign_dlg
	}

	// Init camera centered on spawn
	gs.camera.zoom = CAMERA_ZOOM
	gs.camera.offset = {f32(SCREEN_WIDTH) / 2, f32(SCREEN_HEIGHT) / 2}
	gs.camera.target = {gs.spawn_pos.x, gs.spawn_pos.y - f32(SPRITE_DST_SIZE) / 2}
}

update :: proc() {
	dt := raylib.GetFrameTime()
	update_music(&gs.audio)

	switch gs.phase {
	case .Main_Menu:
		action := update_main_menu(&gs)
		if action == 1 {
			gs.phase = .Character_Select
			gs.menu_selection = 0
		} else if action == 2 {
			gs.should_quit = true
			return
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
				stop_weapon_loops(&gs.audio)
				stop_sfx(gs.audio.footsteps)
			}
		}

		if gs.paused {
			action := handle_pause_input(&gs)
			if action == 1 {
				gs.paused = false
				gs.pause_submenu = .None
			} else if action == 2 {
				reset_game(&gs)
				gs.phase = .Main_Menu
				gs.menu_selection = 0
			}
		} else if gs.door_dialogue.active {
			update_dialogue(&gs.door_dialogue, dt, &gs.audio)
			update_npcs(&gs, dt)
			update_animation(&gs.player, dt)
			update_camera(&gs)
			// Handle door dialogue completion
			if gs.door_dialogue.completed {
				if gs.door_dialogue.chosen == 1 {
					// SKIP TUTORIAL: mark bozzo dialogue as done, transition next frame
					gs.dialogue.completed = true
					gs.door_dialogue.active = false
				} else {
					// GO BACK: reset dialogue and push player off door tile
					gs.door_dialogue.active = false
					gs.door_dialogue.completed = false
					gs.door_dialogue.current_line = 0
					gs.door_dialogue.words_revealed = 0
					gs.door_dialogue.chosen = -1
					gs.player.pos.y -= f32(TILE_SIZE)
				}
			}
		} else if gs.sign_dialogue.active {
			update_dialogue(&gs.sign_dialogue, dt, &gs.audio)
			update_animation(&gs.player, dt)
			update_camera(&gs)
			if gs.sign_dialogue.completed {
				gs.sign_dialogue.active = false
				gs.sign_dialogue.completed = false
				gs.sign_dialogue.current_line = 0
				gs.sign_dialogue.words_revealed = 0
			}
		} else if gs.dialogue.active {
			update_dialogue(&gs.dialogue, dt, &gs.audio)
			update_npcs(&gs, dt)
			update_animation(&gs.player, dt)
			update_camera(&gs)
		} else if !gs.game_over && !gs.boss_victory {
			// Check interact with NPC
			nearby_npc := find_nearby_npc(&gs.player, &gs.npcs)
			if nearby_npc >= 0 && !gs.dialogue.completed {
				if raylib.IsKeyPressed(.E) ||
				   (raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_LEFT)) {
					start_dialogue(&gs.dialogue)
					play_sfx(gs.audio.ui_confirm)
				}
			}

			// Check interact with sign
			nearby_sign := find_nearby_sign(&gs.player, &gs.signs)
			if nearby_sign >= 0 && !gs.sign_dialogue.active {
				if raylib.IsKeyPressed(.E) ||
				   (raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_LEFT)) {
					start_dialogue(&gs.sign_dialogue)
					play_sfx(gs.audio.ui_confirm)
				}
			}

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

			move_and_collide(&gs.player, &gs.map_data, dt, gs.enemies_cleared, gs.dialogue.completed)

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

			check_pickup(&gs.player, &gs.map_data, &gs.audio)
			check_health_crate_pickup(&gs)

			update_npcs(&gs, dt)

			// Check if player is bumping into a locked door
			if check_door_blocked(&gs.player, &gs.map_data, gs.dialogue.completed) {
				if gs.door_dialogue.loaded && !gs.door_dialogue.active && !gs.dialogue.completed {
					start_dialogue(&gs.door_dialogue)
				} else {
					if gs.door_locked_msg_timer <= 0 {
						play_sfx(gs.audio.ui_back)
					}
					gs.door_locked_msg_timer = 2.0
				}
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
				stop_weapon_loops(&gs.audio)
				stop_sfx(gs.audio.footsteps)
				stop_sfx(gs.audio.boss_warcry)
			}

			if gs.arena.boss_defeated && !gs.boss_victory {
				gs.boss_victory = true
				gs.boss_victory_selection = 0
				stop_weapon_loops(&gs.audio)
				stop_sfx(gs.audio.footsteps)
				stop_sfx(gs.audio.boss_warcry)
			}

			update_camera(&gs)
		} else if gs.boss_victory {
			action := handle_boss_victory_input(&gs)
			if action == 1 {
				reset_game(&gs)
			} else if action == 2 {
				reset_game(&gs)
				gs.phase = .Main_Menu
				gs.menu_selection = 0
			}
		} else {
			action := handle_game_over_input(&gs)
			if action == 1 {
				reset_game(&gs)
			} else if action == 2 {
				reset_game(&gs)
				gs.phase = .Main_Menu
				gs.menu_selection = 0
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

		// Draw [E] interact prompt above nearby NPC or sign (world space)
		if !gs.paused && !gs.game_over && !gs.boss_victory {
			if !gs.dialogue.active && !gs.dialogue.completed {
				nearby_npc := find_nearby_npc(&gs.player, &gs.npcs)
				if nearby_npc >= 0 {
					draw_interact_prompt(gs.npcs[nearby_npc].pos)
				}
			}
			if !gs.sign_dialogue.active {
				nearby_sign := find_nearby_sign(&gs.player, &gs.signs)
				if nearby_sign >= 0 {
					draw_interact_prompt(gs.signs[nearby_sign].pos)
				}
			}
		}

		raylib.EndMode2D()

		draw_hp_bar(&gs.player)
		draw_ammo_display(&gs.player, gs.ammo_tex)
		draw_boss_hp_bar(&gs)
		draw_exit_compass(&gs)

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

		// Draw dialogue box (screen space)
		draw_dialogue(&gs.dialogue, gs.font)
		draw_dialogue(&gs.door_dialogue, gs.font)
		draw_dialogue(&gs.sign_dialogue, gs.font)

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

should_run :: proc() -> bool {
	return !raylib.WindowShouldClose() && !gs.should_quit
}

shutdown :: proc() {
	destroy_audio(&gs.audio)

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
	raylib.UnloadTexture(gs.compass_arrow_tex)
	raylib.UnloadShader(gs.white_flash_shader)

	raylib.UnloadTexture(gs.menu_bg_tex)
	raylib.UnloadTexture(gs.menu_floor_tex)

	destroy_dialogue(&gs.dialogue)
	destroy_dialogue(&gs.door_dialogue)
	destroy_dialogue(&gs.sign_dialogue)
	dm.destroy_map(&gs.map_data)

	raylib.CloseWindow()
}

parent_window_size_changed :: proc(w, h: int) {
	gs.window_w = i32(w)
	gs.window_h = i32(h)
	raylib.SetWindowSize(i32(w), i32(h))
	update_screen_scale()
}

handle_menu_input :: proc(state: ^Game_State) {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		state.menu_selection = 1 - state.menu_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			state.menu_selection = 1 - state.menu_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		play_sfx(state.audio.ui_confirm)
		init_player(state)
		update_camera(state)
		state.phase = .Playing
	}
}

init_player :: proc(state: ^Game_State) {
	if state.menu_selection == 0 {
		// Sheryl
		state.player = Player {
			pos              = state.spawn_pos,
			sprite_sheet     = state.sheryl_move_tex,
			idle_sheet       = state.sheryl_idle_tex,
			frame_count      = 3,
			idle_frame_count = 4,
			hp               = PLAYER_HP,
			weapon           = .Blaster,
			ammo             = BLASTER_MAX_AMMO,
		}
	} else {
		// Benny
		state.player = Player {
			pos              = state.spawn_pos,
			sprite_sheet     = state.benny_move_tex,
			idle_sheet       = state.benny_idle_tex,
			frame_count      = 3,
			idle_frame_count = 5,
			hp               = PLAYER_HP,
			weapon           = .Blaster,
			ammo             = BLASTER_MAX_AMMO,
		}
	}
}

draw_character_select :: proc(state: ^Game_State) {
	// Title
	title_size: f32 = 28
	title_w := raylib.MeasureTextEx(state.font, "CHOOSE YOUR CHARACTER", title_size, 1).x
	title_x := (f32(SCREEN_WIDTH) - title_w) / 2
	raylib.DrawTextEx(state.font, "CHOOSE YOUR CHARACTER", {title_x, 60}, title_size, 1, {220, 210, 240, 255})

	option_size: f32 = 22
	PREVIEW_SIZE :: 48

	// Sheryl
	{
		y: f32 = 140
		color: raylib.Color = state.menu_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		preview_x := f32(SCREEN_WIDTH) / 2 - 60
		src := raylib.Rectangle{0, 0, f32(SPRITE_SRC_SIZE), f32(SPRITE_SRC_SIZE)}
		dst := raylib.Rectangle{preview_x, y - 14, PREVIEW_SIZE, PREVIEW_SIZE}
		raylib.DrawTexturePro(state.sheryl_idle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		name_x := preview_x + PREVIEW_SIZE + 12
		if state.menu_selection == 0 {
			raylib.DrawTextEx(state.font, ">", {name_x - 18, y}, option_size, 1, color)
		}
		raylib.DrawTextEx(state.font, "SHERYL", {name_x, y}, option_size, 1, color)
	}

	// Benny
	{
		y: f32 = 210
		color: raylib.Color = state.menu_selection == 1 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		preview_x := f32(SCREEN_WIDTH) / 2 - 60
		src := raylib.Rectangle{0, 0, f32(SPRITE_SRC_SIZE), f32(SPRITE_SRC_SIZE)}
		dst := raylib.Rectangle{preview_x, y - 14, PREVIEW_SIZE, PREVIEW_SIZE}
		raylib.DrawTexturePro(state.benny_idle_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		name_x := preview_x + PREVIEW_SIZE + 12
		if state.menu_selection == 1 {
			raylib.DrawTextEx(state.font, ">", {name_x - 18, y}, option_size, 1, color)
		}
		raylib.DrawTextEx(state.font, "BENNY", {name_x, y}, option_size, 1, color)
	}
}

// Returns 0=none, 1=restart, 2=quit
handle_game_over_input :: proc(state: ^Game_State) -> i32 {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		state.game_over_selection = 1 - state.game_over_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			state.game_over_selection = 1 - state.game_over_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		play_sfx(state.audio.ui_confirm)
		return state.game_over_selection == 0 ? 1 : 2
	}
	return 0
}

draw_game_over :: proc(state: ^Game_State) {
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
	title_w := raylib.MeasureTextEx(state.font, "GAME OVER", title_size, 1).x
	title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
	title_y := f32(PANEL_Y) + 15
	raylib.DrawTextEx(state.font, "GAME OVER", {title_x, title_y}, title_size, 1, {220, 50, 50, 255})

	// Menu options
	option_size: f32 = 20

	// Restart
	restart_w := raylib.MeasureTextEx(state.font, "RESTART", option_size, 1).x
	restart_x := f32(PANEL_X) + (f32(PANEL_W) - restart_w) / 2
	restart_y := f32(PANEL_Y) + 65
	restart_color: raylib.Color = state.game_over_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
	if state.game_over_selection == 0 {
		raylib.DrawTextEx(state.font, ">", {restart_x - 18, restart_y}, option_size, 1, restart_color)
	}
	raylib.DrawTextEx(state.font, "RESTART", {restart_x, restart_y}, option_size, 1, restart_color)

	// Quit
	quit_w := raylib.MeasureTextEx(state.font, "QUIT", option_size, 1).x
	quit_x := f32(PANEL_X) + (f32(PANEL_W) - quit_w) / 2
	quit_y := f32(PANEL_Y) + 95
	quit_color: raylib.Color = state.game_over_selection == 0 ? {180, 180, 180, 255} : {255, 220, 50, 255}
	if state.game_over_selection == 1 {
		raylib.DrawTextEx(state.font, ">", {quit_x - 18, quit_y}, option_size, 1, quit_color)
	}
	raylib.DrawTextEx(state.font, "QUIT", {quit_x, quit_y}, option_size, 1, quit_color)
}

// Returns 0=none, 1=continue(restart), 2=quit
handle_boss_victory_input :: proc(state: ^Game_State) -> i32 {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		state.boss_victory_selection = 1 - state.boss_victory_selection
	}

	confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)

	if raylib.IsGamepadAvailable(0) {
		if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			state.boss_victory_selection = 1 - state.boss_victory_selection
		}
		if raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
	}

	if confirmed {
		play_sfx(state.audio.ui_confirm)
		return state.boss_victory_selection == 0 ? 1 : 2
	}
	return 0
}

draw_boss_victory :: proc(state: ^Game_State) {
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
	title_w := raylib.MeasureTextEx(state.font, "You captured Monroe!", title_size, 1).x
	title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
	title_y := f32(PANEL_Y) + 15
	raylib.DrawTextEx(state.font, "You captured Monroe!", {title_x, title_y}, title_size, 1, {255, 220, 50, 255})

	// Menu options
	option_size: f32 = 20

	// Continue
	continue_w := raylib.MeasureTextEx(state.font, "CONTINUE", option_size, 1).x
	continue_x := f32(PANEL_X) + (f32(PANEL_W) - continue_w) / 2
	continue_y := f32(PANEL_Y) + 65
	continue_color: raylib.Color = state.boss_victory_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
	if state.boss_victory_selection == 0 {
		raylib.DrawTextEx(state.font, ">", {continue_x - 18, continue_y}, option_size, 1, continue_color)
	}
	raylib.DrawTextEx(state.font, "CONTINUE", {continue_x, continue_y}, option_size, 1, continue_color)

	// Quit
	quit_w := raylib.MeasureTextEx(state.font, "QUIT", option_size, 1).x
	quit_x := f32(PANEL_X) + (f32(PANEL_W) - quit_w) / 2
	quit_y := f32(PANEL_Y) + 95
	quit_color: raylib.Color = state.boss_victory_selection == 0 ? {180, 180, 180, 255} : {255, 220, 50, 255}
	if state.boss_victory_selection == 1 {
		raylib.DrawTextEx(state.font, ">", {quit_x - 18, quit_y}, option_size, 1, quit_color)
	}
	raylib.DrawTextEx(state.font, "QUIT", {quit_x, quit_y}, option_size, 1, quit_color)
}

// Returns 0=none, 1=continue, 2=quit
handle_pause_input :: proc(state: ^Game_State) -> i32 {
	switch state.pause_submenu {
	case .None:
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
			state.pause_selection = (state.pause_selection + 1) % 4
		}
		if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
			state.pause_selection = (state.pause_selection + 3) % 4
		}

		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
				state.pause_selection = (state.pause_selection + 1) % 4
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
				state.pause_selection = (state.pause_selection + 3) % 4
			}
		}

		confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}

		if confirmed {
			play_sfx(state.audio.ui_confirm)
			switch state.pause_selection {
			case 0:
				return 1 // Continue
			case 1:
				state.pause_submenu = .Controls
			case 2:
				state.pause_submenu = .Audio
				state.pause_audio_selection = 0
			case 3:
				state.pause_submenu = .Quit_Confirm
				state.pause_confirm_selection = 1 // Default to "No"
			}
		}

	case .Controls:
		back := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE) || raylib.IsKeyPressed(.ESCAPE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			back = true
		}
		if back {
			play_sfx(state.audio.ui_back)
			state.pause_submenu = .None
		}

	case .Audio:
		// 0=music, 1=sfx, 2=back
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
			state.pause_audio_selection = (state.pause_audio_selection + 1) % 3
		}
		if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
			state.pause_audio_selection = (state.pause_audio_selection + 2) % 3
		}

		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
				state.pause_audio_selection = (state.pause_audio_selection + 1) % 3
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
				state.pause_audio_selection = (state.pause_audio_selection + 2) % 3
			}
		}

		// Left/right to adjust volume
		VOLUME_STEP :: f32(0.1)
		adjust: f32 = 0
		if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressed(.A) {
			adjust = -VOLUME_STEP
		}
		if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D) {
			adjust = VOLUME_STEP
		}
		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
				adjust = -VOLUME_STEP
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
				adjust = VOLUME_STEP
			}
		}

		if adjust != 0 {
			switch state.pause_audio_selection {
			case 0:
				state.audio.music_volume = clamp(state.audio.music_volume + adjust, 0, 1)
			case 1:
				state.audio.sfx_volume = clamp(state.audio.sfx_volume + adjust, 0, 1)
			}
			apply_audio_volumes(&state.audio)
		}

		// Back via escape
		if raylib.IsKeyPressed(.ESCAPE) {
			play_sfx(state.audio.ui_back)
			state.pause_submenu = .None
			return 0
		}

		// Confirm on back button
		confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
		if confirmed && state.pause_audio_selection == 2 {
			play_sfx(state.audio.ui_back)
			state.pause_submenu = .None
		}

	case .Quit_Confirm:
		if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
			state.pause_confirm_selection = 1 - state.pause_confirm_selection
		}
		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) || raylib.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
				state.pause_confirm_selection = 1 - state.pause_confirm_selection
			}
		}

		back := raylib.IsKeyPressed(.ESCAPE)
		if back {
			play_sfx(state.audio.ui_back)
			state.pause_submenu = .None
			return 0
		}

		confirmed := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirmed = true
		}
		if confirmed {
			play_sfx(state.audio.ui_confirm)
			if state.pause_confirm_selection == 0 {
				return 2 // Quit
			} else {
				state.pause_submenu = .None
			}
		}
	}
	return 0
}

draw_pause_menu :: proc(state: ^Game_State) {
	// Dark overlay
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, {0, 0, 0, 150})

	switch state.pause_submenu {
	case .None:
		PANEL_W :: 220
		PANEL_H :: 190
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
		title_w := raylib.MeasureTextEx(state.font, "PAUSED", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 12
		raylib.DrawTextEx(state.font, "PAUSED", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		option_size: f32 = 20
		options := [4]cstring{"CONTINUE", "CONTROLS", "AUDIO", "QUIT"}

		for i: i32 = 0; i < 4; i += 1 {
			opt_w := raylib.MeasureTextEx(state.font, options[i], option_size, 1).x
			opt_x := f32(PANEL_X) + (f32(PANEL_W) - opt_w) / 2
			opt_y := f32(PANEL_Y) + 55 + f32(i) * 30
			color: raylib.Color = state.pause_selection == i ? {255, 220, 50, 255} : {180, 180, 180, 255}
			if state.pause_selection == i {
				raylib.DrawTextEx(state.font, ">", {opt_x - 18, opt_y}, option_size, 1, color)
			}
			raylib.DrawTextEx(state.font, options[i], {opt_x, opt_y}, option_size, 1, color)
		}

	case .Controls:
		PANEL_W :: 280
		PANEL_H :: 218
		PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
		PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

		raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
		raylib.DrawRectangleLinesEx(
			{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
			2,
			{200, 180, 220, 255},
		)

		title_size: f32 = 22
		title_w := raylib.MeasureTextEx(state.font, "CONTROLS", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 10
		raylib.DrawTextEx(state.font, "CONTROLS", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		label_size: f32 = 12
		lx: f32 = f32(PANEL_X) + 20
		ly: f32 = f32(PANEL_Y) + 42
		line_h: f32 = 18
		label_color := raylib.Color{180, 180, 180, 255}
		value_color := raylib.Color{255, 220, 50, 255}

		controls := [6][2]cstring{
			{"MOVE", "WASD"},
			{"AIM", "MOUSE"},
			{"SHOOT", "LEFT CLICK"},
			{"RELOAD", "RIGHT CLICK"},
			{"INTERACT", "E"},
			{"PAUSE", "P"},
		}

		for i := 0; i < 6; i += 1 {
			y := ly + f32(i) * line_h
			raylib.DrawTextEx(state.font, controls[i][0], {lx, y}, label_size, 1, label_color)
			raylib.DrawTextEx(state.font, controls[i][1], {lx + 130, y}, label_size, 1, value_color)
		}

		// Back button
		back_size: f32 = 16
		back_w := raylib.MeasureTextEx(state.font, "BACK", back_size, 1).x
		back_x := f32(PANEL_X) + (f32(PANEL_W) - back_w) / 2
		back_y := f32(PANEL_Y) + f32(PANEL_H) - 32
		raylib.DrawTextEx(state.font, "> BACK", {back_x - 18, back_y}, back_size, 1, {255, 220, 50, 255})

	case .Audio:
		PANEL_W :: 260
		PANEL_H :: 160
		PANEL_X :: (SCREEN_WIDTH - PANEL_W) / 2
		PANEL_Y :: (SCREEN_HEIGHT - PANEL_H) / 2

		raylib.DrawRectangle(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, {20, 16, 30, 240})
		raylib.DrawRectangleLinesEx(
			{f32(PANEL_X), f32(PANEL_Y), f32(PANEL_W), f32(PANEL_H)},
			2,
			{200, 180, 220, 255},
		)

		title_size: f32 = 22
		title_w := raylib.MeasureTextEx(state.font, "AUDIO", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 10
		raylib.DrawTextEx(state.font, "AUDIO", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		label_size: f32 = 14
		lx: f32 = f32(PANEL_X) + 20
		label_color := raylib.Color{180, 180, 180, 255}
		selected_color := raylib.Color{255, 220, 50, 255}

		SLIDER_X :: f32(PANEL_X) + 100
		SLIDER_W :: f32(120)
		SLIDER_H :: f32(8)
		KNOB_R :: f32(5)

		// Music volume slider
		{
			y: f32 = f32(PANEL_Y) + 50
			color: raylib.Color = state.pause_audio_selection == 0 ? selected_color : label_color
			if state.pause_audio_selection == 0 {
				raylib.DrawTextEx(state.font, ">", {lx - 14, y - 2}, label_size, 1, color)
			}
			raylib.DrawTextEx(state.font, "MUSIC", {lx, y - 2}, label_size, 1, color)

			// Slider track
			track_y := y + 2
			raylib.DrawRectangleRounded({SLIDER_X, track_y, SLIDER_W, SLIDER_H}, 0.5, 4, {60, 50, 80, 255})

			// Filled portion
			fill_w := SLIDER_W * state.audio.music_volume
			if fill_w > 0 {
				raylib.DrawRectangleRounded({SLIDER_X, track_y, fill_w, SLIDER_H}, 0.5, 4, color)
			}

			// Knob
			knob_x := SLIDER_X + fill_w
			knob_y := track_y + SLIDER_H / 2
			raylib.DrawCircleV({knob_x, knob_y}, KNOB_R, color)
		}

		// SFX volume slider
		{
			y: f32 = f32(PANEL_Y) + 80
			color: raylib.Color = state.pause_audio_selection == 1 ? selected_color : label_color
			if state.pause_audio_selection == 1 {
				raylib.DrawTextEx(state.font, ">", {lx - 14, y - 2}, label_size, 1, color)
			}
			raylib.DrawTextEx(state.font, "SFX", {lx, y - 2}, label_size, 1, color)

			// Slider track
			track_y := y + 2
			raylib.DrawRectangleRounded({SLIDER_X, track_y, SLIDER_W, SLIDER_H}, 0.5, 4, {60, 50, 80, 255})

			// Filled portion
			fill_w := SLIDER_W * state.audio.sfx_volume
			if fill_w > 0 {
				raylib.DrawRectangleRounded({SLIDER_X, track_y, fill_w, SLIDER_H}, 0.5, 4, color)
			}

			// Knob
			knob_x := SLIDER_X + fill_w
			knob_y := track_y + SLIDER_H / 2
			raylib.DrawCircleV({knob_x, knob_y}, KNOB_R, color)
		}

		// Back button
		{
			back_size: f32 = 16
			back_color: raylib.Color = state.pause_audio_selection == 2 ? selected_color : label_color
			back_w := raylib.MeasureTextEx(state.font, "BACK", back_size, 1).x
			back_x := f32(PANEL_X) + (f32(PANEL_W) - back_w) / 2
			back_y := f32(PANEL_Y) + f32(PANEL_H) - 32
			if state.pause_audio_selection == 2 {
				raylib.DrawTextEx(state.font, ">", {back_x - 18, back_y}, back_size, 1, back_color)
			}
			raylib.DrawTextEx(state.font, "BACK", {back_x, back_y}, back_size, 1, back_color)
		}

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
		title_w := raylib.MeasureTextEx(state.font, "ARE YOU SURE?", title_size, 1).x
		title_x := f32(PANEL_X) + (f32(PANEL_W) - title_w) / 2
		title_y := f32(PANEL_Y) + 15
		raylib.DrawTextEx(state.font, "ARE YOU SURE?", {title_x, title_y}, title_size, 1, {220, 210, 240, 255})

		option_size: f32 = 20

		// Yes
		yes_w := raylib.MeasureTextEx(state.font, "YES", option_size, 1).x
		yes_x := f32(PANEL_X) + (f32(PANEL_W) - yes_w) / 2
		yes_y := f32(PANEL_Y) + 60
		yes_color: raylib.Color = state.pause_confirm_selection == 0 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		if state.pause_confirm_selection == 0 {
			raylib.DrawTextEx(state.font, ">", {yes_x - 18, yes_y}, option_size, 1, yes_color)
		}
		raylib.DrawTextEx(state.font, "YES", {yes_x, yes_y}, option_size, 1, yes_color)

		// No
		no_w := raylib.MeasureTextEx(state.font, "NO", option_size, 1).x
		no_x := f32(PANEL_X) + (f32(PANEL_W) - no_w) / 2
		no_y := f32(PANEL_Y) + 90
		no_color: raylib.Color = state.pause_confirm_selection == 1 ? {255, 220, 50, 255} : {180, 180, 180, 255}
		if state.pause_confirm_selection == 1 {
			raylib.DrawTextEx(state.font, ">", {no_x - 18, no_y}, option_size, 1, no_color)
		}
		raylib.DrawTextEx(state.font, "NO", {no_x, no_y}, option_size, 1, no_color)
	}
}

reset_game :: proc(state: ^Game_State) {
	stop_weapon_loops(&state.audio)
	stop_sfx(state.audio.footsteps)

	// Transition back to the first map
	transition_to_map(state, "home_base.map")

	// Reset player state — preserve identity fields (sprite_sheet, frame_count, etc.)
	state.player.aim_dir = {0, 0}
	state.player.facing_left = false
	state.player.weapon = .Blaster
	state.player.ammo = BLASTER_MAX_AMMO
	state.player.blaster_angle = 0
	state.player.fire_cooldown = 0
	state.player.hp = PLAYER_HP
	state.player.invincibility_timer = 0
	state.player.blaster_recoil = 0

	state.enemies_cleared = false
	state.game_over = false
	state.game_over_selection = 0
	state.boss_victory = false
	state.boss_victory_selection = 0
	state.paused = false
	state.pause_submenu = .None

	// Reset dialogue state for new map
	state.dialogue.active = false
	state.dialogue.completed = false
	state.dialogue.current_line = 0
	state.dialogue.words_revealed = 0

	update_camera(state)
}


check_door_transition :: proc(state: ^Game_State) -> string {
	if !state.enemies_cleared {
		return ""
	}

	center_x := int(state.player.pos.x) / TILE_SIZE
	center_y := int(state.player.pos.y - f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE

	if center_y < 0 || center_y >= state.map_data.height {
		return ""
	}
	if center_x < 0 || center_x >= len(state.map_data.grid[center_y]) {
		return ""
	}

	cell := state.map_data.grid[center_y][center_x]
	if td, ok := state.map_data.metadata[cell.symbol]; ok {
		if len(td.to_room) > 0 {
			// Check all conditions before allowing transition
			if strings.contains(td.condition, "has_key") && !state.player.has_key {
				return ""
			}
			if strings.contains(td.condition, ".dialg") && !state.dialogue.completed {
				return ""
			}
			// If door dialogue needs to be shown, start it instead of transitioning
			if state.door_dialogue.loaded && !state.door_dialogue.completed && !state.dialogue.completed {
				if !state.door_dialogue.active {
					start_dialogue(&state.door_dialogue)
				}
				return ""
			}
			// Wait for door animation to finish
			if state.door_unlocked && state.door_anim_frame < 2 {
				return ""
			}
			return td.to_room
		}
	}

	return ""
}

transition_to_map :: proc(state: ^Game_State, map_name: string) {
	stop_weapon_loops(&state.audio)
	stop_sfx(state.audio.footsteps)

	// Switch music based on destination map
	switch_music(&state.audio, map_name == "arena.map")

	// Build path relative to current map directory
	map_path := strings.concatenate({"assets/maps/", map_name})
	defer delete(map_path)

	map_bytes, map_read_ok := read_entire_file(map_path)
	if !map_read_ok {
		fmt.eprintln("Failed to load map:", map_path)
		return
	}
	new_map, map_ok := dm.parse_map(string(map_bytes))
	delete(map_bytes)
	if !map_ok {
		fmt.eprintln("Failed to parse map:", map_path)
		return
	}

	// Unload old tile textures
	for _, &textures in state.tile_textures {
		for &tex in textures {
			raylib.UnloadTexture(tex)
		}
		delete(textures)
	}
	delete(state.tile_textures)

	// Destroy old map
	dm.destroy_map(&state.map_data)
	state.map_data = new_map
	state.current_map_name = map_name
	find_exit_door(state)

	// Load new tile textures
	state.tile_textures = make(map[u8][dynamic]raylib.Texture2D)
	for sym, td in state.map_data.metadata {
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
		state.tile_textures[sym] = textures
	}

	// Assign random tile variants for 'w' cells
	if w_texs, ok := state.tile_textures['w']; ok {
		num_variants := len(w_texs)
		if num_variants > 1 {
			for &row in state.map_data.grid {
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
	for row, y in state.map_data.grid {
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

	state.spawn_pos = {spawn_x, spawn_y}

	// Reset player to new spawn
	state.player.pos = state.spawn_pos
	state.player.move_dir = {0, 0}
	state.player.current_frame = 0
	state.player.anim_timer = 0
	state.player.knockback_vel = {0, 0}

	// Clear projectiles and particles
	for &proj in state.projectiles {
		proj.active = false
	}
	for &part in state.particles {
		part.active = false
	}
	for &fp in state.flame_particles {
		fp.active = false
	}
	for &beam in state.laser_beams {
		beam.active = false
	}
	for &crate in state.health_crates {
		crate.active = false
	}

	// Re-init enemies, NPCs, and signs
	for &enemy in state.enemies {
		enemy = {}
	}
	for &npc in state.npcs {
		npc = {}
	}
	for &sign in state.signs {
		sign = {}
	}
	init_enemies(state)
	init_npcs(state)
	init_signs(state)
	init_arena(state)
	state.sign_dialogue.active = false
	state.sign_dialogue.completed = false

	state.enemies_cleared = false
	state.door_locked_msg_timer = 0
	state.door_unlocked = false
	state.door_anim_timer = 0
	state.door_anim_frame = 0
	state.player.has_key = false
	update_camera(state)
}

find_exit_door :: proc(state: ^Game_State) {
	state.has_exit_door = false
	for row, y in state.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'd' {
				if td, ok := state.map_data.metadata['d']; ok {
					if len(td.to_room) > 0 {
						state.exit_door_pos = {
							f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2,
							f32(y * TILE_SIZE) + f32(TILE_SIZE) / 2,
						}
						state.has_exit_door = true
						return
					}
				}
			}
		}
	}
}

COMPASS_CX :: 20.0
COMPASS_CY :: 20.0

draw_exit_compass :: proc(state: ^Game_State) {
	if !state.has_exit_door {
		return
	}
	if state.current_map_name == "arena.map" {
		return
	}
	if state.game_over || state.boss_victory || state.paused {
		return
	}

	// Direction from player to door in world space
	player_center := raylib.Vector2{state.player.pos.x, state.player.pos.y - f32(SPRITE_DST_SIZE) / 2}
	dir := state.exit_door_pos - player_center
	dist := math.sqrt(dir.x * dir.x + dir.y * dir.y)
	if dist < 1 {
		return
	}

	// Angle in degrees
	angle := math.atan2(dir.y, dir.x) * (180.0 / math.PI)

	src := raylib.Rectangle{0, 0, 16, 16}
	dst := raylib.Rectangle{COMPASS_CX, COMPASS_CY, f32(SPRITE_DST_SIZE), f32(SPRITE_DST_SIZE)}
	origin := raylib.Vector2{f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}

	raylib.DrawTexturePro(state.compass_arrow_tex, src, dst, origin, f32(angle), raylib.WHITE)
}

spawn_health_crate :: proc(state: ^Game_State, pos: raylib.Vector2) {
	for &crate in state.health_crates {
		if !crate.active {
			crate = Health_Crate {
				pos    = pos,
				active = true,
			}
			return
		}
	}
}

check_health_crate_pickup :: proc(state: ^Game_State) {
	px := state.player.pos.x - f32(PLAYER_HITBOX) / 2
	py := state.player.pos.y - f32(PLAYER_HITBOX)
	ps := f32(PLAYER_HITBOX)

	for &crate in state.health_crates {
		if !crate.active {
			continue
		}

		cs := f32(SPRITE_DST_SIZE)
		if px < crate.pos.x + cs && px + ps > crate.pos.x &&
		   py < crate.pos.y + cs && py + ps > crate.pos.y {
			state.player.hp = min(state.player.hp + HEALTH_CRATE_HEAL, PLAYER_HP)
			crate.active = false
			play_sfx(state.audio.item_pickup)
		}
	}
}

draw_health_crates :: proc(state: ^Game_State) {
	for &crate in state.health_crates {
		if !crate.active {
			continue
		}

		src := raylib.Rectangle {
			x      = 0,
			y      = 0,
			width  = f32(state.health_crate_tex.width),
			height = f32(state.health_crate_tex.height),
		}
		dst := raylib.Rectangle {
			x      = crate.pos.x,
			y      = crate.pos.y,
			width  = f32(SPRITE_DST_SIZE),
			height = f32(SPRITE_DST_SIZE),
		}
		raylib.DrawTexturePro(state.health_crate_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	}
}

init_npcs :: proc(state: ^Game_State) {
	npc_idx := 0
	for row, y in state.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'n' && npc_idx < MAX_NPCS {
				state.npcs[npc_idx] = NPC {
					pos          = {f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2, f32(y * TILE_SIZE) + f32(TILE_SIZE)},
					active       = true,
					sprite_sheet = state.npc_bunny_tex,
					frame_count  = 3,
				}
				npc_idx += 1
			}
		}
	}
}

init_signs :: proc(state: ^Game_State) {
	sign_idx := 0
	for row, y in state.map_data.grid {
		for cell, x in row {
			if cell.symbol == 's' && sign_idx < MAX_SIGNS {
				state.signs[sign_idx] = Sign {
					pos    = {f32(x * TILE_SIZE) + f32(TILE_SIZE) / 2, f32(y * TILE_SIZE) + f32(TILE_SIZE)},
					active = true,
				}
				sign_idx += 1
			}
		}
	}
}

update_npcs :: proc(state: ^Game_State, dt: f32) {
	for &npc in state.npcs {
		if !npc.active {
			continue
		}
		npc.anim_timer += dt
		if npc.anim_timer >= NPC_ANIM_FRAME_TIME {
			npc.anim_timer -= NPC_ANIM_FRAME_TIME
			npc.current_frame = (npc.current_frame + 1) % npc.frame_count
		}

		// Face the player
		if state.player.pos.x < npc.pos.x {
			npc.facing_left = true
		} else {
			npc.facing_left = false
		}
	}
}

draw_npcs :: proc(state: ^Game_State) {
	for &npc in state.npcs {
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
