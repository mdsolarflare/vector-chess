class_name GameRules
extends RefCounted
## Core game state and movement rule engine for Glinski's Hexagonal Chess.
## Uses axial coordinates (q, r) for flat-topped hexagons on a 91-cell regular hexagonal board
## of radius 5 (side length 6): max(|q|, |r|, |q + r|) <= 5.

class VectorMove extends RefCounted:
	var piece_id: int
	var from: Vector2i
	var to: Vector2i
	var delta: Vector2i
	var is_capture: bool = false
	var is_en_passant: bool = false
	var captured_piece_id: int = -1
	var captured_pos: Vector2i = Vector2i.ZERO
	var is_double_step: bool = false
	var en_passant_target: Vector2i = Vector2i(99, 99)
	var is_promotion: bool = false
	var promotion_type: PieceData.Type = PieceData.Type.QUEEN
	var ray_steps: Array[Vector2i] = []

	func _init(p_piece_id: int, p_from: Vector2i, p_to: Vector2i) -> void:
		piece_id = p_piece_id
		from = p_from
		to = p_to
		delta = p_to - p_from
		captured_pos = p_to

	func duplicate_move() -> VectorMove:
		var copy := VectorMove.new(piece_id, from, to)
		copy.is_capture = is_capture
		copy.is_en_passant = is_en_passant
		copy.captured_piece_id = captured_piece_id
		copy.captured_pos = captured_pos
		copy.is_double_step = is_double_step
		copy.en_passant_target = en_passant_target
		copy.is_promotion = is_promotion
		copy.promotion_type = promotion_type
		if not ray_steps.is_empty():
			copy.ray_steps = ray_steps.duplicate()
		return copy

	## Returns the 2D Euclidean displacement vector in screen-normalized hex units (Right = +X, Up = +Y).
	func get_cartesian_vector() -> Vector2:
		var dx := 1.5 * float(delta.x)
		var dy := -sqrt(3.0) * (float(delta.y) + 0.5 * float(delta.x))
		return Vector2(dx, dy)

	func get_magnitude() -> float:
		return get_cartesian_vector().length()

	func get_angle_degrees() -> float:
		var v := get_cartesian_vector()
		var deg := rad_to_deg(atan2(v.y, v.x))
		if deg < 0.0:
			deg += 360.0
		return deg


const BOARD_RADIUS: int = 5
const GRID_SPAN: int = BOARD_RADIUS * 2 + 1
const GRID_SIZE: int = GRID_SPAN * GRID_SPAN
const INVALID_HEX := Vector2i(99, 99)

## Glinski file labels from q = -5 to q = +5 (omits 'j' by tradition)
const FILE_NAMES: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "k", "l"]

## 6 Orthogonal (edge-adjacent) hex directions in axial (dq, dr)
const ORTHO_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),   # North
	Vector2i(1, -1),   # North-East
	Vector2i(1, 0),    # South-East
	Vector2i(0, 1),    # South
	Vector2i(-1, 1),   # South-West
	Vector2i(-1, 0),   # North-West
]

## 6 Diagonal (same-color vertex-connected) hex directions in axial (dq, dr)
const DIAG_DIRS: Array[Vector2i] = [
	Vector2i(1, -2),   # North-North-East
	Vector2i(2, -1),   # East
	Vector2i(1, 1),    # South-South-East
	Vector2i(-1, 2),   # South-South-West
	Vector2i(-2, 1),   # West
	Vector2i(-1, -1),  # North-North-West
]

## 12 Knight jump vectors in axial (dq, dr) (2 orthogonal + 1 orthogonal at 60 degrees)
const KNIGHT_DIRS: Array[Vector2i] = [
	Vector2i(1, -3),
	Vector2i(2, -3),
	Vector2i(3, -2),
	Vector2i(3, -1),
	Vector2i(2, 1),
	Vector2i(1, 2),
	Vector2i(-1, 3),
	Vector2i(-2, 3),
	Vector2i(-3, 2),
	Vector2i(-3, 1),
	Vector2i(-2, -1),
	Vector2i(-1, -2),
]

const CYAN_PAWN_CAP_DIRS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, -1),
]

const MAGENTA_PAWN_CAP_DIRS: Array[Vector2i] = [
	Vector2i(-1, 1),
	Vector2i(1, 0),
]

var pieces: Array[PieceData] = []
var current_turn: PieceData.Team = PieceData.Team.CYAN
var en_passant_target: Vector2i = INVALID_HEX
var en_passant_pawn_id: int = -1
var move_history: Array[Dictionary] = []
var captured_by_cyan: Array[PieceData.Type] = []
var captured_by_magenta: Array[PieceData.Type] = []
var is_game_over: bool = false
var status_text: String = "Cyan's Turn"
var last_move: VectorMove = null
var _next_id: int = 1

var _cyan_pawn_starts: Array[Vector2i] = []
var _magenta_pawn_starts: Array[Vector2i] = []

## O(1) spatial lookup grid indexed by (q + BOARD_RADIUS) * GRID_SPAN + (r + BOARD_RADIUS)
var _grid: Array[PieceData] = []
## O(1) piece ID lookup table indexed by piece.id
var _id_map: Array[PieceData] = []
## Direct King references for O(1) check detection
var _cyan_king: PieceData = null
var _magenta_king: PieceData = null
var _indexed_piece_count: int = 0


func _init(skip_reset: bool = false) -> void:
	_grid.resize(GRID_SIZE)
	_id_map.resize(64)
	_init_pawn_start_tables()
	if not skip_reset:
		reset_game()


func _init_pawn_start_tables() -> void:
	_cyan_pawn_starts.clear()
	for alg in ["b1", "c2", "d3", "e4", "f5", "g4", "h3", "i2", "k1"]:
		_cyan_pawn_starts.append(algebraic_to_axial(alg))

	_magenta_pawn_starts.clear()
	for alg in ["b7", "c7", "d7", "e7", "f7", "g7", "h7", "i7", "k7"]:
		_magenta_pawn_starts.append(algebraic_to_axial(alg))


func _rebuild_spatial_index() -> void:
	_grid.fill(null)
	_id_map.fill(null)
	_cyan_king = null
	_magenta_king = null
	for p in pieces:
		if is_inside_board(p.grid_pos):
			_grid[(p.grid_pos.x + BOARD_RADIUS) * GRID_SPAN + (p.grid_pos.y + BOARD_RADIUS)] = p
		if p.id >= _id_map.size():
			_id_map.resize(p.id + 32)
		if p.id >= 0:
			_id_map[p.id] = p
		if p.type == PieceData.Type.KING:
			if p.team == PieceData.Team.CYAN:
				_cyan_king = p
			else:
				_magenta_king = p
	_indexed_piece_count = pieces.size()


func reset_game() -> void:
	pieces.clear()
	_grid.fill(null)
	_id_map.fill(null)
	_cyan_king = null
	_magenta_king = null
	_indexed_piece_count = 0
	move_history.clear()
	captured_by_cyan.clear()
	captured_by_magenta.clear()
	current_turn = PieceData.Team.CYAN
	en_passant_target = INVALID_HEX
	en_passant_pawn_id = -1
	is_game_over = false
	last_move = null
	_next_id = 1

	# White / Cyan starting pieces (Bottom)
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, algebraic_to_axial("c1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, algebraic_to_axial("d1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, algebraic_to_axial("e1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, algebraic_to_axial("f1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, algebraic_to_axial("f2"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, algebraic_to_axial("f3"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, algebraic_to_axial("g1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, algebraic_to_axial("h1"))
	_spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, algebraic_to_axial("i1"))

	for start_hex in _cyan_pawn_starts:
		_spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, start_hex)

	# Black / Magenta starting pieces (Top)
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, algebraic_to_axial("c8"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, algebraic_to_axial("d9"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, algebraic_to_axial("e10"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, algebraic_to_axial("f11"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, algebraic_to_axial("f10"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, algebraic_to_axial("f9"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, algebraic_to_axial("g10"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, algebraic_to_axial("h9"))
	_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, algebraic_to_axial("i8"))

	for start_hex in _magenta_pawn_starts:
		_spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, start_hex)

	_update_game_status()


func _spawn_piece(team: PieceData.Team, type: PieceData.Type, pos: Vector2i) -> PieceData:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	var p := PieceData.new(_next_id, team, type, pos)
	_next_id += 1
	pieces.append(p)
	if is_inside_board(pos):
		_grid[(pos.x + BOARD_RADIUS) * GRID_SPAN + (pos.y + BOARD_RADIUS)] = p
	if p.id >= _id_map.size():
		_id_map.resize(p.id + 32)
	_id_map[p.id] = p
	if type == PieceData.Type.KING:
		if team == PieceData.Team.CYAN:
			_cyan_king = p
		else:
			_magenta_king = p
	_indexed_piece_count = pieces.size()
	return p


## Creates an isolated copy of the current game state for AI search.
func clone_state() -> GameRules:
	var copy := GameRules.new(true)
	copy.pieces = _clone_pieces_array()
	copy.current_turn = current_turn
	copy.en_passant_target = en_passant_target
	copy.en_passant_pawn_id = en_passant_pawn_id
	copy.captured_by_cyan = captured_by_cyan.duplicate()
	copy.captured_by_magenta = captured_by_magenta.duplicate()
	copy.is_game_over = is_game_over
	copy.status_text = status_text
	copy.last_move = last_move.duplicate_move() if last_move != null else null
	copy._next_id = _next_id
	copy._rebuild_spatial_index()
	return copy


## Returns all legal moves for all pieces belonging to `team`.
func get_all_legal_moves(team: PieceData.Team) -> Array[VectorMove]:
	var all_moves: Array[VectorMove] = []
	if is_game_over:
		return all_moves
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	for p in pieces:
		if p.team == team:
			all_moves.append_array(get_legal_moves_for_piece(p))
	return all_moves


## Fast in-place move execution for AI search tree traversal (no string formatting or full array cloning).
func push_search_move(move: VectorMove) -> Dictionary:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	var piece := get_piece_by_id(move.piece_id)
	var target: PieceData = null
	if move.is_en_passant:
		target = get_piece_by_id(move.captured_piece_id)
		if target == null:
			target = get_piece_at(move.captured_pos)
	elif move.is_capture:
		target = get_piece_at(move.to)

	var old_pos := piece.grid_pos
	var undo_record := {
		"piece": piece,
		"old_pos": old_pos,
		"old_type": piece.type,
		"old_sides": piece.sides_count,
		"old_has_moved": piece.has_moved,
		"captured": target,
		"old_turn": current_turn,
		"old_ep_target": en_passant_target,
		"old_ep_pawn_id": en_passant_pawn_id,
	}

	if target != null:
		var cap_idx := (target.grid_pos.x + BOARD_RADIUS) * GRID_SPAN + (target.grid_pos.y + BOARD_RADIUS)
		if _grid[cap_idx] == target:
			_grid[cap_idx] = null
		if target.id > 0 and target.id < _id_map.size():
			_id_map[target.id] = null
		pieces.erase(target)
		_indexed_piece_count = pieces.size()

	var from_idx := (old_pos.x + BOARD_RADIUS) * GRID_SPAN + (old_pos.y + BOARD_RADIUS)
	if _grid[from_idx] == piece:
		_grid[from_idx] = null
	var to_idx := (move.to.x + BOARD_RADIUS) * GRID_SPAN + (move.to.y + BOARD_RADIUS)
	_grid[to_idx] = piece

	piece.grid_pos = move.to
	piece.has_moved = true

	if move.is_promotion:
		piece.type = move.promotion_type
		piece.sides_count = PieceData.get_polygon_sides(move.promotion_type)

	if move.is_double_step:
		en_passant_target = move.en_passant_target
		en_passant_pawn_id = piece.id
	else:
		en_passant_target = INVALID_HEX
		en_passant_pawn_id = -1

	current_turn = PieceData.Team.MAGENTA if current_turn == PieceData.Team.CYAN else PieceData.Team.CYAN
	return undo_record


## Reverts a move previously applied with `push_search_move()`.
func pop_search_move(undo_record: Dictionary) -> void:
	var piece: PieceData = undo_record["piece"]
	var moved_pos := piece.grid_pos
	var old_pos: Vector2i = undo_record["old_pos"]

	var moved_idx := (moved_pos.x + BOARD_RADIUS) * GRID_SPAN + (moved_pos.y + BOARD_RADIUS)
	if _grid[moved_idx] == piece:
		_grid[moved_idx] = null

	piece.grid_pos = old_pos
	piece.type = undo_record["old_type"]
	piece.sides_count = undo_record["old_sides"]
	piece.has_moved = undo_record["old_has_moved"]

	var old_idx := (old_pos.x + BOARD_RADIUS) * GRID_SPAN + (old_pos.y + BOARD_RADIUS)
	_grid[old_idx] = piece

	var captured: PieceData = undo_record["captured"]
	if captured != null:
		pieces.append(captured)
		_indexed_piece_count = pieces.size()
		var cap_idx := (captured.grid_pos.x + BOARD_RADIUS) * GRID_SPAN + (captured.grid_pos.y + BOARD_RADIUS)
		_grid[cap_idx] = captured
		if captured.id > 0 and captured.id < _id_map.size():
			_id_map[captured.id] = captured

	current_turn = undo_record["old_turn"]
	en_passant_target = undo_record["old_ep_target"]
	en_passant_pawn_id = undo_record["old_ep_pawn_id"]


## Returns all 91 valid axial hex coordinates on the board.
static func get_all_board_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var r_min := maxi(-BOARD_RADIUS, -q - BOARD_RADIUS)
		var r_max := mini(BOARD_RADIUS, -q + BOARD_RADIUS)
		for r in range(r_min, r_max + 1):
			cells.append(Vector2i(q, r))
	return cells


static func is_inside_board(pos: Vector2i) -> bool:
	return (
		absi(pos.x) <= BOARD_RADIUS
		and absi(pos.y) <= BOARD_RADIUS
		and absi(pos.x + pos.y) <= BOARD_RADIUS
	)


## Returns 0, 1, or 2 for the 3-color hexagonal tiling.
## Bishops always remain on cells of the same color index.
static func get_cell_color_index(pos: Vector2i) -> int:
	return ((pos.x - pos.y) % 3 + 3) % 3


## Converts axial (q, r) to Glinski algebraic coordinates (e.g. "f1", "e4", "f11").
static func coord_to_algebraic(pos: Vector2i) -> String:
	var file_idx := pos.x + BOARD_RADIUS
	if file_idx < 0 or file_idx >= FILE_NAMES.size():
		return "?"
	var r_max := mini(BOARD_RADIUS, BOARD_RADIUS - pos.x)
	var rank := 1 + (r_max - pos.y)
	return FILE_NAMES[file_idx] + str(rank)


## Converts Glinski algebraic coordinates (e.g. "f5", "g10") to axial (q, r).
static func algebraic_to_axial(alg: String) -> Vector2i:
	if alg.length() < 2:
		return INVALID_HEX
	var file_char := alg.substr(0, 1).to_lower()
	var rank_num := alg.substr(1).to_int()
	var file_idx := FILE_NAMES.find(file_char)
	if file_idx == -1:
		return INVALID_HEX
	var q := file_idx - BOARD_RADIUS
	var r_max := mini(BOARD_RADIUS, BOARD_RADIUS - q)
	var r := r_max + 1 - rank_num
	return Vector2i(q, r)


func is_pawn_start_cell(team: PieceData.Team, pos: Vector2i) -> bool:
	if team == PieceData.Team.CYAN:
		return _cyan_pawn_starts.has(pos)
	return _magenta_pawn_starts.has(pos)


static func is_promotion_cell(team: PieceData.Team, pos: Vector2i) -> bool:
	if team == PieceData.Team.CYAN:
		return not is_inside_board(pos + Vector2i(0, -1))
	else:
		return not is_inside_board(pos + Vector2i(0, 1))


func get_piece_at(pos: Vector2i) -> PieceData:
	if not is_inside_board(pos):
		return null
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	return _grid[(pos.x + BOARD_RADIUS) * GRID_SPAN + (pos.y + BOARD_RADIUS)]


func get_piece_by_id(id: int) -> PieceData:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	if id <= 0 or id >= _id_map.size():
		return null
	return _id_map[id]


## Generates all legal moves for a piece, filtering out moves that leave own King in check.
func get_legal_moves_for_piece(piece: PieceData) -> Array[VectorMove]:
	if piece == null or is_game_over:
		return []
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	var pseudo_moves := _get_pseudo_legal_moves(piece)
	var legal_moves: Array[VectorMove] = []
	for mv in pseudo_moves:
		if not _move_leaves_king_in_check(piece, mv):
			legal_moves.append(mv)
	return legal_moves


## Executes a validated move and advances the turn.
func execute_move(move: VectorMove) -> bool:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	var piece := get_piece_by_id(move.piece_id)
	if piece == null:
		return false

	var snapshot := {
		"pieces": _clone_pieces_array(),
		"current_turn": current_turn,
		"en_passant_target": en_passant_target,
		"en_passant_pawn_id": en_passant_pawn_id,
		"captured_by_cyan": captured_by_cyan.duplicate(),
		"captured_by_magenta": captured_by_magenta.duplicate(),
		"is_game_over": is_game_over,
		"status_text": status_text,
		"last_move": last_move,
		"notation": "",
	}

	var target: PieceData = null
	if move.is_en_passant:
		target = get_piece_by_id(move.captured_piece_id)
		if target == null:
			target = get_piece_at(move.captured_pos)
	elif move.is_capture:
		target = get_piece_at(move.to)

	if target != null:
		if piece.team == PieceData.Team.CYAN:
			captured_by_cyan.append(target.type)
		else:
			captured_by_magenta.append(target.type)
		var cap_idx := (target.grid_pos.x + BOARD_RADIUS) * GRID_SPAN + (target.grid_pos.y + BOARD_RADIUS)
		if _grid[cap_idx] == target:
			_grid[cap_idx] = null
		if target.id > 0 and target.id < _id_map.size():
			_id_map[target.id] = null
		pieces.erase(target)
		_indexed_piece_count = pieces.size()

	var from_idx := (piece.grid_pos.x + BOARD_RADIUS) * GRID_SPAN + (piece.grid_pos.y + BOARD_RADIUS)
	if _grid[from_idx] == piece:
		_grid[from_idx] = null
	var to_idx := (move.to.x + BOARD_RADIUS) * GRID_SPAN + (move.to.y + BOARD_RADIUS)
	_grid[to_idx] = piece

	piece.grid_pos = move.to
	piece.has_moved = true

	if move.is_promotion:
		piece.type = move.promotion_type
		piece.sides_count = PieceData.get_polygon_sides(move.promotion_type)

	if move.is_double_step:
		en_passant_target = move.en_passant_target
		en_passant_pawn_id = piece.id
	else:
		en_passant_target = INVALID_HEX
		en_passant_pawn_id = -1

	snapshot["notation"] = format_move_notation(piece, move)
	move_history.append(snapshot)

	last_move = move
	current_turn = PieceData.Team.MAGENTA if current_turn == PieceData.Team.CYAN else PieceData.Team.CYAN
	_update_game_status()
	return true


func undo_last_move() -> bool:
	if move_history.is_empty():
		return false
	var snapshot: Dictionary = move_history.pop_back()
	pieces = snapshot["pieces"]
	for p in pieces:
		p.visual_pos = Vector2(p.grid_pos)
	_rebuild_spatial_index()
	current_turn = snapshot["current_turn"]
	en_passant_target = snapshot["en_passant_target"]
	en_passant_pawn_id = snapshot["en_passant_pawn_id"]
	captured_by_cyan = snapshot["captured_by_cyan"]
	captured_by_magenta = snapshot["captured_by_magenta"]
	is_game_over = snapshot["is_game_over"]
	status_text = snapshot["status_text"]
	last_move = snapshot["last_move"]
	return true


## Allocation-free reverse-attack lookup from `target_pos` for pieces belonging to `by_team`.
func is_cell_attacked(target_pos: Vector2i, by_team: PieceData.Team) -> bool:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()

	# 1. Orthogonal rays: Rook, Queen, or adjacent King
	for d in ORTHO_DIRS:
		var step_pos := target_pos + d
		var is_first_step := true
		while (
			absi(step_pos.x) <= BOARD_RADIUS
			and absi(step_pos.y) <= BOARD_RADIUS
			and absi(step_pos.x + step_pos.y) <= BOARD_RADIUS
		):
			var occ := _grid[(step_pos.x + BOARD_RADIUS) * GRID_SPAN + (step_pos.y + BOARD_RADIUS)]
			if occ != null:
				if occ.team == by_team:
					var t := occ.type
					if (
						t == PieceData.Type.ROOK
						or t == PieceData.Type.QUEEN
						or (is_first_step and t == PieceData.Type.KING)
					):
						return true
				break
			step_pos += d
			is_first_step = false

	# 2. Diagonal rays: Bishop, Queen, or adjacent King
	for d in DIAG_DIRS:
		var step_pos := target_pos + d
		var is_first_step := true
		while (
			absi(step_pos.x) <= BOARD_RADIUS
			and absi(step_pos.y) <= BOARD_RADIUS
			and absi(step_pos.x + step_pos.y) <= BOARD_RADIUS
		):
			var occ := _grid[(step_pos.x + BOARD_RADIUS) * GRID_SPAN + (step_pos.y + BOARD_RADIUS)]
			if occ != null:
				if occ.team == by_team:
					var t := occ.type
					if (
						t == PieceData.Type.BISHOP
						or t == PieceData.Type.QUEEN
						or (is_first_step and t == PieceData.Type.KING)
					):
						return true
				break
			step_pos += d
			is_first_step = false

	# 3. Knight jumps (12 offsets)
	for j in KNIGHT_DIRS:
		var k_pos := target_pos + j
		if (
			absi(k_pos.x) <= BOARD_RADIUS
			and absi(k_pos.y) <= BOARD_RADIUS
			and absi(k_pos.x + k_pos.y) <= BOARD_RADIUS
		):
			var occ := _grid[(k_pos.x + BOARD_RADIUS) * GRID_SPAN + (k_pos.y + BOARD_RADIUS)]
			if occ != null and occ.team == by_team and occ.type == PieceData.Type.KNIGHT:
				return true

	# 4. Pawn captures (reverse of by_team's pawn capture vectors)
	var cap_dirs: Array[Vector2i] = (
		CYAN_PAWN_CAP_DIRS if by_team == PieceData.Team.CYAN else MAGENTA_PAWN_CAP_DIRS
	)
	for cd in cap_dirs:
		var p_pos := target_pos - cd
		if (
			absi(p_pos.x) <= BOARD_RADIUS
			and absi(p_pos.y) <= BOARD_RADIUS
			and absi(p_pos.x + p_pos.y) <= BOARD_RADIUS
		):
			var occ := _grid[(p_pos.x + BOARD_RADIUS) * GRID_SPAN + (p_pos.y + BOARD_RADIUS)]
			if occ != null and occ.team == by_team and occ.type == PieceData.Type.PAWN:
				return true

	return false


func is_king_in_check(team: PieceData.Team) -> bool:
	if _indexed_piece_count != pieces.size():
		_rebuild_spatial_index()
	var king := _cyan_king if team == PieceData.Team.CYAN else _magenta_king
	if king == null:
		return true
	var enemy_team := PieceData.Team.MAGENTA if team == PieceData.Team.CYAN else PieceData.Team.CYAN
	return is_cell_attacked(king.grid_pos, enemy_team)


func format_move_notation(piece: PieceData, move: VectorMove) -> String:
	var code := "P" if move.is_promotion else PieceData.get_piece_short_code(piece.type)
	var from_alg := coord_to_algebraic(move.from)
	var to_alg := coord_to_algebraic(move.to)
	var sep := "x" if move.is_capture else "->"
	var suffix := ""
	if move.is_en_passant:
		suffix = " e.p."
	elif move.is_promotion:
		suffix = "=" + PieceData.get_piece_short_code(move.promotion_type)
	return "%s %s%s%s%s  d(%+d,%+d)" % [code, from_alg, sep, to_alg, suffix, move.delta.x, move.delta.y]


func _get_pseudo_legal_moves(piece: PieceData, include_en_passant: bool = true) -> Array[VectorMove]:
	var moves: Array[VectorMove] = []
	match piece.type:
		PieceData.Type.PAWN:
			var forward_dir := Vector2i(0, -1) if piece.team == PieceData.Team.CYAN else Vector2i(0, 1)
			var one_step := piece.grid_pos + forward_dir
			if is_inside_board(one_step) and _grid[(one_step.x + BOARD_RADIUS) * GRID_SPAN + (one_step.y + BOARD_RADIUS)] == null:
				var mv := VectorMove.new(piece.id, piece.grid_pos, one_step)
				mv.is_promotion = is_promotion_cell(piece.team, one_step)
				moves.append(mv)

				# Glinski double-step: allowed from ANY friendly starting pawn cell
				var two_step := piece.grid_pos + forward_dir * 2
				if (
					is_pawn_start_cell(piece.team, piece.grid_pos)
					and is_inside_board(two_step)
					and _grid[(two_step.x + BOARD_RADIUS) * GRID_SPAN + (two_step.y + BOARD_RADIUS)] == null
				):
					var mv2 := VectorMove.new(piece.id, piece.grid_pos, two_step)
					mv2.is_double_step = true
					mv2.en_passant_target = one_step
					moves.append(mv2)

			# Glinski pawn captures: 60-degree forward-sideways orthogonal cells
			var cap_dirs: Array[Vector2i] = (
				CYAN_PAWN_CAP_DIRS if piece.team == PieceData.Team.CYAN else MAGENTA_PAWN_CAP_DIRS
			)
			for cd in cap_dirs:
				var cap_pos := piece.grid_pos + cd
				if not is_inside_board(cap_pos):
					continue
				var target := _grid[(cap_pos.x + BOARD_RADIUS) * GRID_SPAN + (cap_pos.y + BOARD_RADIUS)]
				if target != null and target.team != piece.team:
					var cmv := VectorMove.new(piece.id, piece.grid_pos, cap_pos)
					cmv.is_capture = true
					cmv.captured_piece_id = target.id
					cmv.captured_pos = cap_pos
					cmv.is_promotion = is_promotion_cell(piece.team, cap_pos)
					moves.append(cmv)
				elif include_en_passant and cap_pos == en_passant_target and en_passant_pawn_id != -1:
					var ep_pawn := get_piece_by_id(en_passant_pawn_id)
					if ep_pawn != null and ep_pawn.team != piece.team:
						var epmv := VectorMove.new(piece.id, piece.grid_pos, cap_pos)
						epmv.is_capture = true
						epmv.is_en_passant = true
						epmv.captured_piece_id = ep_pawn.id
						epmv.captured_pos = ep_pawn.grid_pos
						moves.append(epmv)

		PieceData.Type.KNIGHT:
			for j in KNIGHT_DIRS:
				_try_add_step_move(piece, piece.grid_pos + j, moves)

		PieceData.Type.BISHOP:
			_add_sliding_moves(piece, DIAG_DIRS, moves)

		PieceData.Type.ROOK:
			_add_sliding_moves(piece, ORTHO_DIRS, moves)

		PieceData.Type.QUEEN:
			_add_sliding_moves(piece, ORTHO_DIRS, moves)
			_add_sliding_moves(piece, DIAG_DIRS, moves)

		PieceData.Type.KING:
			for d in ORTHO_DIRS:
				_try_add_step_move(piece, piece.grid_pos + d, moves)
			for d in DIAG_DIRS:
				_try_add_step_move(piece, piece.grid_pos + d, moves)

	return moves


func _try_add_step_move(piece: PieceData, target_pos: Vector2i, moves: Array[VectorMove]) -> void:
	if not is_inside_board(target_pos):
		return
	var occ := _grid[(target_pos.x + BOARD_RADIUS) * GRID_SPAN + (target_pos.y + BOARD_RADIUS)]
	if occ == null:
		var mv := VectorMove.new(piece.id, piece.grid_pos, target_pos)
		moves.append(mv)
	elif occ.team != piece.team:
		var mv := VectorMove.new(piece.id, piece.grid_pos, target_pos)
		mv.is_capture = true
		mv.captured_piece_id = occ.id
		mv.captured_pos = target_pos
		moves.append(mv)


func _add_sliding_moves(piece: PieceData, dirs: Array[Vector2i], moves: Array[VectorMove]) -> void:
	for d in dirs:
		var step_pos := piece.grid_pos + d
		while is_inside_board(step_pos):
			var occ := _grid[(step_pos.x + BOARD_RADIUS) * GRID_SPAN + (step_pos.y + BOARD_RADIUS)]
			if occ == null:
				var mv := VectorMove.new(piece.id, piece.grid_pos, step_pos)
				moves.append(mv)
			else:
				if occ.team != piece.team:
					var mv := VectorMove.new(piece.id, piece.grid_pos, step_pos)
					mv.is_capture = true
					mv.captured_piece_id = occ.id
					mv.captured_pos = step_pos
					moves.append(mv)
				break
			step_pos += d


func _move_leaves_king_in_check(piece: PieceData, move: VectorMove) -> bool:
	var old_pos := piece.grid_pos
	var from_idx := (old_pos.x + BOARD_RADIUS) * GRID_SPAN + (old_pos.y + BOARD_RADIUS)
	var to_idx := (move.to.x + BOARD_RADIUS) * GRID_SPAN + (move.to.y + BOARD_RADIUS)
	var enemy_team := PieceData.Team.MAGENTA if piece.team == PieceData.Team.CYAN else PieceData.Team.CYAN
	var king := _cyan_king if piece.team == PieceData.Team.CYAN else _magenta_king
	if king == null:
		return true

	if move.is_en_passant:
		var cap_idx := (move.captured_pos.x + BOARD_RADIUS) * GRID_SPAN + (move.captured_pos.y + BOARD_RADIUS)
		var captured_ep := _grid[cap_idx]
		_grid[cap_idx] = null
		_grid[from_idx] = null
		_grid[to_idx] = piece
		piece.grid_pos = move.to

		var in_check_ep := is_cell_attacked(king.grid_pos, enemy_team)

		piece.grid_pos = old_pos
		_grid[to_idx] = null
		_grid[from_idx] = piece
		_grid[cap_idx] = captured_ep
		return in_check_ep

	var captured := _grid[to_idx]
	_grid[from_idx] = null
	_grid[to_idx] = piece
	piece.grid_pos = move.to

	var in_check := is_cell_attacked(king.grid_pos, enemy_team)

	piece.grid_pos = old_pos
	_grid[to_idx] = captured
	_grid[from_idx] = piece
	return in_check


func _update_game_status() -> void:
	var team_name := "Cyan" if current_turn == PieceData.Team.CYAN else "Magenta"
	var any_legal := false
	for p in pieces:
		if p.team == current_turn:
			if not get_legal_moves_for_piece(p).is_empty():
				any_legal = true
				break

	var in_check := is_king_in_check(current_turn)
	if not any_legal:
		is_game_over = true
		var other_team := "Magenta" if current_turn == PieceData.Team.CYAN else "Cyan"
		if in_check:
			status_text = "CHECKMATE - %s Wins!" % other_team
		else:
			status_text = "STALEMATE - %s 0.75 : 0.25 %s" % [other_team, team_name]
	else:
		if in_check:
			status_text = "%s's Turn - CHECK!" % team_name
		else:
			status_text = "%s's Turn" % team_name


func _clone_pieces_array() -> Array[PieceData]:
	var arr: Array[PieceData] = []
	for p in pieces:
		arr.append(p.duplicate_piece())
	return arr
