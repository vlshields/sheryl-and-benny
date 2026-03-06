package sheryl_and_benny

import dm "../dotmap"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"
import "vendor:raylib"

PLAYER_SPEED :: 80.0
ANIM_FRAME_TIME :: 0.15
STICK_DEADZONE :: 0.25
SPRITE_SRC_SIZE :: 24
SPRITE_DST_SIZE :: 16
PLAYER_HP :: 25
PLAYER_INVINCIBILITY_TIME :: 0.3
KNOCKBACK_DECAY :: 0.9
KNOCKBACK_MIN :: 1.0
RECOIL_DECAY :: 0.85
RECOIL_MIN :: 0.1

Player :: struct {
	pos:                 raylib.Vector2,
	aim_dir:             raylib.Vector2,
	move_dir:            raylib.Vector2,
	sprite_sheet:        raylib.Texture2D,
	idle_sheet:          raylib.Texture2D,
	frame_count:         i32,
	idle_frame_count:    i32,
	current_frame:       i32,
	anim_timer:          f32,
	facing_left:         bool,
	moving:              bool,
	weapon:              Weapon_Kind,
	blaster_angle:       f32,
	fire_cooldown:       f32,
	hp:                  i32,
	invincibility_timer: f32,
	knockback_vel:       raylib.Vector2,
	blaster_recoil:      f32,
}

get_player_input :: proc(player: ^Player, gs: ^Game_State) {
	player.move_dir = {0, 0}
	player.aim_dir = {0, 0}

	// Check gamepad
	using_gamepad := false
	if raylib.IsGamepadAvailable(0) {
		// Left stick for movement
		lx := raylib.GetGamepadAxisMovement(0, .LEFT_X)
		ly := raylib.GetGamepadAxisMovement(0, .LEFT_Y)
		if abs(lx) > STICK_DEADZONE || abs(ly) > STICK_DEADZONE {
			player.move_dir = {lx, ly}
			mag := linalg.length(player.move_dir)
			if mag > 1.0 {
				player.move_dir /= mag
			}
			using_gamepad = true
		}

		// Right stick for aiming
		rx := raylib.GetGamepadAxisMovement(0, .RIGHT_X)
		ry := raylib.GetGamepadAxisMovement(0, .RIGHT_Y)
		if abs(rx) > STICK_DEADZONE || abs(ry) > STICK_DEADZONE {
			player.aim_dir = linalg.normalize(raylib.Vector2{rx, ry})
			using_gamepad = true
		}

		// RT to fire (held for autofire)
		if raylib.IsGamepadButtonDown(0, .RIGHT_TRIGGER_2) {
			if player.weapon == .Flamethrower {
				spawn_flame_particles(player, &gs.flame_particles)
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
			}
			using_gamepad = true
		}
	}

	if !using_gamepad {
		// Keyboard fallback
		if raylib.IsKeyDown(.W) {
			player.move_dir.y -= 1
		}
		if raylib.IsKeyDown(.S) {
			player.move_dir.y += 1
		}
		if raylib.IsKeyDown(.A) {
			player.move_dir.x -= 1
		}
		if raylib.IsKeyDown(.D) {
			player.move_dir.x += 1
		}

		mag := linalg.length(player.move_dir)
		if mag > 0 {
			player.move_dir /= mag
		}

		// Mouse aim
		mouse_screen := raylib.GetMousePosition()
		mouse_world := raylib.GetScreenToWorld2D(mouse_screen, gs.camera)
		player_center := player.pos + {f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE) / 2}
		aim_vec := mouse_world - player_center
		aim_mag := linalg.length(aim_vec)
		if aim_mag > 0 {
			player.aim_dir = aim_vec / aim_mag
		}

		// Left click to fire (held for autofire)
		if raylib.IsMouseButtonDown(.LEFT) {
			if player.weapon == .Flamethrower {
				spawn_flame_particles(player, &gs.flame_particles)
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
			}
		}
	}

	update_blaster_angle(player)
}

update_blaster_angle :: proc(player: ^Player) {
	if player.weapon == .None {
		return
	}
	aim_len := linalg.length(player.aim_dir)
	if aim_len > 0 {
		angle := math.atan2(player.aim_dir.y, player.aim_dir.x) * (180.0 / math.PI)

		// Clamp to forward-facing 180-degree arc so the weapon never points behind the player
		if player.facing_left {
			if angle > -90 && angle < 90 {
				angle = angle >= 0 ? 90 : -90
			}
		} else {
			angle = clamp(angle, -90, 90)
		}

		player.blaster_angle = angle
	}
}

move_and_collide :: proc(player: ^Player, map_data: ^dm.Dot_Map, dt: f32, enemies_cleared: bool) {
	// Apply and decay knockback
	if linalg.length(player.knockback_vel) > KNOCKBACK_MIN {
		kb := player.knockback_vel * dt
		size := f32(SPRITE_DST_SIZE)
		inset: f32 = 1.0
		new_kx := player.pos.x + kb.x
		if !check_collision(
			new_kx + inset,
			player.pos.y + inset,
			size - inset * 2,
			size - inset * 2,
			map_data,
			enemies_cleared,
		) {
			player.pos.x = new_kx
		}
		new_ky := player.pos.y + kb.y
		if !check_collision(
			player.pos.x + inset,
			new_ky + inset,
			size - inset * 2,
			size - inset * 2,
			map_data,
			enemies_cleared,
		) {
			player.pos.y = new_ky
		}
		player.knockback_vel *= KNOCKBACK_DECAY
		if linalg.length(player.knockback_vel) < KNOCKBACK_MIN {
			player.knockback_vel = {0, 0}
		}
	}

	// Decay blaster recoil
	if player.blaster_recoil > RECOIL_MIN {
		player.blaster_recoil *= RECOIL_DECAY
		if player.blaster_recoil < RECOIL_MIN {
			player.blaster_recoil = 0
		}
	}

	if player.move_dir.x == 0 && player.move_dir.y == 0 {
		return
	}

	velocity := player.move_dir * PLAYER_SPEED * dt
	size := f32(SPRITE_DST_SIZE)
	inset: f32 = 1.0

	// Try X axis
	new_x := player.pos.x + velocity.x
	if !check_collision(
		new_x + inset,
		player.pos.y + inset,
		size - inset * 2,
		size - inset * 2,
		map_data,
		enemies_cleared,
	) {
		player.pos.x = new_x
	}

	// Try Y axis
	new_y := player.pos.y + velocity.y
	if !check_collision(
		player.pos.x + inset,
		new_y + inset,
		size - inset * 2,
		size - inset * 2,
		map_data,
		enemies_cleared,
	) {
		player.pos.y = new_y
	}

	// Update facing direction and flip blaster to match
	old_facing := player.facing_left
	if player.move_dir.x < -0.1 {
		player.facing_left = true
	} else if player.move_dir.x > 0.1 {
		player.facing_left = false
	}
	if player.weapon != .None && player.facing_left != old_facing {
		if player.blaster_angle >= 0 {
			player.blaster_angle = 180 - player.blaster_angle
		} else {
			player.blaster_angle = -180 - player.blaster_angle
		}
	}
}

check_collision :: proc(x, y, w, h: f32, map_data: ^dm.Dot_Map, enemies_cleared: bool) -> bool {
	// Check all four corners of the rect
	corners := [4]raylib.Vector2{{x, y}, {x + w, y}, {x, y + h}, {x + w, y + h}}

	for corner in corners {
		tx := int(corner.x) / TILE_SIZE
		ty := int(corner.y) / TILE_SIZE

		// Out of bounds = blocked
		if tx < 0 || ty < 0 || ty >= map_data.height || tx >= len(map_data.grid[ty]) {
			return true
		}

		cell := map_data.grid[ty][tx]
		sym := cell.symbol

		// p, e, and f tiles are passable (spawn points)
		if sym == 'p' || sym == 'e' || sym == 'f' {
			continue
		}

		if td, ok := map_data.metadata[sym]; ok {
			if !td.passable {
				return true
			}
			if td.condition == "enemies_cleared" && !enemies_cleared {
				return true
			}
		} else {
			// Unknown tile = blocked
			return true
		}
	}

	return false
}

update_animation :: proc(player: ^Player, dt: f32) {
	is_moving := linalg.length(player.move_dir) > 0.1

	// Reset frame on state transition
	if is_moving != player.moving {
		player.current_frame = 0
		player.anim_timer = 0
		player.moving = is_moving
	}

	fc := is_moving ? player.frame_count : player.idle_frame_count
	player.anim_timer += dt
	if player.anim_timer >= ANIM_FRAME_TIME {
		player.anim_timer -= ANIM_FRAME_TIME
		player.current_frame = (player.current_frame + 1) % fc
	}
}

draw_player :: proc(
	player: ^Player,
	blaster_tex: raylib.Texture2D,
	slinger_tex: raylib.Texture2D,
	flamethrower_tex: raylib.Texture2D,
) {
	tex := player.moving ? player.sprite_sheet : player.idle_sheet

	src_w := f32(SPRITE_SRC_SIZE)
	if player.facing_left {
		src_w = -src_w
	}

	src := raylib.Rectangle {
		x      = f32(player.current_frame * SPRITE_SRC_SIZE),
		y      = 0,
		width  = src_w,
		height = f32(SPRITE_SRC_SIZE),
	}

	dst := raylib.Rectangle {
		x      = player.pos.x,
		y      = player.pos.y,
		width  = f32(SPRITE_DST_SIZE),
		height = f32(SPRITE_DST_SIZE),
	}

	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)

	// Draw weapon if player has one — rotated toward aim direction
	if player.weapon != .None {
		weapon_tex: raylib.Texture2D
		#partial switch player.weapon {
		case .Blaster:
			weapon_tex = blaster_tex
		case .Slinger:
			weapon_tex = slinger_tex
		case .Flamethrower:
			weapon_tex = flamethrower_tex
		}

		player_center := player.pos + {f32(SPRITE_DST_SIZE) / 2, 11}
		weapon_size: f32 = f32(SPRITE_DST_SIZE) * 0.78
		angle := player.blaster_angle

		// Apply recoil: pull the weapon back toward the player
		angle_rad := angle * (math.PI / 180.0)
		recoil_offset := raylib.Vector2 {
			math.cos(angle_rad) * -player.blaster_recoil,
			math.sin(angle_rad) * -player.blaster_recoil,
		}

		// Flip sprite vertically when aiming left so it doesn't appear upside-down
		src_h: f32 = 24
		if angle > 90 || angle < -90 {
			src_h = -24
		}

		weapon_src := raylib.Rectangle{0, 0, 24, src_h}
		weapon_dst := raylib.Rectangle {
			x      = player_center.x + recoil_offset.x,
			y      = player_center.y + recoil_offset.y,
			width  = weapon_size,
			height = weapon_size,
		}

		// Origin at center so weapon looks symmetrical when facing either direction
		origin := raylib.Vector2{weapon_size / 2, weapon_size / 2}
		raylib.DrawTexturePro(weapon_tex, weapon_src, weapon_dst, origin, angle, raylib.WHITE)
	}
}

draw_hp_bar :: proc(player: ^Player) {
	HP_BAR_W: i32 = 120
	HP_BAR_H: i32 = 14
	BAR_X: i32 = 10
	BAR_Y: i32 = SCREEN_HEIGHT - 24
	border_color := raylib.Color{71, 50, 75, 255}
	fill_color := raylib.Color{221, 103, 76, 255}

	raylib.DrawRectangle(BAR_X - 3, BAR_Y - 3, HP_BAR_W + 6, HP_BAR_H + 6, border_color)

	fill_ratio := f32(player.hp) / f32(PLAYER_HP)
	if fill_ratio < 0 {
		fill_ratio = 0
	}
	fill_w := i32(f32(HP_BAR_W) * fill_ratio)
	raylib.DrawRectangle(BAR_X, BAR_Y, fill_w, HP_BAR_H, fill_color)
}

check_pickup :: proc(player: ^Player, map_data: ^dm.Dot_Map) {
	// Get player center tile coords
	center_x := int(player.pos.x + f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE
	center_y := int(player.pos.y + f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE

	if center_y < 0 || center_y >= map_data.height {
		return
	}
	if center_x < 0 || center_x >= len(map_data.grid[center_y]) {
		return
	}

	cell := &map_data.grid[center_y][center_x]

	if td, ok := map_data.metadata[cell.symbol]; ok {
		if td.collectable && !cell.collected {
			weapon := parse_weapon_from_item(td.other)
			if weapon != .None {
				player.weapon = weapon
				player.blaster_angle = player.facing_left ? 180.0 : 0.0
				cell.collected = true
			}
		}
	}
}

parse_weapon_from_item :: proc(other: string) -> Weapon_Kind {
	idx := strings.index(other, "contains_item=")
	if idx < 0 {
		return .None
	}
	val_start := idx + len("contains_item=")
	val := other[val_start:]

	// Array format: [item1,item2]
	if len(val) > 0 && val[0] == '[' {
		end := strings.index(val, "]")
		if end < 0 {
			return .None
		}
		items_str := val[1:end]
		items := strings.split(items_str, ",")
		defer delete(items)
		if len(items) == 0 {
			return .None
		}
		pick := rand.int_max(len(items))
		return weapon_from_name(strings.trim_space(items[pick]))
	}

	// Single item — trim at comma if more fields follow
	comma := strings.index(val, ",")
	if comma >= 0 {
		val = val[:comma]
	}
	return weapon_from_name(strings.trim_space(val))
}

weapon_from_name :: proc(name: string) -> Weapon_Kind {
	switch name {
	case "blaster":
		return .Blaster
	case "slinger":
		return .Slinger
	case "flamethrower":
		return .Flamethrower
	}
	return .None
}
