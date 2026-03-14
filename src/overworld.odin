package sheryl_and_benny

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"
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

BOSS_HP :: 150
BOSS_ORBIT_SPEED :: 1.2
BOSS_FIRE_COOLDOWN :: 1.5
BOSS_PROJ_DAMAGE :: 8
BOSS_PROJ_SPEED :: 80.0
BOSS_CONTACT_DAMAGE :: 5
BOSS_KNOCKBACK :: 180.0

BOSS_SPIRAL_DURATION :: 26.0
BOSS_SPIRAL_COOLDOWN :: 20.0
BOSS_SPIRAL_FIRE_RATE :: 0.1
BOSS_SPIRAL_ARMS :: 4
BOSS_SPIRAL_ROT_SPEED :: 3.0
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
