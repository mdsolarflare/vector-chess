class_name VectorBoard
extends Control
## Procedural vector-graphics hexagonal chessboard renderer for Gliński's Hexagonal Chess.
## Renders the 91-cell flat-top hexagonal board in 3 colors with axial coordinate hit-testing,
## displacement vector rays, and procedural polygon pieces.

signal move_executed(move: GameRules.VectorMove, notation: String)
signal selection_changed(piece: PieceData, hovered_move: GameRules.VectorMove)
signal promotion_requested(pending_move: GameRules.VectorMove, team: PieceData.Team)

const SQRT3: float = 1.73205080757

const COLOR_HEX_0 := Color(0.065, 0.082, 0.135, 1.0)     # Darkest hex shade
const COLOR_HEX_1 := Color(0.105, 0.132, 0.210, 1.0)     # Medium hex shade
const COLOR_HEX_2 := Color(0.150, 0.188, 0.290, 1.0)     # Lightest hex shade
const COLOR_GRID_LINE := Color(0.22, 0.31, 0.46, 0.85)
const COLOR_OUTER_BORDER := Color(0.32, 0.48, 0.72, 0.9)
const COLOR_CYAN := Color(0.0, 0.94, 1.0, 1.0)
const COLOR_MAGENTA := Color(1.0, 0.16, 0.52, 1.0)
const COLOR_VECTOR_RAY := Color(0.25, 1.0, 0.65, 0.85)
const COLOR_CAPTURE_RAY := Color(1.0, 0.32, 0.25, 0.95)
const COLOR_LAST_MOVE := Color(1.0, 0.82, 0.2, 0.70)

var rules: GameRules = GameRules.new()
var selected_piece: PieceData = null
var legal_moves: Array[GameRules.VectorMove] = []
var hovered_cell: Vector2i = GameRules.INVALID_HEX
var hovered_move: GameRules.VectorMove = null
var pending_promotion_move: GameRules.VectorMove = null
var board_flipped: bool = false
var show_all_team_vectors: bool = false
var show_cell_coords: bool = true

var _board_center: Vector2 = Vector2.ZERO
var _hex_radius: float = 28.0
var _pulse_time: float = 0.0
var _bursts: Array[Dictionary] = []
var _all_cells: Array[Vector2i] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_all_cells = GameRules.get_all_board_cells()
	set_process(true)


func _process(delta: float) -> void:
	_pulse_time += delta

	for p in rules.pieces:
		var target := Vector2(p.grid_pos)
		if p.visual_pos.distance_squared_to(target) > 0.0001:
			p.visual_pos = p.visual_pos.lerp(target, clampf(delta * 16.0, 0.0, 1.0))
		else:
			p.visual_pos = target

	for i in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["age"] += delta
		if _bursts[i]["age"] >= _bursts[i]["lifetime"]:
			_bursts.remove_at(i)

	queue_redraw()


func start_new_game() -> void:
	rules.reset_game()
	selected_piece = null
	legal_moves.clear()
	hovered_move = null
	pending_promotion_move = null
	_bursts.clear()
	selection_changed.emit(null, null)
	queue_redraw()


func undo_move() -> bool:
	pending_promotion_move = null
	if rules.undo_last_move():
		selected_piece = null
		legal_moves.clear()
		hovered_move = null
		selection_changed.emit(null, null)
		queue_redraw()
		return true
	return false


func toggle_flip_board() -> void:
	board_flipped = not board_flipped
	queue_redraw()


func toggle_vector_overlay() -> bool:
	show_all_team_vectors = not show_all_team_vectors
	queue_redraw()
	return show_all_team_vectors


func complete_promotion(chosen_type: PieceData.Type) -> void:
	if pending_promotion_move == null:
		return
	var mv := pending_promotion_move
	pending_promotion_move = null
	mv.promotion_type = chosen_type
	_commit_move(mv)


func _gui_input(event: InputEvent) -> void:
	if pending_promotion_move != null:
		return

	if event is InputEventMouseMotion:
		var cell := _screen_to_axial(event.position)
		if cell != hovered_cell:
			hovered_cell = cell
			_update_hovered_move()
			queue_redraw()

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _screen_to_axial(event.position)
		_handle_cell_interaction(cell)


func _handle_cell_interaction(cell: Vector2i) -> void:
	if not GameRules.is_inside_board(cell) or rules.is_game_over:
		_clear_selection()
		return

	if selected_piece != null:
		for mv in legal_moves:
			if mv.to == cell:
				if mv.is_promotion:
					pending_promotion_move = mv
					promotion_requested.emit(mv, selected_piece.team)
				else:
					_commit_move(mv)
				return

	var clicked_piece := rules.get_piece_at(cell)
	if clicked_piece != null and clicked_piece.team == rules.current_turn:
		selected_piece = clicked_piece
		legal_moves = rules.get_legal_moves_for_piece(selected_piece)
		_update_hovered_move()
		selection_changed.emit(selected_piece, hovered_move)
		queue_redraw()
	else:
		_clear_selection()


func _commit_move(move: GameRules.VectorMove) -> void:
	if move.is_capture:
		var captured_piece := rules.get_piece_by_id(move.captured_piece_id)
		if captured_piece == null:
			captured_piece = rules.get_piece_at(move.captured_pos)
		var burst_color := COLOR_MAGENTA if (captured_piece != null and captured_piece.team == PieceData.Team.MAGENTA) else COLOR_CYAN
		_spawn_polygon_burst(move.captured_pos, burst_color)

	if rules.execute_move(move):
		var notation: String = str(rules.move_history[-1].get("notation", ""))
		selected_piece = null
		legal_moves.clear()
		hovered_move = null
		selection_changed.emit(null, null)
		move_executed.emit(move, notation)
		queue_redraw()


func _clear_selection() -> void:
	selected_piece = null
	legal_moves.clear()
	hovered_move = null
	selection_changed.emit(null, null)
	queue_redraw()


func _update_hovered_move() -> void:
	hovered_move = null
	if selected_piece != null and GameRules.is_inside_board(hovered_cell):
		for mv in legal_moves:
			if mv.to == hovered_cell:
				hovered_move = mv
				break
	selection_changed.emit(selected_piece, hovered_move)


func _draw() -> void:
	_compute_board_metrics()

	var hex_colors: Array[Color] = [COLOR_HEX_0, COLOR_HEX_1, COLOR_HEX_2]

	# 1. Draw all 91 hexagonal cells with 3-color tiling
	for cell in _all_cells:
		var center := _axial_to_screen(Vector2(cell))
		var col_idx := GameRules.get_cell_color_index(cell)
		var poly := _make_hex_polygon(center, _hex_radius)
		draw_colored_polygon(poly, hex_colors[col_idx])

		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, COLOR_GRID_LINE, 1.3, true)

		# Subtle starting-pawn chevron indicator on empty pawn start cells
		if rules.is_pawn_start_cell(PieceData.Team.CYAN, cell) or rules.is_pawn_start_cell(PieceData.Team.MAGENTA, cell):
			var inner_hex := _make_hex_polygon(center, _hex_radius * 0.22)
			inner_hex.append(inner_hex[0])
			draw_polyline(inner_hex, Color(0.35, 0.5, 0.7, 0.22), 1.0, true)

	# 2. Draw coordinate labels (files along bottom/top, algebraic inside edge cells)
	if show_cell_coords:
		_draw_hex_coordinates()

	# 3. Highlight last executed move
	if rules.last_move != null:
		var from_c := _axial_to_screen(Vector2(rules.last_move.from))
		var to_c := _axial_to_screen(Vector2(rules.last_move.to))
		_draw_hex_highlight(from_c, Color(COLOR_LAST_MOVE, 0.16), Color(COLOR_LAST_MOVE, 0.55), 1.8)
		_draw_hex_highlight(to_c, Color(COLOR_LAST_MOVE, 0.24), Color(COLOR_LAST_MOVE, 0.75), 2.2)
		_draw_vector_arrow(from_c, to_c, COLOR_LAST_MOVE, 2.0, false)

	# 4. Optional team-wide vector overlay
	if show_all_team_vectors:
		for p in rules.pieces:
			if p.team == rules.current_turn:
				var p_moves := rules.get_legal_moves_for_piece(p)
				var team_col := COLOR_CYAN if p.team == PieceData.Team.CYAN else COLOR_MAGENTA
				var ray_col := Color(team_col.r, team_col.g, team_col.b, 0.24)
				var origin := _axial_to_screen(p.visual_pos)
				for mv in p_moves:
					var dest := _axial_to_screen(Vector2(mv.to))
					_draw_vector_arrow(origin, dest, ray_col, 1.4, false)

	# 5. Selected piece & legal move vectors
	if selected_piece != null:
		var sel_center := _axial_to_screen(Vector2(selected_piece.grid_pos))
		var sel_col := COLOR_CYAN if selected_piece.team == PieceData.Team.CYAN else COLOR_MAGENTA
		_draw_hex_highlight(sel_center, Color(sel_col, 0.22), sel_col, 2.6)

		var origin := _axial_to_screen(selected_piece.visual_pos)
		for mv in legal_moves:
			var dest := _axial_to_screen(Vector2(mv.to))
			var is_hovered := (hovered_move == mv)
			var col := COLOR_CAPTURE_RAY if mv.is_capture else COLOR_VECTOR_RAY
			var alpha := 1.0 if is_hovered else 0.68
			var width := 3.0 if is_hovered else 1.7

			if mv.is_capture:
				_draw_hex_highlight(dest, Color(col, 0.18 if not is_hovered else 0.34), Color(col, alpha), width)
			else:
				draw_circle(dest, _hex_radius * (0.24 if is_hovered else 0.16), Color(col, alpha))

			_draw_vector_arrow(origin, dest, Color(col, alpha), width, is_hovered)

	# 6. Hover cursor hex outline
	if GameRules.is_inside_board(hovered_cell):
		var h_center := _axial_to_screen(Vector2(hovered_cell))
		_draw_hex_highlight(h_center, Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.35), 1.6)

	# 7. Highlight King in check
	for team in [PieceData.Team.CYAN, PieceData.Team.MAGENTA]:
		if rules.is_king_in_check(team):
			for p in rules.pieces:
				if p.team == team and p.type == PieceData.Type.KING:
					var k_center := _axial_to_screen(Vector2(p.grid_pos))
					var pulse := 0.5 + 0.5 * sin(_pulse_time * 8.0)
					_draw_hex_highlight(
						k_center,
						Color(1.0, 0.15, 0.15, 0.25 + 0.25 * pulse),
						Color(1.0, 0.2, 0.2, 0.95),
						3.0
					)

	# 8. Draw all pieces
	for p in rules.pieces:
		_draw_polygon_piece(p)

	# 9. Draw capture bursts
	_draw_bursts()


func _draw_hex_highlight(center: Vector2, fill_col: Color, border_col: Color, border_width: float) -> void:
	var poly := _make_hex_polygon(center, _hex_radius * 0.92)
	if fill_col.a > 0.001:
		draw_colored_polygon(poly, fill_col)
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, border_col, border_width, true)


func _draw_polygon_piece(piece: PieceData) -> void:
	var center := _axial_to_screen(piece.visual_pos)
	var radius := _hex_radius * 0.68
	var primary := COLOR_CYAN if piece.team == PieceData.Team.CYAN else COLOR_MAGENTA
	var fill_col := Color(primary.r * 0.18, primary.g * 0.18, primary.b * 0.24, 0.92)
	var is_selected := (selected_piece != null and selected_piece.id == piece.id)

	if is_selected:
		radius *= (1.0 + 0.07 * sin(_pulse_time * 6.0))

	var layers := piece.get_normalized_polygons()
	for layer_idx in range(layers.size()):
		var norm_poly: PackedVector2Array = layers[layer_idx]
		var world_poly := PackedVector2Array()
		world_poly.resize(norm_poly.size())

		var rot := PI if board_flipped else 0.0
		if is_selected and layer_idx > 0:
			rot += _pulse_time * 1.2

		for i in range(norm_poly.size()):
			world_poly[i] = center + norm_poly[i].rotated(rot) * radius

		if layer_idx == 0:
			draw_colored_polygon(world_poly, fill_col)
			var closed := world_poly.duplicate()
			closed.append(world_poly[0])
			draw_polyline(closed, Color(primary, 0.35), 4.0, true)
			draw_polyline(closed, primary, 2.0, true)
		else:
			var closed_inner := world_poly.duplicate()
			closed_inner.append(world_poly[0])
			var inner_col := Color(1.0, 1.0, 1.0, 0.9) if is_selected else Color(primary.lightened(0.35), 0.85)
			draw_polyline(closed_inner, inner_col, 1.5, true)

	# Piece letter badge in center for instant chess readability alongside polygon shape
	var font := ThemeDB.fallback_font
	if font != null and _hex_radius >= 18.0:
		var code := PieceData.get_piece_short_code(piece.type)
		var font_size := clampi(int(_hex_radius * 0.42), 9, 14)
		draw_string(
			font,
			center + Vector2(-float(font_size) * 0.3, float(font_size) * 0.35),
			code,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			Color(1.0, 1.0, 1.0, 0.92)
		)


func _draw_vector_arrow(from_pt: Vector2, to_pt: Vector2, color: Color, width: float, draw_label: bool) -> void:
	var diff := to_pt - from_pt
	var dist := diff.length()
	if dist < 4.0:
		return
	var dir := diff / dist
	var normal := Vector2(-dir.y, dir.x)

	var start_pt := from_pt + dir * (_hex_radius * 0.32)
	var tip_pt := to_pt - dir * (_hex_radius * 0.25)
	draw_line(start_pt, tip_pt, color, width, true)

	var head_len := clampf(_hex_radius * 0.34, 7.0, 14.0)
	var head_width := head_len * 0.55
	var arrow_head := PackedVector2Array([
		tip_pt,
		tip_pt - dir * head_len + normal * head_width,
		tip_pt - dir * (head_len * 0.65),
		tip_pt - dir * head_len - normal * head_width,
	])
	draw_colored_polygon(arrow_head, color)

	if draw_label and ThemeDB.fallback_font != null:
		var mid := (start_pt + tip_pt) * 0.5 + normal * 12.0
		var axial_delta := _screen_to_axial(to_pt) - _screen_to_axial(from_pt)
		var label := "Δ(%+d,%+d)" % [axial_delta.x, axial_delta.y]
		draw_string(ThemeDB.fallback_font, mid, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, color.lightened(0.35))


func _draw_hex_coordinates() -> void:
	var font := ThemeDB.fallback_font
	if font == null or _hex_radius < 16.0:
		return

	var font_size := clampi(int(_hex_radius * 0.34), 8, 11)
	var label_col := Color(0.62, 0.75, 0.92, 0.42)

	for cell in _all_cells:
		var center := _axial_to_screen(Vector2(cell))
		var alg := GameRules.coord_to_algebraic(cell)
		var pos := center + Vector2(-_hex_radius * 0.46, -_hex_radius * 0.42)
		draw_string(font, pos, alg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_col)


func _spawn_polygon_burst(cell: Vector2i, color: Color) -> void:
	_bursts.append({
		"cell": cell,
		"color": color,
		"age": 0.0,
		"lifetime": 0.45,
	})


func _draw_bursts() -> void:
	for b in _bursts:
		var t: float = b["age"] / b["lifetime"]
		var center := _axial_to_screen(Vector2(b["cell"]))
		var r := _hex_radius * (0.4 + 1.1 * t)
		var col: Color = b["color"]
		col.a = 1.0 - t
		var poly := _make_hex_polygon(center, r)
		poly.append(poly[0])
		draw_polyline(poly, col, 2.5 * (1.0 - t), true)


func _make_hex_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(6)
	for i in range(6):
		# Flat-top hexagon vertices at 0°, 60°, 120°, 180°, 240°, 300°
		var angle := TAU * float(i) / 6.0
		pts[i] = center + Vector2(cos(angle), sin(angle)) * radius
	return pts


func _compute_board_metrics() -> void:
	var padding := 20.0
	var avail := size - Vector2(padding * 2.0, padding * 2.0)
	# Flat-top hex board of radius 5 spans:
	# Width = (3/2 * 10 + 2) * R = 17.0 * R
	# Height = (11 * sqrt(3)) * R ≈ 19.0526 * R
	var max_r_x := avail.x / 17.2
	var max_r_y := avail.y / (11.2 * SQRT3)
	_hex_radius = maxf(minf(max_r_x, max_r_y), 10.0)
	_board_center = size * 0.5


func _axial_to_screen(axial: Vector2) -> Vector2:
	var a := -axial if board_flipped else axial
	var x := _hex_radius * 1.5 * a.x
	var y := _hex_radius * SQRT3 * (a.y + a.x * 0.5)
	return _board_center + Vector2(x, y)


func _screen_to_axial(screen_pos: Vector2) -> Vector2i:
	_compute_board_metrics()
	var local := screen_pos - _board_center
	if board_flipped:
		local = -local

	var q_f := (2.0 / 3.0 * local.x) / _hex_radius
	var r_f := ((-1.0 / 3.0) * local.x + (SQRT3 / 3.0) * local.y) / _hex_radius
	return _axial_round(q_f, r_f)


static func _axial_round(q_f: float, r_f: float) -> Vector2i:
	var s_f := -q_f - r_f
	var q := roundi(q_f)
	var r := roundi(r_f)
	var s := roundi(s_f)

	var q_diff := absf(float(q) - q_f)
	var r_diff := absf(float(r) - r_f)
	var s_diff := absf(float(s) - s_f)

	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s

	return Vector2i(q, r)
