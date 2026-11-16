extends SceneTree
## Headless unit test runner for Vector Chess (Glinski's Hexagonal Chess).
## Run with: godot --headless -s res://tests/test_rules.gd

const MainScript = preload("res://scripts/main.gd")
const MainScene = preload("res://scenes/main.tscn")

var _tests_run: int = 0
var _tests_failed: int = 0


func _initialize() -> void:
	_run_all_tests()


func _run_all_tests() -> void:
	print("=== Vector Chess Headless Test Suite ===")
	_test_board_geometry_and_coordinates()
	_test_initial_glinski_setup()
	_test_pawn_double_step_and_en_passant()
	_test_pawn_promotion()
	_test_bishop_three_color_invariance()
	_test_check_checkmate_and_stalemate()
	_test_move_execution_and_undo()
	_test_search_push_pop_consistency()
	_test_spatial_index_and_reverse_attack_check()
	_test_piece_faceted_meshes()
	_test_ai_player_move_selection()
	await _test_ai_player_async_move_selection()
	_test_software_renderer_detection()
	_test_vector_board_caching_and_idle_redraw()
	_test_mobile_scaling_and_responsive_layout()

	print("========================================")
	print("Tests run: %d | Failed: %d" % [_tests_run, _tests_failed])
	if _tests_failed > 0:
		push_error("Test suite failed with %d failure(s)." % _tests_failed)
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	_tests_run += 1
	if not condition:
		_tests_failed += 1
		printerr("  [FAIL] %s" % message)
	else:
		print("  [PASS] %s" % message)


func _is_move_in_list(candidate: GameRules.VectorMove, moves: Array[GameRules.VectorMove]) -> bool:
	if candidate == null:
		return false
	for mv in moves:
		if (
			mv.piece_id == candidate.piece_id
			and mv.from == candidate.from
			and mv.to == candidate.to
			and mv.is_promotion == candidate.is_promotion
		):
			return true
	return false


func _test_board_geometry_and_coordinates() -> void:
	print("\n-- Board Geometry & Coordinates --")
	var cells := GameRules.get_all_board_cells()
	_assert(cells.size() == 91, "Board has exactly 91 hex cells (got %d)" % cells.size())

	var roundtrip_ok := true
	for cell in cells:
		if not GameRules.is_inside_board(cell):
			roundtrip_ok = false
			break
		var alg := GameRules.coord_to_algebraic(cell)
		var back := GameRules.algebraic_to_axial(alg)
		if back != cell:
			roundtrip_ok = false
			break
	_assert(roundtrip_ok, "All 91 axial coordinates round-trip cleanly through Glinski algebraic notation")
	_assert(not GameRules.is_inside_board(Vector2i(6, 0)), "Out-of-bounds hex (6, 0) is rejected")
	_assert(not GameRules.is_inside_board(Vector2i(3, 3)), "Out-of-bounds hex (3, 3) where |q+r|=6 is rejected")


func _test_initial_glinski_setup() -> void:
	print("\n-- Initial Glinski Setup --")
	var rules := GameRules.new()
	_assert(rules.pieces.size() == 36, "Initial board has 36 pieces (18 per team)")
	_assert(rules.current_turn == PieceData.Team.CYAN, "Cyan moves first")

	var cyan_pawns := 0
	var cyan_bishops := 0
	var bishop_shades := {}
	for p in rules.pieces:
		if p.team == PieceData.Team.CYAN:
			if p.type == PieceData.Type.PAWN:
				cyan_pawns += 1
			elif p.type == PieceData.Type.BISHOP:
				cyan_bishops += 1
				bishop_shades[GameRules.get_cell_color_index(p.grid_pos)] = true

	_assert(cyan_pawns == 9, "Cyan starts with 9 pawns")
	_assert(cyan_bishops == 3, "Cyan starts with 3 bishops")
	_assert(bishop_shades.size() == 3, "Cyan's 3 bishops occupy all 3 distinct hex tile shades")


func _test_pawn_double_step_and_en_passant() -> void:
	print("\n-- Pawn Double-Step & En Passant --")
	var rules := GameRules.new()
	rules.pieces.clear()

	# Place Kings safely tucked away
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))

	# Cyan pawn on starting cell e4 (-1, 2), Magenta pawn positioned at d5 (-2, 1)
	var cyan_pawn := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	var mag_pawn := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("d5"))

	var cyan_moves := rules.get_legal_moves_for_piece(cyan_pawn)
	var double_move: GameRules.VectorMove = null
	for mv in cyan_moves:
		if mv.is_double_step:
			double_move = mv
			break

	_assert(double_move != null, "Cyan pawn on starting cell e4 can double-step to e6")
	rules.execute_move(double_move)
	_assert(
		rules.en_passant_target == GameRules.algebraic_to_axial("e5"),
		"Double-step sets en_passant_target to skipped cell e5"
	)
	_assert(
		rules.move_history.back()["notation"] == "P e4->e6  d(+0,-2)",
		"Double-step records notation 'P e4->e6  d(+0,-2)'"
	)

	var mag_moves := rules.get_legal_moves_for_piece(mag_pawn)
	var ep_move: GameRules.VectorMove = null
	for mv in mag_moves:
		if mv.is_en_passant:
			ep_move = mv
			break

	_assert(ep_move != null, "Magenta pawn on d5 has legal en passant capture onto e5")
	if ep_move != null:
		rules.execute_move(ep_move)
		_assert(rules.get_piece_by_id(cyan_pawn.id) == null, "En passant removes captured Cyan pawn from board")
		_assert(
			rules.move_history.back()["notation"] == "P d5xe5 e.p.  d(+1,+0)",
			"En passant capture records notation 'P d5xe5 e.p.  d(+1,+0)'"
		)

	# Orthogonal 2-pawn discovered check pin:
	# Along r = 0, Cyan Rook at b6 (-4, 0) attacks Magenta King at h4 (2, 0) through e6 (-1, 0) and f6 (0, 0).
	# After Cyan pawn double-steps e4 -> e6, vacating BOTH f6 and e6 via en passant f6xe5 exposes h4 to check,
	# even though quiet step f6 -> f5 leaves e6 occupied and remains legal.
	var ortho_pin_rules := GameRules.new()
	ortho_pin_rules.pieces.clear()
	ortho_pin_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	ortho_pin_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("h4"))
	ortho_pin_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("b6"))
	var pinned_mag_pawn := ortho_pin_rules._spawn_piece(
		PieceData.Team.MAGENTA,
		PieceData.Type.PAWN,
		GameRules.algebraic_to_axial("f6")
	)
	var ep_cyan_pawn := ortho_pin_rules._spawn_piece(
		PieceData.Team.CYAN,
		PieceData.Type.PAWN,
		GameRules.algebraic_to_axial("e4")
	)

	var ep_setup_move: GameRules.VectorMove = null
	for mv in ortho_pin_rules.get_legal_moves_for_piece(ep_cyan_pawn):
		if mv.is_double_step:
			ep_setup_move = mv
			break
	ortho_pin_rules.execute_move(ep_setup_move)

	var pinned_moves := ortho_pin_rules.get_legal_moves_for_piece(pinned_mag_pawn)
	var has_illegal_ep := false
	var has_legal_quiet_step := false
	var target_f5 := GameRules.algebraic_to_axial("f5")
	for mv in pinned_moves:
		if mv.is_en_passant:
			has_illegal_ep = true
		elif mv.to == target_f5:
			has_legal_quiet_step = true

	var mag_tactical := ortho_pin_rules.get_all_tactical_moves(PieceData.Team.MAGENTA)
	var has_tactical_ep := false
	for mv in mag_tactical:
		if mv.is_en_passant:
			has_tactical_ep = true

	_assert(
		not has_illegal_ep and not has_tactical_ep,
		"En passant f6xe5 that removes both pawns on r=0 ray and exposes Magenta King to Rook check is rejected"
	)
	_assert(
		has_legal_quiet_step,
		"Quiet step f6->f5 remains legal because captured Cyan pawn on e6 still blocks the r=0 Rook ray"
	)
	_assert(
		_verify_spatial_index_invariants(ortho_pin_rules),
		"Spatial grid invariants remain intact after pinned en passant check simulation"
	)

	# Diagonal Bishop ray pin on en passant:
	# Cyan Bishop at c3 (-3, 3) pins Magenta pawn at d5 (-2, 1) against Magenta King at e7 (-1, -1) along (1, -2).
	var diag_pin_rules := GameRules.new()
	diag_pin_rules.pieces.clear()
	diag_pin_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	diag_pin_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("e7"))
	diag_pin_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("c3"))
	var diag_mag_pawn := diag_pin_rules._spawn_piece(
		PieceData.Team.MAGENTA,
		PieceData.Type.PAWN,
		GameRules.algebraic_to_axial("d5")
	)
	var diag_cyan_pawn := diag_pin_rules._spawn_piece(
		PieceData.Team.CYAN,
		PieceData.Type.PAWN,
		GameRules.algebraic_to_axial("e4")
	)
	for mv in diag_pin_rules.get_legal_moves_for_piece(diag_cyan_pawn):
		if mv.is_double_step:
			diag_pin_rules.execute_move(mv)
			break

	var diag_ep_found := false
	for mv in diag_pin_rules.get_legal_moves_for_piece(diag_mag_pawn):
		if mv.is_en_passant:
			diag_ep_found = true
	_assert(
		not diag_ep_found,
		"En passant d5xe5 by diagonally pinned pawn is rejected when vacating d5 exposes King to Bishop ray"
	)


func _test_pawn_promotion() -> void:
	print("\n-- Pawn Promotion, Capture-Promotion & Move Notation --")
	var rules := GameRules.new()
	rules.pieces.clear()
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))

	# Cyan pawn at f10 (one step below top hex f11)
	var pawn := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	var moves := rules.get_legal_moves_for_piece(pawn)
	_assert(moves.size() == 1 and moves[0].is_promotion, "Pawn stepping onto f11 is flagged as promotion")

	moves[0].promotion_type = PieceData.Type.QUEEN
	rules.execute_move(moves[0])
	_assert(pawn.type == PieceData.Type.QUEEN, "Executed promotion updates piece type to Queen")
	_assert(
		rules.move_history.back()["notation"] == "P f10->f11=Q  d(+0,-1)",
		"Quiet Queen promotion formats as 'P f10->f11=Q  d(+0,-1)'"
	)

	# Capture-promotion onto top border: Cyan pawn at e10 (-1, -4) capturing Magenta Rook at f11 (0, -5)
	var cap_rules := GameRules.new()
	cap_rules.pieces.clear()
	cap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	cap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var cap_pawn := cap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e10"))
	var enemy_rook := cap_rules._spawn_piece(
		PieceData.Team.MAGENTA,
		PieceData.Type.ROOK,
		GameRules.algebraic_to_axial("f11")
	)

	var cap_moves := cap_rules.get_legal_moves_for_piece(cap_pawn)
	var cap_promo_mv: GameRules.VectorMove = null
	var target_f11 := GameRules.algebraic_to_axial("f11")
	for mv in cap_moves:
		if mv.to == target_f11:
			cap_promo_mv = mv
			break

	_assert(
		cap_promo_mv != null and cap_promo_mv.is_capture and cap_promo_mv.is_promotion,
		"Pawn capture e10xf11 onto promotion border sets both is_capture and is_promotion"
	)

	if cap_promo_mv != null:
		var promo_cases := [
			{"type": PieceData.Type.QUEEN, "code": "Q", "sides": 8},
			{"type": PieceData.Type.ROOK, "code": "R", "sides": 6},
			{"type": PieceData.Type.BISHOP, "code": "B", "sides": 4},
			{"type": PieceData.Type.KNIGHT, "code": "N", "sides": 5},
		]
		for pc in promo_cases:
			var p_type: PieceData.Type = pc["type"]
			var p_code: String = pc["code"]
			var p_sides: int = pc["sides"]
			var mv_variant := cap_promo_mv.duplicate_move()
			mv_variant.promotion_type = p_type
			cap_rules.execute_move(mv_variant)

			var promoted := cap_rules.get_piece_at(target_f11)
			var expected_notation := "P e10xf11=%s  d(+1,-1)" % p_code
			var actual_notation: String = cap_rules.move_history.back()["notation"]
			_assert(
				promoted != null
				and promoted.type == p_type
				and promoted.sides_count == p_sides
				and cap_rules.get_piece_by_id(enemy_rook.id) == null
				and actual_notation == expected_notation,
				"Capture-promotion to %s updates type/sides, removes victim, and formats '%s'" % [
					p_code,
					expected_notation,
				]
			)
			cap_rules.undo_last_move()
			var restored_pawn := cap_rules.get_piece_at(GameRules.algebraic_to_axial("e10"))
			var restored_rook := cap_rules.get_piece_at(target_f11)
			_assert(
				restored_pawn != null
				and restored_pawn.type == PieceData.Type.PAWN
				and restored_rook != null
				and restored_rook.type == PieceData.Type.ROOK,
				"Undo after =%s capture-promotion restores Cyan pawn on e10 and Magenta Rook on f11" % p_code
			)

	# Non-pawn capture notation check (e.g., Knight capture uses 'N' prefix and 'x' separator without suffix)
	var knight_rules := GameRules.new()
	knight_rules.pieces.clear()
	knight_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	knight_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var knight := knight_rules._spawn_piece(
		PieceData.Team.CYAN,
		PieceData.Type.KNIGHT,
		GameRules.algebraic_to_axial("f6")
	)
	knight_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("g8"))
	var target_g8 := GameRules.algebraic_to_axial("g8")
	for mv in knight_rules.get_legal_moves_for_piece(knight):
		if mv.to == target_g8:
			knight_rules.execute_move(mv)
			break
	_assert(
		knight_rules.move_history.back()["notation"] == "N f6xg8  d(+1,-3)",
		"Non-pawn capture formats as 'N f6xg8  d(+1,-3)'"
	)


func _test_bishop_three_color_invariance() -> void:
	print("\n-- Bishop 3-Color Invariance --")
	var rules := GameRules.new()
	rules.pieces.clear()
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))

	var bishop := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, Vector2i(0, 0))
	var start_shade := GameRules.get_cell_color_index(bishop.grid_pos)
	var moves := rules.get_legal_moves_for_piece(bishop)
	var same_shade := not moves.is_empty()
	for mv in moves:
		if GameRules.get_cell_color_index(mv.to) != start_shade:
			same_shade = false
			break
	_assert(same_shade, "Center bishop generates %d diagonal moves, all preserving shade %d" % [moves.size(), start_shade])


func _test_check_checkmate_and_stalemate() -> void:
	print("\n-- Check, Checkmate & Stalemate Detection --")
	var rules := GameRules.new()
	rules.pieces.clear()

	# Corner Magenta King at f11 (0, -5), Cyan King at f1 (0, 5), Cyan Queen at f9 (0, -3), Cyan Rook protecting f10
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	var queen := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f9"))
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f8"))

	var q_moves := rules.get_legal_moves_for_piece(queen)
	var mate_move: GameRules.VectorMove = null
	var target_f10 := GameRules.algebraic_to_axial("f10")
	for mv in q_moves:
		if mv.to == target_f10:
			mate_move = mv
			break

	_assert(mate_move != null, "Queen on f9 can move to f10")
	if mate_move != null:
		rules.execute_move(mate_move)
		_assert(rules.is_king_in_check(PieceData.Team.MAGENTA), "Magenta King on f11 is in check")
		_assert(rules.is_game_over, "Game is marked over on checkmate")
		_assert(rules.status_text.begins_with("CHECKMATE"), "Status text reports CHECKMATE (%s)" % rules.status_text)

	# Glinski Stalemate (0.75 : 0.25):
	# Magenta King at f11 (0, -5) has 5 adjacent board cells: g10 (1,-5), g9 (1,-4), f10 (0,-4), e9 (-1,-3), e10 (-1,-4).
	# Cyan Rook at e6 (-1, 0) covers file e (e9, e10) without checking f11.
	# Cyan Queen moving g7 (1, -2) -> g8 (1, -3) covers g10, g9, f10, and e9 while offset (-1, -2) to f11 is a Knight jump!
	var stale_rules := GameRules.new()
	stale_rules.pieces.clear()
	stale_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	var stale_queen := stale_rules._spawn_piece(
		PieceData.Team.CYAN,
		PieceData.Type.QUEEN,
		GameRules.algebraic_to_axial("g7")
	)

	var stale_move: GameRules.VectorMove = null
	var target_g8 := GameRules.algebraic_to_axial("g8")
	for mv in stale_rules.get_legal_moves_for_piece(stale_queen):
		if mv.to == target_g8:
			stale_move = mv
			break

	_assert(stale_move != null, "Cyan Queen on g7 can move to g8 to deliver stalemate")
	if stale_move != null:
		stale_rules.execute_move(stale_move)
		_assert(
			not stale_rules.is_king_in_check(PieceData.Team.MAGENTA),
			"Magenta King on f11 is NOT in check in stalemate position"
		)
		_assert(stale_rules.is_game_over, "Game is marked over on Glinski stalemate")
		_assert(
			stale_rules.status_text == "STALEMATE - Cyan 0.75 : 0.25 Magenta",
			"Status text reports Glinski 0.75 : 0.25 stalemate (%s)" % stale_rules.status_text
		)
		stale_rules.undo_last_move()
		_assert(not stale_rules.is_game_over, "Undoing stalemate move clears is_game_over")


func _test_move_execution_and_undo() -> void:
	print("\n-- Move Execution & Undo --")
	var rules := GameRules.new()
	var all_opening := rules.get_all_legal_moves(PieceData.Team.CYAN)
	_assert(not all_opening.is_empty(), "Cyan has %d legal opening moves" % all_opening.size())

	var first_move := all_opening[0]
	var orig_from := first_move.from
	var piece_id := first_move.piece_id
	rules.execute_move(first_move)
	_assert(rules.current_turn == PieceData.Team.MAGENTA, "Turn advances to Magenta after Cyan move")

	var undone := rules.undo_last_move()
	_assert(undone, "undo_last_move() returns true")
	_assert(rules.current_turn == PieceData.Team.CYAN, "Turn reverts to Cyan after undo")
	_assert(rules.get_piece_by_id(piece_id).grid_pos == orig_from, "Piece returns to original hex after undo")


func _test_search_push_pop_consistency() -> void:
	print("\n-- AI Search push_search_move / pop_search_move --")
	var rules := GameRules.new()
	var moves := rules.get_all_legal_moves(PieceData.Team.CYAN)
	var mv := moves[0]
	var piece := rules.get_piece_by_id(mv.piece_id)
	var orig_pos := piece.grid_pos
	var orig_count := rules.pieces.size()

	var undo := rules.push_search_move(mv)
	_assert(piece.grid_pos == mv.to, "push_search_move moves piece in-place")
	rules.pop_search_move(undo)
	_assert(piece.grid_pos == orig_pos and rules.pieces.size() == orig_count, "pop_search_move restores exact board state")


func _verify_spatial_index_invariants(rules: GameRules) -> bool:
	for cell in GameRules.get_all_board_cells():
		var expected: PieceData = null
		for p in rules.pieces:
			if p.grid_pos == cell:
				expected = p
				break
		if rules.get_piece_at(cell) != expected:
			return false
	for p in rules.pieces:
		if rules.get_piece_by_id(p.id) != p:
			return false
	return true


func _test_spatial_index_and_reverse_attack_check() -> void:
	print("\n-- O(1) Spatial Index & Allocation-Free Reverse-Attack Check --")
	var rules := GameRules.new()
	_assert(_verify_spatial_index_invariants(rules), "Initial 36-piece board spatial grid and ID map match linear scan")

	# Play a sequence of moves including captures and verify index invariants after push/pop and execute/undo
	for pair in [["f5", "f7"], ["e7", "f6"], ["e4", "f6"], ["g7", "f6"]]:
		var from_c := GameRules.algebraic_to_axial(pair[0])
		var to_c := GameRules.algebraic_to_axial(pair[1])
		var p := rules.get_piece_at(from_c)
		var chosen: GameRules.VectorMove = null
		if p != null:
			for mv in rules.get_legal_moves_for_piece(p):
				if mv.to == to_c:
					chosen = mv
					break
		if chosen != null:
			var undo := rules.push_search_move(chosen)
			var ok_push := _verify_spatial_index_invariants(rules)
			rules.pop_search_move(undo)
			var ok_pop := _verify_spatial_index_invariants(rules)
			rules.execute_move(chosen)
			var ok_exec := _verify_spatial_index_invariants(rules)
			if not (ok_push and ok_pop and ok_exec):
				_assert(false, "Spatial index desynchronized during move %s->%s" % [pair[0], pair[1]])
				return
	_assert(true, "Spatial grid and ID map stay synchronized across push_search_move, pop_search_move, and execute_move captures")

	while rules.undo_last_move():
		if not _verify_spatial_index_invariants(rules):
			_assert(false, "Spatial index desynchronized after undo_last_move()")
			return
	_assert(rules.pieces.size() == 36, "Spatial grid and ID map stay synchronized after full undo history rollback")

	# Verify reverse-attack detection across all piece types and ray blockers
	rules.pieces.clear()
	var king_pos := Vector2i(0, 0)
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, king_pos)
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, Vector2i(0, -5))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Center King is not in check when enemy King is 5 hexes away")

	# Knight attack at jump vector (2, -3)
	var knight := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, Vector2i(2, -3))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects enemy Knight jump at (2, -3)")
	rules.pieces.erase(knight)

	# Diagonal Bishop attack at (2, -4) = 2 * (1, -2) and blocker at (1, -2)
	var bishop := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, Vector2i(2, -4))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects unobstructed diagonal Bishop ray")
	var diag_blocker := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(1, -2))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Intermediate piece on diagonal ray blocks Bishop check")
	rules.pieces.erase(diag_blocker)
	rules.pieces.erase(bishop)

	# Orthogonal Rook attack at (-3, 0) and blocker at (-1, 0)
	var rook := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, Vector2i(-3, 0))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects unobstructed orthogonal Rook ray")
	var ortho_blocker := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(-1, 0))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Intermediate piece on orthogonal ray blocks Rook check")
	rules.pieces.erase(ortho_blocker)
	rules.pieces.erase(rook)

	# Magenta Pawn capture attack from (1, -1) -> attacks (0, 0) via MAGENTA_PAWN_CAP_DIRS (-1, 1)
	var mpawn := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, Vector2i(1, -1))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects enemy Magenta Pawn capture vector")
	rules.pieces.erase(mpawn)


func _test_piece_faceted_meshes() -> void:
	print("\n-- PieceData Faceted Vector Meshes & Pre-Baked ArrayMeshes --")
	var all_valid := true
	var array_meshes_valid := true
	var atlas_regions := {}
	for t in [
		PieceData.Type.PAWN,
		PieceData.Type.KNIGHT,
		PieceData.Type.BISHOP,
		PieceData.Type.ROOK,
		PieceData.Type.QUEEN,
		PieceData.Type.KING,
	]:
		var mesh := PieceData.get_faceted_mesh(t)
		var facets: Array = mesh.get("facets", [])
		var outlines: Array = mesh.get("outlines", [])
		if facets.is_empty() or outlines.is_empty():
			all_valid = false
			break

		for team in [PieceData.Team.CYAN, PieceData.Team.MAGENTA]:
			for sel in [false, true]:
				var am := PieceData.get_piece_array_mesh(t, team, sel)
				var am_cached := PieceData.get_piece_array_mesh(t, team, sel)
				if am == null or am.get_surface_count() != 1 or am != am_cached:
					array_meshes_valid = false
					break
				var reg := VectorBoard.get_piece_atlas_region(t, team, sel)
				atlas_regions[reg.position] = reg

	_assert(all_valid, "All 6 piece types generate non-empty faceted vector silhouettes and outlines")
	_assert(array_meshes_valid, "All 24 (type, team, selected) piece variants build and cache valid 2D ArrayMeshes")
	_assert(atlas_regions.size() == 24, "All 24 piece variants map to distinct 128x128 regions in the shared piece atlas")


func _test_ai_player_move_selection() -> void:
	print("\n-- AIPlayer Move Selection & Tactical Generator --")
	var rules := GameRules.new()
	var ai := AIPlayer.new()

	# Opening position has zero captures or promotions
	var initial_tactical := rules.get_all_tactical_moves(PieceData.Team.CYAN)
	_assert(
		initial_tactical.is_empty(),
		"Opening position generates 0 tactical moves (avoids quiet move generation in quiescence)"
	)

	var easy_mv := ai.choose_move(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY)
	var med_mv := ai.choose_move(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	var t0 := Time.get_ticks_msec()
	var hard_mv := ai.choose_move(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	var hard_ms := Time.get_ticks_msec() - t0

	_assert(easy_mv != null, "AIPlayer (Easy) selects a valid opening move")
	_assert(med_mv != null, "AIPlayer (Medium) selects a valid opening move")
	_assert(hard_mv != null, "AIPlayer (Hard, depth 3 + quiescence) selects a valid opening move in %d ms" % hard_ms)

	# Verify get_all_tactical_moves matches filtered get_all_legal_moves on a tactical board
	var tac_rules := GameRules.new()
	tac_rules.pieces.clear()
	tac_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	tac_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	tac_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10")) # Promotion on f11
	tac_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("f6"))
	tac_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("g8")) # Capturable by Knight

	var all_legal := tac_rules.get_all_legal_moves(PieceData.Team.CYAN)
	var expected_tactical := 0
	for mv in all_legal:
		if mv.is_capture or mv.is_promotion:
			expected_tactical += 1
	var actual_tactical := tac_rules.get_all_tactical_moves(PieceData.Team.CYAN)
	_assert(
		actual_tactical.size() == expected_tactical and expected_tactical >= 2,
		"get_all_tactical_moves() matches exact legal capture/promotion count (%d == %d)" % [
			actual_tactical.size(),
			expected_tactical,
		]
	)


func _test_ai_player_async_move_selection() -> void:
	print("\n-- AIPlayer Async Time-Sliced Coroutine (choose_move_async) --")
	var rules := GameRules.new()
	var opening_moves := rules.get_all_legal_moves(PieceData.Team.CYAN)
	var ai := AIPlayer.new()

	var async_easy := await ai.choose_move_async(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY, self)
	var async_med := await ai.choose_move_async(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM, self)

	var frame_counter := [0]
	var on_frame := func() -> void:
		frame_counter[0] += 1
	process_frame.connect(on_frame)
	var t0_usec := Time.get_ticks_usec()
	var async_hard := await ai.choose_move_async(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	var hard_usec := Time.get_ticks_usec() - t0_usec
	process_frame.disconnect(on_frame)
	var frames_yielded: int = frame_counter[0]

	_assert(
		_is_move_in_list(async_easy, opening_moves),
		"choose_move_async (Easy, active SceneTree) returns a valid legal opening move"
	)
	_assert(
		_is_move_in_list(async_med, opening_moves),
		"choose_move_async (Medium, active SceneTree) returns a valid legal opening move"
	)
	_assert(
		_is_move_in_list(async_hard, opening_moves),
		"choose_move_async (Hard, active SceneTree) returns a valid legal opening move (%d frame yields in %d ms)" % [
			frames_yielded,
			hard_usec / 1000,
		]
	)
	_assert(
		hard_usec < AIPlayer.ASYNC_FRAME_BUDGET_USEC or frames_yielded > 0,
		"choose_move_async yields to SceneTree.process_frame when search exceeds ASYNC_FRAME_BUDGET_USEC (%d yields)" % frames_yielded
	)
	_assert(
		rules.pieces.size() == 36
		and rules.current_turn == PieceData.Team.CYAN
		and _verify_spatial_index_invariants(rules),
		"choose_move_async searches on an isolated clone without mutating source GameRules"
	)

	# Verify null-SceneTree synchronous fallback across Easy, Medium, and Hard on a compact tactical position
	var compact := GameRules.new()
	compact.pieces.clear()
	compact._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	compact._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	compact._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f4"))
	compact._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("f8"))
	var compact_legal := compact.get_all_legal_moves(PieceData.Team.CYAN)

	var null_easy := await ai.choose_move_async(compact, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY, null)
	var null_med := await ai.choose_move_async(compact, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM, null)
	var null_hard := await ai.choose_move_async(compact, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, null)
	_assert(
		_is_move_in_list(null_easy, compact_legal)
		and _is_move_in_list(null_med, compact_legal)
		and _is_move_in_list(null_hard, compact_legal),
		"choose_move_async with null SceneTree falls back cleanly across Easy, Medium, and Hard"
	)

	# Verify single-legal-move fast path and game-over empty-move null return
	var forced := GameRules.new()
	forced.pieces.clear()
	forced._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	forced._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	# Magenta Rook on e6 (-1, 0) covers e9, e10; Magenta Rook on g6 (1, -1) covers g9, g10; leaving only f10 (0, -4)
	forced._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	forced._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("g6"))
	var forced_moves := forced.get_all_legal_moves(PieceData.Team.CYAN)
	var forced_choice := await ai.choose_move_async(forced, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		forced_moves.size() == 1
		and forced_choice != null
		and forced_choice.to == GameRules.algebraic_to_axial("f10"),
		"choose_move_async immediately returns the sole legal escape move when only 1 move exists"
	)

	forced.is_game_over = true
	var over_choice := await ai.choose_move_async(forced, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(over_choice == null, "choose_move_async returns null when no legal moves exist")


func _test_software_renderer_detection() -> void:
	print("\n-- Software Renderer Detection & Fallback --")
	_assert(
		MainScript.is_software_renderer("ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)))"),
		"Detects Google SwiftShader software WebGL adapter"
	)
	_assert(
		MainScript.is_software_renderer("llvmpipe (LLVM 15.0.7, 256 bits)"),
		"Detects Mesa llvmpipe software adapter"
	)
	_assert(
		MainScript.is_software_renderer("Microsoft Basic Render Driver"),
		"Detects Microsoft Basic Render Driver fallback"
	)
	_assert(
		not MainScript.is_software_renderer("ANGLE (NVIDIA, NVIDIA GeForce RTX 4070 Direct3D11)"),
		"Does not false-positive on hardware GPU adapter"
	)


func _test_vector_board_caching_and_idle_redraw() -> void:
	print("\n-- VectorBoard Move Caching, SubViewport Board/Piece Atlas & Idle Animation State --")
	var board := VectorBoard.new()
	board._setup_bg_layer()
	board._setup_piece_atlas()
	board._rebuild_board_cache()

	_assert(
		board._cell_meta.size() == 91,
		"VectorBoard precomputes static metadata (color, pawn start, algebraic coord) for all 91 hex cells"
	)
	_assert(
		board._bg_viewport != null and board._bg_viewport.transparent_bg and board._bg_layer != null,
		"VectorBoard initializes BoardBackgroundViewport (SubViewport UPDATE_ONCE) with BoardBackgroundLayer"
	)
	_assert(
		board._piece_atlas_viewport != null
		and board._piece_atlas_viewport.size == Vector2i(768, 512)
		and VectorBoard._piece_atlas_texture != null,
		"VectorBoard initializes 768x512 PieceAtlasViewport and shared _piece_atlas_texture"
	)
	_assert(
		board._cached_turn_moves.size() == 18,
		"VectorBoard caches legal moves for all 18 active-turn pieces on startup"
	)
	_assert(
		board._cached_check_kings.is_empty(),
		"VectorBoard check cache is empty at initial position"
	)
	_assert(
		not board.is_animating(),
		"VectorBoard is not animating when idle at initial position"
	)

	var pulse_before := board._pulse_time
	board._process(0.016)
	_assert(
		board._pulse_time == pulse_before,
		"VectorBoard._process does not advance pulse or redraw when board is idle"
	)

	# Select a piece via cell interaction and verify cached moves are used and pulse activates
	var cyan_pawn_cell := GameRules.algebraic_to_axial("f5")
	board._handle_cell_interaction(cyan_pawn_cell)
	var initial_f5_move_count := board.legal_moves.size()
	_assert(
		board.selected_piece != null and initial_f5_move_count == 1,
		"Selecting f5 pawn populates 1 legal_move from cache"
	)
	_assert(
		board.is_animating(),
		"VectorBoard is_animating() is true while a piece is selected"
	)
	board._process(0.016)
	_assert(
		board._pulse_time > pulse_before,
		"VectorBoard._process advances pulse and redraws while a piece is selected"
	)

	# Regression test for Issues #18 & #22:
	# Deselecting a piece by clicking an empty hex or rotating across pieces must NOT wipe _cached_turn_moves.
	var non_target_empty_cell := GameRules.algebraic_to_axial("a4")
	board._handle_cell_interaction(non_target_empty_cell)
	_assert(
		board.selected_piece == null and board.legal_moves.is_empty(),
		"Clicking an empty non-target hex clears the active selection"
	)
	board._handle_cell_interaction(cyan_pawn_cell)
	_assert(
		board.selected_piece != null and board.legal_moves.size() == initial_f5_move_count,
		"Re-selecting f5 pawn after backing out to the board preserves all %d legal moves (Issues #18/#22 regression)" % initial_f5_move_count
	)

	# Rotate selection across multiple pieces, back out to out-of-bounds hex, and re-verify
	var cyan_knight_cell := GameRules.algebraic_to_axial("d1")
	board._handle_cell_interaction(cyan_knight_cell)
	var knight_move_count := board.legal_moves.size()
	board._handle_cell_interaction(GameRules.INVALID_HEX)
	board._handle_cell_interaction(cyan_knight_cell)
	_assert(
		board.selected_piece != null and board.legal_moves.size() == knight_move_count and knight_move_count > 0,
		"Re-selecting d1 Knight after out-of-bounds deselection preserves all %d legal moves" % knight_move_count
	)
	board._handle_cell_interaction(cyan_pawn_cell)

	# Execute a move and verify cache updates to Magenta's turn and piece interpolation animates
	var first_mv: GameRules.VectorMove = board.legal_moves[0]
	board._commit_move(first_mv)
	_assert(
		board.rules.current_turn == PieceData.Team.MAGENTA,
		"Move commit advances turn to Magenta"
	)
	var all_magenta_cached := board._cached_turn_moves.size() == 18
	for p in board.rules.pieces:
		if p.team == PieceData.Team.MAGENTA and not board._cached_turn_moves.has(p.id):
			all_magenta_cached = false
	_assert(
		all_magenta_cached,
		"Move commit rebuilds cache for all 18 Magenta pieces"
	)
	_assert(
		board.is_animating(),
		"VectorBoard is_animating() is true while moved piece interpolates to target hex"
	)
	board.free()


func _test_mobile_scaling_and_responsive_layout() -> void:
	print("\n-- Mobile Scaling & Responsive Layout --")
	# 1. Environment detection
	_assert(
		not MainScript.is_mobile_environment(false, false, false, Vector2i(1280, 800)),
		"Desktop 1280x800 is not flagged as mobile"
	)
	_assert(
		not MainScript.is_mobile_environment(false, false, true, Vector2i(1280, 800)),
		"Desktop touchscreen laptop at 1280x800 is not flagged as mobile"
	)
	_assert(
		MainScript.is_mobile_environment(true, false, true, Vector2i(1080, 2400)),
		"Native Android/iOS portrait 1080x2400 is flagged as mobile"
	)
	_assert(
		MainScript.is_mobile_environment(true, false, true, Vector2i(2400, 1080)),
		"Native Android/iOS landscape 2400x1080 is flagged as mobile"
	)
	_assert(
		MainScript.is_mobile_environment(false, true, true, Vector2i(390, 844)),
		"Mobile Web touch portrait 390x844 is flagged as mobile"
	)
	_assert(
		MainScript.is_mobile_environment(false, true, true, Vector2i(844, 390)),
		"Mobile Web touch landscape 844x390 is flagged as mobile"
	)

	# 2. Content scale size calculation
	_assert(
		MainScript.compute_target_content_scale_size(Vector2i(1920, 1080), false) == Vector2i(1280, 800),
		"Desktop landscape keeps 1280x800 content_scale_size"
	)
	_assert(
		MainScript.compute_target_content_scale_size(Vector2i(800, 1280), false) == Vector2i(800, 1280),
		"Desktop portrait swaps to 800x1280 content_scale_size"
	)
	_assert(
		MainScript.compute_target_content_scale_size(Vector2i(1080, 2400), true) == Vector2i(480, 800),
		"Mobile portrait uses 480x800 content_scale_size (~2.67x larger UI than 1280-wide portrait)"
	)
	_assert(
		MainScript.compute_target_content_scale_size(Vector2i(2400, 1080), true) == Vector2i(800, 480),
		"Mobile landscape uses 800x480 content_scale_size (~1.67x larger UI with matching physical scale)"
	)

	# 3. Scene layout adaptation across Desktop, Mobile Portrait, and Mobile Landscape
	var main_ui: Control = MainScene.instantiate()
	root.add_child(main_ui)
	main_ui._resolve_nodes()
	main_ui._setup_confirm_slider_theme()

	# Desktop Landscape (1280x800)
	main_ui._apply_responsive_layout(Vector2(1280, 800), false)
	_assert(
		not main_ui.split_container.vertical
		and main_ui.side_panel.custom_minimum_size == Vector2(340, 0)
		and main_ui.title_label.visible
		and main_ui.controls_grid.columns == 2
		and main_ui.toggle_panel_button.size == Vector2(44, 44)
		and main_ui.confirm_slider.custom_minimum_size.y == 48.0,
		"Desktop 1280x800 layout preserves horizontal split, 340px side panel, title header, 2-col controls, 44x44 toggle button, and 48px slide-to-unlock track"
	)

	# Mobile Portrait (480x1040 logical)
	main_ui._apply_responsive_layout(Vector2(480, 1040), true)
	_assert(
		main_ui.split_container.vertical
		and main_ui.side_panel.custom_minimum_size == Vector2(0, 176)
		and not main_ui.title_label.visible
		and not main_ui.history_header.visible
		and main_ui.controls_grid.columns == 4
		and main_ui.toggle_panel_button.size == Vector2(54, 54)
		and main_ui.confirm_slider.custom_minimum_size.y == 48.0,
		"Mobile Portrait 480x1040 layout stacks vertically, compacts dock to 176px, hides decorative headers, uses 4-col controls, and enlarges toggle button to 54x54"
	)

	# Mobile Landscape (1040x480 logical)
	main_ui._apply_responsive_layout(Vector2(1040, 480), true)
	_assert(
		not main_ui.split_container.vertical
		and main_ui.side_panel.custom_minimum_size == Vector2(248, 0)
		and not main_ui.title_label.visible
		and main_ui.controls_grid.columns == 4
		and main_ui.promote_grid.columns == 2
		and not main_ui.modal_description.visible
		and main_ui.toggle_panel_button.size == Vector2(54, 54)
		and main_ui.confirm_slider.custom_minimum_size.y == 44.0,
		"Mobile Landscape 1040x480 layout narrows side panel to 248px, uses 4-col controls, 2-col promotion grid, 54x54 toggle button, and compacts NewGameModal height"
	)

	# 4. Slide-to-Unlock custom theme & idle animation behavior
	main_ui.new_game_modal.visible = true
	var anim_before: float = main_ui._slider_anim_time
	main_ui._process(0.05)
	_assert(
		main_ui._slider_anim_time > anim_before,
		"ConfirmSlider animates marching chevrons and thumb halo while NewGameModal is visible"
	)
	main_ui.new_game_modal.visible = false
	var anim_paused: float = main_ui._slider_anim_time
	main_ui._process(0.05)
	_assert(
		main_ui._slider_anim_time == anim_paused,
		"ConfirmSlider animation pauses with zero overhead when NewGameModal is closed"
	)

	main_ui.free()
