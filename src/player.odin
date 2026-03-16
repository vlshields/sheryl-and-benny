package sheryl_and_benny

import dm "../dotmap"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import "vendor:raylib"

PLAYER_SPEED :: 100.0
ANIM_FRAME_TIME :: 0.15
STICK_DEADZONE :: 0.25
SPRITE_SRC_SIZE :: 24
SPRITE_DST_SIZE :: 16
PLAYER_HITBOX :: 8
PLAYER_HP :: 55
PLAYER_INVINCIBILITY_TIME :: 1.3
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
	ammo:                i32,
	has_key:             bool,
}

get_player_input :: proc(player: ^Player, gs: ^Game_State) {
	player.move_dir = {0, 0}
	player.aim_dir = {0, 0}
	audio := &gs.audio

	// Track whether any weapon loop sound should play this frame
	firing_loop := false

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

		// If stationary, only fire if already facing the reticle direction
		gp_stationary := abs(player.move_dir.x) < 0.01 && abs(player.move_dir.y) < 0.01
		gp_needs_turn := gp_stationary && ((player.aim_dir.x < -0.1 && !player.facing_left) || (player.aim_dir.x > 0.1 && player.facing_left))

		// RT to fire (held for autofire)
		if raylib.IsGamepadButtonDown(0, .RIGHT_TRIGGER_2) && player.ammo > 0 && !gp_needs_turn {
			if player.weapon == .Flamethrower {
				spawn_flame_particles(player, &gs.flame_particles)
				player.ammo -= 1
				play_sfx_loop(audio.flamethrower_loop)
				firing_loop = true
			} else if player.weapon == .Laser_Gun {
				update_plasma_beam(player, gs)
				if player.fire_cooldown <= 0 {
					player.fire_cooldown = weapon_fire_cooldown(player.weapon)
					player.ammo -= 1
				}
				play_sfx_loop(audio.lasergun_loop)
				firing_loop = true
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
				player.ammo -= 1
				if player.weapon == .Blaster {
					play_sfx(audio.blaster_shot)
				} else if player.weapon == .Slinger {
					play_sfx_loop(audio.slinger_loop)
					firing_loop = true
				}
			}
			using_gamepad = true
		}

		// Out of ammo click
		if raylib.IsGamepadButtonPressed(0, .RIGHT_TRIGGER_2) && player.ammo <= 0 && player.weapon != .None {
			play_sfx(audio.out_of_ammo)
		}

		// LB to reload (cannot reload while shooting)
		if raylib.IsGamepadButtonPressed(0, .LEFT_TRIGGER_1) && player.weapon != .None && !raylib.IsGamepadButtonDown(0, .RIGHT_TRIGGER_2) {
			player.ammo = weapon_max_ammo(player.weapon)
			play_sfx(audio.reload)
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
		mouse_virtual := get_virtual_mouse(gs)
		mouse_world := raylib.GetScreenToWorld2D(mouse_virtual, gs.camera)
		player_center := raylib.Vector2{player.pos.x, player.pos.y - f32(SPRITE_DST_SIZE) / 2}
		aim_vec := mouse_world - player_center
		aim_mag := linalg.length(aim_vec)
		if aim_mag > 0 {
			player.aim_dir = aim_vec / aim_mag
		}

		// If stationary, only fire if already facing the reticle direction
		kb_stationary := player.move_dir.x == 0 && player.move_dir.y == 0
		kb_needs_turn := kb_stationary && ((player.aim_dir.x < -0.1 && !player.facing_left) || (player.aim_dir.x > 0.1 && player.facing_left))

		// Left click to fire (held for autofire)
		if raylib.IsMouseButtonDown(.LEFT) && player.ammo > 0 && !kb_needs_turn {
			if player.weapon == .Flamethrower {
				spawn_flame_particles(player, &gs.flame_particles)
				player.ammo -= 1
				play_sfx_loop(audio.flamethrower_loop)
				firing_loop = true
			} else if player.weapon == .Laser_Gun {
				update_plasma_beam(player, gs)
				if player.fire_cooldown <= 0 {
					player.fire_cooldown = weapon_fire_cooldown(player.weapon)
					player.ammo -= 1
				}
				play_sfx_loop(audio.lasergun_loop)
				firing_loop = true
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
				player.ammo -= 1
				if player.weapon == .Blaster {
					play_sfx(audio.blaster_shot)
				} else if player.weapon == .Slinger {
					play_sfx_loop(audio.slinger_loop)
					firing_loop = true
				}
			}
		}

		// Out of ammo click
		if raylib.IsMouseButtonPressed(.LEFT) && player.ammo <= 0 && player.weapon != .None {
			play_sfx(audio.out_of_ammo)
		}

		// Right click to reload (cannot reload while shooting)
		if raylib.IsMouseButtonPressed(.RIGHT) && player.weapon != .None && !raylib.IsMouseButtonDown(.LEFT) {
			player.ammo = weapon_max_ammo(player.weapon)
			play_sfx(audio.reload)
		}
	}

	// Stop weapon loops if not firing this frame
	if !firing_loop {
		stop_weapon_loops(audio)
	}

	// Footsteps
	is_moving := linalg.length(player.move_dir) > 0.1
	if is_moving {
		play_sfx_loop(audio.footsteps)
	} else {
		stop_sfx(audio.footsteps)
	}

	// Face toward reticule when stationary and shooting
	is_shooting := false
	if using_gamepad {
		is_shooting = raylib.IsGamepadButtonDown(0, .RIGHT_TRIGGER_2)
	} else {
		is_shooting = raylib.IsMouseButtonDown(.LEFT)
	}

	if is_shooting && player.move_dir.x == 0 && player.move_dir.y == 0 {
		if player.aim_dir.x < -0.1 {
			old_facing := player.facing_left
			player.facing_left = true
			if player.weapon != .None && !old_facing {
				if player.blaster_angle >= 0 {
					player.blaster_angle = 180 - player.blaster_angle
				} else {
					player.blaster_angle = -180 - player.blaster_angle
				}
			}
		} else if player.aim_dir.x > 0.1 {
			old_facing := player.facing_left
			player.facing_left = false
			if player.weapon != .None && old_facing {
				if player.blaster_angle >= 0 {
					player.blaster_angle = 180 - player.blaster_angle
				} else {
					player.blaster_angle = -180 - player.blaster_angle
				}
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
		hb := f32(PLAYER_HITBOX)
		new_kx := player.pos.x + kb.x
		if !check_collision(
			new_kx - hb / 2,
			player.pos.y - hb,
			hb,
			hb,
			map_data,
			enemies_cleared,
			player.has_key,
		) {
			player.pos.x = new_kx
		}
		new_ky := player.pos.y + kb.y
		if !check_collision(
			player.pos.x - hb / 2,
			new_ky - hb,
			hb,
			hb,
			map_data,
			enemies_cleared,
			player.has_key,
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
	hb := f32(PLAYER_HITBOX)

	// Try X axis
	new_x := player.pos.x + velocity.x
	if !check_collision(
		new_x - hb / 2,
		player.pos.y - hb,
		hb,
		hb,
		map_data,
		enemies_cleared,
		player.has_key,
	) {
		player.pos.x = new_x
	}

	// Try Y axis
	new_y := player.pos.y + velocity.y
	if !check_collision(
		player.pos.x - hb / 2,
		new_y - hb,
		hb,
		hb,
		map_data,
		enemies_cleared,
		player.has_key,
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

check_collision :: proc(
	x, y, w, h: f32,
	map_data: ^dm.Dot_Map,
	enemies_cleared: bool,
	has_key: bool = false,
) -> bool {
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

		// p, e, f, h, k, c, n tiles are passable (spawn points, pickups, NPCs)
		if sym == 'p' ||
		   sym == 'e' ||
		   sym == 'f' ||
		   sym == 'h' ||
		   sym == 'k' ||
		   sym == 'c' ||
		   sym == 'n' ||
		   sym == 'B' {
			continue
		}

		if td, ok := map_data.metadata[sym]; ok {
			if !td.passable {
				return true
			}
			if strings.contains(td.condition, "enemies_cleared") && !enemies_cleared {
				return true
			}
			if strings.contains(td.condition, "has_key") && !has_key {
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
	lasergun_tex: raylib.Texture2D,
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

	sprite_origin := raylib.Vector2{f32(SPRITE_DST_SIZE) / 2, f32(SPRITE_DST_SIZE)}
	raylib.DrawTexturePro(tex, src, dst, sprite_origin, 0, raylib.WHITE)

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
		case .Laser_Gun:
			weapon_tex = lasergun_tex
		}

		player_center := player.pos + {0, -4}
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
		origin := raylib.Vector2{weapon_size / 2 - 1, weapon_size / 2}
		raylib.DrawTexturePro(weapon_tex, weapon_src, weapon_dst, origin, angle, raylib.WHITE)
	}
}

draw_hp_bar :: proc(player: ^Player) {
	HP_BAR_W: i32 = 120
	HP_BAR_H: i32 = 14
	BAR_X: i32 = 10
	BAR_Y: i32 = SCREEN_HEIGHT - 36
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

draw_ammo_display :: proc(player: ^Player, ammo_tex: raylib.Texture2D) {
	if player.weapon == .None {
		return
	}

	per_icon := weapon_ammo_per_icon(player.weapon)
	icon_count := (player.ammo + per_icon - 1) / per_icon
	ICON_SIZE :: 10
	ICON_SPACING :: 2
	BAR_X: i32 = 10
	BAR_Y: i32 = SCREEN_HEIGHT - 14

	src := raylib.Rectangle {
		x      = 0,
		y      = 0,
		width  = f32(ammo_tex.width),
		height = f32(ammo_tex.height),
	}

	for i: i32 = 0; i < icon_count; i += 1 {
		dst := raylib.Rectangle {
			x      = f32(BAR_X + i * (ICON_SIZE + ICON_SPACING)),
			y      = f32(BAR_Y),
			width  = ICON_SIZE,
			height = ICON_SIZE,
		}
		raylib.DrawTexturePro(ammo_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	}
}

check_pickup :: proc(player: ^Player, map_data: ^dm.Dot_Map, audio: ^Audio_State) {
	// Get player center tile coords
	center_x := int(player.pos.x) / TILE_SIZE
	center_y := int(player.pos.y - f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE

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
				player.ammo = weapon_max_ammo(weapon)
				player.blaster_angle = player.facing_left ? 180.0 : 0.0
				cell.collected = true
				play_sfx(audio.item_pickup)
			}

			heal := parse_heal_amount(td.other)
			if heal > 0 {
				player.hp = min(player.hp + heal, PLAYER_HP)
				cell.collected = true
				play_sfx(audio.item_pickup)
			}

			// Key pickup
			if cell.symbol == 'k' {
				player.has_key = true
				cell.collected = true
				play_sfx(audio.item_pickup)
			}
		}
	}
}

parse_heal_amount :: proc(other: string) -> i32 {
	idx := strings.index(other, "amount_healed=")
	if idx < 0 {
		return 0
	}
	val_start := idx + len("amount_healed=")
	val := other[val_start:]

	// Trim at comma if more fields follow
	comma := strings.index(val, ",")
	if comma >= 0 {
		val = val[:comma]
	}
	val = strings.trim_space(val)

	num, ok := strconv.parse_int(val)
	if !ok {
		return 0
	}
	return i32(num)
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
	case "lasergun":
		return .Laser_Gun
	}
	return .None
}

weapon_max_ammo :: proc(kind: Weapon_Kind) -> i32 {
	#partial switch kind {
	case .Blaster:
		return BLASTER_MAX_AMMO
	case .Slinger:
		return SLINGER_MAX_AMMO
	case .Flamethrower:
		return FLAMETHROWER_MAX_AMMO
	case .Laser_Gun:
		return LASER_GUN_MAX_AMMO
	}
	return 0
}

check_door_blocked :: proc(player: ^Player, map_data: ^dm.Dot_Map) -> bool {
	if player.move_dir.x == 0 && player.move_dir.y == 0 {
		return false
	}

	// Check the tile the player is trying to move into
	center_x := player.pos.x + player.move_dir.x * f32(PLAYER_HITBOX) / 2
	center_y :=
		player.pos.y - f32(SPRITE_DST_SIZE) / 2 + player.move_dir.y * f32(PLAYER_HITBOX) / 2
	tx := int(center_x) / TILE_SIZE
	ty := int(center_y) / TILE_SIZE

	if ty < 0 || ty >= map_data.height || tx < 0 || tx >= len(map_data.grid[ty]) {
		return false
	}

	cell := map_data.grid[ty][tx]
	if td, ok := map_data.metadata[cell.symbol]; ok {
		if strings.contains(td.condition, "has_key") && !player.has_key {
			return true
		}
	}
	return false
}

player_near_door :: proc(player: ^Player, map_data: ^dm.Dot_Map) -> bool {
	center_x := int(player.pos.x) / TILE_SIZE
	center_y := int(player.pos.y - f32(SPRITE_DST_SIZE) / 2) / TILE_SIZE

	// Check the player's tile and all 8 neighbors
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			ty := center_y + dy
			tx := center_x + dx
			if ty < 0 || ty >= map_data.height || tx < 0 || tx >= len(map_data.grid[ty]) {
				continue
			}
			cell := map_data.grid[ty][tx]
			if td, ok := map_data.metadata[cell.symbol]; ok {
				if strings.contains(td.condition, "has_key") {
					return true
				}
			}
		}
	}
	return false
}

weapon_ammo_per_icon :: proc(kind: Weapon_Kind) -> i32 {
	#partial switch kind {
	case .Blaster:
		return 1
	case .Slinger:
		return 5
	case .Flamethrower:
		return 10
	case .Laser_Gun:
		return 5
	}
	return 1
}
