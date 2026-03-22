package sheryl_and_benny

import dm "../dotmap"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import "vendor:raylib"



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
				if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
				play_sfx_loop(audio.flamethrower_loop)
				firing_loop = true
			} else if player.weapon == .Laser_Gun {
				update_plasma_beam(player, gs)
				if player.fire_cooldown <= 0 {
					player.fire_cooldown = weapon_fire_cooldown(player.weapon)
					player.ammo -= 1
					if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
				}
				play_sfx_loop(audio.lasergun_loop)
				firing_loop = true
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
				player.ammo -= 1
				if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
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
				if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
				play_sfx_loop(audio.flamethrower_loop)
				firing_loop = true
			} else if player.weapon == .Laser_Gun {
				update_plasma_beam(player, gs)
				if player.fire_cooldown <= 0 {
					player.fire_cooldown = weapon_fire_cooldown(player.weapon)
					player.ammo -= 1
					if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
				}
				play_sfx_loop(audio.lasergun_loop)
				firing_loop = true
			} else if weapon_can_shoot(player.weapon) && player.fire_cooldown <= 0 {
				spawn_projectile(player, &gs.projectiles)
				spawn_muzzle_flash(player, &gs.particles)
				player.fire_cooldown = weapon_fire_cooldown(player.weapon)
				player.ammo -= 1
				if player.ammo == 0 { play_sfx(audio.out_of_ammo) }
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

move_and_collide :: proc(player: ^Player, map_data: ^dm.Dot_Map, dt: f32, enemies_cleared: bool, dialogue_done: bool = false) {
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
			dialogue_done,
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
			dialogue_done,
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
		dialogue_done,
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
		dialogue_done,
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
	dialogue_done: bool = false,
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
			if strings.contains(td.condition, ".dialg") && !dialogue_done {
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

check_door_blocked :: proc(player: ^Player, map_data: ^dm.Dot_Map, dialogue_done: bool = false) -> bool {
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
		if strings.contains(td.condition, ".dialg") && !dialogue_done {
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




Weapon_Kind :: enum {
	None,
	Blaster,
	Slinger,
	Flamethrower,
	Laser_Gun,
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

Laser_Beam :: struct {
	start:    raylib.Vector2,
	end:      raylib.Vector2,
	lifetime: f32,
	max_life: f32,
	active:   bool,
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
	case .Laser_Gun:
		return LASER_GUN_FIRE_COOLDOWN
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
	case .Laser_Gun:
		return LASER_GUN_DAMAGE
	}
	return 0
}

get_barrel_tip :: proc(player: ^Player) -> raylib.Vector2 {
	player_center := raylib.Vector2{player.pos.x, player.pos.y - 4}
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
			radius: f32 = proj.is_enemy ? ENEMY_PROJECTILE_RADIUS : PROJECTILE_RADIUS
			raylib.DrawCircleV(proj.pos, radius, color)
		}
	}
}

check_enemy_projectile_player_collision :: proc(gs: ^Game_State) {
	if gs.player.hp <= 0 || gs.player.invincibility_timer > 0 {
		return
	}

	px := gs.player.pos.x - f32(PLAYER_HITBOX) / 2
	py := gs.player.pos.y - f32(PLAYER_HITBOX)
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
			play_sfx(gs.audio.hit)

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

update_plasma_beam :: proc(player: ^Player, gs: ^Game_State) {
	tip := get_barrel_tip(player)
	angle_rad := player.blaster_angle * (math.PI / 180.0)
	dir := raylib.Vector2{math.cos(angle_rad), math.sin(angle_rad)}

	// Raycast to find hit point — stops at first wall OR first enemy
	hit_pos := tip + dir * LASER_BEAM_RANGE
	hit_enemy_idx := -1

	// Find closest enemy along beam direction
	closest_enemy_dist: f32 = LASER_BEAM_RANGE + 1
	for &enemy, idx in gs.enemies {
		if !enemy.alive || !enemy.spawned {
			continue
		}

		ex := enemy.pos.x
		ey := enemy.pos.y
		s := f32(SPRITE_DST_SIZE)

		// Sample along beam to check enemy rect
		for i: f32 = 0; i < LASER_BEAM_RANGE; i += 2 {
			px := tip.x + dir.x * i
			py := tip.y + dir.y * i
			if px >= ex && px <= ex + s && py >= ey && py <= ey + s {
				if i < closest_enemy_dist {
					closest_enemy_dist = i
					hit_enemy_idx = idx
				}
				break
			}
		}
	}

	// Raycast for walls, but stop if we already hit an enemy closer
	max_range: f32 = LASER_BEAM_RANGE
	if hit_enemy_idx >= 0 {
		max_range = closest_enemy_dist
	}

	for i: f32 = 0; i < max_range; i += 1 {
		check_pos := tip + dir * i
		tx := int(check_pos.x) / TILE_SIZE
		ty := int(check_pos.y) / TILE_SIZE

		if tx < 0 || ty < 0 || ty >= gs.map_data.height || tx >= gs.map_data.width {
			hit_pos = check_pos
			hit_enemy_idx = -1
			break
		}

		cell := gs.map_data.grid[ty][tx]
		sym := cell.symbol

		if sym != 'p' && sym != 'e' && sym != 'f' && sym != 'B' &&
		   sym != 'h' && sym != 'k' && sym != 'c' && sym != 'n' {
			if td, ok := gs.map_data.metadata[sym]; ok {
				if !td.passable {
					hit_pos = check_pos
					hit_enemy_idx = -1
					break
				}
			} else {
				hit_pos = check_pos
				hit_enemy_idx = -1
				break
			}
		}
	}

	// If enemy was closest hit, set beam end to enemy center
	if hit_enemy_idx >= 0 {
		hit_pos = tip + dir * closest_enemy_dist
	}

	// Update beam visual — reuse slot 0 so there is only one active beam
	gs.laser_beams[0] = Laser_Beam {
		start    = tip,
		end      = hit_pos,
		lifetime = LASER_BEAM_LIFETIME,
		max_life = LASER_BEAM_LIFETIME,
		active   = true,
	}

	// Recoil
	player.blaster_recoil = SHOOT_RECOIL * 0.3

	// Damage the first enemy hit on a tick timer
	if hit_enemy_idx >= 0 {
		enemy := &gs.enemies[hit_enemy_idx]
		if enemy.flame_damage_timer <= 0 {
			enemy.hp -= LASER_GUN_DAMAGE
			enemy.flash_timer = ENEMY_FLASH_TIME
			enemy.flame_damage_timer = PLASMA_DAMAGE_TICK
			spawn_plasma_impact_particles(hit_pos, &gs.particles)

			if enemy.hp <= 0 {
				enemy.alive = false
				if gs.arena.active && rand.float32() < 0.05 {
					spawn_health_crate(gs, enemy.pos)
				}
			}
		}
	}
}

spawn_plasma_impact_particles :: proc(pos: raylib.Vector2, particles: ^[MAX_PARTICLES]Particle) {
	colors := [3]raylib.Color{{100, 255, 150, 255}, {200, 255, 220, 255}, {50, 255, 100, 255}}

	for i := 0; i < 8; i += 1 {
		angle := rand.float32() * math.PI * 2
		speed := 30.0 + rand.float32() * 70.0
		dir := raylib.Vector2{math.cos(angle), math.sin(angle)}
		lt := 0.1 + rand.float32() * 0.15

		spawn_particle(
			particles,
			Particle {
				pos = pos,
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

update_laser_beams :: proc(laser_beams: ^[MAX_LASER_BEAMS]Laser_Beam, dt: f32) {
	for &beam in laser_beams {
		if !beam.active {
			continue
		}
		beam.lifetime -= dt
		if beam.lifetime <= 0 {
			beam.active = false
		}
	}
}

draw_laser_beams :: proc(laser_beams: ^[MAX_LASER_BEAMS]Laser_Beam) {
	for &beam in laser_beams {
		if !beam.active {
			continue
		}

		alpha := beam.lifetime / beam.max_life
		time := f32(raylib.GetTime())
		pulse := 0.8 + math.sin(time * 30) * 0.2
		thickness: f32 = 3.0 * f32(pulse)

		dir := beam.end - beam.start
		length := linalg.length(dir)
		if length < 1 {
			continue
		}
		dir /= length
		perp := raylib.Vector2{-dir.y, dir.x}

		// Draw as series of overlapping circles for blobby plasma effect
		steps := max(int(length / 2), 1)
		for i in 0 ..< steps {
			t := f32(i) / f32(steps)
			pos := beam.start + dir * length * t

			// Wobble perpendicular to beam direction
			wobble := math.sin(time * 20 + t * 10) * 1.5
			pos += perp * f32(wobble)

			// Outer glow
			raylib.DrawCircleV(pos, thickness * 1.5, {100, 255, 150, u8(alpha * 25)})
			// Inner
			raylib.DrawCircleV(pos, thickness * 0.7, {100, 255, 150, u8(alpha * 140)})
			// Core
			raylib.DrawCircleV(pos, thickness * 0.3, {255, 255, 255, u8(alpha * 200)})
		}

		// Impact glow at endpoint
		flash_radius := 3.0 * alpha
		raylib.DrawCircleV(beam.end, flash_radius * 1.5, {100, 255, 150, u8(alpha * 40)})
		raylib.DrawCircleV(beam.end, flash_radius, {200, 255, 220, u8(alpha * 180)})
	}
}
