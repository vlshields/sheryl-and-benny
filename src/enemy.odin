package sheryl_and_benny

import "core:math/linalg"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import "vendor:raylib"

MAX_ENEMIES :: 24
ENEMY_SPEED :: 40.0
ENEMY_DAMAGE :: 7
ENEMY_HP :: 14
ENEMY_KNOCKBACK :: 150.0
ENEMY_FLASH_TIME :: 0.12

FLY_HP :: 24
FLY_SPEED :: 30.0
FLY_HOVER_DIST :: 48.0
FLY_FIRE_COOLDOWN :: 2.0
FLY_PROJECTILE_DAMAGE :: 6
FLY_PROJECTILE_SPEED :: 70.0
FLY_KNOCKBACK :: 100.0

CRAZY_BUNNY_HP :: ENEMY_HP
CRAZY_BUNNY_SPEED :: 55.0

Enemy_Kind :: enum {
	Slug,
	Fly,
	Crazy_Bunny,
	Boss,
}

Enemy :: struct {
	pos:                raylib.Vector2,
	hp:                 i32,
	kind:               Enemy_Kind,
	sprite_sheet:       raylib.Texture2D,
	dead_tex:           raylib.Texture2D,
	frame_count:        i32,
	current_frame:      i32,
	anim_timer:         f32,
	facing_left:        bool,
	alive:              bool,
	spawn_timer:        f32,
	spawned:            bool,
	flash_timer:        f32,
	fire_cooldown:      f32,
	flame_damage_timer: f32,
	activated:          bool,
}

init_enemies :: proc(gs: ^Game_State) {
	enemy_idx := 0

	// Parse spawn_time_offset from 'e' metadata
	slug_spawn_time: f32 = 1.3
	if td, ok := gs.map_data.metadata['e']; ok {
		slug_spawn_time = parse_spawn_time(td.other)
	}

	fly_spawn_time: f32 = 1.3
	if td, ok := gs.map_data.metadata['f']; ok {
		fly_spawn_time = parse_spawn_time(td.other)
	}

	bunny_spawn_time: f32 = 1.3
	if td, ok := gs.map_data.metadata['c']; ok {
		bunny_spawn_time = parse_spawn_time(td.other)
	}

	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'e' && enemy_idx < MAX_ENEMIES {
				gs.enemies[enemy_idx] = Enemy {
					pos          = {f32(x * TILE_SIZE), f32(y * TILE_SIZE)},
					hp           = ENEMY_HP,
					kind         = .Slug,
					sprite_sheet = gs.slug_move_tex,
					dead_tex     = gs.slug_dead_tex,
					frame_count  = 2,
					alive        = true,
					spawn_timer  = slug_spawn_time,
				}
				enemy_idx += 1
			} else if cell.symbol == 'c' && enemy_idx < MAX_ENEMIES {
				gs.enemies[enemy_idx] = Enemy {
					pos          = {f32(x * TILE_SIZE), f32(y * TILE_SIZE)},
					hp           = CRAZY_BUNNY_HP,
					kind         = .Crazy_Bunny,
					sprite_sheet = gs.bunny_move_tex,
					dead_tex     = gs.bunny_dead_tex,
					frame_count  = 3,
					alive        = true,
					spawn_timer  = bunny_spawn_time,
				}
				enemy_idx += 1
			} else if cell.symbol == 'f' && enemy_idx < MAX_ENEMIES {
				gs.enemies[enemy_idx] = Enemy {
					pos          = {f32(x * TILE_SIZE), f32(y * TILE_SIZE)},
					hp           = FLY_HP,
					kind         = .Fly,
					sprite_sheet = gs.fly_move_tex,
					dead_tex     = gs.fly_dead_tex,
					frame_count  = 2,
					alive        = true,
					spawn_timer  = fly_spawn_time,
				}
				enemy_idx += 1
			}
		}
	}
}

parse_spawn_time :: proc(other: string) -> f32 {
	// Format: "spawn_point=enemy_slug,spawn_time_offset=1300"
	parts := strings.split(other, ",")
	defer delete(parts)
	for part in parts {
		kv := strings.split(strings.trim_space(part), "=")
		defer delete(kv)
		if len(kv) == 2 && strings.trim_space(kv[0]) == "spawn_time_offset" {
			val, ok := strconv.parse_f64(strings.trim_space(kv[1]))
			if ok {
				return f32(val) / 1000.0
			}
		}
	}
	return 1.3
}

are_enemies_cleared :: proc(gs: ^Game_State) -> bool {
	for &enemy in gs.enemies {
		if enemy.alive {
			return false
		}
	}
	return true
}

update_enemies :: proc(gs: ^Game_State, dt: f32) {
	any_armed := gs.player.weapon != .None

	for &enemy in gs.enemies {
		if !enemy.alive {
			continue
		}

		// Boss is updated separately by arena wave system
		if enemy.kind == .Boss {
			if enemy.flash_timer > 0 {
				enemy.flash_timer -= dt
			}
			if enemy.flame_damage_timer > 0 {
				enemy.flame_damage_timer -= dt
			}
			continue
		}

		if enemy.flash_timer > 0 {
			enemy.flash_timer -= dt
		}
		if enemy.flame_damage_timer > 0 {
			enemy.flame_damage_timer -= dt
		}

		if !enemy.spawned {
			if !any_armed {
				continue
			}
			enemy.spawn_timer -= dt
			if enemy.spawn_timer <= 0 {
				enemy.spawned = true
			}
			continue
		}

		size := f32(SPRITE_DST_SIZE)

		// Activate enemy when first seen in the camera viewport
		if !enemy.activated {
			cam := gs.camera
			view_left := cam.target.x - cam.offset.x / cam.zoom
			view_right := cam.target.x + cam.offset.x / cam.zoom
			view_top := cam.target.y - cam.offset.y / cam.zoom
			view_bottom := cam.target.y + cam.offset.y / cam.zoom

			in_view :=
				enemy.pos.x + size > view_left &&
				enemy.pos.x < view_right &&
				enemy.pos.y + size > view_top &&
				enemy.pos.y < view_bottom

			if !in_view {
				continue
			}
			enemy.activated = true
		}

		// Chase player
		nearest_dist: f32 = 999999
		nearest_dir: raylib.Vector2
		if gs.player.hp > 0 {
			diff := gs.player.pos - enemy.pos
			dist := linalg.length(diff)
			if dist > 0 {
				nearest_dist = dist
				nearest_dir = linalg.normalize(diff)
			}
		}

		if nearest_dist < 999999 {
			if enemy.kind == .Fly {
				// Fly: hover near player, stop at hover distance
				speed: f32 = FLY_SPEED
				if nearest_dist < FLY_HOVER_DIST {
					speed = 0
				}
				velocity := nearest_dir * speed * dt
				enemy.pos.x += velocity.x
				enemy.pos.y += velocity.y

				// Fire projectile at player
				if enemy.fire_cooldown <= 0 {
					spawn_enemy_projectile(&enemy, nearest_dir, &gs.projectiles)
					enemy.fire_cooldown = FLY_FIRE_COOLDOWN
				}
			} else {
				// Slug / Crazy_Bunny: chase and collide
				speed: f32 = enemy.kind == .Crazy_Bunny ? CRAZY_BUNNY_SPEED : ENEMY_SPEED
				velocity := nearest_dir * speed * dt
				inset: f32 = 1.0

				new_x := enemy.pos.x + velocity.x
				if !check_collision(
					new_x + inset,
					enemy.pos.y + inset,
					size - inset * 2,
					size - inset * 2,
					&gs.map_data,
					false,
				) {
					enemy.pos.x = new_x
				}

				new_y := enemy.pos.y + velocity.y
				if !check_collision(
					enemy.pos.x + inset,
					new_y + inset,
					size - inset * 2,
					size - inset * 2,
					&gs.map_data,
					false,
				) {
					enemy.pos.y = new_y
				}
			}

			// Update facing
			if nearest_dir.x < -0.1 {
				enemy.facing_left = true
			} else if nearest_dir.x > 0.1 {
				enemy.facing_left = false
			}
		}

		if enemy.fire_cooldown > 0 {
			enemy.fire_cooldown -= dt
		}

		update_enemy_animation(&enemy, dt)
	}
}

update_enemy_animation :: proc(enemy: ^Enemy, dt: f32) {
	enemy.anim_timer += dt
	if enemy.anim_timer >= ANIM_FRAME_TIME {
		enemy.anim_timer -= ANIM_FRAME_TIME
		enemy.current_frame = (enemy.current_frame + 1) % enemy.frame_count
	}
}

spawn_enemy_projectile :: proc(
	enemy: ^Enemy,
	dir: raylib.Vector2,
	projectiles: ^[MAX_PROJECTILES]Projectile,
) {
	center := enemy.pos + {f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}
	vel := dir * FLY_PROJECTILE_SPEED

	for &proj in projectiles {
		if !proj.active {
			proj = Projectile {
				pos      = center,
				vel      = vel,
				lifetime = PROJECTILE_LIFETIME,
				damage   = FLY_PROJECTILE_DAMAGE,
				active   = true,
				is_enemy = true,
			}
			return
		}
	}
}

check_enemy_player_collision :: proc(gs: ^Game_State) {
	if gs.player.hp <= 0 || gs.player.invincibility_timer > 0 {
		return
	}

	for &enemy in gs.enemies {
		if !enemy.alive || !enemy.spawned || enemy.kind == .Fly || enemy.kind == .Boss {
			continue
		}

		// AABB overlap — player hitbox is 8x8 at bottom-center
		ex := enemy.pos.x
		ey := enemy.pos.y
		es := f32(SPRITE_DST_SIZE)
		px := gs.player.pos.x - f32(PLAYER_HITBOX) / 2
		py := gs.player.pos.y - f32(PLAYER_HITBOX) / 2
		ps := f32(PLAYER_HITBOX)

		if ex < px + ps && ex + es > px && ey < py + ps && ey + es > py {
			gs.player.hp -= ENEMY_DAMAGE
			gs.player.invincibility_timer = PLAYER_INVINCIBILITY_TIME
			spawn_damage_text(gs, gs.player.pos, ENEMY_DAMAGE)

			// Knockback direction: enemy -> player
			diff := gs.player.pos - enemy.pos
			dist := linalg.length(diff)
			if dist > 0 {
				gs.player.knockback_vel = linalg.normalize(diff) * ENEMY_KNOCKBACK
			}
			return
		}
	}
}

check_projectile_enemy_collision :: proc(gs: ^Game_State) {
	for &proj in gs.projectiles {
		if !proj.active || proj.is_enemy {
			continue
		}

		for &enemy in gs.enemies {
			if !enemy.alive || !enemy.spawned {
				continue
			}

			// Point vs AABB
			ex := enemy.pos.x
			ey := enemy.pos.y
			s := f32(SPRITE_DST_SIZE)

			if proj.pos.x >= ex &&
			   proj.pos.x <= ex + s &&
			   proj.pos.y >= ey &&
			   proj.pos.y <= ey + s {
				enemy.hp -= proj.damage
				enemy.flash_timer = ENEMY_FLASH_TIME
				proj.active = false
				spawn_impact_particles(proj.pos, &gs.particles)

				if enemy.hp <= 0 {
					enemy.alive = false
					if gs.arena.active && rand.float32() < 0.05 {
						spawn_health_crate(gs, enemy.pos)
					}
				}
				break
			}
		}
	}
}

draw_boss_hp_bar :: proc(gs: ^Game_State) {
	if !gs.arena.boss_spawned || gs.arena.boss_defeated {
		return
	}

	// Find boss to get current HP
	boss_hp: i32 = 0
	for &enemy in gs.enemies {
		if enemy.alive && enemy.kind == .Boss {
			boss_hp = enemy.hp
			break
		}
	}

	BOSS_BAR_W: i32 = 180
	BOSS_BAR_H: i32 = 14
	BAR_X := (SCREEN_WIDTH - BOSS_BAR_W) / 2
	BAR_Y: i32 = 20
	border_color := raylib.Color{71, 50, 75, 255}
	fill_color := raylib.Color{221, 103, 76, 255}

	// Draw boss name above bar
	name_size: f32 = 14
	name_w := raylib.MeasureTextEx(gs.font, "Donald Monroe", name_size, 1).x
	name_x := (f32(SCREEN_WIDTH) - name_w) / 2
	name_y := f32(BAR_Y) - 16
	raylib.DrawTextEx(
		gs.font,
		"Donald Monroe",
		{name_x, name_y},
		name_size,
		1,
		{220, 210, 240, 255},
	)

	// Draw bar border
	raylib.DrawRectangle(BAR_X - 3, BAR_Y - 3, BOSS_BAR_W + 6, BOSS_BAR_H + 6, border_color)

	// Draw bar fill
	fill_ratio := f32(boss_hp) / f32(BOSS_HP)
	if fill_ratio < 0 {
		fill_ratio = 0
	}
	fill_w := i32(f32(BOSS_BAR_W) * fill_ratio)
	raylib.DrawRectangle(BAR_X, BAR_Y, fill_w, BOSS_BAR_H, fill_color)
}

draw_enemies :: proc(gs: ^Game_State) {
	for &enemy in gs.enemies {
		if !enemy.alive {
			// Draw dead sprite
			if enemy.spawned {
				dst := raylib.Rectangle {
					x      = enemy.pos.x,
					y      = enemy.pos.y,
					width  = f32(SPRITE_DST_SIZE),
					height = f32(SPRITE_DST_SIZE),
				}
				src_w: f32 = f32(SPRITE_SRC_SIZE)
				if enemy.facing_left {
					src_w = -src_w
				}
				src := raylib.Rectangle {
					x      = 0,
					y      = 0,
					width  = src_w,
					height = f32(SPRITE_SRC_SIZE),
				}
				raylib.DrawTexturePro(enemy.dead_tex, src, dst, {0, 0}, 0, raylib.WHITE)
			}
			continue
		}

		if !enemy.spawned {
			continue
		}

		src_w: f32 = f32(SPRITE_SRC_SIZE)
		if enemy.facing_left {
			src_w = -src_w
		}

		src := raylib.Rectangle {
			x      = f32(enemy.current_frame * SPRITE_SRC_SIZE),
			y      = 0,
			width  = src_w,
			height = f32(SPRITE_SRC_SIZE),
		}

		dst := raylib.Rectangle {
			x      = enemy.pos.x,
			y      = enemy.pos.y,
			width  = f32(SPRITE_DST_SIZE),
			height = f32(SPRITE_DST_SIZE),
		}

		if enemy.flash_timer > 0 {
			raylib.BeginShaderMode(gs.white_flash_shader)
		}
		raylib.DrawTexturePro(enemy.sprite_sheet, src, dst, {0, 0}, 0, raylib.WHITE)
		if enemy.flash_timer > 0 {
			raylib.EndShaderMode()
		}
	}
}
