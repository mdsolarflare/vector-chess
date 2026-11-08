extends Control
## Main controller for Vector Chess (Glinski's Hexagonal Chess baseline).
## Manages responsive cross-platform layout, hexagonal telemetry HUD, pawn promotion UI,
## procedural vector icon buttons, and the slide-to-unlock New Game confirmation modal.

const SHADE_NAMES: Array[String] = ["Dark", "Mid", "Light"]
const SLIDER_UNLOCK_THRESHOLD: float = 98.0

@onready var split_container: BoxContainer = %MainLayout
@onready var vector_board: VectorBoard = %VectorBoard
@onready var status_label: Label = %StatusLabel
@onready var telemetry_label: RichTextLabel = %TelemetryLabel
@onready var history_label: RichTextLabel = %HistoryLabel
@onready var side_panel: PanelContainer = %SidePanel
@onready var promotion_box: VBoxContainer = %PromotionBox
@onready var toggle_panel_button: Button = %TogglePanelButton
@onready var controls_grid: GridContainer = %ControlsGrid
@onready var new_game_button: Button = %NewGameButton
@onready var undo_button: Button = %UndoButton
@onready var flip_button: Button = %FlipButton
@onready var vectors_button: Button = %VectorsButton

@onready var new_game_modal: ColorRect = %NewGameModal
@onready var confirm_slider: HSlider = %ConfirmSlider
@onready var slider_hint_label: Label = %SliderHintLabel
@onready var cancel_new_game_button: Button = %CancelNewGameButton
@onready var confirm_new_game_button: Button = %ConfirmNewGameButton


func _ready() -> void:
	vector_board.move_executed.connect(_on_move_executed)
	vector_board.selection_changed.connect(_on_selection_changed)
	vector_board.promotion_requested.connect(_on_promotion_requested)

	toggle_panel_button.draw.connect(_on_toggle_panel_button_draw)
	new_game_button.draw.connect(_on_new_game_button_draw)
	undo_button.draw.connect(_on_undo_button_draw)
	flip_button.draw.connect(_on_flip_button_draw)
	vectors_button.draw.connect(_on_vectors_button_draw)
	cancel_new_game_button.draw.connect(_on_cancel_new_game_button_draw)
	confirm_new_game_button.draw.connect(_on_confirm_new_game_button_draw)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_toggle_panel_button()
	_update_control_buttons()
	_refresh_hud()


func _on_viewport_size_changed() -> void:
	if split_container == null or side_panel == null:
		return
	var vp_size := get_viewport_rect().size
	var is_portrait := vp_size.y > vp_size.x * 1.05
	split_container.vertical = is_portrait
	if is_portrait:
		side_panel.custom_minimum_size = Vector2(0, 210)
		if controls_grid != null:
			controls_grid.columns = 4
	else:
		side_panel.custom_minimum_size = Vector2(340, 0)
		if controls_grid != null:
			controls_grid.columns = 2


func _on_toggle_panel_pressed() -> void:
	side_panel.visible = not side_panel.visible
	_update_toggle_panel_button()
	vector_board.queue_redraw()


func _update_toggle_panel_button() -> void:
	if toggle_panel_button == null or side_panel == null:
		return
	toggle_panel_button.text = ""
	toggle_panel_button.tooltip_text = "Hide Side Panel" if side_panel.visible else "Show Side Panel"
	toggle_panel_button.queue_redraw()


func _update_control_buttons() -> void:
	if new_game_button != null:
		new_game_button.text = ""
		new_game_button.tooltip_text = "New Game"
		new_game_button.queue_redraw()

	if undo_button != null and vector_board != null:
		undo_button.text = ""
		undo_button.disabled = vector_board.rules.move_history.is_empty()
		undo_button.tooltip_text = "Undo Last Move"
		undo_button.queue_redraw()

	if flip_button != null:
		flip_button.text = ""
		flip_button.tooltip_text = "Flip Board"
		flip_button.queue_redraw()

	if vectors_button != null and vector_board != null:
		vectors_button.text = ""
		vectors_button.tooltip_text = "Vectors: ON (Click to Hide)" if vector_board.show_vectors else "Vectors: OFF (Click to Show)"
		vectors_button.queue_redraw()


func _on_toggle_panel_button_draw() -> void:
	var btn := toggle_panel_button
	var s := btn.size
	var icon_w := 20.0
	var icon_h := 15.0
	var top_left := (s - Vector2(icon_w, icon_h)) * 0.5
	var rect := Rect2(top_left, Vector2(icon_w, icon_h))

	var stroke_col := Color(0.75, 0.88, 1.0, 0.95)
	var fill_col := Color(0.0, 0.94, 1.0, 0.28)
	var split_x := rect.position.x + icon_w * 0.65

	if side_panel != null and side_panel.visible:
		var side_rect := Rect2(
			Vector2(split_x, rect.position.y + 1.0),
			Vector2(rect.end.x - split_x - 1.0, icon_h - 2.0)
		)
		btn.draw_rect(side_rect, fill_col, true)

	btn.draw_rect(rect, stroke_col, false, 1.6)
	btn.draw_line(
		Vector2(split_x, rect.position.y),
		Vector2(split_x, rect.end.y),
		stroke_col,
		1.5,
		true
	)

	var cy := rect.get_center().y
	var cx := rect.position.x + (split_x - rect.position.x) * 0.5
	var chev_w := 2.4
	var chev_h := 3.0
	var chevron: PackedVector2Array
	if side_panel != null and side_panel.visible:
		chevron = PackedVector2Array([
			Vector2(cx - chev_w * 0.5, cy - chev_h),
			Vector2(cx + chev_w * 0.5, cy),
			Vector2(cx - chev_w * 0.5, cy + chev_h),
		])
	else:
		chevron = PackedVector2Array([
			Vector2(cx + chev_w * 0.5, cy - chev_h),
			Vector2(cx - chev_w * 0.5, cy),
			Vector2(cx + chev_w * 0.5, cy + chev_h),
		])
	btn.draw_polyline(chevron, stroke_col, 1.6, true)


## Draws a flat-top Hexagon with a bold '+' sign inside for New Game.
func _on_new_game_button_draw() -> void:
	var btn := new_game_button
	var c := btn.size * 0.5
	var r := 12.5
	var stroke_col := Color(0.82, 0.92, 1.0, 0.95)
	var fill_col := Color(0.0, 0.94, 1.0, 0.12)

	var hex := PackedVector2Array()
	hex.resize(7)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		hex[i] = c + Vector2(cos(a), sin(a)) * r
	hex[6] = hex[0]

	btn.draw_colored_polygon(hex.slice(0, 6), fill_col)
	btn.draw_polyline(hex, stroke_col, 1.8, true)

	var arm := 5.5
	btn.draw_line(c + Vector2(-arm, 0), c + Vector2(arm, 0), VectorBoard.COLOR_CYAN, 2.2, true)
	btn.draw_line(c + Vector2(0, -arm), c + Vector2(0, arm), VectorBoard.COLOR_CYAN, 2.2, true)


## Draws a Left Hook Arrow (↩) for Undo.
func _on_undo_button_draw() -> void:
	var btn := undo_button
	var c := btn.size * 0.5
	var alpha := 0.32 if btn.disabled else 0.95
	var col := Color(0.82, 0.92, 1.0, alpha)

	var arc_center := c + Vector2(3.5, 1.5)
	var arc_r := 6.5
	var top_y := arc_center.y - arc_r
	var bot_y := arc_center.y + arc_r
	var left_x := c.x - 8.5

	var path := PackedVector2Array()
	path.append(Vector2(left_x, top_y))
	var steps := 10
	for i in range(steps + 1):
		var angle := -PI * 0.5 + PI * (float(i) / float(steps))
		path.append(arc_center + Vector2(cos(angle), sin(angle)) * arc_r)
	path.append(Vector2(c.x - 5.5, bot_y))

	btn.draw_polyline(path, col, 2.0, true)

	var tip := Vector2(left_x - 1.0, top_y)
	var head := PackedVector2Array([
		tip + Vector2(5.5, -4.5),
		tip,
		tip + Vector2(5.5, 4.5),
	])
	btn.draw_polyline(head, col, 2.0, true)


## Draws Dual Opposing Vertical Arrows (⇅) for Flip Board, colored by current team orientation.
func _on_flip_button_draw() -> void:
	var btn := flip_button
	var c := btn.size * 0.5
	var flipped := vector_board != null and vector_board.board_flipped
	var up_col := VectorBoard.COLOR_MAGENTA if flipped else VectorBoard.COLOR_CYAN
	var down_col := VectorBoard.COLOR_CYAN if flipped else VectorBoard.COLOR_MAGENTA

	var lx := c.x - 5.0
	var top_y := c.y - 9.5
	var bot_y := c.y + 9.5
	btn.draw_line(Vector2(lx, bot_y), Vector2(lx, top_y), up_col, 2.0, true)
	var up_head := PackedVector2Array([
		Vector2(lx - 4.2, top_y + 4.8),
		Vector2(lx, top_y),
		Vector2(lx + 4.2, top_y + 4.8),
	])
	btn.draw_polyline(up_head, up_col, 2.0, true)

	var rx := c.x + 5.0
	btn.draw_line(Vector2(rx, top_y), Vector2(rx, bot_y), down_col, 2.0, true)
	var down_head := PackedVector2Array([
		Vector2(rx - 4.2, bot_y - 4.8),
		Vector2(rx, bot_y),
		Vector2(rx + 4.2, bot_y - 4.8),
	])
	btn.draw_polyline(down_head, down_col, 2.0, true)


## Draws Radiating Vector Rays from an origin node for Vectors ON/OFF.
func _on_vectors_button_draw() -> void:
	var btn := vectors_button
	var c := btn.size * 0.5
	var active := vector_board != null and vector_board.show_vectors

	if active:
		var inner_rect := Rect2(Vector2(3, 3), btn.size - Vector2(6, 6))
		btn.draw_rect(inner_rect, Color(0.25, 1.0, 0.65, 0.12), true)
		btn.draw_rect(inner_rect, Color(0.25, 1.0, 0.65, 0.45), false, 1.2)

	var ray_col := Color(0.25, 1.0, 0.65, 0.98) if active else Color(0.55, 0.65, 0.78, 0.42)
	var origin := c + Vector2(-8.0, 7.5)

	var angles := [-deg_to_rad(75.0), -deg_to_rad(45.0), -deg_to_rad(15.0)]
	var lengths := [17.0, 19.5, 17.0]
	for i in range(3):
		var a: float = angles[i]
		var len_px: float = lengths[i]
		var dir := Vector2(cos(a), sin(a))
		var normal := Vector2(-dir.y, dir.x)
		var tip := origin + dir * len_px

		btn.draw_line(origin, tip, ray_col, 1.8 if active else 1.4, true)
		var head := PackedVector2Array([
			tip,
			tip - dir * 5.0 + normal * 2.8,
			tip - dir * 5.0 - normal * 2.8,
		])
		btn.draw_colored_polygon(head, ray_col)

	var node_col := Color(1.0, 1.0, 1.0, 0.95) if active else ray_col
	btn.draw_circle(origin, 2.8, node_col)


## Draws a red 'X' icon on the New Game modal Cancel button.
func _on_cancel_new_game_button_draw() -> void:
	var btn := cancel_new_game_button
	var c := btn.size * 0.5
	var red_col := Color(1.0, 0.30, 0.34, 0.95)

	var inner_rect := Rect2(Vector2(3, 3), btn.size - Vector2(6, 6))
	btn.draw_rect(inner_rect, Color(1.0, 0.25, 0.30, 0.12), true)
	btn.draw_rect(inner_rect, Color(1.0, 0.30, 0.34, 0.48), false, 1.3)

	var arm := 6.8
	btn.draw_line(c + Vector2(-arm, -arm), c + Vector2(arm, arm), red_col, 2.4, true)
	btn.draw_line(c + Vector2(-arm, arm), c + Vector2(arm, -arm), red_col, 2.4, true)


## Draws a green '+' icon on the New Game modal Confirm button (dimmed until unlocked).
func _on_confirm_new_game_button_draw() -> void:
	var btn := confirm_new_game_button
	var c := btn.size * 0.5
	var unlocked := not btn.disabled

	if unlocked:
		var inner_rect := Rect2(Vector2(3, 3), btn.size - Vector2(6, 6))
		btn.draw_rect(inner_rect, Color(0.20, 1.0, 0.55, 0.16), true)
		btn.draw_rect(inner_rect, Color(0.25, 1.0, 0.60, 0.68), false, 1.5)

	var green_col := Color(0.25, 1.0, 0.60, 0.98) if unlocked else Color(0.25, 1.0, 0.60, 0.26)
	var arm := 7.5
	btn.draw_line(c + Vector2(-arm, 0), c + Vector2(arm, 0), green_col, 2.6, true)
	btn.draw_line(c + Vector2(0, -arm), c + Vector2(0, arm), green_col, 2.6, true)


func _on_move_executed(_move: GameRules.VectorMove, _notation: String) -> void:
	promotion_box.visible = false
	_refresh_hud()


func _on_selection_changed(piece: PieceData, hovered_move: GameRules.VectorMove) -> void:
	_update_telemetry(piece, hovered_move)


func _on_promotion_requested(_pending_move: GameRules.VectorMove, _team: PieceData.Team) -> void:
	if not side_panel.visible:
		side_panel.visible = true
		_update_toggle_panel_button()
	promotion_box.visible = true
	status_label.text = "Select Promotion Piece"


func _refresh_hud() -> void:
	var rules := vector_board.rules
	status_label.text = rules.status_text
	if rules.current_turn == PieceData.Team.CYAN:
		status_label.modulate = VectorBoard.COLOR_CYAN
	else:
		status_label.modulate = VectorBoard.COLOR_MAGENTA

	_update_telemetry(vector_board.selected_piece, vector_board.hovered_move)
	_update_history()
	_update_control_buttons()


func _update_telemetry(piece: PieceData, hovered_move: GameRules.VectorMove) -> void:
	if piece == null:
		telemetry_label.text = (
			"[b]Glinski Hexagonal Chess (91 Hexes)[/b]\n"
			+ "Select a polygon piece to inspect its axial & Euclidean movement vectors."
		)
		return

	var p_name := PieceData.get_piece_name(piece.type)
	var coord := GameRules.coord_to_algebraic(piece.grid_pos)
	var shade: String = SHADE_NAMES[GameRules.get_cell_color_index(piece.grid_pos)]
	var text := "[b]%s[/b] @ [code]%s[/code]  axial=(%+d,%+d) [%s]\n" % [
		p_name, coord, piece.grid_pos.x, piece.grid_pos.y, shade
	]

	if hovered_move != null:
		var dest := GameRules.coord_to_algebraic(hovered_move.to)
		var deg := hovered_move.get_angle_degrees()
		var mag := hovered_move.get_magnitude()
		var action := "[color=#ff5240]CAPTURE[/color]" if hovered_move.is_capture else "[color=#40ffa6]MOVE[/color]"
		if hovered_move.is_en_passant:
			action = "[color=#ff5240]EN PASSANT[/color]"
		text += (
			"Target: [code]%s[/code] (%s)\n" % [dest, action]
			+ "Axial d=(%+d, %+d)  |v|=%.2f  angle=%.0f deg" % [
				hovered_move.delta.x, hovered_move.delta.y, mag, deg
			]
		)
	else:
		var count := vector_board.legal_moves.size()
		text += "Active Legal Hex Vectors: [b]%d[/b]" % count

	telemetry_label.text = text


func _update_history() -> void:
	var hist := vector_board.rules.move_history
	if hist.is_empty():
		history_label.text = "[i]No moves recorded yet.[/i]"
		return

	var lines: PackedStringArray = []
	for i in range(hist.size()):
		var turn_num := (i / 2) + 1
		var prefix := ("%d. " % turn_num) if (i % 2 == 0) else "    ... "
		lines.append(prefix + str(hist[i].get("notation", "")))
	history_label.text = "\n".join(lines)


func _on_new_game_pressed() -> void:
	_open_new_game_modal()


func _open_new_game_modal() -> void:
	confirm_slider.value = 0.0
	_update_new_game_modal_state(0.0)
	new_game_modal.visible = true


func _on_cancel_new_game_pressed() -> void:
	new_game_modal.visible = false
	confirm_slider.value = 0.0


func _on_confirm_slider_value_changed(val: float) -> void:
	_update_new_game_modal_state(val)


func _on_confirm_slider_drag_ended(_value_changed: bool) -> void:
	if confirm_slider.value < SLIDER_UNLOCK_THRESHOLD:
		confirm_slider.value = 0.0
		_update_new_game_modal_state(0.0)
	else:
		confirm_slider.value = 100.0
		_update_new_game_modal_state(100.0)


func _update_new_game_modal_state(val: float) -> void:
	var unlocked := val >= SLIDER_UNLOCK_THRESHOLD
	confirm_new_game_button.disabled = not unlocked
	cancel_new_game_button.text = ""
	confirm_new_game_button.text = ""
	cancel_new_game_button.queue_redraw()
	confirm_new_game_button.queue_redraw()

	if unlocked:
		slider_hint_label.text = "Unlocked - Press + to Reset"
		slider_hint_label.modulate = Color(0.25, 1.0, 0.65, 1.0)
	else:
		slider_hint_label.text = "Slide all the way right to unlock >>"
		slider_hint_label.modulate = Color(0.65, 0.78, 0.95, 0.9)


func _on_confirm_new_game_pressed() -> void:
	if confirm_slider.value < SLIDER_UNLOCK_THRESHOLD:
		return
	new_game_modal.visible = false
	promotion_box.visible = false
	vector_board.start_new_game()
	_refresh_hud()


func _on_undo_pressed() -> void:
	promotion_box.visible = false
	if vector_board.undo_move():
		_refresh_hud()


func _on_flip_pressed() -> void:
	vector_board.toggle_flip_board()
	_update_control_buttons()


func _on_vectors_pressed() -> void:
	vector_board.toggle_vector_overlay()
	_update_control_buttons()


func _on_promote_queen_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.QUEEN)


func _on_promote_rook_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.ROOK)


func _on_promote_bishop_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.BISHOP)


func _on_promote_knight_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.KNIGHT)
