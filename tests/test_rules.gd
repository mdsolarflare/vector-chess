extends SceneTree
## Headless unit test runner for Vector Chess (Glinski's Hexagonal Chess).
## Run with: godot --headless -s res://tests/test_rules.gd

const MainScript = preload("res://scripts/main.gd")
const MainScene = preload("res://scenes/main.tscn")

const VALID_PROMOTION_TYPES: Array[PieceData.Type] = [
	PieceData.Type.QUEEN,
	PieceData.Type.ROOK,
	PieceData.Type.BISHOP,
	PieceData.Type.KNIGHT,
]

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
	await _test_vector_board_atlas_and_aa_isolation()
	_test_hover_exit_and_touch_release_clearing()
	await _test_vector_arrow_label_centering_and_draw()
	_test_hex_tile_color_variation()
	_test_mobile_scaling_and_responsive_layout()
	await _test_pending_promotion_cancel_and_undo()
	await _test_ui_layout_non_overlap_and_resource_isolation()

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
	if candidate.is_promotion and not VALID_PROMOTION_TYPES.has(candidate.promotion_type):
		return false
	for mv in moves:
		if (
			mv.piece_id == candidate.piece_id
			and mv.from == candidate.from
			and mv.to == candidate.to
			and mv.is_capture == candidate.is_capture
			and mv.is_en_passant == candidate.is_en_passant
			and mv.captured_piece_id == candidate.captured_piece_id
			and mv.captured_pos == candidate.captured_pos
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
			roundi(float(hard_usec) * 0.001),
		]
	)
	_assert(
		hard_usec < 2 * AIPlayer.ASYNC_FRAME_BUDGET_USEC or frames_yielded > 0,
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

	# Verify 1-pawn capture-promotion expands into 2 [=Q, =N] candidates (bypassing legal_moves.size() == 1 fast path):
	# Cyan King on f1 (0, 5) is immobilized by Magenta Rooks on e6/g6 and Bishop on d1, leaving e10xf11 as Cyan's sole raw move.
	# Magenta King on a6 (-5, 0) is self-blocked except along the f11->a6 (-1, +1) ray, so e10xf11=Q# is mate in 1 (zero jitter).
	var single_promo := GameRules.new()
	single_promo.pieces.clear()
	single_promo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	single_promo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	single_promo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("g6"))
	single_promo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("d1"))
	single_promo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, Vector2i(-5, 0))
	for blk in [Vector2i(-4, 0), Vector2i(-5, 1), Vector2i(-3, -1), Vector2i(-4, 1)]:
		single_promo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, blk)
	single_promo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e10"))
	var promo_victim := single_promo._spawn_piece(
		PieceData.Team.MAGENTA,
		PieceData.Type.KNIGHT,
		GameRules.algebraic_to_axial("f11")
	)
	var raw_promo_moves := single_promo.get_all_legal_moves(PieceData.Team.CYAN)
	var promo_choice := await ai.choose_move_async(single_promo, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		raw_promo_moves.size() == 1
		and _is_move_in_list(promo_choice, raw_promo_moves)
		and promo_choice.is_capture
		and promo_choice.captured_piece_id == promo_victim.id
		and promo_choice.promotion_type == PieceData.Type.QUEEN,
		"choose_move_async expands sole capture-promotion e10xf11 into [=Q, =N] and selects =Q"
	)

	# Verify _is_move_in_list rejects invalid promotion types (PAWN/KING) and mismatched capture metadata
	var bad_promo_king := promo_choice.duplicate_move()
	bad_promo_king.promotion_type = PieceData.Type.KING
	var bad_promo_pawn := promo_choice.duplicate_move()
	bad_promo_pawn.promotion_type = PieceData.Type.PAWN
	var bad_capture_flag := promo_choice.duplicate_move()
	bad_capture_flag.is_capture = false
	_assert(
		not _is_move_in_list(bad_promo_king, raw_promo_moves)
		and not _is_move_in_list(bad_promo_pawn, raw_promo_moves)
		and not _is_move_in_list(bad_capture_flag, raw_promo_moves),
		"_is_move_in_list rejects invalid promotion types (KING/PAWN) and mismatched capture metadata"
	)

	# Verify async Knight underpromotion (=N) selection via smothered checkmate in 1:
	# Magenta King at h8 (2, -4) is surrounded on all 11 in-bounds adjacent hexes by friendly Magenta pawns;
	# f10->f11=N# delivers unblockable Knight checkmate via (+2, +1), whereas f10->f11=Q does not check h8.
	var smothered_rules := GameRules.new()
	smothered_rules.pieces.clear()
	smothered_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	smothered_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	var m_king_pos := GameRules.algebraic_to_axial("h8")
	smothered_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, m_king_pos)
	for dir_vec in GameRules.ORTHO_DIRS + GameRules.DIAG_DIRS:
		var adj: Vector2i = m_king_pos + dir_vec
		if GameRules.is_inside_board(adj):
			smothered_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, adj)

	var smothered_legal := smothered_rules.get_all_legal_moves(PieceData.Team.CYAN)
	var smothered_easy := await ai.choose_move_async(smothered_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY, self)
	var smothered_hard := await ai.choose_move_async(smothered_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		_is_move_in_list(smothered_easy, smothered_legal)
		and smothered_easy.promotion_type == PieceData.Type.KNIGHT
		and _is_move_in_list(smothered_hard, smothered_legal)
		and smothered_hard.is_promotion
		and smothered_hard.to == GameRules.algebraic_to_axial("f11")
		and smothered_hard.promotion_type == PieceData.Type.KNIGHT,
		"choose_move_async selects Knight underpromotion f10->f11=N# for smothered mate in 1"
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
		and board._piece_atlas_texture != null,
		"VectorBoard initializes per-instance 768x512 PieceAtlasViewport and _piece_atlas_texture"
	)
	_assert(
		board.get_piece_atlas_texture() == null,
		"Off-tree VectorBoard.get_piece_atlas_texture() returns null until SubViewport enters SceneTree"
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


func _test_vector_board_atlas_and_aa_isolation() -> void:
	print("\n-- VectorBoard Per-Instance Atlas Lifecycle & Line AA Isolation (Issue #37) --")
	# 1. Freeing an off-tree VectorBoard after _setup_piece_atlas() leaves no stale global atlas
	#    and draw_faceted_piece_icon() safely falls back to ArrayMesh rendering.
	var off_tree := VectorBoard.new()
	off_tree._setup_piece_atlas()
	var off_tree_vp := off_tree._piece_atlas_viewport
	off_tree.free()
	_assert(
		not is_instance_valid(off_tree_vp),
		"Freeing off-tree VectorBoard frees its owned PieceAtlasViewport cleanly"
	)

	var tiny_img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var tiny_tex := ImageTexture.create_from_image(tiny_img)
	_assert(
		not VectorBoard._is_valid_atlas_texture(null) and not VectorBoard._is_valid_atlas_texture(tiny_tex),
		"_is_valid_atlas_texture rejects null and undersized textures"
	)

	# 2. Multi-instance isolation: two VectorBoard instances own independent atlases and AA flags
	var board_a := VectorBoard.new()
	var board_b := VectorBoard.new()
	root.add_child(board_a)
	root.add_child(board_b)

	var tex_a := board_a.get_piece_atlas_texture()
	var tex_b := board_b.get_piece_atlas_texture()
	_assert(
		tex_a != null
		and tex_b != null
		and tex_a != tex_b
		and VectorBoard._is_valid_atlas_texture(tex_a),
		"Two in-tree VectorBoard instances own distinct valid atlas textures"
	)

	board_a.set_line_antialiasing(false)
	_assert(
		not board_a.line_aa_enabled and board_b.line_aa_enabled,
		"Disabling line_aa_enabled on one VectorBoard does not mutate another instance"
	)

	# Freeing board_b must not clobber board_a's atlas texture; detached tex_b must be rejected
	board_b.free()
	_assert(
		board_a.get_piece_atlas_texture() == tex_a and is_instance_valid(board_a._piece_atlas_viewport),
		"Freeing a second VectorBoard leaves the first VectorBoard's atlas texture intact"
	)
	_assert(
		not VectorBoard._is_valid_atlas_texture(tex_b),
		"Detached ViewportTexture from a freed VectorBoard is rejected by _is_valid_atlas_texture()"
	)

	# Verify draw_faceted_piece_icon safely falls back to ArrayMesh for both null and detached ViewportTexture
	var fallback_drawn := [false]
	var canvas := Control.new()
	canvas.size = Vector2(64, 64)
	canvas.draw.connect(func() -> void:
		VectorBoard.draw_faceted_piece_icon(
			canvas,
			PieceData.Type.QUEEN,
			PieceData.Team.CYAN,
			Vector2(20, 32),
			14.0,
			false
		)
		VectorBoard.draw_faceted_piece_icon(
			canvas,
			PieceData.Type.ROOK,
			PieceData.Team.MAGENTA,
			Vector2(44, 32),
			14.0,
			true,
			tex_b
		)
		fallback_drawn[0] = true
	)
	root.add_child(canvas)
	canvas.queue_redraw()
	await process_frame
	await process_frame
	_assert(
		fallback_drawn[0],
		"draw_faceted_piece_icon() safely falls back to ArrayMesh rendering for null and detached ViewportTextures"
	)
	canvas.free()

	# Removing board_a from tree hides its atlas texture; re-adding restores atlas AND re-arms background SubViewport
	board_a._bg_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.remove_child(board_a)
	_assert(
		board_a.get_piece_atlas_texture() == null,
		"Removing VectorBoard from SceneTree returns null from get_piece_atlas_texture()"
	)
	root.add_child(board_a)
	_assert(
		board_a.get_piece_atlas_texture() != null
		and board_a._bg_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE
		and board_a._piece_atlas_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"Re-adding VectorBoard to SceneTree restores atlas texture and re-arms both SubViewports (UPDATE_ONCE)"
	)

	# Verify Main._apply_software_renderer_fallback() only disables AA on its own board instance
	var main_ui: Control = MainScene.instantiate()
	root.add_child(main_ui)
	board_a.set_line_antialiasing(true)
	main_ui._apply_software_renderer_fallback("SwiftShader")
	_assert(
		not main_ui.vector_board.line_aa_enabled
		and not main_ui._is_line_aa_enabled()
		and board_a.line_aa_enabled,
		"Main._apply_software_renderer_fallback() disables line AA on its VectorBoard without affecting other instances"
	)
	main_ui.free()
	board_a.free()


func _test_hover_exit_and_touch_release_clearing() -> void:
	print("\n-- Hover Clear on mouse_exited, Touch Release & State Transitions (Issue #42) --")
	var board := VectorBoard.new()
	board.size = Vector2(800, 600)
	root.add_child(board)
	board._compute_board_metrics()

	var f5 := GameRules.algebraic_to_axial("f5")
	var f6 := GameRules.algebraic_to_axial("f6")
	board._handle_cell_interaction(f5)
	_assert(
		board.selected_piece != null and board.legal_moves.size() == 1 and board.legal_moves[0].to == f6,
		"Setup: f5 pawn selected with legal target f6"
	)

	# Desktop mouse motion over f6 sets hovered_cell and hovered_move
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = board._axial_to_screen(Vector2(f6))
	board._gui_input(motion)
	_assert(
		board.hovered_cell == f6 and board.hovered_move != null and board.hovered_move.to == f6,
		"Mouse motion over f6 sets hovered_cell and hovered_move"
	)

	# mouse_exited clears hovered_cell, clears hovered_move, and emits selection_changed
	var signal_events: Array = []
	var on_sel := func(piece: PieceData, mv: GameRules.VectorMove) -> void:
		signal_events.append({"piece": piece, "move": mv})
	board.selection_changed.connect(on_sel)
	board.mouse_exited.emit()
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX
		and board.hovered_move == null
		and signal_events.size() == 1
		and signal_events[0]["piece"] == board.selected_piece
		and signal_events[0]["move"] == null,
		"mouse_exited resets hovered_cell to INVALID_HEX, clears hovered_move, and emits selection_changed"
	)

	# Calling _on_mouse_exited again when already cleared is a no-op
	board.mouse_exited.emit()
	_assert(
		signal_events.size() == 1,
		"Repeated mouse_exited when already cleared does not emit redundant selection_changed"
	)

	# Desktop mouse-emulated touch release (DEVICE_ID_EMULATION) must NOT wipe real desktop hover
	board._gui_input(motion)
	var emu_touch_up := InputEventScreenTouch.new()
	emu_touch_up.device = InputEvent.DEVICE_ID_EMULATION
	emu_touch_up.pressed = false
	board._gui_input(emu_touch_up)
	_assert(
		board.hovered_cell == f6 and board.hovered_move != null,
		"Mouse-emulated InputEventScreenTouch release preserves desktop mouse hover"
	)

	# Real touchscreen release (device != DEVICE_ID_EMULATION) clears hover
	var real_touch_up := InputEventScreenTouch.new()
	real_touch_up.device = 0
	real_touch_up.pressed = false
	board._gui_input(real_touch_up)
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX and board.hovered_move == null,
		"Real InputEventScreenTouch release clears hovered_cell and hovered_move"
	)

	# Hybrid touchscreen laptop: stale desktop hover on f6, then touch-emulated tap on f5
	# must clear hover BEFORE selecting f5 so only ONE clean selection_changed(f5_pawn, null) fires.
	board._clear_selection()
	board._gui_input(motion)
	signal_events.clear()
	var emu_tap_down := InputEventMouseButton.new()
	emu_tap_down.device = InputEvent.DEVICE_ID_EMULATION
	emu_tap_down.button_index = MOUSE_BUTTON_LEFT
	emu_tap_down.pressed = true
	emu_tap_down.position = board._axial_to_screen(Vector2(f5))
	board._gui_input(emu_tap_down)
	var emu_tap_up := InputEventMouseButton.new()
	emu_tap_up.device = InputEvent.DEVICE_ID_EMULATION
	emu_tap_up.button_index = MOUSE_BUTTON_LEFT
	emu_tap_up.pressed = false
	emu_tap_up.position = board._axial_to_screen(Vector2(f5))
	board._gui_input(emu_tap_up)
	_assert(
		board.selected_piece != null
		and board.hovered_cell == GameRules.INVALID_HEX
		and board.hovered_move == null
		and signal_events.size() == 1
		and signal_events[0]["piece"] == board.selected_piece
		and signal_events[0]["move"] == null,
		"Touch-emulated tap over stale desktop hover emits single clean selection_changed(piece, null)"
	)

	# Touch-emulated mouse motion & touch release clear hover even when input_locked == true
	board._gui_input(motion)
	board.input_locked = true
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX and board.hovered_move == null,
		"Setting input_locked = true clears stale hover highlight immediately"
	)
	board.hovered_cell = f6
	var emu_motion_locked := InputEventMouseMotion.new()
	emu_motion_locked.device = InputEvent.DEVICE_ID_EMULATION
	emu_motion_locked.position = board._axial_to_screen(Vector2(f6))
	board._gui_input(emu_motion_locked)
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX,
		"Touch-emulated motion clears stale hover even while input_locked is true"
	)
	board.input_locked = false

	# State transitions: board_flipped, undo_move, start_new_game, and _exit_tree clear hovered_cell
	board._gui_input(motion)
	board.board_flipped = true
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX and board.hovered_move == null,
		"Flipping board clears stale hovered_cell and hovered_move"
	)
	board.board_flipped = false

	board._handle_cell_interaction(f5)
	board._commit_move(board.legal_moves[0])
	board.hovered_cell = f6
	board.undo_move()
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX,
		"undo_move() resets hovered_cell to INVALID_HEX"
	)
	board.hovered_cell = f6
	board.start_new_game()
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX,
		"start_new_game() resets hovered_cell to INVALID_HEX"
	)

	# Moving cursor into out-of-board padding normalizes hovered_cell to INVALID_HEX
	board._handle_cell_interaction(f5)
	board._gui_input(motion)
	var oob_motion := InputEventMouseMotion.new()
	oob_motion.device = 0
	oob_motion.position = Vector2(2.0, 2.0)
	board._gui_input(oob_motion)
	_assert(
		board.hovered_cell == GameRules.INVALID_HEX and board.hovered_move == null,
		"Moving cursor off the hex grid into empty board padding resets hovered_cell to INVALID_HEX"
	)

	# Main HUD integration: mouse_exited clears "Target:" hovered-move telemetry in SidePanel
	var main_ui: Control = MainScene.instantiate()
	root.add_child(main_ui)
	main_ui.vector_board.size = Vector2(800, 600)
	main_ui.vector_board._compute_board_metrics()
	main_ui.vector_board._handle_cell_interaction(f5)
	var main_motion := InputEventMouseMotion.new()
	main_motion.device = 0
	main_motion.position = main_ui.vector_board._axial_to_screen(Vector2(f6))
	main_ui.vector_board._gui_input(main_motion)
	var had_target: bool = main_ui.telemetry_label.text.contains("Target:")
	main_ui.vector_board.mouse_exited.emit()
	var cleared_target: bool = not main_ui.telemetry_label.text.contains("Target:")
	_assert(
		had_target and cleared_target,
		"Main HUD telemetry clears hovered 'Target:' readout when cursor exits VectorBoard"
	)
	main_ui.free()
	board.free()


func _test_vector_arrow_label_centering_and_draw() -> void:
	print("\n-- Vector Arrow Label Centering & Animation-Safe Delta (Issue #43) --")
	_assert(
		VectorBoard.format_vector_delta_label(Vector2i(1, -2)) == "d(+1,-2)"
		and VectorBoard.format_vector_delta_label(Vector2i(0, -1)) == "d(+0,-1)",
		"format_vector_delta_label formats axial move deltas directly with explicit signs"
	)

	var font := ThemeDB.fallback_font
	_assert(font != null, "ThemeDB.fallback_font is available for label centering calculations")
	if font != null:
		var label := VectorBoard.format_vector_delta_label(Vector2i(1, -2))
		var anchor := Vector2(200.0, 150.0)
		var expected_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var expected_y := anchor.y + (font.get_ascent(11) - font.get_descent(11)) * 0.5
		var centered_pos := VectorBoard.compute_centered_label_pos(anchor, font, label, 11)
		_assert(
			expected_w > 0.0
			and is_equal_approx(centered_pos.x, anchor.x - expected_w * 0.5)
			and centered_pos.x < anchor.x
			and is_equal_approx(centered_pos.y, expected_y)
			and centered_pos.y > anchor.y,
			"compute_centered_label_pos centers text horizontally (-%.1fpx) and vertically by baseline offset" % (expected_w * 0.5)
		)

	# Verify _draw() renders hovered vector arrow cleanly (normal and flipped) even while
	# selected_piece.visual_pos is shifted >1 full hex away from grid_pos (where _screen_to_axial would disagree).
	var board := VectorBoard.new()
	board.size = Vector2(800, 600)
	board.show_vectors = true
	root.add_child(board)
	board._compute_board_metrics()
	var f5 := GameRules.algebraic_to_axial("f5")
	var f6 := GameRules.algebraic_to_axial("f6")
	board._handle_cell_interaction(f5)
	board.selected_piece.visual_pos = Vector2(f5) + Vector2(1.4, -1.2)
	board.hovered_cell = f6
	board._update_hovered_move()
	var screen_roundtrip_delta := (
		board._screen_to_axial(board._axial_to_screen(Vector2(f6)))
		- board._screen_to_axial(board._axial_to_screen(board.selected_piece.visual_pos))
	)
	board.queue_redraw()
	await process_frame
	await process_frame
	_assert(
		board.hovered_move != null
		and screen_roundtrip_delta != board.hovered_move.delta
		and VectorBoard.format_vector_delta_label(board.hovered_move.delta) == "d(+0,-1)",
		"Hovered arrow label uses exact mv.delta d(+0,-1) rather than drifted visual_pos round-trip %s" % str(screen_roundtrip_delta)
	)

	board.board_flipped = true
	board._handle_cell_interaction(f5)
	board.hovered_cell = f6
	board._update_hovered_move()
	board.queue_redraw()
	await process_frame
	await process_frame
	_assert(
		board.hovered_move != null and VectorBoard.format_vector_delta_label(board.hovered_move.delta) == "d(+0,-1)",
		"Flipped board preserves exact mv.delta label rendering during _draw()"
	)
	board.free()


func _blend_over(fg: Color, bg: Color) -> Color:
	return Color(
		bg.r * (1.0 - fg.a) + fg.r * fg.a,
		bg.g * (1.0 - fg.a) + fg.g * fg.a,
		bg.b * (1.0 - fg.a) + fg.b * fg.a,
		1.0
	)


func _test_hex_tile_color_variation() -> void:
	print("\n-- Hex Tile 3-Color Palette Contrast (Issue #20) --")
	var l0 := VectorBoard.COLOR_HEX_0.get_luminance()
	var l1 := VectorBoard.COLOR_HEX_1.get_luminance()
	var l2 := VectorBoard.COLOR_HEX_2.get_luminance()
	_assert(
		l0 < l1 and l1 < l2,
		"Hex tile shades strictly increase from Dark (%.3f) < Mid (%.3f) < Light (%.3f)" % [l0, l1, l2]
	)
	_assert(
		(l1 - l0) >= 0.09 and (l2 - l1) >= 0.09,
		"Adjacent hex tile luminance steps are clearly separated (d01=%.3f, d12=%.3f >= 0.090)" % [l1 - l0, l2 - l1]
	)

	var l_grid_on_light := _blend_over(VectorBoard.COLOR_GRID_LINE, VectorBoard.COLOR_HEX_2).get_luminance()
	var l_coord_on_light := _blend_over(VectorBoard.COLOR_COORD_LABEL, VectorBoard.COLOR_HEX_2).get_luminance()
	var l_pawn_on_light := _blend_over(VectorBoard.COLOR_PAWN_START, VectorBoard.COLOR_HEX_2).get_luminance()
	var l_hover_on_light := _blend_over(VectorBoard.COLOR_HOVER_BORDER, VectorBoard.COLOR_HEX_2).get_luminance()
	_assert(
		l_grid_on_light > l2 + 0.10
		and l_coord_on_light > l2 + 0.30
		and l_pawn_on_light > l2 + 0.20
		and l_hover_on_light > l2 + 0.30,
		"Alpha-blended overlays remain clearly legible over lightest hex shade (grid=%.3f, pawn=%.3f, coord=%.3f, hover=%.3f vs hex2=%.3f)" % [
			l_grid_on_light,
			l_pawn_on_light,
			l_coord_on_light,
			l_hover_on_light,
			l2,
		]
	)


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
	# Adding main_ui to the initialized SceneTree.root triggers main.gd:_ready()
	var main_ui: Control = MainScene.instantiate()
	root.add_child(main_ui)
	_assert(
		main_ui.split_container != null
		and main_ui.confirm_slider != null
		and main_ui.confirm_slider.has_theme_icon_override("grabber")
		and main_ui.new_game_modal.visible,
		"MainScene._ready() resolves UI nodes, configures ConfirmSlider theme, and opens NewGameModal on startup"
	)

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

	# 4. Slide-to-Unlock custom theme & idle animation behavior (NewGameModal opened by _ready())
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


func _test_pending_promotion_cancel_and_undo() -> void:
	print("\n-- Pending Pawn Promotion Cancel & Undo Behavior (Issue #36) --")
	var main_ui: Control = MainScene.instantiate()
	root.add_child(main_ui)
	main_ui.new_game_modal.visible = false
	main_ui.is_single_player = true
	main_ui.human_team = PieceData.Team.CYAN

	var board: VectorBoard = main_ui.vector_board
	board.size = Vector2(800, 600)
	board._compute_board_metrics()

	# Setup a clean position with a Cyan pawn ready to promote (f10 -> f11) and 2 committed moves in history
	var rules := board.rules
	rules.pieces.clear()
	rules.move_history.clear()
	rules.current_turn = PieceData.Team.CYAN
	rules.is_game_over = false
	rules.last_move = null
	rules.status_text = "Cyan's Turn"
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var cyan_rook := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	var mag_rook := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("i1"))
	var promo_pawn := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	rules._rebuild_spatial_index()
	board._rebuild_board_cache()

	# Commit 1 full round (Cyan move + Magenta move) so move_history.size() == 2
	var c2 := GameRules.algebraic_to_axial("c2")
	for mv in rules.get_legal_moves_for_piece(cyan_rook):
		if mv.to == c2:
			rules.execute_move(mv)
			break
	var i2 := GameRules.algebraic_to_axial("i2")
	for mv in rules.get_legal_moves_for_piece(mag_rook):
		if mv.to == i2:
			rules.execute_move(mv)
			break
	board._rebuild_board_cache()
	main_ui._refresh_hud()

	var f10 := GameRules.algebraic_to_axial("f10")
	var f11 := GameRules.algebraic_to_axial("f11")
	_assert(
		rules.move_history.size() == 2 and rules.current_turn == PieceData.Team.CYAN,
		"Setup: 2 prior moves committed and Cyan pawn positioned on f10"
	)

	# 1. Pre-existing desktop hover clears on promotion trigger, hidden SidePanel auto-opens, and _draw() renders pending highlight
	main_ui.side_panel.visible = false
	board._handle_cell_interaction(f10)
	var hover_f11 := InputEventMouseMotion.new()
	hover_f11.device = 0
	hover_f11.position = board._axial_to_screen(Vector2(f11))
	board._gui_input(hover_f11)
	var had_hover_target: bool = main_ui.telemetry_label.text.contains("Target:")
	board._handle_cell_interaction(f11)
	board.queue_redraw()
	await process_frame
	await process_frame
	_assert(
		had_hover_target
		and board.pending_promotion_move != null
		and board.hovered_cell == GameRules.INVALID_HEX
		and board.hovered_move == null
		and not main_ui.telemetry_label.text.contains("Target:")
		and main_ui.side_panel.visible
		and main_ui.promotion_box.visible
		and main_ui.promote_cancel_button != null
		and main_ui.status_label.text == "Select Promotion Piece"
		and main_ui.undo_button.tooltip_text == "Cancel Promotion"
		and rules.move_history.size() == 2,
		"Clicking promotion square f11 clears desktop hover/Target telemetry, auto-opens SidePanel, and renders pending prompt without committing"
	)

	# Cancel via PromotionBox Cancel button
	main_ui.promote_cancel_button.pressed.emit()
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and board.selected_piece == null
		and board.hovered_cell == GameRules.INVALID_HEX
		and board.hovered_move == null
		and main_ui.status_label.text == "Cyan's Turn"
		and main_ui.undo_button.tooltip_text == "Undo Last Move"
		and rules.move_history.size() == 2
		and promo_pawn.grid_pos == f10
		and promo_pawn.type == PieceData.Type.PAWN,
		"Pressing PromotionBox Cancel button cleanly cancels pending promotion without popping move_history"
	)

	# 2. Cancel via Escape (ui_cancel) dispatched through SceneTree root.push_input, guarded when NewGameModal is visible
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.pressed = true
	main_ui.new_game_modal.visible = true
	root.push_input(esc_ev)
	_assert(
		board.pending_promotion_move != null and main_ui.promotion_box.visible,
		"Escape does not cancel pending promotion while NewGameModal is open"
	)
	main_ui.new_game_modal.visible = false
	root.push_input(esc_ev)
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and main_ui.status_label.text == "Cyan's Turn"
		and rules.move_history.size() == 2,
		"Escape (ui_cancel via root.push_input) cancels pending promotion and restores HUD state"
	)

	# 3. Cancel via clicking/tapping outside on the board (desktop left-click, right-click, and touch-emulated tap)
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	var click_c2 := InputEventMouseButton.new()
	click_c2.button_index = MOUSE_BUTTON_LEFT
	click_c2.pressed = true
	click_c2.position = board._axial_to_screen(Vector2(c2))
	board._gui_input(click_c2)
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and board.selected_piece == null
		and rules.move_history.size() == 2,
		"Left-clicking on the board while promotion is pending cancels promotion instead of locking board"
	)

	board._gui_input(click_c2)
	_assert(
		board.selected_piece == cyan_rook,
		"After canceling promotion, player can immediately select another friendly piece (Rook on c2)"
	)

	# Right-click also cancels pending promotion
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	var rclick := InputEventMouseButton.new()
	rclick.button_index = MOUSE_BUTTON_RIGHT
	rclick.pressed = true
	rclick.position = board._axial_to_screen(Vector2(c2))
	board._gui_input(rclick)
	_assert(
		board.pending_promotion_move == null and not main_ui.promotion_box.visible,
		"Right-clicking on the board cancels pending promotion"
	)

	# Touch-emulated tap (DEVICE_ID_EMULATION) cancels pending promotion cleanly
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	var touch_tap := InputEventMouseButton.new()
	touch_tap.device = InputEvent.DEVICE_ID_EMULATION
	touch_tap.button_index = MOUSE_BUTTON_LEFT
	touch_tap.pressed = true
	touch_tap.position = board._axial_to_screen(Vector2(c2))
	board._gui_input(touch_tap)
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and board.hovered_cell == GameRules.INVALID_HEX,
		"Touch-emulated tap on the board cancels pending promotion cleanly"
	)

	# Flipping board while promotion is pending keeps pending state intact until user confirms or cancels
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	main_ui._on_flip_pressed()
	_assert(
		board.board_flipped and board.pending_promotion_move != null and main_ui.promotion_box.visible,
		"Flipping board while promotion is pending preserves pending promotion state"
	)
	main_ui._on_flip_pressed()

	# 4. Undo while promotion is pending cancels promotion FIRST without popping prior committed turns (1P mode)
	main_ui._on_undo_pressed()
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and board.selected_piece == null
		and main_ui.status_label.text == "Cyan's Turn"
		and rules.move_history.size() == 2
		and cyan_rook.grid_pos == c2
		and mag_rook.grid_pos == i2,
		"Undo during pending promotion cancels promotion and keeps all 2 prior committed turns intact"
	)

	# 2P Pass & Play Undo: first Undo cancels promotion, second Undo pops ONLY 1 half-move (returning to Magenta)
	main_ui.is_single_player = false
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	main_ui._on_undo_pressed()
	_assert(
		board.pending_promotion_move == null and rules.move_history.size() == 2 and rules.current_turn == PieceData.Team.CYAN,
		"2P Undo during pending promotion cancels promotion without popping move_history"
	)
	main_ui._on_undo_pressed()
	_assert(
		rules.move_history.size() == 1 and rules.current_turn == PieceData.Team.MAGENTA,
		"2P subsequent Undo pops exactly 1 half-move and returns turn to Magenta"
	)

	# Re-commit Magenta move so we also test 1P subsequent Undo popping full 2-ply round
	var mag_rook_now := rules.get_piece_at(GameRules.algebraic_to_axial("i1"))
	for mv in rules.get_legal_moves_for_piece(mag_rook_now):
		if mv.to == i2:
			rules.execute_move(mv)
			break
	board._rebuild_board_cache()
	main_ui.is_single_player = true
	main_ui._refresh_hud()

	main_ui._on_undo_pressed()
	var restored_rook := rules.get_piece_at(GameRules.algebraic_to_axial("c1"))
	_assert(
		rules.move_history.is_empty()
		and rules.current_turn == PieceData.Team.CYAN
		and restored_rook != null
		and restored_rook.type == PieceData.Type.ROOK
		and main_ui.undo_button.disabled,
		"1P subsequent Undo after promotion cancellation reverts the previous committed 2-ply turn cleanly"
	)

	# 5. Undo button enabled during pending promotion even with empty move_history, and direct board.undo_move() emits promotion_canceled
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	_assert(
		not main_ui.undo_button.disabled and main_ui.undo_button.tooltip_text == "Cancel Promotion",
		"Undo button is enabled as 'Cancel Promotion' while promotion is pending even with empty move_history"
	)
	var canceled_count := [0]
	var on_cancel := func() -> void:
		canceled_count[0] += 1
	board.promotion_canceled.connect(on_cancel)
	var direct_undone := board.undo_move()
	board.promotion_canceled.disconnect(on_cancel)
	_assert(
		not direct_undone
		and canceled_count[0] == 1
		and board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and main_ui.undo_button.disabled,
		"Direct VectorBoard.undo_move() with empty move_history cancels pending promotion and emits promotion_canceled"
	)

	# 6. Canceling a promotion while Cyan King is in check restores 'Cyan is in CHECK!' status text
	# Place Magenta Rook at f11 (0, -5) and Cyan King at a6 (-5, 0) along the (-1, +1) orthogonal ray,
	# with Cyan Pawn on e10 (-1, -4) capturing f11 to resolve check via capture-promotion.
	rules.pieces.clear()
	rules.move_history.clear()
	rules.current_turn = PieceData.Team.CYAN
	rules.is_game_over = false
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, f11)
	var e10 := GameRules.algebraic_to_axial("e10")
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, e10)
	rules._rebuild_spatial_index()
	rules.status_text = "Cyan is in CHECK!"
	board._rebuild_board_cache()
	main_ui._refresh_hud()
	board._handle_cell_interaction(e10)
	board._handle_cell_interaction(f11)
	_assert(
		board.pending_promotion_move != null and main_ui.status_label.text == "Select Promotion Piece",
		"Capture-promotion e10xf11 while in check enters pending promotion prompt"
	)
	main_ui._on_undo_pressed()
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and main_ui.status_label.text == "Cyan is in CHECK!",
		"Canceling promotion while in check restores 'Cyan is in CHECK!' status label"
	)

	# 7. Confirming NewGameModal while promotion is pending resets board and hides PromotionBox cleanly
	board._handle_cell_interaction(e10)
	board._handle_cell_interaction(f11)
	main_ui._on_new_game_pressed()
	main_ui.confirm_slider.value = 100.0
	main_ui._on_mode_2p_pressed()
	main_ui._on_confirm_new_game_pressed()
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and not main_ui.new_game_modal.visible
		and rules.pieces.size() == 36,
		"Confirming NewGameModal while promotion is pending clears pending promotion and resets board"
	)

	# 8. Completing promotion after previous cancellations commits cleanly
	rules.pieces.clear()
	rules.move_history.clear()
	rules.current_turn = PieceData.Team.CYAN
	rules.is_game_over = false
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, f10)
	rules._rebuild_spatial_index()
	board._rebuild_board_cache()
	board._handle_cell_interaction(f10)
	board._handle_cell_interaction(f11)
	main_ui._on_promote_queen_pressed()
	var promoted_queen := rules.get_piece_at(f11)
	_assert(
		board.pending_promotion_move == null
		and not main_ui.promotion_box.visible
		and promoted_queen != null
		and promoted_queen.type == PieceData.Type.QUEEN
		and rules.move_history.size() == 1,
		"Completing promotion after prior cancellations promotes pawn to Queen and commits move"
	)

	main_ui.free()


func _test_ui_layout_non_overlap_and_resource_isolation() -> void:
	print("\n-- UI Layout Non-Overlap, Dead UI Cleanup & StyleBoxFlat Isolation (Issues #15 & #44) --")
	var main_a: Control = MainScene.instantiate()
	var main_b: Control = MainScene.instantiate()
	root.add_child(main_a)
	root.add_child(main_b)

	# 1. Dead SliderHintLabel node removed (Issue #44)
	_assert(
		main_a.get_node_or_null("%SliderHintLabel") == null
		and main_a.modal_vbox.get_node_or_null("SliderHintLabel") == null,
		"Dead SliderHintLabel node has been removed from NewGameModal"
	)
	main_a.confirm_slider.value = 100.0
	_assert(
		not main_a.confirm_new_game_button.disabled,
		"ConfirmSlider unlocks ConfirmNewGameButton without dead SliderHintLabel updates"
	)

	# 2. StyleBoxFlat subresources are resource_local_to_scene and isolated across MainScene instances & PackedScene template (Issue #44)
	main_a._apply_responsive_layout(Vector2(480, 800), true)
	main_b._apply_responsive_layout(Vector2(1280, 800), false)
	var panel_style_a := main_a.side_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var panel_style_b := main_b.side_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var modal_style_a := main_a.modal_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var modal_style_b := main_b.modal_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var banner_style_a := main_a.gpu_warning_banner.get_theme_stylebox("panel") as StyleBoxFlat
	var banner_style_b := main_b.gpu_warning_banner.get_theme_stylebox("panel") as StyleBoxFlat
	_assert(
		panel_style_a != null
		and panel_style_b != null
		and panel_style_a != panel_style_b
		and panel_style_a.content_margin_left == 10.0
		and panel_style_b.content_margin_left == 14.0,
		"SidePanel StyleBoxFlat is local to scene: mobile margins (10px) do not mutate desktop instance (14px)"
	)
	_assert(
		modal_style_a != null
		and modal_style_b != null
		and modal_style_a != modal_style_b
		and modal_style_a.content_margin_left == 16.0
		and modal_style_b.content_margin_left == 22.0,
		"ModalPanel StyleBoxFlat is local to scene: mobile margins (16px) do not mutate desktop instance (22px)"
	)
	_assert(
		banner_style_a != null and banner_style_b != null and banner_style_a != banner_style_b,
		"GpuWarningBanner StyleBoxFlat is local to scene across MainScene instances"
	)
	# Instantiate a fresh scene AFTER mutating main_a to verify PackedScene template was not mutated
	var main_fresh: Control = MainScene.instantiate()
	var fresh_panel_style := main_fresh.get_node("%SidePanel").get_theme_stylebox("panel") as StyleBoxFlat
	var fresh_modal_style := main_fresh.get_node("%ModalPanel").get_theme_stylebox("panel") as StyleBoxFlat
	_assert(
		fresh_panel_style != null
		and fresh_panel_style.content_margin_left == 14.0
		and fresh_modal_style != null
		and fresh_modal_style.content_margin_left == 22.0,
		"Fresh MainScene instantiated after mobile layout mutation still starts with untouched desktop StyleBoxFlat defaults"
	)
	main_fresh.free()
	main_b.free()

	# 3. GpuWarningBanner renders behind NewGameModal in scene tree so it never occludes the startup modal
	_assert(
		main_a.gpu_warning_banner.get_index() < main_a.new_game_modal.get_index(),
		"GpuWarningBanner precedes NewGameModal in Main scene tree so startup modal is never occluded"
	)

	# 4. Non-overlapping rects across Narrow Portrait, Mobile Portrait, Desktop Portrait, Compact/Mobile Landscape, and Desktop Landscape
	#    Uses longest realistic subtitle, long unbroken adapter string, and checks PromotionBox + SidePanel toggle states.
	main_a.new_game_modal.visible = false
	main_a.side_panel.visible = true
	main_a._apply_software_renderer_fallback("ANGLE_SwiftShader_Software_WebGL_UnbrokenAdapterName_1234567890")
	main_a.subtitle_label.text = "1P vs CPU (Medium) • You: #2 Magenta"
	main_a.status_label.text = "Magenta (CPU) Thinking..."
	main_a.set_anchors_preset(Control.PRESET_TOP_LEFT)

	var viewports := [
		{"name": "Narrow Portrait 360x640", "size": Vector2(360, 640), "mobile": true, "portrait": true},
		{"name": "Mobile Portrait 480x1040", "size": Vector2(480, 1040), "mobile": true, "portrait": true},
		{"name": "Desktop Portrait 800x1280", "size": Vector2(800, 1280), "mobile": false, "portrait": true},
		{"name": "Compact Landscape 800x480", "size": Vector2(800, 480), "mobile": true, "portrait": false},
		{"name": "Mobile Landscape 1040x480", "size": Vector2(1040, 480), "mobile": true, "portrait": false},
		{"name": "Desktop Landscape 1280x800", "size": Vector2(1280, 800), "mobile": false, "portrait": false},
	]

	var narrow_banner_h: float = 0.0
	var desktop_banner_h: float = 0.0

	for vp in viewports:
		var vp_name: String = vp["name"]
		var vp_size: Vector2 = vp["size"]
		var is_mob: bool = vp["mobile"]
		var is_port: bool = vp["portrait"]
		main_a.position = Vector2.ZERO
		main_a.size = vp_size
		main_a.side_panel.visible = true
		main_a.promotion_box.visible = (vp_name == "Compact Landscape 800x480" or vp_name == "Mobile Portrait 480x1040")
		main_a._apply_responsive_layout(vp_size, is_mob)
		await process_frame
		await process_frame

		var toggle_rect: Rect2 = main_a.toggle_panel_button.get_global_rect()
		var banner_rect: Rect2 = main_a.gpu_warning_banner.get_global_rect()
		var side_rect: Rect2 = main_a.side_panel.get_global_rect()
		var subtitle_rect: Rect2 = main_a.subtitle_label.get_global_rect()
		var status_rect: Rect2 = main_a.status_label.get_global_rect()
		var telemetry_rect: Rect2 = main_a.telemetry_label.get_global_rect()
		var promo_clear: bool = (
			not main_a.promotion_box.visible
			or not main_a.promotion_box.get_global_rect().intersects(toggle_rect)
		)
		var title_clear: bool = (
			not main_a.title_label.visible
			or not main_a.title_label.get_global_rect().intersects(toggle_rect)
		)
		var banner_clears_side: bool = is_port or not banner_rect.intersects(side_rect)

		if vp_name == "Narrow Portrait 360x640":
			narrow_banner_h = banner_rect.size.y
		elif vp_name == "Desktop Landscape 1280x800":
			desktop_banner_h = banner_rect.size.y

		_assert(
			main_a.gpu_warning_banner.visible
			and main_a.gpu_warning_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
			and not banner_rect.intersects(toggle_rect)
			and banner_rect.end.x < toggle_rect.position.x
			and banner_clears_side,
			"%s: GpuWarningBanner (%s) clears TogglePanelButton (%s) and SidePanel in landscape" % [
				vp_name,
				str(banner_rect),
				str(toggle_rect),
			]
		)
		_assert(
			title_clear
			and not subtitle_rect.intersects(toggle_rect)
			and not status_rect.intersects(toggle_rect)
			and promo_clear
			and not telemetry_rect.intersects(toggle_rect),
			"%s: TogglePanelButton (%s) does not overlap SidePanel text/promotion (subtitle=%s, status=%s)" % [
				vp_name,
				str(toggle_rect),
				str(subtitle_rect),
				str(status_rect),
			]
		)

	_assert(
		narrow_banner_h > desktop_banner_h and desktop_banner_h > 0.0,
		"GpuWarningBanner shrinks cleanly from narrow portrait (%.0fpx) back to desktop landscape (%.0fpx)" % [
			narrow_banner_h,
			desktop_banner_h,
		]
	)

	# 5. Toggling SidePanel hidden in landscape expands GpuWarningBanner while still clearing TogglePanelButton,
	#    and toggling SidePanel back restores board-width docking without overlapping SidePanel.
	main_a.position = Vector2.ZERO
	main_a.size = Vector2(1280, 800)
	main_a.side_panel.visible = true
	main_a._apply_responsive_layout(Vector2(1280, 800), false)
	await process_frame
	var docked_banner_w: float = main_a.gpu_warning_banner.get_global_rect().size.x
	main_a._on_toggle_panel_pressed()
	await process_frame
	await process_frame
	var expanded_banner_rect: Rect2 = main_a.gpu_warning_banner.get_global_rect()
	var toggle_rect_after: Rect2 = main_a.toggle_panel_button.get_global_rect()
	_assert(
		not main_a.side_panel.visible
		and expanded_banner_rect.size.x > docked_banner_w
		and not expanded_banner_rect.intersects(toggle_rect_after)
		and expanded_banner_rect.end.x < toggle_rect_after.position.x,
		"Hiding SidePanel in landscape expands GpuWarningBanner (%.0f -> %.0fpx) while keeping clearance before TogglePanelButton" % [
			docked_banner_w,
			expanded_banner_rect.size.x,
		]
	)
	main_a._on_toggle_panel_pressed()
	await process_frame
	await process_frame
	var redocked_banner_rect: Rect2 = main_a.gpu_warning_banner.get_global_rect()
	_assert(
		main_a.side_panel.visible
		and not redocked_banner_rect.intersects(main_a.side_panel.get_global_rect())
		and not redocked_banner_rect.intersects(main_a.toggle_panel_button.get_global_rect()),
		"Re-showing SidePanel re-docks GpuWarningBanner cleanly left of SidePanel and TogglePanelButton"
	)

	main_a.free()
