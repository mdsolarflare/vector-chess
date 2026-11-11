class_name VectorBoard
extends Control
## Procedural vector-graphics hexagonal chessboard renderer for Glinski's Hexagonal Chess.
## Renders the 91-cell flat-top hexagonal board in 3 colors with axial coordinate hit-testing,
## displacement vector rays, and Option A Low-Poly Faceted Staunton piece silhouettes.

signal move_executed(move: GameRules.VectorMove, notation: String)
signal promotion_requested(pending_move: GameRules.VectorMove, team: PieceData.Team)
signal selection_changed(piece: PieceData, hovered_move: GameRules.VectorMove)

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
const COLOR_CHECK_VECTOR := Color(1.0, 0.55, 0.0, 0.95)

const ATLAS_CELL_SIZE: int = 128
const ATLAS_COLS: int = 6
const ATLAS_ROWS: int = 4
const ATLAS_RADIUS_RATIO: float = 0.45

static var line_aa_enabled: bool = true
static var _piece_atlas_texture: Texture2D = null

var rules: GameRules = GameRules.new()
var selected_piece: PieceData = null
var legal_moves: Array[GameRules.VectorMove] = []
var hovered_cell: Vector2i = GameRules.INVALID_HEX
var hovered_move: GameRules.VectorMove = null
var pending_promotion_move: GameRules.VectorMove = null
var board_flipped: bool = false:
	set(value):
		if board_flipped != value:
			board_flipped = value
			_request_bg_redraw()
			queue_redraw()
var show_vectors: bool = true
var show_cell_coords: bool = true:
	set(value):
		if show_cell_coords != value:
			show_cell_coords = value
			_request_bg_redraw()
			queue_redraw()
var input_locked: bool = false

var _board_center: Vector2 = Vector2.ZERO
var _hex_radius: float = 28.0
var _pulse_time: float = 0.0
var _bursts: Array[Dictionary] = []
var _all_cells: Array[Vector2i] = []
var _cell_meta: Array[Dictionary] = []
var _cached_turn_moves: Dictionary = {}
var _cached_check_kings: Array[PieceData] = []
var _cached_check_vectors: Array[Dictionary] = []
var _bg_viewport: SubViewport = null
var _bg_layer: Control = null
var _piece_atlas_viewport: SubViewport = null
var _piece_atlas_layer: Control = null


func _init() -> void:
	_init_cell_metadata()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_cell_metadata()
	_setup_bg_layer()
	_setup_piece_atlas()
	resized.connect(_on_board_resized)
	_rebuild_board_cache()
	set_process(true)


func _exit_tree() -> void:
	if _piece_atlas_viewport != null and _piece_atlas_texture == _piece_atlas_viewport.get_texture():
		_piece_atlas_texture = null


func _init_cell_metadata() -> void:
	if not _cell_meta.is_empty():
		return
	_all_cells = GameRules.get_all_board_cells()
	_cell_meta.resize(_all_cells.size())
	for i in range(_all_cells.size()):
		var cell := _all_cells[i]
		_cell_meta[i] = {
			"cell": cell,
			"color_idx": GameRules.get_cell_color_index(cell),
			"is_pawn_start": (
				rules.is_pawn_start_cell(PieceData.Team.CYAN, cell)
				or rules.is_pawn_start_cell(PieceData.Team.MAGENTA, cell)
			),
			"algebraic": GameRules.coord_to_algebraic(cell),
		}


func _setup_bg_layer() -> void:
	if _bg_viewport != null:
		return
	_bg_viewport = SubViewport.new()
	_bg_viewport.name = "BoardBackgroundViewport"
	_bg_viewport.transparent_bg = true
	_bg_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var vp_w := maxi(int(size.x), 1)
	var vp_h := maxi(int(size.y), 1)
	_bg_viewport.size = Vector2i(vp_w, vp_h)

	_bg_layer = Control.new()
	_bg_layer.name = "BoardBackgroundLayer"
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.size = Vector2(vp_w, vp_h)
	_bg_layer.draw.connect(_on_bg_layer_draw)
	_bg_viewport.add_child(_bg_layer)
	add_child(_bg_viewport)


func _setup_piece_atlas() -> void:
	if _piece_atlas_viewport != null:
		return
	var atlas_size := Vector2i(ATLAS_COLS * ATLAS_CELL_SIZE, ATLAS_ROWS * ATLAS_CELL_SIZE)
	_piece_atlas_viewport = SubViewport.new()
	_piece_atlas_viewport.name = "PieceAtlasViewport"
	_piece_atlas_viewport.transparent_bg = true
	_piece_atlas_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_piece_atlas_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_piece_atlas_viewport.size = atlas_size

	_piece_atlas_layer = Control.new()
	_piece_atlas_layer.name = "PieceAtlasLayer"
	_piece_atlas_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_piece_atlas_layer.size = Vector2(atlas_size)
	_piece_atlas_layer.draw.connect(_on_piece_atlas_draw)
	_piece_atlas_viewport.add_child(_piece_atlas_layer)
	add_child(_piece_atlas_viewport)
	_piece_atlas_texture = _piece_atlas_viewport.get_texture()


func _on_piece_atlas_draw() -> void:
	var cell_px := float(ATLAS_CELL_SIZE)
	var atlas_r := cell_px * ATLAS_RADIUS_RATIO
	var piece_types := [
		PieceData.Type.PAWN,
		PieceData.Type.KNIGHT,
		PieceData.Type.BISHOP,
		PieceData.Type.ROOK,
		PieceData.Type.QUEEN,
		PieceData.Type.KING,
	]
	for col_idx in range(piece_types.size()):
		var p_type: PieceData.Type = piece_types[col_idx]
		for team_idx in range(2):
			var p_team: PieceData.Team = PieceData.Team.CYAN if team_idx == 0 else PieceData.Team.MAGENTA
			for sel_idx in range(2):
				var is_sel: bool = (sel_idx == 1)
				var row_idx: int = team_idx * 2 + sel_idx
				var cell_center := Vector2(
					(float(col_idx) + 0.5) * cell_px,
					(float(row_idx) + 0.5) * cell_px
				)
				var mesh := PieceData.get_piece_array_mesh(p_type, p_team, is_sel)
				var xform := Transform2D(0.0, Vector2(atlas_r, atlas_r), 0.0, cell_center)
				_piece_atlas_layer.draw_mesh(mesh, null, xform)


static func get_piece_atlas_region(p_type: PieceData.Type, p_team: PieceData.Team, is_selected: bool) -> Rect2:
	var col_idx := int(p_type)
	var row_idx := int(p_team) * 2 + (1 if is_selected else 0)
	var cell_px := float(ATLAS_CELL_SIZE)
	return Rect2(
		float(col_idx) * cell_px,
		float(row_idx) * cell_px,
		cell_px,
		cell_px
	)


func _on_board_resized() -> void:
	_compute_board_metrics()
	_request_bg_redraw()
	queue_redraw()


func _request_bg_redraw() -> void:
	if _bg_viewport != null and _bg_layer != null:
		var vp_w := maxi(int(size.x), 1)
		var vp_h := maxi(int(size.y), 1)
		var target_size := Vector2i(vp_w, vp_h)
		if _bg_viewport.size != target_size:
			_bg_viewport.size = target_size
		_bg_layer.size = Vector2(vp_w, vp_h)
		_bg_layer.queue_redraw()
		_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_line_antialiasing(enabled: bool) -> void:
	line_aa_enabled = enabled
	_request_bg_redraw()
	queue_redraw()


func _rebuild_board_cache() -> void:
	_cached_turn_moves.clear()
	_cached_check_kings.clear()
	_cached_check_vectors.clear()

	if not rules.is_game_over:
		for p in rules.pieces:
			if p.team == rules.current_turn:
				_cached_turn_moves[p.id] = rules.get_legal_moves_for_piece(p)

	for team in [PieceData.Team.CYAN, PieceData.Team.MAGENTA]:
		if rules.is_king_in_check(team):
			var checking_pieces := rules.get_checking_pieces(team)
			for p in rules.pieces:
				if p.team == team and p.type == PieceData.Type.KING:
					_cached_check_kings.append(p)
					for attacker in checking_pieces:
						_cached_check_vectors.append({
							"attacker": attacker,
							"king": p,
						})


func is_animating() -> bool:
	if selected_piece != null or not _cached_check_kings.is_empty() or not _bursts.is_empty():
		return true
	for p in rules.pieces:
		if p.visual_pos != Vector2(p.grid_pos):
			return true
	return false


func _process(delta: float) -> void:
	var needs_redraw := false

	for p in rules.pieces:
		var target := Vector2(p.grid_pos)
		if p.visual_pos.distance_squared_to(target) > 0.0001:
			p.visual_pos = p.visual_pos.lerp(target, clampf(delta * 16.0, 0.0, 1.0))
			needs_redraw = true
		elif p.visual_pos != target:
			p.visual_pos = target
			needs_redraw = true

	if not _bursts.is_empty():
		needs_redraw = true
		for i in range(_bursts.size() - 1, -1, -1):
			_bursts[i]["age"] += delta
			if _bursts[i]["age"] >= _bursts[i]["lifetime"]:
				_bursts.remove_at(i)

	if selected_piece != null or not _cached_check_kings.is_empty():
		needs_redraw = true

	if needs_redraw:
		_pulse_time += delta
		queue_redraw()


func start_new_game() -> void:
	rules.reset_game()
	selected_piece = null
	legal_moves = []
	hovered_move = null
	pending_promotion_move = null
	input_locked = false
	_bursts.clear()
	_rebuild_board_cache()
	selection_changed.emit(null, null)
	queue_redraw()


func undo_move() -> bool:
	pending_promotion_move = null
	if rules.undo_last_move():
		selected_piece = null
		legal_moves = []
		hovered_move = null
		_rebuild_board_cache()
		selection_changed.emit(null, null)
		queue_redraw()
		return true
	return false


func execute_ai_move(move: GameRules.VectorMove) -> void:
	if move == null or rules.is_game_over:
		return
	pending_promotion_move = null
	_commit_move(move)


func toggle_flip_board() -> void:
	board_flipped = not board_flipped


func toggle_vector_overlay() -> bool:
	show_vectors = not show_vectors
	queue_redraw()
	return show_vectors


func complete_promotion(chosen_type: PieceData.Type) -> void:
	if pending_promotion_move == null:
		return
	var mv := pending_promotion_move
	pending_promotion_move = null
	mv.promotion_type = chosen_type
	_commit_move(mv)


func _gui_input(event: InputEvent) -> void:
	if pending_promotion_move != null or input_locked:
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
		if _cached_turn_moves.has(selected_piece.id):
			var cached: Array[GameRules.VectorMove] = _cached_turn_moves[selected_piece.id]
			legal_moves = cached.duplicate()
		else:
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
		legal_moves = []
		hovered_move = null
		_rebuild_board_cache()
		selection_changed.emit(null, null)
		move_executed.emit(move, notation)
		queue_redraw()


func _clear_selection() -> void:
	selected_piece = null
	legal_moves = []
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


func _on_bg_layer_draw() -> void:
	_compute_board_metrics()
	_draw_board_background_on(_bg_layer)


func _draw_board_background_on(canvas: CanvasItem) -> void:
	var hex_colors: Array[Color] = [COLOR_HEX_0, COLOR_HEX_1, COLOR_HEX_2]

	# 1. Draw all 91 hexagonal cells with 3-color tiling
	for meta in _cell_meta:
		var cell: Vector2i = meta["cell"]
		var col_idx: int = meta["color_idx"]
		var is_pawn_start: bool = meta["is_pawn_start"]

		var center := _axial_to_screen(Vector2(cell))
		var poly := _make_hex_polygon(center, _hex_radius)
		canvas.draw_colored_polygon(poly, hex_colors[col_idx])

		var outline := poly.duplicate()
		outline.append(poly[0])
		canvas.draw_polyline(outline, COLOR_GRID_LINE, 1.3, line_aa_enabled)

		# Subtle starting-pawn hex indicator
		if is_pawn_start:
			var inner_hex := _make_hex_polygon(center, _hex_radius * 0.20)
			inner_hex.append(inner_hex[0])
			canvas.draw_polyline(inner_hex, Color(0.35, 0.5, 0.7, 0.20), 1.0, line_aa_enabled)

	# 2. Draw coordinate labels
	if show_cell_coords:
		_draw_hex_coordinates_on(canvas)


func _draw() -> void:
	_compute_board_metrics()

	# 1 & 2. Render cached static board SubViewport texture as 1 quad (or fallback if headless)
	if _bg_viewport != null and size.x > 1.0 and size.y > 1.0:
		var target_vp_size := Vector2i(int(size.x), int(size.y))
		if _bg_viewport.size != target_vp_size:
			_request_bg_redraw()
		draw_texture_rect(_bg_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	else:
		_draw_board_background_on(self)

	# 3. Highlight last executed move
	if rules.last_move != null:
		var from_c := _axial_to_screen(Vector2(rules.last_move.from))
		var to_c := _axial_to_screen(Vector2(rules.last_move.to))
		_draw_hex_highlight(from_c, Color(COLOR_LAST_MOVE, 0.16), Color(COLOR_LAST_MOVE, 0.55), 1.8)
		_draw_hex_highlight(to_c, Color(COLOR_LAST_MOVE, 0.24), Color(COLOR_LAST_MOVE, 0.75), 2.2)
		if show_vectors:
			_draw_vector_arrow(from_c, to_c, COLOR_LAST_MOVE, 2.0, false)

	# 4. Team-wide vector overlay (when Vectors: ON)
	if show_vectors:
		for p in rules.pieces:
			if p.team == rules.current_turn:
				var p_moves: Array = _cached_turn_moves.get(p.id, [])
				if p_moves.is_empty():
					continue
				var team_col := COLOR_CYAN if p.team == PieceData.Team.CYAN else COLOR_MAGENTA
				var ray_col := Color(team_col.r, team_col.g, team_col.b, 0.24)
				var origin := _axial_to_screen(p.visual_pos)
				for mv in p_moves:
					var dest := _axial_to_screen(Vector2(mv.to))
					_draw_vector_arrow(origin, dest, ray_col, 1.4, false)

	# 5. Selected piece & legal move targets/vectors
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

			if show_vectors:
				_draw_vector_arrow(origin, dest, Color(col, alpha), width, is_hovered)

	# 6. Hover cursor hex outline
	if GameRules.is_inside_board(hovered_cell):
		var h_center := _axial_to_screen(Vector2(hovered_cell))
		_draw_hex_highlight(h_center, Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.35), 1.6)

	# 7. Highlight King in check & caution orange check vectors
	for king_piece in _cached_check_kings:
		var k_center := _axial_to_screen(Vector2(king_piece.grid_pos))
		var pulse := 0.5 + 0.5 * sin(_pulse_time * 8.0)
		_draw_hex_highlight(
			k_center,
			Color(1.0, 0.15, 0.15, 0.25 + 0.25 * pulse),
			Color(1.0, 0.2, 0.2, 0.95),
			3.0
		)

	if show_vectors:
		for cv in _cached_check_vectors:
			var attacker: PieceData = cv["attacker"]
			var king_piece: PieceData = cv["king"]
			var from_c := _axial_to_screen(attacker.visual_pos)
			var to_c := _axial_to_screen(king_piece.visual_pos)
			_draw_vector_arrow(from_c, to_c, COLOR_CHECK_VECTOR, 2.4, false)

	# 8. Draw all pieces using batched shared atlas quads
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
	draw_polyline(closed, border_col, border_width, line_aa_enabled)


func _draw_polygon_piece(piece: PieceData) -> void:
	var center := _axial_to_screen(piece.visual_pos)
	var piece_scale := PieceData.get_piece_scale(piece.type)
	var radius := _hex_radius * piece_scale
	var is_selected := (selected_piece != null and selected_piece.id == piece.id)

	if is_selected:
		radius *= (1.0 + 0.07 * sin(_pulse_time * 6.0))

	draw_faceted_piece_icon(self, piece.type, piece.team, center, radius, is_selected)


static func draw_faceted_piece_icon(
	canvas: CanvasItem,
	p_type: PieceData.Type,
	p_team: PieceData.Team,
	center: Vector2,
	radius: float,
	is_selected: bool = false
) -> void:
	if _piece_atlas_texture != null:
		var src_rect := get_piece_atlas_region(p_type, p_team, is_selected)
		var dst_extent := radius / ATLAS_RADIUS_RATIO
		var dst_rect := Rect2(
			center - Vector2(dst_extent * 0.5, dst_extent * 0.5),
			Vector2(dst_extent, dst_extent)
		)
		canvas.draw_texture_rect_region(_piece_atlas_texture, dst_rect, src_rect)
		return

	var mesh := PieceData.get_piece_array_mesh(p_type, p_team, is_selected)
	var xform := Transform2D(0.0, Vector2(radius, radius), 0.0, center)
	canvas.draw_mesh(mesh, null, xform)


func _draw_vector_arrow(from_pt: Vector2, to_pt: Vector2, color: Color, width: float, draw_label: bool) -> void:
	var diff := to_pt - from_pt
	var dist := diff.length()
	if dist < 4.0:
		return
	var dir := diff / dist
	var normal := Vector2(-dir.y, dir.x)

	var start_pt := from_pt + dir * (_hex_radius * 0.32)
	var tip_pt := to_pt - dir * (_hex_radius * 0.25)
	draw_line(start_pt, tip_pt, color, width, line_aa_enabled)

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
		var label := "d(%+d,%+d)" % [axial_delta.x, axial_delta.y]
		draw_string(ThemeDB.fallback_font, mid, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, color.lightened(0.35))


func _draw_hex_coordinates_on(canvas: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	if font == null or _hex_radius < 16.0:
		return

	var font_size := clampi(int(_hex_radius * 0.34), 8, 11)
	var label_col := Color(0.62, 0.75, 0.92, 0.42)

	for meta in _cell_meta:
		var cell: Vector2i = meta["cell"]
		var alg: String = meta["algebraic"]
		var center := _axial_to_screen(Vector2(cell))
		var pos := center + Vector2(-_hex_radius * 0.46, -_hex_radius * 0.42)
		canvas.draw_string(font, pos, alg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_col)


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
		draw_polyline(poly, col, 2.5 * (1.0 - t), line_aa_enabled)


func _make_hex_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(6)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		pts[i] = center + Vector2(cos(angle), sin(angle)) * radius
	return pts


func _compute_board_metrics() -> void:
	var min_dim := minf(size.x, size.y)
	var padding := 10.0 if min_dim < 540.0 else 20.0
	var avail := size - Vector2(padding * 2.0, padding * 2.0)
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
