extends Control
## Main controller for Vector Chess (Glinski's Hexagonal Chess baseline).
## Manages responsive cross-platform layout, hexagonal telemetry HUD, and pawn promotion UI.

const SHADE_NAMES: Array[String] = ["Dark", "Mid", "Light"]

@onready var split_container: BoxContainer = %MainLayout
@onready var vector_board: VectorBoard = %VectorBoard
@onready var status_label: Label = %StatusLabel
@onready var telemetry_label: RichTextLabel = %TelemetryLabel
@onready var history_label: RichTextLabel = %HistoryLabel
@onready var vectors_button: Button = %VectorsButton
@onready var side_panel: PanelContainer = %SidePanel
@onready var promotion_box: VBoxContainer = %PromotionBox
@onready var toggle_panel_button: Button = %TogglePanelButton


func _ready() -> void:
	vector_board.move_executed.connect(_on_move_executed)
	vector_board.selection_changed.connect(_on_selection_changed)
	vector_board.promotion_requested.connect(_on_promotion_requested)
	toggle_panel_button.draw.connect(_on_toggle_panel_button_draw)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_toggle_panel_button()
	_refresh_hud()


func _on_viewport_size_changed() -> void:
	if split_container == null or side_panel == null:
		return
	var vp_size := get_viewport_rect().size
	var is_portrait := vp_size.y > vp_size.x * 1.05
	split_container.vertical = is_portrait
	if is_portrait:
		side_panel.custom_minimum_size = Vector2(0, 220)
	else:
		side_panel.custom_minimum_size = Vector2(340, 0)


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

	# If panel is visible, highlight the right-hand sidebar column fill
	if side_panel != null and side_panel.visible:
		var side_rect := Rect2(
			Vector2(split_x, rect.position.y + 1.0),
			Vector2(rect.end.x - split_x - 1.0, icon_h - 2.0)
		)
		btn.draw_rect(side_rect, fill_col, true)

	# Outer frame of the split-panel icon
	btn.draw_rect(rect, stroke_col, false, 1.6)

	# Vertical sidebar divider line
	btn.draw_line(
		Vector2(split_x, rect.position.y),
		Vector2(split_x, rect.end.y),
		stroke_col,
		1.5,
		true
	)

	# Collapse/expand chevron inside the main viewport section
	var cy := rect.get_center().y
	var cx := rect.position.x + (split_x - rect.position.x) * 0.5
	var chev_w := 2.4
	var chev_h := 3.0
	var chevron: PackedVector2Array
	if side_panel != null and side_panel.visible:
		# Point right (collapse panel ->)
		chevron = PackedVector2Array([
			Vector2(cx - chev_w * 0.5, cy - chev_h),
			Vector2(cx + chev_w * 0.5, cy),
			Vector2(cx - chev_w * 0.5, cy + chev_h),
		])
	else:
		# Point left (expand panel <-)
		chevron = PackedVector2Array([
			Vector2(cx + chev_w * 0.5, cy - chev_h),
			Vector2(cx - chev_w * 0.5, cy),
			Vector2(cx + chev_w * 0.5, cy + chev_h),
		])
	btn.draw_polyline(chevron, stroke_col, 1.6, true)


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
	promotion_box.visible = false
	vector_board.start_new_game()
	_refresh_hud()


func _on_undo_pressed() -> void:
	promotion_box.visible = false
	if vector_board.undo_move():
		_refresh_hud()


func _on_flip_pressed() -> void:
	vector_board.toggle_flip_board()


func _on_vectors_pressed() -> void:
	var active := vector_board.toggle_vector_overlay()
	vectors_button.text = "Vectors: ON" if active else "Vectors: OFF"


func _on_promote_queen_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.QUEEN)


func _on_promote_rook_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.ROOK)


func _on_promote_bishop_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.BISHOP)


func _on_promote_knight_pressed() -> void:
	vector_board.complete_promotion(PieceData.Type.KNIGHT)
