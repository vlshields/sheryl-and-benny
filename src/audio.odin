package sheryl_and_benny

import "vendor:raylib"

Audio_State :: struct {
	music:              raylib.Music,
	arena_music:        raylib.Music,
	playing_arena:      bool,
	blaster_shot:       raylib.Sound,
	flamethrower_loop:  raylib.Sound,
	lasergun_loop:      raylib.Sound,
	slinger_loop:       raylib.Sound,
	hit:                raylib.Sound,
	item_pickup:        raylib.Sound,
	out_of_ammo:        raylib.Sound,
	footsteps:          raylib.Sound,
	reload:             raylib.Sound,
	ui_back:            raylib.Sound,
	ui_confirm:         raylib.Sound,
	boss_warcry:        raylib.Sound,
	music_volume:       f32,
	sfx_volume:         f32,
}

init_audio :: proc(audio: ^Audio_State) {
	raylib.InitAudioDevice()

	audio.music_volume = 0.5
	audio.sfx_volume = 1.0

	audio.music = raylib.LoadMusicStream("assets/audio/soundtrack/sheryl_and_benny.ogg")
	audio.music.looping = true
	raylib.SetMusicVolume(audio.music, audio.music_volume)
	raylib.PlayMusicStream(audio.music)

	audio.arena_music = raylib.LoadMusicStream("assets/audio/soundtrack/arena.ogg")
	audio.arena_music.looping = true
	raylib.SetMusicVolume(audio.arena_music, audio.music_volume)

	audio.blaster_shot = raylib.LoadSound("assets/audio/sfx/blaster_shot.wav")
	audio.flamethrower_loop = raylib.LoadSound("assets/audio/sfx/flamethrower_loop.wav")
	audio.lasergun_loop = raylib.LoadSound("assets/audio/sfx/lasergun_loop.wav")
	audio.slinger_loop = raylib.LoadSound("assets/audio/sfx/slinger_loop.wav")
	audio.hit = raylib.LoadSound("assets/audio/sfx/hit.wav")
	audio.item_pickup = raylib.LoadSound("assets/audio/sfx/item_pickup.wav")
	audio.out_of_ammo = raylib.LoadSound("assets/audio/sfx/out_of_ammo.wav")
	audio.footsteps = raylib.LoadSound("assets/audio/sfx/player_footsteps.wav")
	audio.reload = raylib.LoadSound("assets/audio/sfx/reload.wav")
	audio.ui_back = raylib.LoadSound("assets/audio/sfx/ui_back_or_door_locked.wav")
	audio.ui_confirm = raylib.LoadSound("assets/audio/sfx/ui_confirm.wav")
	audio.boss_warcry = raylib.LoadSound("assets/audio/sfx/donald_monroe_warcry.wav")

	raylib.SetSoundVolume(audio.blaster_shot, 0.6)
	raylib.SetSoundVolume(audio.flamethrower_loop, 0.4)
	raylib.SetSoundVolume(audio.lasergun_loop, 0.5)
	raylib.SetSoundVolume(audio.slinger_loop, 0.5)
	raylib.SetSoundVolume(audio.hit, 0.7)
	raylib.SetSoundVolume(audio.item_pickup, 0.7)
	raylib.SetSoundVolume(audio.out_of_ammo, 0.6)
	raylib.SetSoundVolume(audio.footsteps, 0.1)
	raylib.SetSoundVolume(audio.reload, 0.7)
	raylib.SetSoundVolume(audio.ui_back, 0.6)
	raylib.SetSoundVolume(audio.ui_confirm, 0.6)
	raylib.SetSoundVolume(audio.boss_warcry, 0.8)
}

destroy_audio :: proc(audio: ^Audio_State) {
	raylib.UnloadMusicStream(audio.music)
	raylib.UnloadMusicStream(audio.arena_music)
	raylib.UnloadSound(audio.blaster_shot)
	raylib.UnloadSound(audio.flamethrower_loop)
	raylib.UnloadSound(audio.lasergun_loop)
	raylib.UnloadSound(audio.slinger_loop)
	raylib.UnloadSound(audio.hit)
	raylib.UnloadSound(audio.item_pickup)
	raylib.UnloadSound(audio.out_of_ammo)
	raylib.UnloadSound(audio.footsteps)
	raylib.UnloadSound(audio.reload)
	raylib.UnloadSound(audio.ui_back)
	raylib.UnloadSound(audio.ui_confirm)
	raylib.UnloadSound(audio.boss_warcry)
	raylib.CloseAudioDevice()
}

update_music :: proc(audio: ^Audio_State) {
	if audio.playing_arena {
		raylib.UpdateMusicStream(audio.arena_music)
	} else {
		raylib.UpdateMusicStream(audio.music)
	}
}

switch_music :: proc(audio: ^Audio_State, arena: bool) {
	if audio.playing_arena == arena {
		return
	}
	if arena {
		raylib.StopMusicStream(audio.music)
		raylib.PlayMusicStream(audio.arena_music)
	} else {
		raylib.StopMusicStream(audio.arena_music)
		raylib.PlayMusicStream(audio.music)
	}
	audio.playing_arena = arena
}

play_sfx :: proc(sound: raylib.Sound) {
	raylib.PlaySound(sound)
}

stop_sfx :: proc(sound: raylib.Sound) {
	if raylib.IsSoundPlaying(sound) {
		raylib.StopSound(sound)
	}
}

// Play a looping sound only if it's not already playing
play_sfx_loop :: proc(sound: raylib.Sound) {
	if !raylib.IsSoundPlaying(sound) {
		raylib.PlaySound(sound)
	}
}

// Stop all weapon loop sounds
stop_weapon_loops :: proc(audio: ^Audio_State) {
	stop_sfx(audio.flamethrower_loop)
	stop_sfx(audio.lasergun_loop)
	stop_sfx(audio.slinger_loop)
}

// Apply current volume levels to all audio
apply_audio_volumes :: proc(audio: ^Audio_State) {
	raylib.SetMusicVolume(audio.music, audio.music_volume)
	raylib.SetMusicVolume(audio.arena_music, audio.music_volume)

	sv := audio.sfx_volume
	raylib.SetSoundVolume(audio.blaster_shot, 0.6 * sv)
	raylib.SetSoundVolume(audio.flamethrower_loop, 0.4 * sv)
	raylib.SetSoundVolume(audio.lasergun_loop, 0.5 * sv)
	raylib.SetSoundVolume(audio.slinger_loop, 0.5 * sv)
	raylib.SetSoundVolume(audio.hit, 0.7 * sv)
	raylib.SetSoundVolume(audio.item_pickup, 0.7 * sv)
	raylib.SetSoundVolume(audio.out_of_ammo, 0.6 * sv)
	raylib.SetSoundVolume(audio.footsteps, 0.1 * sv)
	raylib.SetSoundVolume(audio.reload, 0.7 * sv)
	raylib.SetSoundVolume(audio.ui_back, 0.6 * sv)
	raylib.SetSoundVolume(audio.ui_confirm, 0.6 * sv)
	raylib.SetSoundVolume(audio.boss_warcry, 0.8 * sv)
}
