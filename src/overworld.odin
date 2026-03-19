package sheryl_and_benny

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"
import "vendor:raylib"
import "core:fmt"


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

			// Spawn points, enemy spawns, NPCs: draw floor tile instead
			if sym == 'p' || sym == 'e' || sym == 'f' || sym == 'c' || sym == 'n' || sym == 'B' {
				if floor_textures != nil && len(floor_textures) > 0 {
					raylib.DrawTexture(
						floor_textures[0],
						i32(x * TILE_SIZE),
						i32(y * TILE_SIZE),
						raylib.WHITE,
					)
				}
				continue
			}

			// Collected tiles: draw floor instead
			if cell.collected {
				if floor_textures != nil && len(floor_textures) > 0 {
					raylib.DrawTexture(
						floor_textures[0],
						i32(x * TILE_SIZE),
						i32(y * TILE_SIZE),
						raylib.WHITE,
					)
				}
				continue
			}

			// Key and door tiles: draw floor underneath first
			if sym == 'k' || sym == 'd' {
				if floor_textures != nil && len(floor_textures) > 0 {
					raylib.DrawTexture(
						floor_textures[0],
						i32(x * TILE_SIZE),
						i32(y * TILE_SIZE),
						raylib.WHITE,
					)
				}
			}

			// Door tiles: draw specific animation frame from spritesheet
			if sym == 'd' {
				if texs, ok := &gs.tile_textures[sym]; ok {
					if len(texs) > 0 {
						tex := texs[0]
						frame := gs.door_unlocked ? gs.door_anim_frame : i32(0)
						src := raylib.Rectangle {
							x      = f32(frame * TILE_SIZE),
							y      = 0,
							width  = f32(TILE_SIZE),
							height = f32(TILE_SIZE),
						}
						dst := raylib.Rectangle {
							x      = f32(x * TILE_SIZE),
							y      = f32(y * TILE_SIZE),
							width  = f32(TILE_SIZE),
							height = f32(TILE_SIZE),
						}
						raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
					}
				}
				continue
			}

			// Draw the actual tile
			if texs, ok := &gs.tile_textures[sym]; ok {
				if len(texs) > 0 {
					idx := cell.tile_index % len(texs)
					raylib.DrawTexture(
						texs[idx],
						i32(x * TILE_SIZE),
						i32(y * TILE_SIZE),
						raylib.WHITE,
					)
				}
			} else {
				// Fallback: draw a colored rect for unknown tiles
				raylib.DrawRectangle(
					i32(f32(x * TILE_SIZE)),
					i32(f32(y * TILE_SIZE)),
					TILE_SIZE,
					TILE_SIZE,
					raylib.MAGENTA,
				)
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

	// Follow player
	target_x := gs.player.pos.x
	target_y := gs.player.pos.y - f32(SPRITE_DST_SIZE) / 2

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

WAVE_SPAWN_INTERVAL :: 0.5
WAVE_DELAY :: 3.0
WAVE_ENEMY_COUNT_MIN :: 6
WAVE_ENEMY_COUNT_MAX :: 7
TOTAL_ENEMY_WAVES :: 3
WAVE_START_DELAY :: 1.5

BOSS_HP :: 250
BOSS_ORBIT_SPEED :: 1.2
BOSS_FIRE_COOLDOWN :: 1.5
BOSS_PROJ_DAMAGE :: 8
BOSS_PROJ_SPEED :: 80.0
BOSS_CONTACT_DAMAGE :: 5
BOSS_KNOCKBACK :: 180.0

BOSS_SPIRAL_DURATION :: 26.0
BOSS_SPIRAL_COOLDOWN :: 10.0
BOSS_SPIRAL_FIRE_RATE :: 0.3
BOSS_SPIRAL_ARMS :: 6
BOSS_SPIRAL_ROT_SPEED :: 5.0
BOSS_SPIRAL_PROJ_SPEED :: 60.0
BOSS_SPIRAL_PROJ_DMG :: 4

Arena_State :: struct {
	active:               bool,
	wave:                 i32,
	wave_active:          bool,
	enemies_to_spawn:     i32,
	enemies_spawned:      i32,
	spawn_timer:          f32,
	wave_delay_timer:     f32,
	boss_spawned:         bool,
	boss_defeated:        bool,
	boss_orbit_angle:     f32,
	boss_orbit_fraction:  f32,
	boss_spiral_timer:    f32,
	boss_spiral_angle:    f32,
	boss_spiral_active:   bool,
	boss_spiral_cooldown: f32,
	boss_fire_cooldown:   f32,
}

init_arena :: proc(gs: ^Game_State) {
	gs.arena = {}
	if td, ok := gs.map_data.metadata['B']; ok {
		if strings.contains(td.other, "three_enemy_waves_cleared") {
			gs.arena.active = true
			gs.arena.wave_delay_timer = WAVE_START_DELAY
			gs.arena.boss_orbit_fraction = 0.3
		}
	}
}

update_arena_waves :: proc(gs: ^Game_State, dt: f32) {
	arena := &gs.arena
	if !arena.active {
		return
	}

	// Start wave 1 after initial delay
	if arena.wave == 0 {
		arena.wave_delay_timer -= dt
		if arena.wave_delay_timer <= 0 {
			start_wave(arena, 1)
		}
		return
	}

	// Boss AI
	if arena.boss_spawned && !arena.boss_defeated {
		update_boss(gs, dt)
	}

	// Delay between waves
	if !arena.wave_active && arena.wave_delay_timer > 0 {
		arena.wave_delay_timer -= dt
		if arena.wave_delay_timer <= 0 {
			if arena.wave < TOTAL_ENEMY_WAVES {
				start_wave(arena, arena.wave + 1)
			} else if !arena.boss_spawned {
				spawn_boss(gs)
			}
		}
		return
	}

	// Spawn enemies in current wave
	if arena.wave_active && arena.wave <= TOTAL_ENEMY_WAVES {
		if arena.enemies_spawned < arena.enemies_to_spawn {
			arena.spawn_timer -= dt
			if arena.spawn_timer <= 0 {
				spawn_wave_enemy(gs)
				arena.enemies_spawned += 1
				arena.spawn_timer = WAVE_SPAWN_INTERVAL
			}
		} else {
			// Check if all wave enemies are dead
			any_alive := false
			for &enemy in gs.enemies {
				if enemy.alive && enemy.kind != .Boss {
					any_alive = true
					break
				}
			}
			if !any_alive {
				arena.wave_active = false
				arena.wave_delay_timer = WAVE_DELAY
			}
		}
	}
}

start_wave :: proc(arena: ^Arena_State, wave_num: i32) {
	arena.wave = wave_num
	arena.wave_active = true
	arena.enemies_to_spawn = WAVE_ENEMY_COUNT_MIN + i32(rand.int_max(2))
	arena.enemies_spawned = 0
	arena.spawn_timer = 0
}

spawn_wave_enemy :: proc(gs: ^Game_State) {
	pos, ok := find_offscreen_spawn_pos(gs)
	if !ok {
		return
	}

	kind_roll := rand.int_max(3)
	kind: Enemy_Kind
	hp: i32
	sprite_sheet: raylib.Texture2D
	dead_tex: raylib.Texture2D
	frame_count: i32

	switch kind_roll {
	case 0:
		kind = .Slug
		hp = ENEMY_HP
		sprite_sheet = gs.slug_move_tex
		dead_tex = gs.slug_dead_tex
		frame_count = 2
	case 1:
		kind = .Fly
		hp = FLY_HP
		sprite_sheet = gs.fly_move_tex
		dead_tex = gs.fly_dead_tex
		frame_count = 2
	case 2:
		kind = .Crazy_Bunny
		hp = CRAZY_BUNNY_HP
		sprite_sheet = gs.bunny_move_tex
		dead_tex = gs.bunny_dead_tex
		frame_count = 3
	}

	for &enemy in gs.enemies {
		if !enemy.alive {
			enemy = Enemy {
				pos          = pos,
				hp           = hp,
				max_hp       = hp,
				kind         = kind,
				sprite_sheet = sprite_sheet,
				dead_tex     = dead_tex,
				frame_count  = frame_count,
				alive        = true,
				spawned      = true,
				activated    = true,
			}
			return
		}
	}
}

spawn_boss :: proc(gs: ^Game_State) {
	arena := &gs.arena

	// Find boss spawn position from 'B' tile in grid
	boss_pos := raylib.Vector2{0, 0}
	found := false
	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'B' {
				boss_pos = {f32(x * TILE_SIZE), f32(y * TILE_SIZE)}
				found = true
				break
			}
		}
		if found {
			break
		}
	}

	if !found {
		// Fallback: center of map
		boss_pos = {
			f32(gs.map_data.width * TILE_SIZE) / 2,
			f32(gs.map_data.height * TILE_SIZE) / 2,
		}
	}

	for &enemy in gs.enemies {
		if !enemy.alive {
			enemy = Enemy {
				pos          = boss_pos,
				hp           = BOSS_HP,
				max_hp       = BOSS_HP,
				kind         = .Boss,
				sprite_sheet = gs.boss_move_tex,
				dead_tex     = gs.boss_move_tex,
				frame_count  = 3,
				alive        = true,
				spawned      = true,
				activated    = true,
			}
			arena.boss_spawned = true
			arena.boss_fire_cooldown = BOSS_FIRE_COOLDOWN
			arena.boss_spiral_cooldown = BOSS_SPIRAL_COOLDOWN
			play_sfx(gs.audio.boss_warcry)
			return
		}
	}
}

update_boss :: proc(gs: ^Game_State, dt: f32) {
	arena := &gs.arena

	// Find boss enemy
	boss: ^Enemy = nil
	for &enemy in gs.enemies {
		if enemy.alive && enemy.kind == .Boss {
			boss = &enemy
			break
		}
	}

	if boss == nil {
		arena.boss_defeated = true
		return
	}

	// Orbit around player
	arena.boss_orbit_angle += BOSS_ORBIT_SPEED * dt

	// Orbit radius derived from viewport size and configurable fraction
	view_width := f32(SCREEN_WIDTH) / CAMERA_ZOOM
	orbit_radius := view_width * arena.boss_orbit_fraction

	player_center := raylib.Vector2{gs.player.pos.x, gs.player.pos.y - f32(SPRITE_DST_SIZE) / 2}
	target_x := player_center.x + math.cos(arena.boss_orbit_angle) * orbit_radius
	target_y := player_center.y + math.sin(arena.boss_orbit_angle) * orbit_radius

	// Smooth follow toward orbit position
	diff := raylib.Vector2{target_x, target_y} - boss.pos
	dist := linalg.length(diff)
	if dist > 1 {
		move_speed: f32 = 100.0
		step := min(move_speed * dt, dist)
		velocity := linalg.normalize(diff) * step
		size := f32(SPRITE_DST_SIZE)
		inset: f32 = 1.0

		new_x := boss.pos.x + velocity.x
		if !check_collision(new_x + inset, boss.pos.y + inset, size - inset * 2, size - inset * 2, &gs.map_data, false) {
			boss.pos.x = new_x
		}

		new_y := boss.pos.y + velocity.y
		if !check_collision(boss.pos.x + inset, new_y + inset, size - inset * 2, size - inset * 2, &gs.map_data, false) {
			boss.pos.y = new_y
		}
	}

	// Facing direction toward player
	dir_to_player := player_center - boss.pos
	dir_len := linalg.length(dir_to_player)
	if dir_len > 0 {
		dir_to_player /= dir_len
	}
	if dir_to_player.x < -0.1 {
		boss.facing_left = true
	} else if dir_to_player.x > 0.1 {
		boss.facing_left = false
	}

	// Bullet hell spiral
	if arena.boss_spiral_active {
		arena.boss_spiral_timer -= dt
		arena.boss_spiral_angle += BOSS_SPIRAL_ROT_SPEED * dt
		arena.boss_fire_cooldown -= dt

		if arena.boss_fire_cooldown <= 0 {
			center := boss.pos + {f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}
			for arm := 0; arm < BOSS_SPIRAL_ARMS; arm += 1 {
				angle :=
					arena.boss_spiral_angle + f32(arm) * (2.0 * math.PI / f32(BOSS_SPIRAL_ARMS))
				dir := raylib.Vector2{math.cos(angle), math.sin(angle)}
				spawn_arena_projectile(
					center,
					dir,
					BOSS_SPIRAL_PROJ_SPEED,
					BOSS_SPIRAL_PROJ_DMG,
					&gs.projectiles,
				)
			}
			arena.boss_fire_cooldown = BOSS_SPIRAL_FIRE_RATE
		}

		if arena.boss_spiral_timer <= 0 {
			arena.boss_spiral_active = false
			arena.boss_spiral_cooldown = BOSS_SPIRAL_COOLDOWN
			arena.boss_fire_cooldown = BOSS_FIRE_COOLDOWN
		}
	} else {
		// Normal shooting toward player
		arena.boss_fire_cooldown -= dt
		if arena.boss_fire_cooldown <= 0 && dir_len > 0 {
			center := boss.pos + {f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}
			spawn_arena_projectile(
				center,
				dir_to_player,
				BOSS_PROJ_SPEED,
				BOSS_PROJ_DAMAGE,
				&gs.projectiles,
			)
			arena.boss_fire_cooldown = BOSS_FIRE_COOLDOWN
		}

		// Countdown to next spiral
		arena.boss_spiral_cooldown -= dt
		if arena.boss_spiral_cooldown <= 0 {
			arena.boss_spiral_active = true
			arena.boss_spiral_timer = BOSS_SPIRAL_DURATION
			arena.boss_spiral_angle = 0
			arena.boss_fire_cooldown = BOSS_SPIRAL_FIRE_RATE
			play_sfx(gs.audio.boss_warcry)
		}
	}

	update_enemy_animation(boss, dt)
}

spawn_arena_projectile :: proc(
	from: raylib.Vector2,
	dir: raylib.Vector2,
	speed: f32,
	damage: i32,
	projectiles: ^[MAX_PROJECTILES]Projectile,
) {
	vel := dir * speed
	for &proj in projectiles {
		if !proj.active {
			proj = Projectile {
				pos      = from,
				vel      = vel,
				lifetime = PROJECTILE_LIFETIME,
				damage   = damage,
				active   = true,
				is_enemy = true,
			}
			return
		}
	}
}

find_offscreen_spawn_pos :: proc(gs: ^Game_State) -> (raylib.Vector2, bool) {
	cam := gs.camera
	view_left := cam.target.x - cam.offset.x / cam.zoom
	view_right := cam.target.x + cam.offset.x / cam.zoom
	view_top := cam.target.y - cam.offset.y / cam.zoom
	view_bottom := cam.target.y + cam.offset.y / cam.zoom

	candidates: [dynamic]raylib.Vector2
	defer delete(candidates)

	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol != 'w' {
				continue
			}
			px := f32(x * TILE_SIZE)
			py := f32(y * TILE_SIZE)

			in_view :=
				px + f32(TILE_SIZE) > view_left &&
				px < view_right &&
				py + f32(TILE_SIZE) > view_top &&
				py < view_bottom

			if !in_view {
				append(&candidates, raylib.Vector2{px, py})
			}
		}
	}

	if len(candidates) == 0 {
		return {}, false
	}
	return candidates[rand.int_max(len(candidates))], true
}





Dialogue_Line :: struct {
	speaker:      string,
	text:         string,
	choices:      [MAX_CHOICES]string,
	choice_count: int,
}

Dialogue_State :: struct {
	lines:            [MAX_DIALOGUE_LINES]Dialogue_Line,
	line_count:       int,
	current_line:     int,
	active:           bool,
	words_revealed:   int,
	word_timer:       f32,
	word_count:       int,
	loaded:           bool,
	completed:        bool,
	selected_choice:  int,
	chosen:           int,
}

parse_dialogue_file :: proc(path: string) -> (state: Dialogue_State, ok: bool) {
	data, read_ok := read_entire_file(path)
	if !read_ok {
		fmt.eprintln("could not open dialogue file:", path)
		return {}, false
	}
	defer delete(data)

	content := string(data)
	in_dialogue := false
	line_idx := 0
	current_text: strings.Builder
	current_speaker := ""
	has_content := false

	for line in strings.split_lines_iterator(&content) {
		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 {
			continue
		}
		if trimmed[0] == '*' {
			continue
		}
		if trimmed == "[START]" {
			in_dialogue = true
			continue
		}
		if trimmed == "[END]" {
			// Flush any remaining content
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
			}
			strings.builder_destroy(&current_text)
			break
		}
		if !in_dialogue {
			continue
		}
		if trimmed == "[PRESS ENTER]" {
			// Flush current line
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
				strings.builder_destroy(&current_text)
				current_text = {}
				has_content = false
			}
			continue
		}

		// Check for choice line: [CHOICE1] [CHOICE2] ...
		if trimmed[0] == '[' && trimmed != "[START]" && trimmed != "[END]" && trimmed != "[PRESS ENTER]" {
			// Flush current text as a line first
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
				strings.builder_destroy(&current_text)
				current_text = {}
				has_content = false
			}
			// Parse choices from brackets
			if line_idx < MAX_DIALOGUE_LINES {
				choice_line: Dialogue_Line
				choice_line.speaker = strings.clone(current_speaker)
				choice_line.text = ""
				remaining := trimmed
				for choice_line.choice_count < MAX_CHOICES {
					open := strings.index(remaining, "[")
					if open < 0 {
						break
					}
					close := strings.index(remaining[open:], "]")
					if close < 0 {
						break
					}
					choice_text := remaining[open + 1:open + close]
					choice_line.choices[choice_line.choice_count] = strings.clone(choice_text)
					choice_line.choice_count += 1
					remaining = remaining[open + close + 1:]
				}
				state.lines[line_idx] = choice_line
				line_idx += 1
			}
			continue
		}

		// Parse "SPEAKER: text"
		colon_idx := strings.index(trimmed, ": ")
		if colon_idx >= 0 {
			current_speaker = trimmed[:colon_idx]
			text_part := trimmed[colon_idx + 2:]
			if has_content {
				strings.write_byte(&current_text, ' ')
			}
			strings.write_string(&current_text, text_part)
			has_content = true
		}
	}

	state.line_count = line_idx
	state.loaded = true
	return state, line_idx > 0
}

start_dialogue :: proc(dialogue: ^Dialogue_State) {
	if !dialogue.loaded || dialogue.line_count == 0 {
		return
	}
	dialogue.active = true
	dialogue.current_line = 0
	dialogue.words_revealed = 0
	dialogue.word_timer = 0
	dialogue.completed = false
	dialogue.selected_choice = 0
	dialogue.chosen = -1
	dialogue.word_count = count_words(dialogue.lines[0].text)
}

update_dialogue :: proc(dialogue: ^Dialogue_State, dt: f32, audio: ^Audio_State) {
	if !dialogue.active {
		return
	}

	cur_line := dialogue.lines[dialogue.current_line]
	has_choices := cur_line.choice_count > 0

	// Choice lines: handle left/right selection and confirm
	if has_choices {
		move_left := raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressed(.A)
		move_right := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D)
		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
				move_left = true
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
				move_right = true
			}
		}
		if move_left && dialogue.selected_choice > 0 {
			dialogue.selected_choice -= 1
			play_sfx(audio.ui_back)
		}
		if move_right && dialogue.selected_choice < cur_line.choice_count - 1 {
			dialogue.selected_choice += 1
			play_sfx(audio.ui_back)
		}

		confirm := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.E) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirm = true
		}
		if confirm {
			play_sfx(audio.ui_confirm)
			dialogue.chosen = dialogue.selected_choice
			dialogue.active = false
			dialogue.completed = true
		}
		return
	}

	all_revealed := dialogue.words_revealed >= dialogue.word_count

	// Advance input: ENTER, E, or SPACE
	advance := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.E) || raylib.IsKeyPressed(.SPACE)
	if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
		advance = true
	}

	if advance {
		if !all_revealed {
			// Reveal all words instantly
			dialogue.words_revealed = dialogue.word_count
		} else {
			// Go to next line
			play_sfx(audio.ui_confirm)
			dialogue.current_line += 1
			if dialogue.current_line >= dialogue.line_count {
				dialogue.active = false
				dialogue.completed = true
				return
			}
			dialogue.words_revealed = 0
			dialogue.word_timer = 0
			dialogue.selected_choice = 0
			dialogue.word_count = count_words(dialogue.lines[dialogue.current_line].text)
		}
		return
	}

	// Word reveal timer
	if !all_revealed {
		dialogue.word_timer += dt
		if dialogue.word_timer >= WORD_REVEAL_INTERVAL {
			dialogue.word_timer -= WORD_REVEAL_INTERVAL
			dialogue.words_revealed += 1
		}
	}
}

draw_dialogue :: proc(dialogue: ^Dialogue_State, font: raylib.Font) {
	if !dialogue.active {
		return
	}

	line := dialogue.lines[dialogue.current_line]

	// Box position: centered at bottom of screen
	box_x: f32 = (f32(SCREEN_WIDTH) - f32(DIALOGUE_BOX_W)) / 2
	box_y: f32 = f32(SCREEN_HEIGHT) - f32(DIALOGUE_BOX_H) - 10

	// Background
	bg_color := raylib.Color{15, 12, 25, 230}
	border_color := raylib.Color{200, 180, 220, 255}
	raylib.DrawRectangle(i32(box_x), i32(box_y), DIALOGUE_BOX_W, DIALOGUE_BOX_H, bg_color)
	raylib.DrawRectangleLinesEx(
		{box_x, box_y, f32(DIALOGUE_BOX_W), f32(DIALOGUE_BOX_H)},
		2,
		border_color,
	)

	// Speaker name
	speaker_color := raylib.Color{255, 220, 50, 255}
	text_color := raylib.Color{220, 215, 235, 255}
	speaker_cstr := strings.clone_to_cstring(line.speaker)
	defer delete(speaker_cstr)
	raylib.DrawTextEx(
		font,
		speaker_cstr,
		{box_x + f32(DIALOGUE_BOX_MARGIN), box_y + 6},
		DIALOGUE_SPEAKER_SIZE,
		1,
		speaker_color,
	)

	// Build revealed text (word by word)
	revealed := get_revealed_text(line.text, dialogue.words_revealed)
	revealed_cstr := strings.clone_to_cstring(revealed)
	defer delete(revealed_cstr)

	// Text area below speaker name, with wrapping
	text_x := box_x + f32(DIALOGUE_BOX_MARGIN)
	text_y := box_y + 28
	max_w := f32(DIALOGUE_BOX_W) - f32(DIALOGUE_BOX_MARGIN) * 2

	draw_wrapped_text(font, revealed_cstr, text_x, text_y, max_w, DIALOGUE_TEXT_SIZE, text_color)

	// Choice buttons or "Press ENTER" prompt
	if line.choice_count > 0 {
		draw_dialogue_choices(dialogue, font, box_x, box_y)
	} else if dialogue.words_revealed >= dialogue.word_count {
		prompt_size: f32 = 12
		pulse_alpha := u8(150 + i32(105 * math.sin(f32(raylib.GetTime()) * 3.0)))
		if pulse_alpha < 150 {
			pulse_alpha = 150
		}
		prompt_color := raylib.Color{180, 180, 180, pulse_alpha}
		prompt_x := box_x + f32(DIALOGUE_BOX_W) - 90
		prompt_y := box_y + f32(DIALOGUE_BOX_H) - 18
		raylib.DrawTextEx(font, "[ENTER]", {prompt_x, prompt_y}, prompt_size, 1, prompt_color)
	}
}

// Check if the player is close enough to any NPC to interact
find_nearby_npc :: proc(player: ^Player, npcs: ^[MAX_NPCS]NPC) -> int {
	for &npc, i in npcs {
		if !npc.active {
			continue
		}
		dx := player.pos.x - npc.pos.x
		dy := (player.pos.y - f32(SPRITE_DST_SIZE) / 2) - (npc.pos.y - f32(SPRITE_DST_SIZE) / 2)
		dist := dx * dx + dy * dy
		if dist < NPC_INTERACT_DIST * NPC_INTERACT_DIST {
			return i
		}
	}
	return -1
}

draw_interact_prompt :: proc(npc: ^NPC) {
	// Hovering gold arrow above NPC
	hover_offset := math.sin(f32(raylib.GetTime()) * 3.0) * 2.0
	color := raylib.Color{255, 220, 50, 230}
	cx := npc.pos.x
	tip_y := npc.pos.y - f32(SPRITE_DST_SIZE) - 10 + hover_offset
	half_w: f32 = 4
	height: f32 = 6
	raylib.DrawTriangle(
		{cx, tip_y + height},
		{cx + half_w, tip_y},
		{cx - half_w, tip_y},
		color,
	)
}

// Helper: count words in a string
count_words :: proc(text: string) -> int {
	count := 0
	in_word := false
	for c in text {
		if c == ' ' || c == '\t' || c == '\n' {
			in_word = false
		} else if !in_word {
			in_word = true
			count += 1
		}
	}
	return count
}

// Helper: get the first N words of a string
get_revealed_text :: proc(text: string, n: int) -> string {
	if n <= 0 {
		return ""
	}
	count := 0
	in_word := false
	for i := 0; i < len(text); i += 1 {
		c := text[i]
		if c == ' ' || c == '\t' || c == '\n' {
			in_word = false
		} else if !in_word {
			in_word = true
			count += 1
			if count > n {
				// Return up to the space before this word
				return text[:i - 1] if i > 0 else ""
			}
		}
	}
	return text
}

// Helper: draw text with word wrapping
draw_wrapped_text :: proc(
	font: raylib.Font,
	text: cstring,
	x, y, max_width, size: f32,
	color: raylib.Color,
) {
	// Use raylib's built-in word wrap by drawing character by character
	odin_text := string(text)
	words := strings.split(odin_text, " ")
	defer delete(words)

	cur_x := x
	cur_y := y
	space_w := raylib.MeasureTextEx(font, " ", size, 1).x

	for word, i in words {
		if len(word) == 0 {
			continue
		}
		word_cstr := strings.clone_to_cstring(word)
		defer delete(word_cstr)
		word_w := raylib.MeasureTextEx(font, word_cstr, size, 1).x

		// Wrap to next line if needed
		if cur_x + word_w > x + max_width && cur_x > x {
			cur_x = x
			cur_y += size + 2
		}

		raylib.DrawTextEx(font, word_cstr, {cur_x, cur_y}, size, 1, color)
		cur_x += word_w + space_w
		_ = i
	}
}

draw_dialogue_choices :: proc(dialogue: ^Dialogue_State, font: raylib.Font, box_x: f32, box_y: f32) {
	line := dialogue.lines[dialogue.current_line]
	choice_size: f32 = 12
	choice_y := box_y + f32(DIALOGUE_BOX_H) - 22
	padding: f32 = 16
	gap: f32 = 12

	// Measure total width to center choices
	total_w: f32 = 0
	for i := 0; i < line.choice_count; i += 1 {
		label := strings.clone_to_cstring(line.choices[i])
		defer delete(label)
		total_w += raylib.MeasureTextEx(font, label, choice_size, 1).x + padding * 2
		if i < line.choice_count - 1 {
			total_w += gap
		}
	}

	cur_x := box_x + (f32(DIALOGUE_BOX_W) - total_w) / 2

	for i := 0; i < line.choice_count; i += 1 {
		label := strings.clone_to_cstring(line.choices[i])
		defer delete(label)
		text_w := raylib.MeasureTextEx(font, label, choice_size, 1).x
		btn_w := text_w + padding * 2
		btn_h: f32 = 18

		selected := i == dialogue.selected_choice
		bg := raylib.Color{255, 220, 50, 220} if selected else raylib.Color{60, 50, 80, 200}
		text_col := raylib.Color{15, 12, 25, 255} if selected else raylib.Color{200, 190, 220, 255}

		raylib.DrawRectangleRounded({cur_x, choice_y, btn_w, btn_h}, 0.3, 4, bg)
		raylib.DrawTextEx(
			font,
			label,
			{cur_x + padding, choice_y + 3},
			choice_size,
			1,
			text_col,
		)

		cur_x += btn_w + gap
	}
}

destroy_dialogue :: proc(dialogue: ^Dialogue_State) {
	for i := 0; i < dialogue.line_count; i += 1 {
		delete(dialogue.lines[i].speaker)
		delete(dialogue.lines[i].text)
		for j := 0; j < dialogue.lines[i].choice_count; j += 1 {
			delete(dialogue.lines[i].choices[j])
		}
	}
	dialogue^ = {}
}

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
		play_sfx(gs.audio.ui_confirm)
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
