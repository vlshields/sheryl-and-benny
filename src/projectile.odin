package sheryl_and_benny

import "vendor:raylib"
import dm "../dotmap"
import "core:math"
import "core:math/rand"

PROJECTILE_SPEED    :: 200.0
PROJECTILE_LIFETIME :: 2.0
PROJECTILE_RADIUS   :: 2.0
MAX_PROJECTILES     :: 32
FIRE_COOLDOWN       :: 0.25
SHOOT_KNOCKBACK     :: 120.0

MAX_PARTICLES :: 128

Weapon_Kind :: enum {
	None,
	Blaster,
}

Projectile :: struct {
	pos:      raylib.Vector2,
	vel:      raylib.Vector2,
	lifetime: f32,
	active:   bool,
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

weapon_can_shoot :: proc(kind: Weapon_Kind) -> bool {
	#partial switch kind {
	case .Blaster:
		return true
	}
	return false
}

get_barrel_tip :: proc(player: ^Player) -> raylib.Vector2 {
	player_center := player.pos + {f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}
	barrel_length: f32 = f32(SPRITE_DST_SIZE) * 0.78
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	return player_center + {math.cos(angle_rad) * barrel_length, math.sin(angle_rad) * barrel_length}
}

spawn_projectile :: proc(player: ^Player, projectiles: ^[MAX_PROJECTILES]Projectile) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	fire_dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}
	vel := fire_dir * PROJECTILE_SPEED

	// Knockback the player opposite to the fire direction
	player.knockback_vel += fire_dir * -SHOOT_KNOCKBACK

	for &proj in projectiles {
		if !proj.active {
			proj = Projectile {
				pos      = tip,
				vel      = vel,
				lifetime = PROJECTILE_LIFETIME,
				active   = true,
			}
			return
		}
	}
}

update_projectiles :: proc(projectiles: ^[MAX_PROJECTILES]Projectile, particles: ^[MAX_PARTICLES]Particle, map_data: ^dm.Dot_Map, dt: f32) {
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

		if sym != 'p' && sym != 'e' {
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
			raylib.DrawCircleV(proj.pos, PROJECTILE_RADIUS, {255, 220, 50, 255})
		}
	}
}

spawn_muzzle_flash :: proc(player: ^Player, particles: ^[MAX_PARTICLES]Particle) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	base_dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}

	colors := [3]raylib.Color{
		{255, 255, 200, 255},
		{255, 200, 50, 255},
		{255, 150, 30, 255},
	}

	for i := 0; i < 7; i += 1 {
		// Spread within a cone of ~30 degrees
		spread := (rand.float32() - 0.5) * 0.5
		cos_s := math.cos(spread)
		sin_s := math.sin(spread)
		dir := raylib.Vector2{
			base_dir.x * cos_s - base_dir.y * sin_s,
			base_dir.x * sin_s + base_dir.y * cos_s,
		}

		speed := 40.0 + rand.float32() * 60.0
		lt := 0.08 + rand.float32() * 0.07

		spawn_particle(particles, Particle {
			pos          = tip,
			vel          = dir * speed,
			lifetime     = lt,
			max_lifetime = lt,
			color        = colors[i % 3],
			size         = 1.0 + rand.float32() * 1.5,
			active       = true,
		})
	}
}

spawn_impact_particles :: proc(pos: raylib.Vector2, particles: ^[MAX_PARTICLES]Particle) {
	colors := [2]raylib.Color{
		{200, 200, 200, 255},
		{255, 200, 100, 255},
	}

	for i := 0; i < 5; i += 1 {
		angle := rand.float32() * math.PI * 2
		speed := 20.0 + rand.float32() * 50.0
		dir := raylib.Vector2{math.cos(angle), math.sin(angle)}
		lt := 0.1 + rand.float32() * 0.1

		spawn_particle(particles, Particle {
			pos          = pos,
			vel          = dir * speed,
			lifetime     = lt,
			max_lifetime = lt,
			color        = colors[i % 2],
			size         = 1.0 + rand.float32() * 1.0,
			active       = true,
		})
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
		c := raylib.Color{
			part.color.r,
			part.color.g,
			part.color.b,
			u8(f32(part.color.a) * alpha),
		}
		raylib.DrawCircleV(part.pos, part.size, c)
	}
}
