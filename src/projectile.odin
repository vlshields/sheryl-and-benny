package sheryl_and_benny

import dm "../dotmap"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "vendor:raylib"

PROJECTILE_SPEED :: 200.0
PROJECTILE_LIFETIME :: 2.0
PROJECTILE_RADIUS :: 2.0
MAX_PROJECTILES :: 256
SHOOT_RECOIL :: 3.0

BLASTER_FIRE_COOLDOWN :: 0.25
BLASTER_DAMAGE :: 6

SLINGER_FIRE_COOLDOWN :: 0.07
SLINGER_DAMAGE :: 3

FLAME_DAMAGE :: 4
FLAME_DAMAGE_TICK :: 0.15

BLASTER_MAX_AMMO :: 9
SLINGER_MAX_AMMO :: 65
FLAMETHROWER_MAX_AMMO :: 100
MAX_FLAME_PARTICLES :: 256
FLAME_SPEED :: 150.0
FLAME_LIFETIME :: 1.3
FLAME_EMIT_COUNT :: 5
FLAME_CONE_SPREAD :: 0.0873

MAX_PARTICLES :: 128

Weapon_Kind :: enum {
	None,
	Blaster,
	Slinger,
	Flamethrower,
}

Projectile :: struct {
	pos:      raylib.Vector2,
	vel:      raylib.Vector2,
	lifetime: f32,
	damage:   i32,
	active:   bool,
	is_enemy: bool,
}

Particle :: struct {
	pos:          raylib.Vector2,
	vel:          raylib.Vector2,
	lifetime:     f32,
	max_lifetime: f32,
	color:        raylib.Color,
	size:         f32,
	active:       bool,
}

Flame_Particle :: struct {
	pos:          raylib.Vector2,
	vel:          raylib.Vector2,
	lifetime:     f32,
	max_lifetime: f32,
	radius:       f32,
	active:       bool,
}

weapon_can_shoot :: proc(kind: Weapon_Kind) -> bool {
	#partial switch kind {
	case .Blaster:
		return true
	case .Slinger:
		return true
	}
	return false
}

weapon_fire_cooldown :: proc(kind: Weapon_Kind) -> f32 {
	#partial switch kind {
	case .Blaster:
		return BLASTER_FIRE_COOLDOWN
	case .Slinger:
		return SLINGER_FIRE_COOLDOWN
	}
	return 0
}

weapon_damage :: proc(kind: Weapon_Kind) -> i32 {
	#partial switch kind {
	case .Blaster:
		return BLASTER_DAMAGE
	case .Slinger:
		return SLINGER_DAMAGE
	case .Flamethrower:
		return FLAME_DAMAGE
	}
	return 0
}

get_barrel_tip :: proc(player: ^Player) -> raylib.Vector2 {
	player_center := raylib.Vector2{player.pos.x, player.pos.y - f32(SPRITE_DST_SIZE) / 2}
	barrel_length: f32 = f32(SPRITE_DST_SIZE) * 0.78
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	return(
		player_center +
		{math.cos(angle_rad) * barrel_length, math.sin(angle_rad) * barrel_length} \
	)
}

spawn_projectile :: proc(player: ^Player, projectiles: ^[MAX_PROJECTILES]Projectile) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	fire_dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}
	vel := fire_dir * PROJECTILE_SPEED

	// Recoil the gun sprite backward
	player.blaster_recoil = SHOOT_RECOIL

	dmg := weapon_damage(player.weapon)

	for &proj in projectiles {
		if !proj.active {
			proj = Projectile {
				pos      = tip,
				vel      = vel,
				lifetime = PROJECTILE_LIFETIME,
				damage   = dmg,
				active   = true,
			}
			return
		}
	}
}

update_projectiles :: proc(
	projectiles: ^[MAX_PROJECTILES]Projectile,
	particles: ^[MAX_PARTICLES]Particle,
	map_data: ^dm.Dot_Map,
	dt: f32,
) {
	for &proj in projectiles {
		if !proj.active {
			continue
		}

		proj.pos += proj.vel * dt
		proj.lifetime -= dt

		if proj.lifetime <= 0 {
			proj.active = false
			continue
		}

		// Check wall collision at projectile center
		tx := int(proj.pos.x) / TILE_SIZE
		ty := int(proj.pos.y) / TILE_SIZE

		if tx < 0 || ty < 0 || ty >= map_data.height || tx >= map_data.width {
			spawn_impact_particles(proj.pos, particles)
			proj.active = false
			continue
		}

		cell := map_data.grid[ty][tx]
		sym := cell.symbol

		if sym != 'p' && sym != 'e' && sym != 'f' && sym != 'B' {
			if td, ok := map_data.metadata[sym]; ok {
				if !td.passable {
					spawn_impact_particles(proj.pos, particles)
					proj.active = false
				}
			} else {
				spawn_impact_particles(proj.pos, particles)
				proj.active = false
			}
		}
	}
}

draw_projectiles :: proc(projectiles: ^[MAX_PROJECTILES]Projectile) {
	for &proj in projectiles {
		if proj.active {
			color: raylib.Color = proj.is_enemy ? {255, 80, 80, 255} : {255, 220, 50, 255}
			raylib.DrawCircleV(proj.pos, PROJECTILE_RADIUS, color)
		}
	}
}

check_enemy_projectile_player_collision :: proc(gs: ^Game_State) {
	if gs.player.hp <= 0 || gs.player.invincibility_timer > 0 {
		return
	}

	px := gs.player.pos.x - f32(PLAYER_HITBOX) / 2
	py := gs.player.pos.y - f32(PLAYER_HITBOX) / 2
	ps := f32(PLAYER_HITBOX)

	for &proj in gs.projectiles {
		if !proj.active || !proj.is_enemy {
			continue
		}

		if proj.pos.x >= px &&
		   proj.pos.x <= px + ps &&
		   proj.pos.y >= py &&
		   proj.pos.y <= py + ps {
			gs.player.hp -= proj.damage
			gs.player.invincibility_timer = PLAYER_INVINCIBILITY_TIME
			proj.active = false
			spawn_impact_particles(proj.pos, &gs.particles)
			spawn_damage_text(gs, gs.player.pos, proj.damage)

			// Knockback from projectile direction
			vel_len := linalg.length(proj.vel)
			if vel_len > 0 {
				gs.player.knockback_vel = linalg.normalize(proj.vel) * FLY_KNOCKBACK
			}
			return
		}
	}
}

spawn_muzzle_flash :: proc(player: ^Player, particles: ^[MAX_PARTICLES]Particle) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	base_dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}

	colors := [3]raylib.Color{{255, 255, 200, 255}, {255, 200, 50, 255}, {255, 150, 30, 255}}

	for i := 0; i < 7; i += 1 {
		// Spread within a cone of ~30 degrees
		spread := (rand.float32() - 0.5) * 0.5
		cos_s := math.cos(spread)
		sin_s := math.sin(spread)
		dir := raylib.Vector2 {
			base_dir.x * cos_s - base_dir.y * sin_s,
			base_dir.x * sin_s + base_dir.y * cos_s,
		}

		speed := 40.0 + rand.float32() * 60.0
		lt := 0.08 + rand.float32() * 0.07

		spawn_particle(
			particles,
			Particle {
				pos = tip,
				vel = dir * speed,
				lifetime = lt,
				max_lifetime = lt,
				color = colors[i % 3],
				size = 1.0 + rand.float32() * 1.5,
				active = true,
			},
		)
	}
}

spawn_impact_particles :: proc(pos: raylib.Vector2, particles: ^[MAX_PARTICLES]Particle) {
	colors := [2]raylib.Color{{200, 200, 200, 255}, {255, 200, 100, 255}}

	for i := 0; i < 5; i += 1 {
		angle := rand.float32() * math.PI * 2
		speed := 20.0 + rand.float32() * 50.0
		dir := raylib.Vector2{math.cos(angle), math.sin(angle)}
		lt := 0.1 + rand.float32() * 0.1

		spawn_particle(
			particles,
			Particle {
				pos = pos,
				vel = dir * speed,
				lifetime = lt,
				max_lifetime = lt,
				color = colors[i % 2],
				size = 1.0 + rand.float32() * 1.0,
				active = true,
			},
		)
	}
}

spawn_particle :: proc(particles: ^[MAX_PARTICLES]Particle, p: Particle) {
	for &part in particles {
		if !part.active {
			part = p
			return
		}
	}
}

update_particles :: proc(particles: ^[MAX_PARTICLES]Particle, dt: f32) {
	for &part in particles {
		if !part.active {
			continue
		}

		part.pos += part.vel * dt
		part.lifetime -= dt

		if part.lifetime <= 0 {
			part.active = false
		}
	}
}

draw_particles :: proc(particles: ^[MAX_PARTICLES]Particle) {
	for &part in particles {
		if !part.active {
			continue
		}

		alpha := part.lifetime / part.max_lifetime
		c := raylib.Color{part.color.r, part.color.g, part.color.b, u8(f32(part.color.a) * alpha)}
		raylib.DrawCircleV(part.pos, part.size, c)
	}
}

spawn_flame_particles :: proc(
	player: ^Player,
	flame_particles: ^[MAX_FLAME_PARTICLES]Flame_Particle,
) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	base_dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}

	for i := 0; i < FLAME_EMIT_COUNT; i += 1 {
		spread := (rand.float32() - 0.5) * FLAME_CONE_SPREAD * 2
		cos_s := math.cos(spread)
		sin_s := math.sin(spread)
		dir := raylib.Vector2 {
			base_dir.x * cos_s - base_dir.y * sin_s,
			base_dir.x * sin_s + base_dir.y * cos_s,
		}

		speed := FLAME_SPEED * (0.8 + rand.float32() * 0.4)
		lt := FLAME_LIFETIME * (0.8 + rand.float32() * 0.4)

		for &fp in flame_particles {
			if !fp.active {
				fp = Flame_Particle {
					pos          = tip,
					vel          = dir * speed,
					lifetime     = lt,
					max_lifetime = lt,
					radius       = 2.5 + rand.float32() * 1.5,
					active       = true,
				}
				break
			}
		}
	}
}

update_flame_particles :: proc(flame_particles: ^[MAX_FLAME_PARTICLES]Flame_Particle, dt: f32) {
	for &fp in flame_particles {
		if !fp.active {
			continue
		}

		fp.lifetime -= dt
		if fp.lifetime <= 0 || fp.radius <= 0.1 {
			fp.active = false
			continue
		}

		fp.pos += fp.vel * dt
		fp.pos.x += math.cos(fp.lifetime * 20.0) * 0.5
		fp.radius -= dt * 1.5
		if fp.radius < 0 {
			fp.radius = 0
		}
	}
}

draw_flame_particles :: proc(flame_particles: ^[MAX_FLAME_PARTICLES]Flame_Particle) {
	for &fp in flame_particles {
		if !fp.active {
			continue
		}

		t := 1.0 - (fp.lifetime / fp.max_lifetime)
		g := u8(255.0 * (1.0 - t))
		alpha := u8(255.0 * (fp.lifetime / fp.max_lifetime))
		color := raylib.Color{255, g, 0, alpha}
		raylib.DrawCircleV(fp.pos, fp.radius, color)
	}
}

check_flame_enemy_collision :: proc(gs: ^Game_State) {
	for &fp in gs.flame_particles {
		if !fp.active {
			continue
		}

		for &enemy in gs.enemies {
			if !enemy.alive || !enemy.spawned || enemy.flame_damage_timer > 0 {
				continue
			}

			ex := enemy.pos.x
			ey := enemy.pos.y
			s := f32(SPRITE_DST_SIZE)

			if fp.pos.x >= ex && fp.pos.x <= ex + s && fp.pos.y >= ey && fp.pos.y <= ey + s {
				enemy.hp -= FLAME_DAMAGE
				enemy.flash_timer = ENEMY_FLASH_TIME
				enemy.flame_damage_timer = FLAME_DAMAGE_TICK

				if enemy.hp <= 0 {
					enemy.alive = false
					if gs.arena.active && rand.float32() < 0.05 {
						spawn_health_crate(gs, enemy.pos)
					}
				}
			}
		}
	}
}
