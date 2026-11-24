class_name AIPlayer
extends RefCounted
## Hexagonal Chess AI Engine for Glinski's 91-Cell Hexagonal Chess.
## Supports Easy (Novice), Medium (Tactical), and Hard (Master) difficulty tiers
## using Minimax with Alpha-Beta pruning, MVV-LVA move ordering, and hexagonal positional heuristics.

enum Difficulty {
	EASY = 0,
	MEDIUM = 1,
	HARD = 2,
}

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]

const MATE_SCORE: int = 100000
const MATE_THRESHOLD: int = MATE_SCORE - 1000
const INF_SCORE: int = 1000000
## Frame time budget in microseconds (~8ms) before yielding on single-threaded Web builds
const ASYNC_FRAME_BUDGET_USEC: int = 8000
## Maximum consecutive check-evasion extensions allowed inside quiescence search
const MAX_Q_CHECK_EXTENSIONS: int = 2
## Glinski 0.75 : 0.25 stalemate score bonus for the stalemating side (in centipawns).
## Strictly above a 0 draw when equal/behind, yet strictly below any winning low-material
## endgame (e.g. K+P vs K >= +72 cp) even after Medium root jitter (+25 cp).
const STALEMATE_BONUS: int = 40
## Piece-count threshold below which leaf nodes also check for non-check stalemates
const ENDGAME_STALEMATE_CHECK_MAX_PIECES: int = 8

const ROOT_PROMOTION_TYPES: Array[PieceData.Type] = [
	PieceData.Type.QUEEN,
	PieceData.Type.KNIGHT,
	PieceData.Type.ROOK,
	PieceData.Type.BISHOP,
]

const SEARCH_PROMOTION_TYPES: Array[PieceData.Type] = [
	PieceData.Type.QUEEN,
	PieceData.Type.KNIGHT,
]

const PIECE_VALUES: Dictionary = {
	PieceData.Type.PAWN: 100,
	PieceData.Type.KNIGHT: 320,
	PieceData.Type.BISHOP: 330,
	PieceData.Type.ROOK: 500,
	PieceData.Type.QUEEN: 950,
	PieceData.Type.KING: 20000,
}


class _RootSearchState extends RefCounted:
	var best_move: GameRules.VectorMove
	var best_raw_score: int = -INF_SCORE
	var best_score: int = -INF_SCORE
	var has_best: bool = false

	func _init(initial_move: GameRules.VectorMove) -> void:
		best_move = initial_move


var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


static func get_difficulty_name(diff: Difficulty) -> String:
	var idx := clampi(int(diff), 0, DIFFICULTY_NAMES.size() - 1)
	return DIFFICULTY_NAMES[idx]


## Returns the Glinski stalemate (0.75 : 0.25) score from `perspective_team`'s point of view
## when `stalemated_team` has no legal moves and is not in check.
static func evaluate_stalemate(
	perspective_team: PieceData.Team,
	stalemated_team: PieceData.Team
) -> int:
	return -STALEMATE_BONUS if perspective_team == stalemated_team else STALEMATE_BONUS


## Returns true if the search node at `ply` should be evaluated as a 0 draw (insufficient material,
## 50-move rule, threefold repetition at any ply, or 2-fold repetition at ply >= 2 so winning AI
## breaks shuffling loops while losing AI cannot hallucinate non-forced 2-fold draws at ply 1).
static func _is_search_draw(state: GameRules, ply: int) -> bool:
	if state.is_insufficient_material() or state.is_fifty_move_draw():
		return true
	var rep_count := state.get_repetition_count()
	if rep_count >= GameRules.THREEFOLD_REPETITION_COUNT:
		return true
	if ply >= 2 and rep_count >= 2:
		return true
	return false


## Chooses the best legal move for `ai_team` on a cloned `GameRules` state.
func choose_move(source_rules: GameRules, ai_team: PieceData.Team, difficulty: Difficulty) -> GameRules.VectorMove:
	var state := source_rules.clone_state()
	var legal_moves := _expand_promotions(state.get_all_legal_moves(ai_team), true)
	if legal_moves.is_empty():
		return null
	if legal_moves.size() == 1:
		return legal_moves[0]

	match difficulty:
		Difficulty.EASY:
			return _choose_easy_move(state, legal_moves, ai_team)
		Difficulty.MEDIUM:
			return _choose_search_move(state, legal_moves, ai_team, 2, false, 25)
		Difficulty.HARD:
			return _choose_search_move(state, legal_moves, ai_team, 3, true, 6)

	return legal_moves[0]


## Time-sliced coroutine variant of `choose_move()` for single-threaded Web (WASM) builds.
## Yields to `tree.process_frame` whenever elapsed frame time exceeds `ASYNC_FRAME_BUDGET_USEC`
## so browser rendering and UI animations stay responsive while the CPU is thinking.
func choose_move_async(
	source_rules: GameRules,
	ai_team: PieceData.Team,
	difficulty: Difficulty,
	tree: SceneTree
) -> GameRules.VectorMove:
	var state := source_rules.clone_state()
	var legal_moves := _expand_promotions(state.get_all_legal_moves(ai_team), true)
	if legal_moves.is_empty():
		return null
	if legal_moves.size() == 1:
		return legal_moves[0]

	if difficulty == Difficulty.EASY:
		return _choose_easy_move(state, legal_moves, ai_team)

	var max_depth := 2 if difficulty == Difficulty.MEDIUM else 3
	var use_quiescence := (difficulty == Difficulty.HARD)
	var jitter_range := 25 if difficulty == Difficulty.MEDIUM else 6

	if tree == null:
		return _choose_search_move(state, legal_moves, ai_team, max_depth, use_quiescence, jitter_range)

	_order_moves(state, legal_moves)

	var root_state := _RootSearchState.new(legal_moves[0])
	var slice_start_usec := Time.get_ticks_usec()

	for mv in legal_moves:
		if Time.get_ticks_usec() - slice_start_usec >= ASYNC_FRAME_BUDGET_USEC:
			await tree.process_frame
			slice_start_usec = Time.get_ticks_usec()

		_evaluate_root_move(state, mv, max_depth, use_quiescence, jitter_range, root_state)

	return root_state.best_move


func _choose_easy_move(
	state: GameRules,
	legal_moves: Array[GameRules.VectorMove],
	ai_team: PieceData.Team
) -> GameRules.VectorMove:
	var best_move: GameRules.VectorMove = legal_moves[0]
	var best_score: int = -INF_SCORE

	for mv in legal_moves:
		var undo := state.push_search_move(mv)
		var enemy_team := state.current_turn
		var score: int
		if not state.has_any_legal_move(enemy_team):
			if state.is_king_in_check(enemy_team):
				score = MATE_SCORE
			else:
				score = evaluate_stalemate(ai_team, enemy_team)
		elif _is_search_draw(state, 1):
			score = 0
		else:
			score = evaluate_board(state, ai_team)
			# Add generous noise so Novice plays casually and makes human-like tactical oversights
			score += _rng.randi_range(-165, 165)
			if mv.is_capture:
				score += 45
		state.pop_search_move(undo)

		if score > best_score:
			best_score = score
			best_move = mv

	return best_move


func _choose_search_move(
	state: GameRules,
	legal_moves: Array[GameRules.VectorMove],
	_ai_team: PieceData.Team,
	max_depth: int,
	use_quiescence: bool,
	jitter_range: int
) -> GameRules.VectorMove:
	_order_moves(state, legal_moves)

	var root_state := _RootSearchState.new(legal_moves[0])
	for mv in legal_moves:
		_evaluate_root_move(state, mv, max_depth, use_quiescence, jitter_range, root_state)

	return root_state.best_move


## Shared root-move evaluation helper for synchronous and async search loops.
## Keeps alpha relaxed by `jitter_range` for non-mate scores and discards fail-low upper bounds
## so post-search tie-breaking jitter can never promote a pruned blunder above `best_move`.
func _evaluate_root_move(
	state: GameRules,
	mv: GameRules.VectorMove,
	max_depth: int,
	use_quiescence: bool,
	jitter_range: int,
	root_state: _RootSearchState
) -> void:
	var search_alpha: int = -INF_SCORE
	if root_state.has_best:
		if jitter_range > 0 and absi(root_state.best_raw_score) < MATE_THRESHOLD:
			search_alpha = root_state.best_raw_score - jitter_range
		else:
			search_alpha = root_state.best_raw_score

	var undo := state.push_search_move(mv)
	var raw_score := -_negamax(
		state,
		max_depth - 1,
		-INF_SCORE,
		-search_alpha,
		state.current_turn,
		1,
		use_quiescence
	)
	state.pop_search_move(undo)

	# Fail-low cutoffs return an upper bound <= search_alpha; never jitter them above best_move
	if root_state.has_best and raw_score <= search_alpha:
		return

	if not root_state.has_best or raw_score > root_state.best_raw_score:
		root_state.best_raw_score = raw_score

	# Small tie-breaking jitter among near-equal non-mate moves so games stay varied
	var score := raw_score
	if jitter_range > 0 and absi(raw_score) < MATE_THRESHOLD:
		score += _rng.randi_range(0, jitter_range)

	if not root_state.has_best or score > root_state.best_score:
		root_state.best_score = score
		root_state.best_move = mv
		root_state.has_best = true


func _negamax(
	state: GameRules,
	depth: int,
	alpha: int,
	beta: int,
	perspective_team: PieceData.Team,
	ply: int,
	use_quiescence: bool
) -> int:
	# Evaluate draw conditions before expanding the subtree, preserving checkmate/stalemate precedence
	if _is_search_draw(state, ply):
		if not state.has_any_legal_move(perspective_team):
			if state.is_king_in_check(perspective_team):
				return -(MATE_SCORE - ply * 10)
			return evaluate_stalemate(perspective_team, perspective_team)
		return 0

	# Cut off at depth-0 leaf nodes BEFORE generating all legal moves (except checks and low-piece endgames)
	if depth <= 0:
		if use_quiescence:
			return _quiescence(state, alpha, beta, perspective_team, 1, ply, MAX_Q_CHECK_EXTENSIONS)
		if state.is_king_in_check(perspective_team):
			if not state.has_any_legal_move(perspective_team):
				return -(MATE_SCORE - ply * 10)
		elif state.pieces.size() <= ENDGAME_STALEMATE_CHECK_MAX_PIECES and not state.has_any_legal_move(perspective_team):
			return evaluate_stalemate(perspective_team, perspective_team)
		return evaluate_board(state, perspective_team)

	var moves := _expand_promotions(state.get_all_legal_moves(perspective_team), false)
	if moves.is_empty():
		if state.is_king_in_check(perspective_team):
			return -(MATE_SCORE - ply * 10)
		return evaluate_stalemate(perspective_team, perspective_team)

	_order_moves(state, moves)

	var best_val: int = -INF_SCORE
	for mv in moves:
		var undo := state.push_search_move(mv)
		var val := -_negamax(
			state,
			depth - 1,
			-beta,
			-alpha,
			state.current_turn,
			ply + 1,
			use_quiescence
		)
		state.pop_search_move(undo)

		if val > best_val:
			best_val = val
		if val > alpha:
			alpha = val
		if alpha >= beta:
			break

	return best_val


## Capture/promotion quiescence search with legal check evasions to prevent horizon-effect blunders
## and detect leaf-node checkmates on Hard difficulty.
func _quiescence(
	state: GameRules,
	alpha: int,
	beta: int,
	perspective_team: PieceData.Team,
	q_depth: int,
	ply: int,
	check_extensions_left: int = MAX_Q_CHECK_EXTENSIONS
) -> int:
	if _is_search_draw(state, ply):
		if not state.has_any_legal_move(perspective_team):
			if state.is_king_in_check(perspective_team):
				return -(MATE_SCORE - ply * 10)
			return evaluate_stalemate(perspective_team, perspective_team)
		return 0

	if state.is_king_in_check(perspective_team):
		if check_extensions_left <= 0:
			if not state.has_any_legal_move(perspective_team):
				return -(MATE_SCORE - ply * 10)
			return evaluate_board(state, perspective_team)

		var evasions := _expand_promotions(state.get_all_legal_moves(perspective_team), false)
		if evasions.is_empty():
			return -(MATE_SCORE - ply * 10)

		_order_moves(state, evasions)
		var best_evasion_val: int = -INF_SCORE
		for mv in evasions:
			var undo := state.push_search_move(mv)
			var score := -_quiescence(
				state,
				-beta,
				-alpha,
				state.current_turn,
				q_depth,
				ply + 1,
				check_extensions_left - 1
			)
			state.pop_search_move(undo)

			if score > best_evasion_val:
				best_evasion_val = score
			if score > alpha:
				alpha = score
			if alpha >= beta:
				break

		return best_evasion_val

	if state.pieces.size() <= ENDGAME_STALEMATE_CHECK_MAX_PIECES and not state.has_any_legal_move(perspective_team):
		return evaluate_stalemate(perspective_team, perspective_team)

	var stand_pat := evaluate_board(state, perspective_team)
	if stand_pat >= beta:
		return stand_pat
	if stand_pat > alpha:
		alpha = stand_pat
	if q_depth <= 0:
		return stand_pat

	# Generate only tactical moves (captures & promotions), avoiding quiet move generation & legality checks
	var tactical_moves := _expand_promotions(state.get_all_tactical_moves(perspective_team), false)
	if tactical_moves.is_empty():
		return stand_pat

	_order_moves(state, tactical_moves)

	var best_val: int = stand_pat
	for mv in tactical_moves:
		var undo := state.push_search_move(mv)
		var score := -_quiescence(
			state,
			-beta,
			-alpha,
			state.current_turn,
			q_depth - 1,
			ply + 1,
			check_extensions_left
		)
		state.pop_search_move(undo)

		if score > best_val:
			best_val = score
		if score > alpha:
			alpha = score
		if alpha >= beta:
			break

	return best_val


## Static evaluation of `state` from `perspective_team`'s point of view (in centipawns).
static func evaluate_board(state: GameRules, perspective_team: PieceData.Team) -> int:
	var cyan_score: int = 0
	var magenta_score: int = 0
	var cyan_bishops_mask: int = 0
	var magenta_bishops_mask: int = 0

	for p in state.pieces:
		var val: int = PIECE_VALUES.get(p.type, 100)
		var pos_bonus: int = _evaluate_piece_position(p)
		var total_piece_score := val + pos_bonus

		if p.team == PieceData.Team.CYAN:
			cyan_score += total_piece_score
			if p.type == PieceData.Type.BISHOP:
				cyan_bishops_mask |= (1 << GameRules.get_cell_color_index(p.grid_pos))
		else:
			magenta_score += total_piece_score
			if p.type == PieceData.Type.BISHOP:
				magenta_bishops_mask |= (1 << GameRules.get_cell_color_index(p.grid_pos))

	# Glinski 3-color Bishop synergy bonus: having all 3 shade bishops or a pair is very strong
	if cyan_bishops_mask == 0b111:
		cyan_score += 55
	elif cyan_bishops_mask in [0b011, 0b101, 0b110]:
		cyan_score += 22

	if magenta_bishops_mask == 0b111:
		magenta_score += 55
	elif magenta_bishops_mask in [0b011, 0b101, 0b110]:
		magenta_score += 22

	# Only the side to move (`state.current_turn`) can legally be in check after a legal move
	if state.is_king_in_check(state.current_turn):
		if state.current_turn == PieceData.Team.MAGENTA:
			cyan_score += 35
		else:
			magenta_score += 35

	var diff := cyan_score - magenta_score
	return diff if perspective_team == PieceData.Team.CYAN else -diff


static func _evaluate_piece_position(p: PieceData) -> int:
	var q := p.grid_pos.x
	var r := p.grid_pos.y
	var hex_dist_from_center := maxi(absi(q), maxi(absi(r), absi(q + r)))

	match p.type:
		PieceData.Type.PAWN:
			# Measure how close the pawn is to its promotion border along its forward ray
			var steps_to_promote := _steps_to_promotion(p.team, p.grid_pos)
			# Max distance on radius-5 board is 10 steps; reward advancement exponentially near promotion
			var advancement := clampi(8 - steps_to_promote, 0, 8)
			var advance_bonus := advancement * 12 + (advancement * advancement * 2)
			var center_file_bonus := (5 - absi(q)) * 4
			return advance_bonus + center_file_bonus

		PieceData.Type.KNIGHT:
			# 12-direction hex knights dominate the center and lose half their jumps on the rim
			return (5 - hex_dist_from_center) * 14

		PieceData.Type.BISHOP:
			return (5 - hex_dist_from_center) * 8 + (8 if p.has_moved else 0)

		PieceData.Type.ROOK:
			return (5 - hex_dist_from_center) * 5 + (6 if p.has_moved else 0)

		PieceData.Type.QUEEN:
			return (5 - hex_dist_from_center) * 9

		PieceData.Type.KING:
			# Prefer staying tucked away from the Volatile center hexes
			return (hex_dist_from_center - 3) * 8

	return 0


static func _steps_to_promotion(team: PieceData.Team, pos: Vector2i) -> int:
	if team == PieceData.Team.CYAN:
		# Cyan moves North (dr = -1); top border is r_min = max(-5, -q - 5)
		var r_min := maxi(-GameRules.BOARD_RADIUS, -pos.x - GameRules.BOARD_RADIUS)
		return maxi(0, pos.y - r_min)
	else:
		# Magenta moves South (dr = +1); bottom border is r_max = min(5, -q + 5)
		var r_max := mini(GameRules.BOARD_RADIUS, -pos.x + GameRules.BOARD_RADIUS)
		return maxi(0, r_max - pos.y)


func _expand_promotions(
	moves: Array[GameRules.VectorMove],
	include_all_underpromotions: bool = true
) -> Array[GameRules.VectorMove]:
	var promo_types: Array[PieceData.Type] = (
		ROOT_PROMOTION_TYPES if include_all_underpromotions else SEARCH_PROMOTION_TYPES
	)
	var expanded: Array[GameRules.VectorMove] = []
	for mv in moves:
		if not mv.is_promotion:
			expanded.append(mv)
		else:
			for ptype in promo_types:
				var promo_mv := mv.duplicate_move()
				promo_mv.promotion_type = ptype
				expanded.append(promo_mv)
	return expanded


func _order_moves(state: GameRules, moves: Array[GameRules.VectorMove]) -> void:
	if moves.size() <= 1:
		return
	var scored: Array[Dictionary] = []
	scored.resize(moves.size())
	for i in range(moves.size()):
		var mv := moves[i]
		var s: int = 0
		if mv.is_capture:
			var victim := state.get_piece_by_id(mv.captured_piece_id)
			var attacker := state.get_piece_by_id(mv.piece_id)
			var v_val: int = PIECE_VALUES.get(victim.type, 100) if victim != null else 100
			var a_val: int = (
				1000 if attacker != null and attacker.type == PieceData.Type.KING
				else (PIECE_VALUES.get(attacker.type, 100) if attacker != null else 100)
			)
			# MVV-LVA: prioritize high-value captures with low-value attackers (King captures stay above quiet moves)
			s += 10000 + v_val * 10 - a_val
		if mv.is_promotion:
			s += 8000 + int(PIECE_VALUES.get(mv.promotion_type, 950))
		# Slight preference for moving toward the center hexes
		var dest_dist := maxi(absi(mv.to.x), maxi(absi(mv.to.y), absi(mv.to.x + mv.to.y)))
		s += (5 - dest_dist) * 10
		scored[i] = {"move": mv, "score": s}

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	for i in range(scored.size()):
		moves[i] = scored[i]["move"]
