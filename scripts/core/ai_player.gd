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
const INF_SCORE: int = 1000000

const PIECE_VALUES: Dictionary = {
	PieceData.Type.PAWN: 100,
	PieceData.Type.KNIGHT: 320,
	PieceData.Type.BISHOP: 330,
	PieceData.Type.ROOK: 500,
	PieceData.Type.QUEEN: 950,
	PieceData.Type.KING: 20000,
}

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


static func get_difficulty_name(diff: Difficulty) -> String:
	var idx := clampi(int(diff), 0, DIFFICULTY_NAMES.size() - 1)
	return DIFFICULTY_NAMES[idx]


## Chooses the best legal move for `ai_team` on a cloned `GameRules` state.
func choose_move(source_rules: GameRules, ai_team: PieceData.Team, difficulty: Difficulty) -> GameRules.VectorMove:
	var state := source_rules.clone_state()
	var legal_moves := _expand_promotions(state.get_all_legal_moves(ai_team))
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
		var enemy_moves := state.get_all_legal_moves(enemy_team)
		var score: int
		if enemy_moves.is_empty():
			if state.is_king_in_check(enemy_team):
				score = MATE_SCORE
			else:
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
	ai_team: PieceData.Team,
	max_depth: int,
	use_quiescence: bool,
	jitter_range: int
) -> GameRules.VectorMove:
	_order_moves(state, legal_moves)

	var best_move: GameRules.VectorMove = legal_moves[0]
	var best_score: int = -INF_SCORE
	var alpha: int = -INF_SCORE
	var beta: int = INF_SCORE

	for mv in legal_moves:
		var undo := state.push_search_move(mv)
		var score := -_negamax(
			state,
			max_depth - 1,
			-beta,
			-alpha,
			state.current_turn,
			1,
			use_quiescence
		)
		state.pop_search_move(undo)

		# Small tie-breaking jitter among near-equal moves so games stay varied
		if jitter_range > 0 and absi(score) < MATE_SCORE - 100:
			score += _rng.randi_range(-jitter_range, jitter_range)

		if score > best_score:
			best_score = score
			best_move = mv
		if score > alpha:
			alpha = score

	return best_move


func _negamax(
	state: GameRules,
	depth: int,
	alpha: int,
	beta: int,
	perspective_team: PieceData.Team,
	ply: int,
	use_quiescence: bool
) -> int:
	var moves := _expand_promotions(state.get_all_legal_moves(perspective_team), false)
	if moves.is_empty():
		if state.is_king_in_check(perspective_team):
			return -(MATE_SCORE - ply * 10)
		# Glinski stalemate is 0.75 : 0.25 in favor of the stalemating player
		return -250

	if depth <= 0:
		if use_quiescence:
			return _quiescence(state, alpha, beta, perspective_team, 1)
		return evaluate_board(state, perspective_team)

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


## 1-ply capture/promotion quiescence search to prevent horizon-effect blunders on Hard difficulty.
func _quiescence(
	state: GameRules,
	alpha: int,
	beta: int,
	perspective_team: PieceData.Team,
	q_depth: int
) -> int:
	var stand_pat := evaluate_board(state, perspective_team)
	if stand_pat >= beta:
		return beta
	if stand_pat > alpha:
		alpha = stand_pat
	if q_depth <= 0:
		return stand_pat

	var all_moves := state.get_all_legal_moves(perspective_team)
	if all_moves.is_empty():
		if state.is_king_in_check(perspective_team):
			return -(MATE_SCORE - 50)
		return -250

	var tactical_moves: Array[GameRules.VectorMove] = []
	for mv in all_moves:
		if mv.is_capture or mv.is_promotion:
			tactical_moves.append(mv)

	if tactical_moves.is_empty():
		return stand_pat

	_order_moves(state, tactical_moves)

	for mv in tactical_moves:
		var undo := state.push_search_move(mv)
		var score := -_quiescence(state, -beta, -alpha, state.current_turn, q_depth - 1)
		state.pop_search_move(undo)

		if score >= beta:
			return beta
		if score > alpha:
			alpha = score

	return alpha


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

	# Check pressure bonus
	if state.is_king_in_check(PieceData.Team.MAGENTA):
		cyan_score += 35
	if state.is_king_in_check(PieceData.Team.CYAN):
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
	include_underpromotions: bool = true
) -> Array[GameRules.VectorMove]:
	var expanded: Array[GameRules.VectorMove] = []
	for mv in moves:
		if not mv.is_promotion:
			expanded.append(mv)
		else:
			mv.promotion_type = PieceData.Type.QUEEN
			expanded.append(mv)
			if include_underpromotions:
				var k_mv := mv.duplicate_move()
				k_mv.promotion_type = PieceData.Type.KNIGHT
				expanded.append(k_mv)
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
			var a_val: int = PIECE_VALUES.get(attacker.type, 100) if attacker != null else 100
			# MVV-LVA: prioritize high-value captures with low-value attackers
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
