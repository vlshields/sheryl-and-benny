package sheryl_and_benny

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "vendor:raylib"

MAX_DIALOGUE_LINES :: 32
MAX_CHOICES :: 4
WORD_REVEAL_INTERVAL :: 0.07
NPC_INTERACT_DIST :: 24.0

DIALOGUE_BOX_W :: 560
DIALOGUE_BOX_H :: 90
DIALOGUE_BOX_MARGIN :: 12
DIALOGUE_TEXT_SIZE: f32 : 12
DIALOGUE_SPEAKER_SIZE: f32 : 16

Dialogue_Line :: struct {
	speaker:      string,
	text:         string,
	choices:      [MAX_CHOICES]string,
	choice_count: int,
}

Dialogue_State :: struct {
	lines:            [MAX_DIALOGUE_LINES]Dialogue_Line,
	line_count:       int,
	current_line:     int,
	active:           bool,
	words_revealed:   int,
	word_timer:       f32,
	word_count:       int,
	loaded:           bool,
	completed:        bool,
	selected_choice:  int,
	chosen:           int,
}

parse_dialogue_file :: proc(path: string) -> (state: Dialogue_State, ok: bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("could not open dialogue file:", path)
		return {}, false
	}
	defer delete(data)

	content := string(data)
	in_dialogue := false
	line_idx := 0
	current_text: strings.Builder
	current_speaker := ""
	has_content := false

	for line in strings.split_lines_iterator(&content) {
		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 {
			continue
		}
		if trimmed[0] == '*' {
			continue
		}
		if trimmed == "[START]" {
			in_dialogue = true
			continue
		}
		if trimmed == "[END]" {
			// Flush any remaining content
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
			}
			strings.builder_destroy(&current_text)
			break
		}
		if !in_dialogue {
			continue
		}
		if trimmed == "[PRESS ENTER]" {
			// Flush current line
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
				strings.builder_destroy(&current_text)
				current_text = {}
				has_content = false
			}
			continue
		}

		// Check for choice line: [CHOICE1] [CHOICE2] ...
		if trimmed[0] == '[' && trimmed != "[START]" && trimmed != "[END]" && trimmed != "[PRESS ENTER]" {
			// Flush current text as a line first
			if has_content && line_idx < MAX_DIALOGUE_LINES {
				state.lines[line_idx] = Dialogue_Line {
					speaker = strings.clone(current_speaker),
					text    = strings.clone(strings.to_string(current_text)),
				}
				line_idx += 1
				strings.builder_destroy(&current_text)
				current_text = {}
				has_content = false
			}
			// Parse choices from brackets
			if line_idx < MAX_DIALOGUE_LINES {
				choice_line: Dialogue_Line
				choice_line.speaker = strings.clone(current_speaker)
				choice_line.text = ""
				remaining := trimmed
				for choice_line.choice_count < MAX_CHOICES {
					open := strings.index(remaining, "[")
					if open < 0 {
						break
					}
					close := strings.index(remaining[open:], "]")
					if close < 0 {
						break
					}
					choice_text := remaining[open + 1:open + close]
					choice_line.choices[choice_line.choice_count] = strings.clone(choice_text)
					choice_line.choice_count += 1
					remaining = remaining[open + close + 1:]
				}
				state.lines[line_idx] = choice_line
				line_idx += 1
			}
			continue
		}

		// Parse "SPEAKER: text"
		colon_idx := strings.index(trimmed, ": ")
		if colon_idx >= 0 {
			current_speaker = trimmed[:colon_idx]
			text_part := trimmed[colon_idx + 2:]
			if has_content {
				strings.write_byte(&current_text, ' ')
			}
			strings.write_string(&current_text, text_part)
			has_content = true
		}
	}

	state.line_count = line_idx
	state.loaded = true
	return state, line_idx > 0
}

start_dialogue :: proc(dialogue: ^Dialogue_State) {
	if !dialogue.loaded || dialogue.line_count == 0 {
		return
	}
	dialogue.active = true
	dialogue.current_line = 0
	dialogue.words_revealed = 0
	dialogue.word_timer = 0
	dialogue.completed = false
	dialogue.selected_choice = 0
	dialogue.chosen = -1
	dialogue.word_count = count_words(dialogue.lines[0].text)
}

update_dialogue :: proc(dialogue: ^Dialogue_State, dt: f32, audio: ^Audio_State) {
	if !dialogue.active {
		return
	}

	cur_line := dialogue.lines[dialogue.current_line]
	has_choices := cur_line.choice_count > 0

	// Choice lines: handle left/right selection and confirm
	if has_choices {
		move_left := raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressed(.A)
		move_right := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D)
		if raylib.IsGamepadAvailable(0) {
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
				move_left = true
			}
			if raylib.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
				move_right = true
			}
		}
		if move_left && dialogue.selected_choice > 0 {
			dialogue.selected_choice -= 1
			play_sfx(audio.ui_back)
		}
		if move_right && dialogue.selected_choice < cur_line.choice_count - 1 {
			dialogue.selected_choice += 1
			play_sfx(audio.ui_back)
		}

		confirm := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.E) || raylib.IsKeyPressed(.SPACE)
		if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			confirm = true
		}
		if confirm {
			play_sfx(audio.ui_confirm)
			dialogue.chosen = dialogue.selected_choice
			dialogue.active = false
			dialogue.completed = true
		}
		return
	}

	all_revealed := dialogue.words_revealed >= dialogue.word_count

	// Advance input: ENTER, E, or SPACE
	advance := raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.E) || raylib.IsKeyPressed(.SPACE)
	if raylib.IsGamepadAvailable(0) && raylib.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
		advance = true
	}

	if advance {
		if !all_revealed {
			// Reveal all words instantly
			dialogue.words_revealed = dialogue.word_count
		} else {
			// Go to next line
			play_sfx(audio.ui_confirm)
			dialogue.current_line += 1
			if dialogue.current_line >= dialogue.line_count {
				dialogue.active = false
				dialogue.completed = true
				return
			}
			dialogue.words_revealed = 0
			dialogue.word_timer = 0
			dialogue.selected_choice = 0
			dialogue.word_count = count_words(dialogue.lines[dialogue.current_line].text)
		}
		return
	}

	// Word reveal timer
	if !all_revealed {
		dialogue.word_timer += dt
		if dialogue.word_timer >= WORD_REVEAL_INTERVAL {
			dialogue.word_timer -= WORD_REVEAL_INTERVAL
			dialogue.words_revealed += 1
		}
	}
}

draw_dialogue :: proc(dialogue: ^Dialogue_State, font: raylib.Font) {
	if !dialogue.active {
		return
	}

	line := dialogue.lines[dialogue.current_line]

	// Box position: centered at bottom of screen
	box_x: f32 = (f32(SCREEN_WIDTH) - f32(DIALOGUE_BOX_W)) / 2
	box_y: f32 = f32(SCREEN_HEIGHT) - f32(DIALOGUE_BOX_H) - 10

	// Background
	bg_color := raylib.Color{15, 12, 25, 230}
	border_color := raylib.Color{200, 180, 220, 255}
	raylib.DrawRectangle(i32(box_x), i32(box_y), DIALOGUE_BOX_W, DIALOGUE_BOX_H, bg_color)
	raylib.DrawRectangleLinesEx(
		{box_x, box_y, f32(DIALOGUE_BOX_W), f32(DIALOGUE_BOX_H)},
		2,
		border_color,
	)

	// Speaker name
	speaker_color := raylib.Color{255, 220, 50, 255}
	text_color := raylib.Color{220, 215, 235, 255}
	speaker_cstr := strings.clone_to_cstring(line.speaker)
	defer delete(speaker_cstr)
	raylib.DrawTextEx(
		font,
		speaker_cstr,
		{box_x + f32(DIALOGUE_BOX_MARGIN), box_y + 6},
		DIALOGUE_SPEAKER_SIZE,
		1,
		speaker_color,
	)

	// Build revealed text (word by word)
	revealed := get_revealed_text(line.text, dialogue.words_revealed)
	revealed_cstr := strings.clone_to_cstring(revealed)
	defer delete(revealed_cstr)

	// Text area below speaker name, with wrapping
	text_x := box_x + f32(DIALOGUE_BOX_MARGIN)
	text_y := box_y + 28
	max_w := f32(DIALOGUE_BOX_W) - f32(DIALOGUE_BOX_MARGIN) * 2

	draw_wrapped_text(font, revealed_cstr, text_x, text_y, max_w, DIALOGUE_TEXT_SIZE, text_color)

	// Choice buttons or "Press ENTER" prompt
	if line.choice_count > 0 {
		draw_dialogue_choices(dialogue, font, box_x, box_y)
	} else if dialogue.words_revealed >= dialogue.word_count {
		prompt_size: f32 = 12
		pulse_alpha := u8(150 + i32(105 * math.sin(f32(raylib.GetTime()) * 3.0)))
		if pulse_alpha < 150 {
			pulse_alpha = 150
		}
		prompt_color := raylib.Color{180, 180, 180, pulse_alpha}
		prompt_x := box_x + f32(DIALOGUE_BOX_W) - 90
		prompt_y := box_y + f32(DIALOGUE_BOX_H) - 18
		raylib.DrawTextEx(font, "[ENTER]", {prompt_x, prompt_y}, prompt_size, 1, prompt_color)
	}
}

// Check if the player is close enough to any NPC to interact
find_nearby_npc :: proc(player: ^Player, npcs: ^[MAX_NPCS]NPC) -> int {
	for &npc, i in npcs {
		if !npc.active {
			continue
		}
		dx := player.pos.x - npc.pos.x
		dy := (player.pos.y - f32(SPRITE_DST_SIZE) / 2) - (npc.pos.y - f32(SPRITE_DST_SIZE) / 2)
		dist := dx * dx + dy * dy
		if dist < NPC_INTERACT_DIST * NPC_INTERACT_DIST {
			return i
		}
	}
	return -1
}

draw_interact_prompt :: proc(npc: ^NPC) {
	// Hovering gold arrow above NPC
	hover_offset := math.sin(f32(raylib.GetTime()) * 3.0) * 2.0
	color := raylib.Color{255, 220, 50, 230}
	cx := npc.pos.x
	tip_y := npc.pos.y - f32(SPRITE_DST_SIZE) - 10 + hover_offset
	half_w: f32 = 4
	height: f32 = 6
	raylib.DrawTriangle(
		{cx, tip_y + height},
		{cx + half_w, tip_y},
		{cx - half_w, tip_y},
		color,
	)
}

// Helper: count words in a string
count_words :: proc(text: string) -> int {
	count := 0
	in_word := false
	for c in text {
		if c == ' ' || c == '\t' || c == '\n' {
			in_word = false
		} else if !in_word {
			in_word = true
			count += 1
		}
	}
	return count
}

// Helper: get the first N words of a string
get_revealed_text :: proc(text: string, n: int) -> string {
	if n <= 0 {
		return ""
	}
	count := 0
	in_word := false
	for i := 0; i < len(text); i += 1 {
		c := text[i]
		if c == ' ' || c == '\t' || c == '\n' {
			in_word = false
		} else if !in_word {
			in_word = true
			count += 1
			if count > n {
				// Return up to the space before this word
				return text[:i - 1] if i > 0 else ""
			}
		}
	}
	return text
}

// Helper: draw text with word wrapping
draw_wrapped_text :: proc(
	font: raylib.Font,
	text: cstring,
	x, y, max_width, size: f32,
	color: raylib.Color,
) {
	// Use raylib's built-in word wrap by drawing character by character
	odin_text := string(text)
	words := strings.split(odin_text, " ")
	defer delete(words)

	cur_x := x
	cur_y := y
	space_w := raylib.MeasureTextEx(font, " ", size, 1).x

	for word, i in words {
		if len(word) == 0 {
			continue
		}
		word_cstr := strings.clone_to_cstring(word)
		defer delete(word_cstr)
		word_w := raylib.MeasureTextEx(font, word_cstr, size, 1).x

		// Wrap to next line if needed
		if cur_x + word_w > x + max_width && cur_x > x {
			cur_x = x
			cur_y += size + 2
		}

		raylib.DrawTextEx(font, word_cstr, {cur_x, cur_y}, size, 1, color)
		cur_x += word_w + space_w
		_ = i
	}
}

draw_dialogue_choices :: proc(dialogue: ^Dialogue_State, font: raylib.Font, box_x: f32, box_y: f32) {
	line := dialogue.lines[dialogue.current_line]
	choice_size: f32 = 12
	choice_y := box_y + f32(DIALOGUE_BOX_H) - 22
	padding: f32 = 16
	gap: f32 = 12

	// Measure total width to center choices
	total_w: f32 = 0
	for i := 0; i < line.choice_count; i += 1 {
		label := strings.clone_to_cstring(line.choices[i])
		defer delete(label)
		total_w += raylib.MeasureTextEx(font, label, choice_size, 1).x + padding * 2
		if i < line.choice_count - 1 {
			total_w += gap
		}
	}

	cur_x := box_x + (f32(DIALOGUE_BOX_W) - total_w) / 2

	for i := 0; i < line.choice_count; i += 1 {
		label := strings.clone_to_cstring(line.choices[i])
		defer delete(label)
		text_w := raylib.MeasureTextEx(font, label, choice_size, 1).x
		btn_w := text_w + padding * 2
		btn_h: f32 = 18

		selected := i == dialogue.selected_choice
		bg := raylib.Color{255, 220, 50, 220} if selected else raylib.Color{60, 50, 80, 200}
		text_col := raylib.Color{15, 12, 25, 255} if selected else raylib.Color{200, 190, 220, 255}

		raylib.DrawRectangleRounded({cur_x, choice_y, btn_w, btn_h}, 0.3, 4, bg)
		raylib.DrawTextEx(
			font,
			label,
			{cur_x + padding, choice_y + 3},
			choice_size,
			1,
			text_col,
		)

		cur_x += btn_w + gap
	}
}

destroy_dialogue :: proc(dialogue: ^Dialogue_State) {
	for i := 0; i < dialogue.line_count; i += 1 {
		delete(dialogue.lines[i].speaker)
		delete(dialogue.lines[i].text)
		for j := 0; j < dialogue.lines[i].choice_count; j += 1 {
			delete(dialogue.lines[i].choices[j])
		}
	}
	dialogue^ = {}
}
