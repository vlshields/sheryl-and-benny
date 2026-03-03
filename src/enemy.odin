package sheryl_and_benny

import "vendor:raylib"
import "core:math/linalg"
import "core:strings"
import "core:strconv"

MAX_ENEMIES      :: 16
ENEMY_SPEED      :: 40.0
ENEMY_DAMAGE     :: 11
ENEMY_HP         :: 14
ENEMY_KNOCKBACK  :: 150.0

Enemy :: struct {
	pos:           raylib.Vector2,
	hp:            i32,
	sprite_sheet:  raylib.Texture2D,
	dead_tex:      raylib.Texture2D,
	frame_count:   i32,
	current_frame: i32,
	anim_timer:    f32,
	facing_left:   bool,
	alive:         bool,
	spawn_timer:   f32,
	spawned:       bool,
}

init_enemies :: proc(gs: ^Game_State) {
	enemy_idx := 0

	// Parse spawn_time_offset from 'e' metadata
	spawn_time: f32 = 1.3
	if td, ok := gs.map_data.metadata['e']; ok {
		spawn_time = parse_spawn_time(td.other)
	}

	for row, y in gs.map_data.grid {
		for cell, x in row {
			if cell.symbol == 'e' && enemy_idx < MAX_ENEMIES {
				gs.enemies[enemy_idx] = Enemy {
					pos          = {f32(x * TILE_SIZE), f32(y * TILE_SIZE)},
					hp           = ENEMY_HP,
					sprite_sheet = gs.slug_move_tex,
					dead_tex     = gs.slug_dead_tex,
					frame_count  = 2,
					alive        = true,
					spawn_timer  = spawn_time,
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

update_enemies :: proc(gs: ^Game_State, dt: f32) {
	any_armed := false
	for &p in gs.players {
		if p.weapon != .None {
			any_armed = true
			break
		}
	}

	for &enemy in gs.enemies {
		if !enemy.alive {
			continue
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

		// Chase nearest player
		nearest_dist: f32 = 999999
		nearest_dir: raylib.Vector2
		for &p in gs.players {
			if p.hp <= 0 {
				continue
			}
			diff := p.pos - enemy.pos
			dist := linalg.length(diff)
			if dist < nearest_dist && dist > 0 {
				nearest_dist = dist
				nearest_dir = linalg.normalize(diff)
			}
		}

		if nearest_dist < 999999 {
			velocity := nearest_dir * ENEMY_SPEED * dt
			size := f32(SPRITE_DST_SIZE)
			inset: f32 = 1.0

			// Try X axis
			new_x := enemy.pos.x + velocity.x
			if !check_collision(new_x + inset, enemy.pos.y + inset, size - inset * 2, size - inset * 2, &gs.map_data) {
				enemy.pos.x = new_x
			}

			// Try Y axis
			new_y := enemy.pos.y + velocity.y
			if !check_collision(enemy.pos.x + inset, new_y + inset, size - inset * 2, size - inset * 2, &gs.map_data) {
				enemy.pos.y = new_y
			}

			// Update facing
			if nearest_dir.x < -0.1 {
				enemy.facing_left = true
			} else if nearest_dir.x > 0.1 {
				enemy.facing_left = false
			}
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

check_enemy_player_collision :: proc(gs: ^Game_State) {
	for &enemy in gs.enemies {
		if !enemy.alive || !enemy.spawned {
			continue
		}

		for &p in gs.players {
			if p.hp <= 0 || p.invincibility_timer > 0 {
				continue
			}

			// AABB overlap
			ex := enemy.pos.x
			ey := enemy.pos.y
			px := p.pos.x
			py := p.pos.y
			s := f32(SPRITE_DST_SIZE)

			if ex < px + s && ex + s > px && ey < py + s && ey + s > py {
				p.hp -= ENEMY_DAMAGE
				p.invincibility_timer = PLAYER_INVINCIBILITY_TIME

				// Knockback direction: enemy -> player
				diff := p.pos - enemy.pos
				dist := linalg.length(diff)
				if dist > 0 {
					p.knockback_vel = linalg.normalize(diff) * ENEMY_KNOCKBACK
				}
			}
		}
	}
}

check_projectile_enemy_collision :: proc(gs: ^Game_State) {
	for &proj in gs.projectiles {
		if !proj.active {
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

			if proj.pos.x >= ex && proj.pos.x <= ex + s && proj.pos.y >= ey && proj.pos.y <= ey + s {
				enemy.hp -= 6
				proj.active = false
				spawn_impact_particles(proj.pos, &gs.particles)

				if enemy.hp <= 0 {
					enemy.alive = false
				}
				break
			}
		}
	}
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

		raylib.DrawTexturePro(enemy.sprite_sheet, src, dst, {0, 0}, 0, raylib.WHITE)
	}
}
