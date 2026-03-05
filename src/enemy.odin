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
ENEMY_FLASH_TIME :: 0.12

FLY_HP                :: 24
FLY_SPEED             :: 30.0
FLY_HOVER_DIST        :: 48.0
FLY_FIRE_COOLDOWN     :: 2.0
FLY_PROJECTILE_DAMAGE :: 6
FLY_PROJECTILE_SPEED  :: 120.0
FLY_KNOCKBACK         :: 100.0

Enemy_Kind :: enum {
	Slug,
	Fly,
}

Enemy :: struct {
	pos:           raylib.Vector2,
	hp:            i32,
	kind:          Enemy_Kind,
	sprite_sheet:  raylib.Texture2D,
	dead_tex:      raylib.Texture2D,
	frame_count:   i32,
	current_frame: i32,
	anim_timer:    f32,
	facing_left:   bool,
	alive:         bool,
	spawn_timer:   f32,
	spawned:       bool,
	flash_timer:        f32,
	fire_cooldown:      f32,
	flame_damage_timer: f32,
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

		// Only chase if enemy is within the camera viewport
		cam := gs.camera
		view_left := cam.target.x - cam.offset.x / cam.zoom
		view_right := cam.target.x + cam.offset.x / cam.zoom
		view_top := cam.target.y - cam.offset.y / cam.zoom
		view_bottom := cam.target.y + cam.offset.y / cam.zoom
		size := f32(SPRITE_DST_SIZE)

		in_view := enemy.pos.x + size > view_left && enemy.pos.x < view_right &&
			enemy.pos.y + size > view_top && enemy.pos.y < view_bottom

		if !in_view {
			continue
		}

		// Find nearest player
		nearest_dist: f32 = 999999
		nearest_dir: raylib.Vector2
		for &p in gs.players {
			if p.hp <= 0 || p.is_ai {
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
				// Slug: chase and collide
				velocity := nearest_dir * ENEMY_SPEED * dt
				inset: f32 = 1.0

				new_x := enemy.pos.x + velocity.x
				if !check_collision(new_x + inset, enemy.pos.y + inset, size - inset * 2, size - inset * 2, &gs.map_data, false) {
					enemy.pos.x = new_x
				}

				new_y := enemy.pos.y + velocity.y
				if !check_collision(enemy.pos.x + inset, new_y + inset, size - inset * 2, size - inset * 2, &gs.map_data, false) {
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

spawn_enemy_projectile :: proc(enemy: ^Enemy, dir: raylib.Vector2, projectiles: ^[MAX_PROJECTILES]Projectile) {
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
	for &enemy in gs.enemies {
		if !enemy.alive || !enemy.spawned || enemy.kind == .Fly {
			continue
		}

		for &p, pi in gs.players {
			if p.hp <= 0 || p.invincibility_timer > 0 || p.is_ai {
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

				if pi == 0 {
					spawn_damage_text(gs, p.pos, ENEMY_DAMAGE)
				}

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

			if proj.pos.x >= ex && proj.pos.x <= ex + s && proj.pos.y >= ey && proj.pos.y <= ey + s {
				enemy.hp -= proj.damage
				enemy.flash_timer = ENEMY_FLASH_TIME
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

		if enemy.flash_timer > 0 {
			raylib.BeginShaderMode(gs.white_flash_shader)
		}
		raylib.DrawTexturePro(enemy.sprite_sheet, src, dst, {0, 0}, 0, raylib.WHITE)
		if enemy.flash_timer > 0 {
			raylib.EndShaderMode()
		}
	}
}
