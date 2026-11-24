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
	_test_execute_move_validation_and_integrity()
	_test_piece_faceted_meshes()
	_test_ai_player_move_selection()
	await _test_ai_player_async_move_selection()
	await _test_ai_player_tactical_correctness_and_search()
	await _test_draw_rules_and_ai_repetition_avoidance()
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
	rules.clear_pieces()

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
	ortho_pin_rules.clear_pieces()
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
	diag_pin_rules.clear_pieces()
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
	rules.clear_pieces()
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
	cap_rules.clear_pieces()
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
	knight_rules.clear_pieces()
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
	rules.clear_pieces()
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
	rules.clear_pieces()

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
	stale_rules.clear_pieces()
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
	_assert(
		piece.grid_pos == mv.to and rules._search_depth == 1 and _verify_spatial_index_invariants(rules),
		"push_search_move moves piece in-place, increments _search_depth, and maintains spatial index"
	)
	rules.pop_search_move(undo)
	_assert(
		piece.grid_pos == orig_pos
		and rules.pieces.size() == orig_count
		and rules._search_depth == 0
		and _verify_spatial_index_invariants(rules),
		"pop_search_move restores exact board state, _search_depth == 0, and spatial index"
	)


func _verify_spatial_index_invariants(rules: GameRules) -> bool:
	var expected_grid: Dictionary = {}
	var expected_ids: Dictionary = {}
	var expected_cyan_king: PieceData = null
	var expected_magenta_king: PieceData = null
	var expected_on_board: int = 0
	for p in rules.pieces:
		if p == null:
			return false
		if GameRules.is_inside_board(p.grid_pos):
			var g_idx := (p.grid_pos.x + GameRules.BOARD_RADIUS) * GameRules.GRID_SPAN + (p.grid_pos.y + GameRules.BOARD_RADIUS)
			expected_grid[g_idx] = p
			expected_on_board += 1
		if p.id <= 0 or p.id >= rules._id_map.size():
			return false
		expected_ids[p.id] = p
		if p.type == PieceData.Type.KING:
			if p.team == PieceData.Team.CYAN:
				expected_cyan_king = p
			else:
				expected_magenta_king = p
	if rules._grid.size() != GameRules.GRID_SIZE:
		return false
	for idx in range(GameRules.GRID_SIZE):
		if rules._grid[idx] != expected_grid.get(idx, null):
			return false
	for id in range(rules._id_map.size()):
		if rules._id_map[id] != expected_ids.get(id, null):
			return false
	if (
		rules._cyan_king != expected_cyan_king
		or rules._magenta_king != expected_magenta_king
		or rules._indexed_piece_count != rules.pieces.size()
		or rules._indexed_on_board_count != expected_on_board
	):
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
	rules.clear_pieces()
	var king_pos := Vector2i(0, 0)
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, king_pos)
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, Vector2i(0, -5))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Center King is not in check when enemy King is 5 hexes away")

	# Knight attack at jump vector (2, -3)
	var knight := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, Vector2i(2, -3))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects enemy Knight jump at (2, -3)")
	rules.remove_piece(knight)

	# Diagonal Bishop attack at (2, -4) = 2 * (1, -2) and blocker at (1, -2)
	var bishop := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, Vector2i(2, -4))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects unobstructed diagonal Bishop ray")
	var diag_blocker := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(1, -2))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Intermediate piece on diagonal ray blocks Bishop check")
	rules.remove_piece(diag_blocker)
	rules.remove_piece(bishop)

	# Orthogonal Rook attack at (-3, 0) and blocker at (-1, 0)
	var rook := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, Vector2i(-3, 0))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects unobstructed orthogonal Rook ray")
	var ortho_blocker := rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(-1, 0))
	_assert(not rules.is_king_in_check(PieceData.Team.CYAN), "Intermediate piece on orthogonal ray blocks Rook check")
	rules.remove_piece(ortho_blocker)
	rules.remove_piece(rook)

	# Magenta Pawn capture attack from (1, -1) -> attacks (0, 0) via MAGENTA_PAWN_CAP_DIRS (-1, 1)
	var mpawn := rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, Vector2i(1, -1))
	_assert(rules.is_king_in_check(PieceData.Team.CYAN), "is_cell_attacked detects enemy Magenta Pawn capture vector")
	rules.remove_piece(mpawn)


func _test_execute_move_validation_and_integrity() -> void:
	print("\n-- execute_move() Validation, Spatial Index Hardening & Attack/Legal Helpers (Issues #38 & #46) --")
	var rules := GameRules.new()

	# 1. execute_move() rejects null move
	_assert(
		not rules.execute_move(null)
		and rules.current_turn == PieceData.Team.CYAN
		and rules.move_history.is_empty(),
		"execute_move(null) returns false without mutating game state"
	)

	# 2. execute_move() rejects out-of-turn move (Magenta pawn on Cyan's turn)
	var f7 := GameRules.algebraic_to_axial("f7")
	var f6 := GameRules.algebraic_to_axial("f6")
	var mag_pawn := rules.get_piece_at(f7)
	var out_of_turn_mv := GameRules.VectorMove.new(mag_pawn.id, f7, f6)
	_assert(
		not rules.execute_move(out_of_turn_mv)
		and rules.current_turn == PieceData.Team.CYAN
		and rules.move_history.is_empty()
		and mag_pawn.grid_pos == f7
		and _verify_spatial_index_invariants(rules),
		"execute_move() rejects out-of-turn Magenta move on Cyan's turn without mutating state"
	)

	# 3. execute_move() rejects nonexistent piece_id, out-of-bounds origin/destination, and zero-delta moves
	var f5 := GameRules.algebraic_to_axial("f5")
	var cyan_pawn := rules.get_piece_at(f5)
	var missing_id_mv := GameRules.VectorMove.new(9999, f5, f6)
	var oob_from_mv := GameRules.VectorMove.new(cyan_pawn.id, Vector2i(6, 0), f6)
	var oob_dest_mv := GameRules.VectorMove.new(cyan_pawn.id, f5, Vector2i(6, 0))
	var oob_diag_mv := GameRules.VectorMove.new(cyan_pawn.id, f5, Vector2i(3, 3))
	var zero_delta_mv := GameRules.VectorMove.new(cyan_pawn.id, f5, f5)
	_assert(
		not rules.execute_move(missing_id_mv)
		and not rules.execute_move(oob_from_mv)
		and not rules.execute_move(oob_dest_mv)
		and not rules.execute_move(oob_diag_mv)
		and not rules.execute_move(zero_delta_mv)
		and rules.current_turn == PieceData.Team.CYAN
		and rules.move_history.is_empty()
		and cyan_pawn.grid_pos == f5,
		"execute_move() rejects nonexistent piece_id, out-of-bounds origin/destination, and zero-delta moves"
	)

	# 4. execute_move() rejects stale-origin move (piece.grid_pos != move.from)
	var stale_mv := rules.get_legal_moves_for_piece(cyan_pawn)[0].duplicate_move()
	var executed_first := rules.execute_move(stale_mv)
	var mag_reply := rules.get_all_legal_moves(PieceData.Team.MAGENTA)[0]
	rules.execute_move(mag_reply)
	var hist_before_stale := rules.move_history.size()
	_assert(
		executed_first
		and rules.current_turn == PieceData.Team.CYAN
		and cyan_pawn.grid_pos != stale_mv.from
		and not rules.execute_move(stale_mv)
		and rules.move_history.size() == hist_before_stale
		and rules.current_turn == PieceData.Team.CYAN
		and _verify_spatial_index_invariants(rules),
		"execute_move() rejects stale-origin VectorMove when piece has already moved away"
	)

	# 5. execute_move() rejects mismatched capture metadata (prevents _grid overwrite corruption)
	var cap_mismatch_rules := GameRules.new()
	cap_mismatch_rules.clear_pieces()
	cap_mismatch_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	cap_mismatch_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var c_rook := cap_mismatch_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, Vector2i(0, 0))
	var c_ally := cap_mismatch_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(0, -1))
	var m_foe := cap_mismatch_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, Vector2i(1, 0))
	var quiet_into_foe := GameRules.VectorMove.new(c_rook.id, Vector2i(0, 0), Vector2i(1, 0))
	var capture_empty := GameRules.VectorMove.new(c_rook.id, Vector2i(0, 0), Vector2i(-1, 0))
	capture_empty.is_capture = true
	var capture_ally := GameRules.VectorMove.new(c_rook.id, Vector2i(0, 0), Vector2i(0, -1))
	capture_ally.is_capture = true
	capture_ally.captured_piece_id = c_ally.id
	var stale_capture_id := GameRules.VectorMove.new(c_rook.id, Vector2i(0, 0), Vector2i(1, 0))
	stale_capture_id.is_capture = true
	stale_capture_id.captured_piece_id = 9999
	_assert(
		not cap_mismatch_rules.execute_move(quiet_into_foe)
		and not cap_mismatch_rules.execute_move(capture_empty)
		and not cap_mismatch_rules.execute_move(capture_ally)
		and not cap_mismatch_rules.execute_move(stale_capture_id)
		and cap_mismatch_rules.get_piece_at(Vector2i(1, 0)) == m_foe
		and cap_mismatch_rules.get_piece_at(Vector2i(0, -1)) == c_ally
		and _verify_spatial_index_invariants(cap_mismatch_rules),
		"execute_move() rejects quiet move onto occupied hex, capture onto empty hex, self-capture, and stale capture ID"
	)

	# 5b. execute_move() rejects stale/expired en-passant moves and invalid promotions (KING/PAWN/non-pawn/non-promo cell)
	var ep_stale_rules := GameRules.new()
	ep_stale_rules.clear_pieces()
	var ep_ck := ep_stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	var ep_mk := ep_stale_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var ep_cp := ep_stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	var ep_mp := ep_stale_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("d5"))
	for mv in ep_stale_rules.get_legal_moves_for_piece(ep_cp):
		if mv.is_double_step:
			ep_stale_rules.execute_move(mv)
			break
	var saved_ep: GameRules.VectorMove = null
	for mv in ep_stale_rules.get_legal_moves_for_piece(ep_mp):
		if mv.is_en_passant:
			saved_ep = mv.duplicate_move()
			break
	# Play two unrelated king moves so en-passant window expires, then replay saved_ep on Magenta's turn
	ep_stale_rules.execute_move(ep_stale_rules.get_legal_moves_for_piece(ep_mk)[0])
	ep_stale_rules.execute_move(ep_stale_rules.get_legal_moves_for_piece(ep_ck)[0])
	_assert(
		saved_ep != null
		and ep_stale_rules.current_turn == PieceData.Team.MAGENTA
		and not ep_stale_rules.execute_move(saved_ep)
		and ep_stale_rules.get_piece_by_id(ep_cp.id) == ep_cp
		and _verify_spatial_index_invariants(ep_stale_rules),
		"execute_move() rejects stale/expired en-passant VectorMove after en-passant window has closed"
	)

	var promo_val_rules := GameRules.new()
	promo_val_rules.clear_pieces()
	promo_val_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	promo_val_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var pv_pawn := promo_val_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	var pv_mid_pawn := promo_val_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f5"))
	var pv_rook := promo_val_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e10"))
	var promo_to_king := promo_val_rules.get_legal_moves_for_piece(pv_pawn)[0].duplicate_move()
	promo_to_king.promotion_type = PieceData.Type.KING
	var promo_to_pawn := promo_to_king.duplicate_move()
	promo_to_pawn.promotion_type = PieceData.Type.PAWN
	var promo_mid_cell := GameRules.VectorMove.new(pv_mid_pawn.id, pv_mid_pawn.grid_pos, GameRules.algebraic_to_axial("f6"))
	promo_mid_cell.is_promotion = true
	var promo_rook := GameRules.VectorMove.new(pv_rook.id, pv_rook.grid_pos, GameRules.algebraic_to_axial("e11"))
	promo_rook.is_promotion = true
	_assert(
		not promo_val_rules.execute_move(promo_to_king)
		and not promo_val_rules.execute_move(promo_to_pawn)
		and not promo_val_rules.execute_move(promo_mid_cell)
		and not promo_val_rules.execute_move(promo_rook)
		and promo_val_rules.move_history.is_empty()
		and _verify_spatial_index_invariants(promo_val_rules),
		"execute_move() rejects invalid promotions (KING/PAWN target, non-promotion cell, or non-pawn mover)"
	)

	# 6. execute_move() rejects moves when is_game_over is true
	var over_rules := GameRules.new()
	over_rules.is_game_over = true
	var f5_pawn_over := over_rules.get_piece_at(f5)
	var over_mv := GameRules.VectorMove.new(f5_pawn_over.id, f5, f6)
	_assert(
		not over_rules.execute_move(over_mv)
		and over_rules.move_history.is_empty()
		and f5_pawn_over.grid_pos == f5
		and over_rules.current_turn == PieceData.Team.CYAN,
		"execute_move() rejects moves after is_game_over is true"
	)

	# 7. clear_pieces() and remove_piece() keep spatial index, King refs, and en-passant state synchronized
	var helper_rules := GameRules.new()
	helper_rules.clear_pieces()
	_assert(
		helper_rules.pieces.is_empty()
		and helper_rules._cyan_king == null
		and helper_rules._magenta_king == null
		and helper_rules.en_passant_target == GameRules.INVALID_HEX
		and helper_rules.en_passant_pawn_id == -1
		and _verify_spatial_index_invariants(helper_rules),
		"clear_pieces() resets pieces, spatial grid, ID map, King refs, and en-passant state"
	)
	var hk_c := helper_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	helper_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var ep_p := helper_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	for mv in helper_rules.get_legal_moves_for_piece(ep_p):
		if mv.is_double_step:
			helper_rules.execute_move(mv)
			break
	var ep_removed := helper_rules.remove_piece(ep_p)
	var ep_removed_again := helper_rules.remove_piece(ep_p)
	var null_removed := helper_rules.remove_piece(null)
	_assert(
		ep_removed
		and not ep_removed_again
		and not null_removed
		and helper_rules.en_passant_target == GameRules.INVALID_HEX
		and helper_rules.en_passant_pawn_id == -1
		and helper_rules.get_piece_by_id(ep_p.id) == null
		and _verify_spatial_index_invariants(helper_rules),
		"remove_piece() clears grid, ID map, and dangling en-passant state, returning false on null/duplicate"
	)
	# Passing a detached/removed piece to get_legal_moves_for_piece() returns [] without corrupting _grid
	var replacement_occupant := helper_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, ep_p.grid_pos)
	var detached_moves := helper_rules.get_legal_moves_for_piece(ep_p)
	_assert(
		detached_moves.is_empty()
		and helper_rules.get_piece_at(ep_p.grid_pos) == replacement_occupant
		and _verify_spatial_index_invariants(helper_rules),
		"get_legal_moves_for_piece() rejects detached piece without overwriting live _grid occupant"
	)
	var king_removed := helper_rules.remove_piece(hk_c)
	_assert(
		king_removed and helper_rules._cyan_king == null and _verify_spatial_index_invariants(helper_rules),
		"remove_piece() clears King reference when a King is removed"
	)

	# 8. _ensure_spatial_index() detects direct mutations to pieces[i].grid_pos, off-board moves, and element replacement
	var mut_rules := GameRules.new()
	var target_p := mut_rules.pieces[5]
	var old_pos := target_p.grid_pos
	target_p.grid_pos = Vector2i(0, 0)
	_assert(
		mut_rules.get_piece_at(Vector2i(0, 0)) == target_p
		and mut_rules.get_piece_at(old_pos) == null
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() resyncs _grid when pieces[5].grid_pos is mutated directly"
	)

	target_p.grid_pos = GameRules.INVALID_HEX
	_assert(
		mut_rules.get_piece_at(Vector2i(0, 0)) == null
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() clears stale _grid cell when pieces[5].grid_pos is moved off-board"
	)

	var replacement := PieceData.new(99, PieceData.Team.CYAN, PieceData.Type.ROOK, Vector2i(0, 0))
	mut_rules.pieces[5] = replacement
	_assert(
		mut_rules.get_piece_at(Vector2i(0, 0)) == replacement
		and mut_rules.get_piece_by_id(99) == replacement
		and mut_rules.get_piece_by_id(target_p.id) == null
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() resyncs _grid and _id_map when pieces[5] is replaced in-place"
	)

	# Replace Cyan King element directly (at index 6) and move it under attack to verify _cyan_king updates
	var king_idx := -1
	for i in range(mut_rules.pieces.size()):
		if mut_rules.pieces[i].team == PieceData.Team.CYAN and mut_rules.pieces[i].type == PieceData.Type.KING:
			king_idx = i
			break
	var new_cyan_king := PieceData.new(100, PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("e6"))
	mut_rules.pieces[king_idx] = new_cyan_king
	_assert(
		mut_rules.is_king_in_check(PieceData.Team.CYAN)
		and mut_rules._cyan_king == new_cyan_king
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() updates _cyan_king when King element is replaced directly in pieces"
	)

	# Same-ID / same-pos replacement, direct King type demotion, and null-entry compaction
	var same_id_replacement := PieceData.new(99, PieceData.Team.CYAN, PieceData.Type.BISHOP, Vector2i(0, 0))
	mut_rules.pieces[5] = same_id_replacement
	_assert(
		mut_rules.get_piece_by_id(99) == same_id_replacement
		and mut_rules.get_piece_at(Vector2i(0, 0)) == same_id_replacement
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() detects same-ID/same-pos reference replacement in pieces"
	)

	new_cyan_king.type = PieceData.Type.QUEEN
	_assert(
		mut_rules.is_king_in_check(PieceData.Team.CYAN)
		and mut_rules._cyan_king == null
		and _verify_spatial_index_invariants(mut_rules),
		"_ensure_spatial_index() clears _cyan_king when King piece type is mutated directly"
	)

	var count_before_null := mut_rules.pieces.size()
	mut_rules.pieces[5] = null
	_assert(
		mut_rules.get_piece_at(Vector2i(0, 0)) == null
		and mut_rules.pieces.size() == count_before_null - 1
		and _verify_spatial_index_invariants(mut_rules),
		"_rebuild_spatial_index() compacts stray null entries out of pieces cleanly"
	)

	# 9. has_any_legal_move() matches opening, checkmate (before & after is_game_over), and stalemate
	var opening_rules := GameRules.new()
	_assert(
		opening_rules.has_any_legal_move(PieceData.Team.CYAN)
		and opening_rules.has_any_legal_move(PieceData.Team.MAGENTA),
		"has_any_legal_move() returns true for both teams in opening position"
	)
	opening_rules.is_game_over = true
	_assert(
		not opening_rules.has_any_legal_move(PieceData.Team.CYAN),
		"has_any_legal_move() returns false when is_game_over is true"
	)

	# Checkmate position with is_game_over still false (as encountered during AI search leaf checks)
	var mate_rules := GameRules.new()
	mate_rules.clear_pieces()
	mate_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f10"))
	mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f8"))
	_assert(
		not mate_rules.is_game_over
		and mate_rules.is_king_in_check(PieceData.Team.MAGENTA)
		and not mate_rules.has_any_legal_move(PieceData.Team.MAGENTA)
		and mate_rules.has_any_legal_move(PieceData.Team.CYAN),
		"has_any_legal_move() returns false for checkmated side and true for attacker even while is_game_over is false"
	)

	# Stalemate position with is_game_over still false
	var stale_check := GameRules.new()
	stale_check.clear_pieces()
	stale_check._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	stale_check._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	stale_check._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	stale_check._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("g8"))
	_assert(
		not stale_check.is_king_in_check(PieceData.Team.MAGENTA)
		and not stale_check.has_any_legal_move(PieceData.Team.MAGENTA),
		"has_any_legal_move() returns false for stalemated side while is_game_over is false"
	)

	# 10. Consolidated attack scanner (is_cell_attacked / get_cell_attackers / get_checking_pieces) with all 6 attacker types
	var atk_rules := GameRules.new()
	atk_rules.clear_pieces()
	atk_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, Vector2i(0, 0))
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, Vector2i(-3, 0))    # Orthogonal ray
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, Vector2i(2, -4))  # Diagonal ray
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, Vector2i(0, -3))   # Orthogonal Queen ray
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, Vector2i(-2, 4))   # Diagonal Queen ray
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, Vector2i(2, -3))  # Knight jump
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, Vector2i(1, -1))    # Magenta reverse pawn capture
	atk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, Vector2i(0, 1))     # Adjacent King
	var all_attackers := atk_rules.get_cell_attackers(Vector2i(0, 0), PieceData.Team.MAGENTA)
	var checking := atk_rules.get_checking_pieces(PieceData.Team.CYAN)
	# Also verify Cyan Pawn reverse-capture lookup (CYAN_PAWN_CAP_DIRS: (-1, 0) and (1, -1))
	var cyan_atk_pawn := atk_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, Vector2i(-1, 2))
	var cyan_pawn_hits := atk_rules.get_cell_attackers(Vector2i(0, 1), PieceData.Team.CYAN)
	_assert(
		atk_rules.is_cell_attacked(Vector2i(0, 0), PieceData.Team.MAGENTA)
		and all_attackers.size() == 7
		and checking.size() == 7
		and atk_rules.is_cell_attacked(Vector2i(0, 1), PieceData.Team.CYAN)
		and cyan_pawn_hits.has(cyan_atk_pawn)
		and not atk_rules.is_cell_attacked(Vector2i(6, 0), PieceData.Team.MAGENTA)
		and atk_rules.get_cell_attackers(Vector2i(6, 0), PieceData.Team.MAGENTA).is_empty(),
		"Consolidated attack scanner detects all 6 piece types (incl. Queens & Cyan/Magenta Pawns) and rejects off-board cells"
	)

	# 11. Pawn en-passant guard skips en passant when en_passant_target is occupied (friendly blocks; enemy yields normal capture)
	var ep_guard_rules := GameRules.new()
	ep_guard_rules.clear_pieces()
	ep_guard_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	ep_guard_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var ep_cyan := ep_guard_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	var ep_mag := ep_guard_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("d5"))
	for mv in ep_guard_rules.get_legal_moves_for_piece(ep_cyan):
		if mv.is_double_step:
			ep_guard_rules.execute_move(mv)
			break
	var e5 := GameRules.algebraic_to_axial("e5")
	var friendly_blocker := ep_guard_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, e5)
	var ep_blocked_legal := false
	for mv in ep_guard_rules.get_legal_moves_for_piece(ep_mag):
		if mv.is_en_passant:
			ep_blocked_legal = true
	var ep_blocked_tactical := false
	for mv in ep_guard_rules.get_all_tactical_moves(PieceData.Team.MAGENTA):
		if mv.is_en_passant:
			ep_blocked_tactical = true
	_assert(
		not ep_blocked_legal
		and not ep_blocked_tactical
		and ep_guard_rules.get_piece_at(e5) == friendly_blocker
		and _verify_spatial_index_invariants(ep_guard_rules),
		"_append_pawn_captures() skips en passant when en_passant_target is occupied by a friendly piece"
	)
	ep_guard_rules.remove_piece(friendly_blocker)
	var enemy_occupant := ep_guard_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, e5)
	var normal_cap_on_e5 := false
	var ep_cap_on_e5 := false
	for mv in ep_guard_rules.get_legal_moves_for_piece(ep_mag):
		if mv.to == e5:
			if mv.is_en_passant:
				ep_cap_on_e5 = true
			elif mv.is_capture and mv.captured_piece_id == enemy_occupant.id:
				normal_cap_on_e5 = true
	_assert(
		normal_cap_on_e5 and not ep_cap_on_e5,
		"_append_pawn_captures() generates normal capture (not en passant) when an enemy occupies en_passant_target"
	)

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
	tac_rules.clear_pieces()
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
	compact.clear_pieces()
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

	# Verify 1-pawn capture-promotion expands into 4 [=Q, =N, =R, =B] candidates (bypassing legal_moves.size() == 1 fast path):
	# Cyan King on f1 (0, 5) is immobilized by Magenta Rooks on e6/g6 and Bishop on d1, leaving e10xf11 as Cyan's sole raw move.
	# Magenta King on a6 (-5, 0) is self-blocked except along the f11->a6 (-1, +1) ray, so e10xf11=Q# is mate in 1 (zero jitter).
	var single_promo := GameRules.new()
	single_promo.clear_pieces()
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
		"choose_move_async expands sole capture-promotion e10xf11 into [=Q, =N, =R, =B] and selects =Q"
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
	smothered_rules.clear_pieces()
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
	forced.clear_pieces()
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


func _has_mate_in_one(rules: GameRules, team: PieceData.Team) -> bool:
	var moves := rules.get_all_legal_moves(team)
	for mv in moves:
		if mv.is_promotion:
			for ptype in VALID_PROMOTION_TYPES:
				var sim := rules.clone_state()
				var variant := mv.duplicate_move()
				variant.promotion_type = ptype
				if sim.execute_move(variant) and sim.is_game_over and sim.status_text.begins_with("CHECKMATE"):
					return true
		else:
			var sim := rules.clone_state()
			if sim.execute_move(mv) and sim.is_game_over and sim.status_text.begins_with("CHECKMATE"):
				return true
	return false


func _test_ai_player_tactical_correctness_and_search() -> void:
	print("\n-- AIPlayer Tactical Correctness & Search (Issues #30, #31, #35, #45) --")
	var ai := AIPlayer.new()

	# ------------------------------------------------------------------
	# Issue #30a: Medium avoids capturing a free pawn that allows Mate-in-1
	# ------------------------------------------------------------------
	# Magenta King on f11 (0, -5), Cyan Queen on g8 (1, -3), Cyan Rook on i7 (3, -4) defending g9/f10.
	# Magenta Rook on a6 (-5, 0) can grab a free Cyan Pawn on a5 (-5, 1), but doing so allows Q g8->g9#.
	var med_mate_rules := GameRules.new()
	med_mate_rules.clear_pieces()
	med_mate_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	med_mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	med_mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("g8"))
	med_mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("i7"))
	var mag_rook := med_mate_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("a6"))
	var free_pawn_pos := GameRules.algebraic_to_axial("a5")
	med_mate_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, free_pawn_pos)
	med_mate_rules.current_turn = PieceData.Team.MAGENTA

	var grab_pawn_mv: GameRules.VectorMove = null
	for mv in med_mate_rules.get_legal_moves_for_piece(mag_rook):
		if mv.to == free_pawn_pos:
			grab_pawn_mv = mv
			break
	var blunder_sim := med_mate_rules.clone_state()
	var grab_allows_mate := (
		not med_mate_rules.is_king_in_check(PieceData.Team.MAGENTA)
		and grab_pawn_mv != null
		and blunder_sim.execute_move(grab_pawn_mv)
		and _has_mate_in_one(blunder_sim, PieceData.Team.CYAN)
	)
	_assert(grab_allows_mate, "#30 setup: Magenta R a6xa5 allows immediate Cyan Mate-in-1 (Q g8->g9#)")

	var med_defends_all := true
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var med_choice := ai.choose_move(med_mate_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.MEDIUM)
		if med_choice == null or med_choice.to == free_pawn_pos:
			med_defends_all = false
			break
		var after_med := med_mate_rules.clone_state()
		if not after_med.execute_move(med_choice) or _has_mate_in_one(after_med, PieceData.Team.CYAN):
			med_defends_all = false
			break
	ai._rng.seed = 42
	var med_async_choice := await ai.choose_move_async(med_mate_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.MEDIUM, self)
	var after_med_async := med_mate_rules.clone_state()
	var med_async_ok := (
		med_async_choice != null
		and med_async_choice.to != free_pawn_pos
		and after_med_async.execute_move(med_async_choice)
		and not _has_mate_in_one(after_med_async, PieceData.Team.CYAN)
	)
	_assert(
		med_defends_all and med_async_ok,
		"#30: Medium AI (sync across 10 seeds & async) rejects free pawn a6xa5 and prevents Cyan Mate-in-1"
	)

	# ------------------------------------------------------------------
	# Issue #30b: Hard finds forced quiet Mate-in-2 over winning free material
	# ------------------------------------------------------------------
	var mate2_rules := GameRules.new()
	mate2_rules.clear_pieces()
	mate2_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("e10"))
	mate2_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	mate2_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("d5"))
	mate2_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("i5"))
	mate2_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("h7"))
	mate2_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("k4"))
	var bait_knight_pos := GameRules.algebraic_to_axial("d2")
	mate2_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, bait_knight_pos)
	mate2_rules.current_turn = PieceData.Team.CYAN

	_assert(
		not mate2_rules.is_king_in_check(PieceData.Team.CYAN)
		and not _has_mate_in_one(mate2_rules, PieceData.Team.CYAN),
		"#30 setup: Hard Mate-in-2 position has no Mate-in-1 on ply 0"
	)

	ai._rng.seed = 7
	var hard_m2 := ai.choose_move(mate2_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 7
	var hard_m2_async := await ai.choose_move_async(mate2_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	var m2_sim := mate2_rules.clone_state()
	var m2_forced_ok := false
	if hard_m2 != null and not hard_m2.is_capture and m2_sim.execute_move(hard_m2):
		var mag_replies := m2_sim.get_all_legal_moves(PieceData.Team.MAGENTA)
		if mag_replies.size() > 0:
			m2_forced_ok = true
			for reply in mag_replies:
				var reply_sim := m2_sim.clone_state()
				if not reply_sim.execute_move(reply) or not _has_mate_in_one(reply_sim, PieceData.Team.CYAN):
					m2_forced_ok = false
					break
	_assert(
		hard_m2 != null
		and hard_m2_async != null
		and hard_m2.to != bait_knight_pos
		and hard_m2_async.to != bait_knight_pos
		and hard_m2.from == hard_m2_async.from
		and hard_m2.to == hard_m2_async.to
		and m2_forced_ok,
		"#30: Hard AI (sync & async) finds forced quiet Mate-in-2 over capturing free Knight on d2"
	)

	# ------------------------------------------------------------------
	# Issue #30c: _quiescence() check evasions, stand_pat disallowance, cap & Mate-in-1 preference
	# ------------------------------------------------------------------
	var qev_rules := GameRules.new()
	qev_rules.clear_pieces()
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b6"))
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("c7"))
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("l1"))
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("h2"))
	qev_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("g2"))
	qev_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("d1"))
	qev_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("a5"))
	qev_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f5"))
	qev_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("l6"))
	qev_rules.current_turn = PieceData.Team.CYAN

	var qev_stand_pat := AIPlayer.evaluate_board(qev_rules, PieceData.Team.CYAN)
	var qev_score := ai._quiescence(qev_rules, -AIPlayer.INF_SCORE, 100, PieceData.Team.CYAN, 1, 3, AIPlayer.MAX_Q_CHECK_EXTENSIONS)
	var qev_cap0_score := ai._quiescence(qev_rules, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.CYAN, 1, 3, 0)
	var qcm_rules := qev_rules.clone_state()
	qcm_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b7"))
	var qcm_cap0_score := ai._quiescence(qcm_rules, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.CYAN, 1, 5, 0)
	_assert(
		qev_rules.is_king_in_check(PieceData.Team.CYAN)
		and not qev_rules.is_king_in_check(PieceData.Team.MAGENTA)
		and qev_rules.get_all_legal_moves(PieceData.Team.CYAN).size() == 1
		and qev_stand_pat > 100
		and qev_score < 0
		and qev_cap0_score == qev_stand_pat
		and qcm_cap0_score == -(AIPlayer.MATE_SCORE - 50),
		"#30: _quiescence() disallows stand_pat in check (stand_pat=%d, score=%d), respects extension cap, and detects checkmate at cap=0" % [
			qev_stand_pat,
			qev_score,
		]
	)

	var kcap_rules := GameRules.new()
	kcap_rules.clear_pieces()
	var kcap_king := kcap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f6"))
	kcap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f7"))
	kcap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	var kcap_moves := kcap_rules.get_legal_moves_for_piece(kcap_king)
	ai._order_moves(kcap_rules, kcap_moves)
	_assert(
		kcap_moves.size() > 1 and kcap_moves[0].is_capture and kcap_moves[0].to == GameRules.algebraic_to_axial("f7"),
		"#30: MVV-LVA caps King attacker value so King capture K f6xf7 sorts before quiet evasion moves"
	)

	var m1_vs_m2 := GameRules.new()
	m1_vs_m2.clear_pieces()
	m1_vs_m2._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	m1_vs_m2._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	m1_vs_m2._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("g8"))
	m1_vs_m2._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("i7"))
	m1_vs_m2.current_turn = PieceData.Team.CYAN
	ai._rng.seed = 1
	var m1_choice := ai.choose_move(m1_vs_m2, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	var m1_sim := m1_vs_m2.clone_state()
	_assert(
		m1_choice != null and m1_sim.execute_move(m1_choice) and m1_sim.is_game_over and m1_sim.status_text.begins_with("CHECKMATE"),
		"#30: Hard AI prefers immediate Mate-in-1 over slower forced mate lines"
	)

	# ------------------------------------------------------------------
	# Issue #31: Multi-seed root jitter + beta cutoff never blunders
	# ------------------------------------------------------------------
	_assert(
		AIPlayer.MATE_THRESHOLD == AIPlayer.MATE_SCORE - 1000,
		"#31: MATE_THRESHOLD is widened to MATE_SCORE - 1000 for deeper quiescence ply mate scores"
	)

	# 31a: White-box test of shared _evaluate_root_move() fail-low guard and widened MATE_THRESHOLD guard
	var wb_rules := GameRules.new()
	wb_rules.clear_pieces()
	wb_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	wb_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l6"))
	var wb_queen := wb_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f6"))
	var wb_q_moves := wb_rules.get_legal_moves_for_piece(wb_queen)
	var wb_safe_mv := wb_q_moves[0]
	var wb_fail_low_mv := wb_q_moves[1]
	var wb_fail_low_ok := true
	for seed_val in range(1, 31):
		ai._rng.seed = seed_val
		var rs := AIPlayer._RootSearchState.new(wb_safe_mv)
		rs.best_raw_score = 5000
		rs.best_score = 5000
		rs.has_best = true
		ai._evaluate_root_move(wb_rules, wb_fail_low_mv, 2, false, 25, rs)
		if rs.best_move != wb_safe_mv or rs.best_raw_score != 5000 or rs.best_score != 5000:
			wb_fail_low_ok = false
			break
	var rs_deep_mate := AIPlayer._RootSearchState.new(wb_safe_mv)
	rs_deep_mate.best_raw_score = AIPlayer.MATE_SCORE - 500
	rs_deep_mate.best_score = AIPlayer.MATE_SCORE - 500
	rs_deep_mate.has_best = true
	ai._rng.seed = 99
	ai._evaluate_root_move(wb_rules, wb_fail_low_mv, 2, false, 25, rs_deep_mate)
	var rs_m1_exact := AIPlayer._RootSearchState.new(m1_choice)
	ai._rng.seed = 99
	ai._evaluate_root_move(m1_vs_m2, m1_choice, 2, false, 25, rs_m1_exact)
	_assert(
		wb_fail_low_ok
		and rs_deep_mate.best_move == wb_safe_mv
		and rs_deep_mate.best_raw_score == AIPlayer.MATE_SCORE - 500
		and rs_m1_exact.best_score == rs_m1_exact.best_raw_score
		and rs_m1_exact.best_raw_score >= AIPlayer.MATE_THRESHOLD,
		"#31: _evaluate_root_move() discards fail-low upper bounds (30 seeds) and applies zero jitter to mate scores >= MATE_THRESHOLD"
	)

	# 31b: Real-board beta-cutoff + jitter trap (triggers 18/30 Med & 19/30 Hard Mate-in-1 blunders under pre-#31 loop)
	var beta_trap_rules := GameRules.new()
	beta_trap_rules.clear_pieces()
	beta_trap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	beta_trap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	beta_trap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("g8"))
	beta_trap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("i7"))
	beta_trap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("d7"))
	beta_trap_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("k3"))
	beta_trap_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("j1"))
	beta_trap_rules.current_turn = PieceData.Team.MAGENTA

	var trap_med_ok := true
	var trap_hard_ok := true
	for seed_val in range(1, 31):
		ai._rng.seed = seed_val
		var tm := ai.choose_move(beta_trap_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.MEDIUM)
		var tm_sim := beta_trap_rules.clone_state()
		if tm == null or not tm_sim.execute_move(tm) or _has_mate_in_one(tm_sim, PieceData.Team.CYAN):
			trap_med_ok = false
			break

		ai._rng.seed = seed_val
		var th := ai.choose_move(beta_trap_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.HARD)
		var th_sim := beta_trap_rules.clone_state()
		if th == null or not th_sim.execute_move(th) or _has_mate_in_one(th_sim, PieceData.Team.CYAN):
			trap_hard_ok = false
			break

	ai._rng.seed = 19
	var trap_async_med := await ai.choose_move_async(beta_trap_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.MEDIUM, self)
	var trap_async_med_sim := beta_trap_rules.clone_state()
	ai._rng.seed = 19
	var trap_async_hard := await ai.choose_move_async(beta_trap_rules, PieceData.Team.MAGENTA, AIPlayer.Difficulty.HARD, self)
	var trap_async_hard_sim := beta_trap_rules.clone_state()
	_assert(
		trap_med_ok
		and trap_hard_ok
		and trap_async_med != null and trap_async_med_sim.execute_move(trap_async_med) and not _has_mate_in_one(trap_async_med_sim, PieceData.Team.CYAN)
		and trap_async_hard != null and trap_async_hard_sim.execute_move(trap_async_hard) and not _has_mate_in_one(trap_async_hard_sim, PieceData.Team.CYAN),
		"#31: Medium & Hard AI (30 deterministic seeds + async) never blunder quiet Mate-in-1 under early capture beta cutoffs + root jitter"
	)

	# 31c: Queen safety across 30 deterministic seeds + async
	var jitter_rules := GameRules.new()
	jitter_rules.clear_pieces()
	jitter_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	jitter_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l6"))
	var j_cyan_queen := jitter_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("e4"))
	jitter_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("c4"))
	jitter_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("d5"))
	jitter_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f8"))
	jitter_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("h7"))
	jitter_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("b7"))
	jitter_rules.current_turn = PieceData.Team.CYAN

	var med_no_blunder := true
	var hard_no_blunder := true
	for seed_val in range(1, 31):
		ai._rng.seed = seed_val
		var m_mv := ai.choose_move(jitter_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		var m_sim := jitter_rules.clone_state()
		if m_mv == null or not m_sim.execute_move(m_mv):
			med_no_blunder = false
			break
		var q_after_m := m_sim.get_piece_by_id(j_cyan_queen.id)
		if q_after_m == null or m_sim.is_cell_attacked(q_after_m.grid_pos, PieceData.Team.MAGENTA):
			med_no_blunder = false
			break

		ai._rng.seed = seed_val
		var h_mv := ai.choose_move(jitter_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
		var h_sim := jitter_rules.clone_state()
		if h_mv == null or not h_sim.execute_move(h_mv):
			hard_no_blunder = false
			break
		var q_after_h := h_sim.get_piece_by_id(j_cyan_queen.id)
		if q_after_h == null or h_sim.is_cell_attacked(q_after_h.grid_pos, PieceData.Team.MAGENTA):
			hard_no_blunder = false
			break

	ai._rng.seed = 19
	var async_j_med := await ai.choose_move_async(jitter_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM, self)
	var async_j_sim := jitter_rules.clone_state()
	var q_after_async: PieceData = null
	var async_j_exec := async_j_med != null and async_j_sim.execute_move(async_j_med)
	if async_j_exec:
		q_after_async = async_j_sim.get_piece_by_id(j_cyan_queen.id)
	var async_j_ok := (
		async_j_exec
		and q_after_async != null
		and not async_j_sim.is_cell_attacked(q_after_async.grid_pos, PieceData.Team.MAGENTA)
	)
	_assert(
		med_no_blunder and hard_no_blunder and async_j_ok,
		"#31: Medium & Hard AI (30 deterministic RNG seeds + async) never hang the Queen due to root jitter + beta cutoff"
	)

	# ------------------------------------------------------------------
	# Issue #35: Consistent Glinski stalemate evaluation
	# ------------------------------------------------------------------
	var stale_for_stalemater := AIPlayer.evaluate_stalemate(PieceData.Team.CYAN, PieceData.Team.MAGENTA)
	var stale_for_victim := AIPlayer.evaluate_stalemate(PieceData.Team.MAGENTA, PieceData.Team.MAGENTA)
	_assert(
		stale_for_stalemater > 0
		and stale_for_victim == -stale_for_stalemater
		and stale_for_stalemater + 25 < 72,
		"#35: evaluate_stalemate() is strictly positive (>0), zero-sum, and below K+P vs K static eval even with Medium jitter (%d cp)" % stale_for_stalemater
	)

	# Winning K+P vs K endgame: Magenta King at a6 (-5, 0), Cyan King at c5 (-3, 1), Cyan Pawn at f5 (0, 1).
	# K c5->c6 (-3, 0) immediately stalemates Magenta while static eval is +136 cp (< old 250 cp bug threshold).
	var kp_rules := GameRules.new()
	kp_rules.clear_pieces()
	kp_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	var kp_cyan_king := kp_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	kp_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f5"))
	kp_rules.current_turn = PieceData.Team.CYAN

	var stale_trap_hex := GameRules.algebraic_to_axial("c6")
	var trap_mv: GameRules.VectorMove = null
	for mv in kp_rules.get_legal_moves_for_piece(kp_cyan_king):
		if mv.to == stale_trap_hex:
			trap_mv = mv
			break
	var trap_sim := kp_rules.clone_state()
	var kp_static_eval := AIPlayer.evaluate_board(kp_rules, PieceData.Team.CYAN)
	_assert(
		trap_mv != null
		and trap_sim.execute_move(trap_mv)
		and trap_sim.is_game_over
		and trap_sim.status_text.begins_with("STALEMATE")
		and kp_static_eval > 0
		and kp_static_eval < 250,
		"#35 setup: K+P vs K has static eval +%d cp (<250) and K c5->c6 immediately stalemates Magenta" % kp_static_eval
	)

	var kp_avoids_stale := true
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var kp_med := ai.choose_move(kp_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		if kp_med == null or (kp_med.piece_id == kp_cyan_king.id and kp_med.to == stale_trap_hex):
			kp_avoids_stale = false
			break
	ai._rng.seed = 3
	var kp_hard := ai.choose_move(kp_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 3
	var kp_hard_async := await ai.choose_move_async(kp_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		kp_avoids_stale
		and kp_hard != null and not (kp_hard.piece_id == kp_cyan_king.id and kp_hard.to == stale_trap_hex)
		and kp_hard_async != null and not (kp_hard_async.piece_id == kp_cyan_king.id and kp_hard_async.to == stale_trap_hex),
		"#35: Winning K+P vs K endgame avoids immediate stalemate trap K c5->c6 on Medium (10 seeds) & Hard (sync/async)"
	)

	# Equal K vs K endgame: stalemating opponent (0.75 pts) beats equal 0 draw across 10 seeds + async
	var kk_rules := GameRules.new()
	kk_rules.clear_pieces()
	kk_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	kk_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	kk_rules.current_turn = PieceData.Team.CYAN
	var kk_all_ok := true
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var kk_med := ai.choose_move(kk_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		ai._rng.seed = seed_val
		var kk_hard := ai.choose_move(kk_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
		if kk_med == null or kk_med.to != stale_trap_hex or kk_hard == null or kk_hard.to != stale_trap_hex:
			kk_all_ok = false
			break
	ai._rng.seed = 5
	var kk_async := await ai.choose_move_async(kk_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		kk_all_ok and kk_async != null and kk_async.to == stale_trap_hex,
		"#35: Equal K vs K endgame chooses K c5->c6 across 10 seeds (Medium/Hard + async) to claim Glinski 0.75 : 0.25 stalemate"
	)

	# Behind-in-material endgame: Easy, Medium, and Hard all claim Glinski stalemate (+40 cp) when losing badly (-932 cp)
	var behind_stale_rules := GameRules.new()
	behind_stale_rules.clear_pieces()
	behind_stale_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	behind_stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	for m_alg in ["l6", "l5", "l4", "l3", "l2"]:
		behind_stale_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial(m_alg))
	behind_stale_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("l1"))
	behind_stale_rules.current_turn = PieceData.Team.CYAN
	var behind_eval := AIPlayer.evaluate_board(behind_stale_rules, PieceData.Team.CYAN)
	var behind_all_ok := behind_eval < -400
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var be := ai.choose_move(behind_stale_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY)
		ai._rng.seed = seed_val
		var bm := ai.choose_move(behind_stale_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		ai._rng.seed = seed_val
		var bh := ai.choose_move(behind_stale_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
		if (
			be == null or be.to != stale_trap_hex
			or bm == null or bm.to != stale_trap_hex
			or bh == null or bh.to != stale_trap_hex
		):
			behind_all_ok = false
			break
	_assert(
		behind_all_ok,
		"#35: Losing endgame (eval=%d cp) claims Glinski stalemate K c5->c6 across Easy, Medium & Hard (10 seeds each)" % behind_eval
	)

	# Low-piece endgame leaf nodes (depth 0 & quiescence) detect stalemates instead of returning static eval
	var leaf_stale := GameRules.new()
	leaf_stale.clear_pieces()
	leaf_stale._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	leaf_stale._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c6"))
	leaf_stale._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f5"))
	leaf_stale.current_turn = PieceData.Team.MAGENTA
	var leaf_stale_med := ai._negamax(leaf_stale, 0, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.MAGENTA, 2, false)
	var leaf_stale_hard := ai._negamax(leaf_stale, 0, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.MAGENTA, 3, true)
	_assert(
		leaf_stale_med == -AIPlayer.STALEMATE_BONUS and leaf_stale_hard == -AIPlayer.STALEMATE_BONUS,
		"#35: Low-piece endgame leaf nodes return evaluate_stalemate() (-%d cp) on both Medium and Hard" % AIPlayer.STALEMATE_BONUS
	)

	# ------------------------------------------------------------------
	# Issue #45: Underpromotion expansion (root =R/=B anti-stalemate & multi-ply =N)
	# ------------------------------------------------------------------
	# 45a: GameRules.get_legal_moves_for_piece() emits 1 VectorMove per promotion hex;
	# _expand_promotions() clones [Q,N,R,B] at root and [Q,N] in search without mutating input.
	var ux_promo_rules := GameRules.new()
	ux_promo_rules.clear_pieces()
	ux_promo_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	ux_promo_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	var ux_pawn := ux_promo_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	var ux_moves := ux_promo_rules.get_legal_moves_for_piece(ux_pawn)
	var ux_orig_promo_type := ux_moves[0].promotion_type
	var ux_expanded_root := ai._expand_promotions(ux_moves, true)
	var ux_expanded_search := ai._expand_promotions(ux_moves, false)
	_assert(
		ux_moves.size() == 1
		and ux_moves[0].is_promotion
		and ux_moves[0].promotion_type == ux_orig_promo_type
		and ux_expanded_root.size() == 4
		and ux_expanded_search.size() == 2
		and ux_expanded_root[0] != ux_moves[0],
		"#45: GameRules emits 1 VectorMove per promotion hex for VectorBoard UI; _expand_promotions() clones [Q,N,R,B] at root and [Q,N] in search without mutating input"
	)

	# 45b: Root =R anti-stalemate underpromotion (Medium & Hard, sync/async)
	var under_r_rules := GameRules.new()
	under_r_rules.clear_pieces()
	under_r_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	under_r_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("a5"))
	under_r_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("a4"))
	under_r_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("c7"))
	under_r_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("c6"))
	under_r_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e8"))
	under_r_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e9"))
	under_r_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	var ur_pawn := under_r_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("k6"))
	under_r_rules.current_turn = PieceData.Team.CYAN

	var k7_hex := GameRules.algebraic_to_axial("k7")
	var ur_base_mv := under_r_rules.get_legal_moves_for_piece(ur_pawn)[0]
	var q_stales := under_r_rules.clone_state()
	var q_mv := ur_base_mv.duplicate_move()
	q_mv.promotion_type = PieceData.Type.QUEEN
	q_stales.execute_move(q_mv)
	var b_stales := under_r_rules.clone_state()
	var b_mv := ur_base_mv.duplicate_move()
	b_mv.promotion_type = PieceData.Type.BISHOP
	b_stales.execute_move(b_mv)
	var r_lives := under_r_rules.clone_state()
	var r_mv := ur_base_mv.duplicate_move()
	r_mv.promotion_type = PieceData.Type.ROOK
	r_lives.execute_move(r_mv)
	_assert(
		q_stales.is_game_over and q_stales.status_text.begins_with("STALEMATE")
		and b_stales.is_game_over and b_stales.status_text.begins_with("STALEMATE")
		and not r_lives.is_game_over,
		"#45 setup: k6->k7=Q and =B stalemate Magenta on a6, while k6->k7=R keeps Magenta alive"
	)

	ai._rng.seed = 11
	var ur_med := ai.choose_move(under_r_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	ai._rng.seed = 11
	var ur_hard := ai.choose_move(under_r_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 11
	var ur_hard_async := await ai.choose_move_async(under_r_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		ur_med != null and ur_med.is_promotion and ur_med.to == k7_hex and ur_med.promotion_type == PieceData.Type.ROOK
		and ur_hard != null and ur_hard.is_promotion and ur_hard.to == k7_hex and ur_hard.promotion_type == PieceData.Type.ROOK
		and ur_hard_async != null and ur_hard_async.is_promotion and ur_hard_async.to == k7_hex and ur_hard_async.promotion_type == PieceData.Type.ROOK,
		"#45: Root anti-stalemate underpromotion selects k6->k7=R on Medium & Hard (sync/async)"
	)

	# 45c: Root =B anti-stalemate underpromotion (seed-robust across 20 seeds on Medium + async):
	# Knight on d6 covers a5; shade-2 Bishop on f2 pairs with g9->g10=B (+40 cp over =N > 25 cp jitter).
	var under_b_rules := GameRules.new()
	under_b_rules.clear_pieces()
	under_b_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	under_b_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b7"))
	under_b_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b6"))
	under_b_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b5"))
	under_b_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("b4"))
	under_b_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d6"))
	under_b_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f2"))
	under_b_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f1"))
	var ub_pawn := under_b_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("g9"))
	under_b_rules.current_turn = PieceData.Team.CYAN

	var g10_hex := GameRules.algebraic_to_axial("g10")
	var ub_base_mv := under_b_rules.get_legal_moves_for_piece(ub_pawn)[0]
	var ub_q := under_b_rules.clone_state()
	var ub_q_mv := ub_base_mv.duplicate_move()
	ub_q_mv.promotion_type = PieceData.Type.QUEEN
	ub_q.execute_move(ub_q_mv)
	var ub_r := under_b_rules.clone_state()
	var ub_r_mv := ub_base_mv.duplicate_move()
	ub_r_mv.promotion_type = PieceData.Type.ROOK
	ub_r.execute_move(ub_r_mv)
	var ub_b := under_b_rules.clone_state()
	var ub_b_mv := ub_base_mv.duplicate_move()
	ub_b_mv.promotion_type = PieceData.Type.BISHOP
	ub_b.execute_move(ub_b_mv)
	_assert(
		ub_q.is_game_over and ub_q.status_text.begins_with("STALEMATE")
		and ub_r.is_game_over and ub_r.status_text.begins_with("STALEMATE")
		and not ub_b.is_game_over,
		"#45 setup: g9->g10=Q and =R stalemate Magenta on a6, while g9->g10=B keeps Magenta alive"
	)
	var ub_all_seeds_ok := true
	for seed_val in range(1, 21):
		ai._rng.seed = seed_val
		var ub_med := ai.choose_move(under_b_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		if ub_med == null or not ub_med.is_promotion or ub_med.to != g10_hex or ub_med.promotion_type != PieceData.Type.BISHOP:
			ub_all_seeds_ok = false
			break
	ai._rng.seed = 47
	var ub_med_async := await ai.choose_move_async(under_b_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM, self)
	_assert(
		ub_all_seeds_ok
		and ub_med_async != null and ub_med_async.is_promotion and ub_med_async.to == g10_hex and ub_med_async.promotion_type == PieceData.Type.BISHOP,
		"#45: Root anti-stalemate underpromotion selects g9->g10=B across 20 seeds (Medium + async) when =Q and =R stalemate"
	)

	# 45d: Multi-ply =N tactical underpromotion (internal _negamax node)
	var mp_n_rules := GameRules.new()
	mp_n_rules.clear_pieces()
	mp_n_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("b1"))
	mp_n_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	mp_n_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("l5"))
	mp_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("i8"))
	for blk_alg in ["h9", "i7", "h7", "g8", "g9", "i6", "g7", "f9", "g10", "k6"]:
		mp_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial(blk_alg))
	var bait_rook_pos := GameRules.algebraic_to_axial("h6")
	mp_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, bait_rook_pos)
	mp_n_rules.current_turn = PieceData.Team.CYAN

	var l6_hex := GameRules.algebraic_to_axial("l6")
	var h8_hex := GameRules.algebraic_to_axial("h8")
	var f11_hex := GameRules.algebraic_to_axial("f11")

	ai._rng.seed = 21
	var mp_move1 := ai.choose_move(mp_n_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 21
	var mp_move1_async := await ai.choose_move_async(mp_n_rules, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	var mp_sim := mp_n_rules.clone_state()
	var mp_line_ok := false
	if mp_move1 != null and mp_move1.to == l6_hex and mp_sim.execute_move(mp_move1):
		var mag_forced := mp_sim.get_all_legal_moves(PieceData.Team.MAGENTA)
		if mag_forced.size() == 1 and mag_forced[0].to == h8_hex and mp_sim.execute_move(mag_forced[0]):
			var mp_move2 := ai.choose_move(mp_sim, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
			if (
				mp_move2 != null
				and mp_move2.is_promotion
				and mp_move2.to == f11_hex
				and mp_move2.promotion_type == PieceData.Type.KNIGHT
				and mp_sim.execute_move(mp_move2)
				and mp_sim.is_game_over
				and mp_sim.status_text.begins_with("CHECKMATE")
			):
				mp_line_ok = true
	_assert(
		mp_move1 != null
		and mp_move1_async != null
		and mp_move1.to == l6_hex
		and mp_move1_async.to == l6_hex
		and mp_line_ok,
		"#45: Hard AI (sync & async) sees internal ply-2 f10->f11=N# mate and plays R l5->l6+ over capturing free Rook on h6"
	)

	# 45e: Direct _quiescence() =N underpromotion test (detects smothered checkmate despite -2095 cp stand_pat)
	var q_n_rules := GameRules.new()
	q_n_rules.clear_pieces()
	q_n_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	q_n_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	q_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("d2"))
	var qn_mk := GameRules.algebraic_to_axial("h8")
	q_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, qn_mk)
	for d in GameRules.ORTHO_DIRS + GameRules.DIAG_DIRS:
		var adj: Vector2i = qn_mk + d
		if GameRules.is_inside_board(adj):
			q_n_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, adj)
	q_n_rules.current_turn = PieceData.Team.CYAN
	var q_n_score := ai._quiescence(q_n_rules, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.CYAN, 1, 3, AIPlayer.MAX_Q_CHECK_EXTENSIONS)
	_assert(
		not q_n_rules.is_king_in_check(PieceData.Team.CYAN)
		and AIPlayer.evaluate_board(q_n_rules, PieceData.Team.CYAN) < -1000
		and q_n_score == AIPlayer.MATE_SCORE - 40,
		"#45: _quiescence() expands =N underpromotion and finds smothered checkmate f10->f11=N# (score=%d)" % q_n_score
	)

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
	rules.clear_pieces()
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
	rules.clear_pieces()
	rules.move_history.clear()
	rules.current_turn = PieceData.Team.CYAN
	rules.is_game_over = false
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, f11)
	var e10 := GameRules.algebraic_to_axial("e10")
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, e10)
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
	rules.clear_pieces()
	rules.move_history.clear()
	rules.current_turn = PieceData.Team.CYAN
	rules.is_game_over = false
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l1"))
	rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, f10)
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
	_assert(
		main_a.issues_button != null and main_a.issues_button.get_index() < main_a.new_game_modal.get_index(),
		"IssuesButton precedes NewGameModal in Main scene tree so startup modal is never occluded"
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
		var issues_rect: Rect2 = main_a.issues_button.get_global_rect()
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
			and not banner_rect.intersects(issues_rect)
			and issues_rect.end.x < banner_rect.position.x
			and banner_clears_side,
			"%s: GpuWarningBanner (%s) clears IssuesButton (%s), TogglePanelButton (%s), and SidePanel in landscape" % [
				vp_name,
				str(banner_rect),
				str(issues_rect),
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


func _find_legal_move(rules: GameRules, from_alg: String, to_alg: String) -> GameRules.VectorMove:
	var from_hex := GameRules.algebraic_to_axial(from_alg)
	var to_hex := GameRules.algebraic_to_axial(to_alg)
	var piece := rules.get_piece_at(from_hex)
	if piece == null:
		return null
	for mv in rules.get_legal_moves_for_piece(piece):
		if mv.to == to_hex:
			return mv
	return null


func _test_draw_rules_and_ai_repetition_avoidance() -> void:
	print("\n-- Draw Rules & AI Repetition Avoidance (Issue #32) --")

	# ------------------------------------------------------------------
	# 1. Conservative insufficient-material detection (Glinski 3-shade hex board)
	# ------------------------------------------------------------------
	# Exact Issue #32 repro using pieces.clear() directly
	var kk_repro := GameRules.new()
	kk_repro.pieces.clear()
	kk_repro._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kk_repro._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kk_repro._update_game_status()
	_assert(
		kk_repro.is_insufficient_material()
		and kk_repro.is_game_over
		and kk_repro.status_text == "DRAW - Insufficient Material",
		"#32: Bare K vs K (pieces.clear() repro) triggers DRAW - Insufficient Material"
	)

	# K+B vs K -> insufficient
	var kb_k := GameRules.new()
	kb_k.clear_pieces()
	kb_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kb_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kb_k._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kb_k._update_game_status()
	_assert(
		kb_k.is_insufficient_material()
		and kb_k.is_game_over
		and kb_k.status_text == "DRAW - Insufficient Material",
		"#32: K+B vs K triggers DRAW - Insufficient Material"
	)

	# K+N vs K -> insufficient
	var kn_k := GameRules.new()
	kn_k.clear_pieces()
	kn_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kn_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d1"))
	kn_k._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kn_k._update_game_status()
	_assert(
		kn_k.is_insufficient_material()
		and kn_k.is_game_over
		and kn_k.status_text == "DRAW - Insufficient Material",
		"#32: K+N vs K triggers DRAW - Insufficient Material"
	)

	# K+B vs K+B on the same hex shade -> insufficient
	var kb_kb_same := GameRules.new()
	kb_kb_same.clear_pieces()
	var shade_f1 := GameRules.get_cell_color_index(GameRules.algebraic_to_axial("f1"))
	var shade_f4 := GameRules.get_cell_color_index(GameRules.algebraic_to_axial("f4"))
	kb_kb_same._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kb_kb_same._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kb_kb_same._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kb_kb_same._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f4"))
	kb_kb_same._update_game_status()
	_assert(
		shade_f1 == shade_f4
		and kb_kb_same.is_insufficient_material()
		and kb_kb_same.is_game_over
		and kb_kb_same.status_text == "DRAW - Insufficient Material",
		"#32: Same-shade K+B vs K+B triggers DRAW - Insufficient Material"
	)

	# K+B vs K+B on different hex shades -> NOT auto-draw
	var kb_kb_diff := GameRules.new()
	kb_kb_diff.clear_pieces()
	var shade_f2 := GameRules.get_cell_color_index(GameRules.algebraic_to_axial("f2"))
	kb_kb_diff._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kb_kb_diff._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kb_kb_diff._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kb_kb_diff._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f2"))
	kb_kb_diff._update_game_status()
	_assert(
		shade_f1 != shade_f2
		and not kb_kb_diff.is_insufficient_material()
		and not kb_kb_diff.is_game_over,
		"#32: Different-shade K+B vs K+B does NOT auto-draw"
	)

	# K+2B vs K -> NOT auto-draw
	var k2b_k := GameRules.new()
	k2b_k.clear_pieces()
	k2b_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	k2b_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	k2b_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f2"))
	k2b_k._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	k2b_k._update_game_status()
	_assert(
		not k2b_k.is_insufficient_material() and not k2b_k.is_game_over,
		"#32: K+2B vs K does NOT auto-draw"
	)

	# K+B+N vs K -> NOT auto-draw
	var kbn_k := GameRules.new()
	kbn_k.clear_pieces()
	kbn_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kbn_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kbn_k._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d1"))
	kbn_k._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kbn_k._update_game_status()
	_assert(
		not kbn_k.is_insufficient_material() and not kbn_k.is_game_over,
		"#32: K+B+N vs K does NOT auto-draw"
	)

	# Capture into K vs K triggers insufficient-material draw; undo cleanly rolls back
	# f5 -> e6 is a diagonal King capture; Rook on e6 does not check f5.
	var cap_insuff := GameRules.new()
	cap_insuff.clear_pieces()
	cap_insuff._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f5"))
	cap_insuff._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	cap_insuff._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	cap_insuff.current_turn = PieceData.Team.CYAN
	cap_insuff._update_game_status()
	var cap_mv := _find_legal_move(cap_insuff, "f5", "e6")
	var cap_ok := cap_mv != null and cap_insuff.execute_move(cap_mv)
	var cap_drew := cap_insuff.is_game_over and cap_insuff.status_text == "DRAW - Insufficient Material"
	var cap_undo_ok := cap_insuff.undo_last_move()
	_assert(
		cap_ok
		and cap_drew
		and cap_undo_ok
		and not cap_insuff.is_game_over
		and cap_insuff.status_text == "Cyan's Turn"
		and cap_insuff.pieces.size() == 3,
		"#32: Capturing last Rook into K vs K draws immediately and undo_last_move() restores live game"
	)

	# Stalemate takes precedence over insufficient material (Glinski 0.75 : 0.25)
	var stale_over_insuff := GameRules.new()
	stale_over_insuff.clear_pieces()
	stale_over_insuff._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	stale_over_insuff._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	stale_over_insuff.current_turn = PieceData.Team.CYAN
	var stale_mv := _find_legal_move(stale_over_insuff, "c5", "c6")
	var stale_exec := stale_mv != null and stale_over_insuff.execute_move(stale_mv)
	_assert(
		stale_exec
		and stale_over_insuff.is_game_over
		and stale_over_insuff.status_text == "STALEMATE - Cyan 0.75 : 0.25 Magenta",
		"#32: Glinski stalemate (0.75 : 0.25) takes precedence over insufficient material"
	)

	# ------------------------------------------------------------------
	# 2. Zobrist position key (turn sensitivity & legal en-passant nuance)
	# ------------------------------------------------------------------
	var key_rules := GameRules.new()
	var key_cyan := key_rules.get_position_key()
	key_rules.current_turn = PieceData.Team.MAGENTA
	var key_magenta := key_rules.get_position_key()
	_assert(
		key_cyan != key_magenta,
		"#32: Zobrist position key distinguishes side-to-move (Cyan vs Magenta)"
	)

	# 2a: Double-step with NO enemy pawn able to capture en passant -> same key as no-EP
	var ep_no_cap := GameRules.new()
	ep_no_cap.clear_pieces()
	ep_no_cap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	ep_no_cap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	ep_no_cap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	ep_no_cap.current_turn = PieceData.Team.CYAN
	var ep_ds_mv := _find_legal_move(ep_no_cap, "e4", "e6")
	var ep_ds_ok := ep_ds_mv != null and ep_ds_mv.is_double_step and ep_no_cap.execute_move(ep_ds_mv)
	var key_with_unused_ep := ep_no_cap.get_position_key()
	var ep_no_cap_ref := ep_no_cap.clone_state()
	ep_no_cap_ref.en_passant_target = GameRules.INVALID_HEX
	ep_no_cap_ref.en_passant_pawn_id = -1
	_assert(
		ep_ds_ok
		and ep_no_cap.en_passant_target == GameRules.algebraic_to_axial("e5")
		and key_with_unused_ep == ep_no_cap_ref.get_position_key(),
		"#32: Position key ignores en_passant_target when no opposing pawn can capture en passant"
	)

	# 2b: Double-step WITH legal enemy en-passant capturer -> distinct key
	var ep_legal := GameRules.new()
	ep_legal.clear_pieces()
	ep_legal._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	ep_legal._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	ep_legal._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	ep_legal._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	ep_legal.current_turn = PieceData.Team.CYAN
	var ep_legal_mv := _find_legal_move(ep_legal, "e4", "e6")
	var ep_legal_ok := ep_legal_mv != null and ep_legal.execute_move(ep_legal_mv)
	var key_with_legal_ep := ep_legal.get_position_key()
	var ep_legal_ref := ep_legal.clone_state()
	ep_legal_ref.en_passant_target = GameRules.INVALID_HEX
	ep_legal_ref.en_passant_pawn_id = -1
	_assert(
		ep_legal_ok and key_with_legal_ep != ep_legal_ref.get_position_key(),
		"#32: Position key includes en_passant_target when an opposing pawn can legally capture en passant"
	)

	# 2c: Double-step where opposing pawn is pinned to its King -> ignored in position key
	var ep_pinned := GameRules.new()
	ep_pinned.clear_pieces()
	ep_pinned._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	ep_pinned._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f1"))
	ep_pinned._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	ep_pinned._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	ep_pinned._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	ep_pinned.current_turn = PieceData.Team.CYAN
	var ep_pinned_mv := _find_legal_move(ep_pinned, "e4", "e6")
	var ep_pinned_ok := ep_pinned_mv != null and ep_pinned.execute_move(ep_pinned_mv)
	var key_with_pinned_ep := ep_pinned.get_position_key()
	var ep_pinned_ref := ep_pinned.clone_state()
	ep_pinned_ref.en_passant_target = GameRules.INVALID_HEX
	ep_pinned_ref.en_passant_pawn_id = -1
	_assert(
		ep_pinned_ok and key_with_pinned_ep == ep_pinned_ref.get_position_key(),
		"#32: Position key ignores en_passant_target when the only candidate capturer is pinned to its King"
	)

	# ------------------------------------------------------------------
	# 3. Threefold repetition & undo rollback
	# ------------------------------------------------------------------
	var rep_rules := GameRules.new()
	_assert(
		rep_rules.get_repetition_count() == 1 and not rep_rules.is_threefold_repetition(),
		"#32: Fresh game starts with repetition count 1"
	)
	var rep_seq := [
		["d1", "c3"], ["d9", "f8"], ["c3", "d1"], ["f8", "d9"],
		["d1", "c3"], ["d9", "f8"], ["c3", "d1"], ["f8", "d9"],
	]
	var rep_seq_ok := true
	var count_after_4 := -1
	var game_over_after_4 := true
	for i in range(rep_seq.size()):
		var mv := _find_legal_move(rep_rules, rep_seq[i][0], rep_seq[i][1])
		if mv == null or not rep_rules.execute_move(mv):
			rep_seq_ok = false
			break
		if i == 3:
			count_after_4 = rep_rules.get_repetition_count()
			game_over_after_4 = rep_rules.is_game_over
	_assert(
		rep_seq_ok
		and count_after_4 == 2
		and not game_over_after_4
		and rep_rules.get_repetition_count() == 3
		and rep_rules.is_threefold_repetition()
		and rep_rules.is_game_over
		and rep_rules.status_text == "DRAW - Threefold Repetition",
		"#32: Twofold repetition continues play; threefold repetition triggers DRAW - Threefold Repetition"
	)

	var rep_undo1 := rep_rules.undo_last_move()
	var after_undo1_ok := (
		rep_undo1
		and not rep_rules.is_game_over
		and not rep_rules.is_threefold_repetition()
		and rep_rules.status_text == "Magenta's Turn"
		and rep_rules.halfmove_clock == 7
	)
	var replay_mv := _find_legal_move(rep_rules, "f8", "d9")
	var replay_ok := replay_mv != null and rep_rules.execute_move(replay_mv)
	var replay_drew := rep_rules.is_game_over and rep_rules.status_text == "DRAW - Threefold Repetition"
	while rep_rules.undo_last_move():
		pass
	_assert(
		after_undo1_ok
		and replay_ok
		and replay_drew
		and rep_rules.move_history.is_empty()
		and rep_rules._position_history.size() == 1
		and rep_rules.get_repetition_count() == 1
		and rep_rules.halfmove_clock == 0,
		"#32: Threefold repetition undo rolls back cleanly, re-triggers on replay, and full undo restores count=1"
	)

	# ------------------------------------------------------------------
	# 4. 50-move rule, clock resets, undo rollback & checkmate precedence
	# ------------------------------------------------------------------
	var clock_rules := GameRules.new()
	var c_mv1 := _find_legal_move(clock_rules, "d1", "c3")
	var c_ok1 := c_mv1 != null and clock_rules.execute_move(c_mv1)
	var clock_after_quiet := clock_rules.halfmove_clock
	var c_mv2 := _find_legal_move(clock_rules, "f7", "f6")
	var c_ok2 := c_mv2 != null and clock_rules.execute_move(c_mv2)
	var clock_after_pawn := clock_rules.halfmove_clock
	var c_undo_pawn := clock_rules.undo_last_move()
	var clock_after_undo_pawn := clock_rules.halfmove_clock
	_assert(
		c_ok1 and c_ok2 and c_undo_pawn
		and clock_after_quiet == 1
		and clock_after_pawn == 0
		and clock_after_undo_pawn == 1,
		"#32: halfmove_clock increments on quiet move, resets to 0 on pawn move, and restores on undo"
	)

	# Capture resets halfmove_clock and undo restores prior value
	var cap_clock := GameRules.new()
	cap_clock.clear_pieces()
	cap_clock._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	cap_clock._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f4"))
	cap_clock._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f6"))
	cap_clock._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	cap_clock.current_turn = PieceData.Team.CYAN
	cap_clock.halfmove_clock = 42
	var cap_clk_mv := _find_legal_move(cap_clock, "f4", "f6")
	var cap_clk_ok := cap_clk_mv != null and cap_clock.execute_move(cap_clk_mv)
	var cap_clk_zero := cap_clock.halfmove_clock == 0
	var cap_clk_undo := cap_clock.undo_last_move()
	_assert(
		cap_clk_ok and cap_clk_zero and cap_clk_undo and cap_clock.halfmove_clock == 42,
		"#32: Capture resets halfmove_clock to 0 and undo restores previous clock (42)"
	)

	# halfmove_clock == 99 + quiet move -> DRAW - 50-Move Rule, undo restores 99
	var fifty_rules := GameRules.new()
	fifty_rules.clear_pieces()
	fifty_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	fifty_rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	fifty_rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	fifty_rules.current_turn = PieceData.Team.CYAN
	fifty_rules.halfmove_clock = 99
	fifty_rules._update_game_status()
	var pre_fifty_live := not fifty_rules.is_game_over and not fifty_rules.is_fifty_move_draw()
	var fifty_mv := _find_legal_move(fifty_rules, "c1", "c2")
	var fifty_exec := fifty_mv != null and fifty_rules.execute_move(fifty_mv)
	var fifty_drew := (
		fifty_rules.halfmove_clock == 100
		and fifty_rules.is_fifty_move_draw()
		and fifty_rules.is_game_over
		and fifty_rules.status_text == "DRAW - 50-Move Rule"
	)
	var fifty_undo := fifty_rules.undo_last_move()
	_assert(
		pre_fifty_live
		and fifty_exec
		and fifty_drew
		and fifty_undo
		and fifty_rules.halfmove_clock == 99
		and not fifty_rules.is_game_over
		and fifty_rules.status_text == "Cyan's Turn",
		"#32: 100th half-move triggers DRAW - 50-Move Rule and undo_last_move() restores halfmove_clock=99"
	)

	# Checkmate on halfmove 100 takes precedence over 50-move draw
	var mate100 := GameRules.new()
	mate100.clear_pieces()
	mate100._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	mate100._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("d7"))
	mate100._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("b1"))
	mate100._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("d3"))
	mate100.current_turn = PieceData.Team.CYAN
	mate100.halfmove_clock = 99
	var mate100_mv := _find_legal_move(mate100, "d3", "a3")
	var mate100_ok := mate100_mv != null and mate100.execute_move(mate100_mv)
	_assert(
		mate100_ok
		and mate100.halfmove_clock == 100
		and mate100.is_game_over
		and mate100.status_text == "CHECKMATE - Cyan Wins!",
		"#32: Checkmate on halfmove 100 takes precedence over 50-move draw"
	)

	# ------------------------------------------------------------------
	# 5. State sync across clone_state(), push/pop_search_move(), reset_game()
	# ------------------------------------------------------------------
	var sync_rules := GameRules.new()
	var sync_m1 := _find_legal_move(sync_rules, "d1", "c3")
	var sync_m2 := _find_legal_move(sync_rules, "d9", "f8")
	var sync_setup_ok := (
		sync_m1 != null and sync_rules.execute_move(sync_m1)
		and sync_m2 != null and sync_rules.execute_move(sync_m2)
	)
	var sync_clone := sync_rules.clone_state()
	var clone_matches := (
		sync_setup_ok
		and sync_clone.halfmove_clock == sync_rules.halfmove_clock
		and sync_clone.get_position_key() == sync_rules.get_position_key()
		and sync_clone.get_repetition_count() == sync_rules.get_repetition_count()
		and sync_clone._position_history == sync_rules._position_history
	)
	var pre_push_key := sync_clone.get_position_key()
	var pre_push_clock := sync_clone.halfmove_clock
	var pre_push_hist := sync_clone._position_history.duplicate()
	var push_mv := _find_legal_move(sync_clone, "c3", "d1")
	var undo_rec := sync_clone.push_search_move(push_mv)
	var mid_push_ok := (
		sync_clone.halfmove_clock == pre_push_clock + 1
		and sync_clone._position_history.size() == pre_push_hist.size() + 1
		and sync_clone.get_position_key() != pre_push_key
	)
	sync_clone.pop_search_move(undo_rec)
	var post_pop_ok := (
		sync_clone.halfmove_clock == pre_push_clock
		and sync_clone.get_position_key() == pre_push_key
		and sync_clone._position_history == pre_push_hist
		and sync_rules.halfmove_clock == 2
		and sync_rules._position_history.size() == 3
	)
	sync_rules.reset_game()
	var post_reset_ok := (
		sync_rules.halfmove_clock == 0
		and sync_rules._position_history.size() == 1
		and sync_rules.get_repetition_count() == 1
		and not sync_rules.is_game_over
	)
	_assert(
		clone_matches and mid_push_ok and post_pop_ok and post_reset_ok,
		"#32: clone_state(), push/pop_search_move(), and reset_game() keep halfmove_clock and Zobrist history synchronized"
	)

	# ------------------------------------------------------------------
	# 6. AI repetition avoidance & draw seeking
	# ------------------------------------------------------------------
	var ai := AIPlayer.new()

	# 6a: Winning AI avoids both 2-fold shuffling loops and immediate 3-fold draws
	var win_rep := GameRules.new()
	win_rep.clear_pieces()
	win_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	win_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f6"))
	win_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l4"))
	win_rep.current_turn = PieceData.Team.MAGENTA
	var f6_hex := GameRules.algebraic_to_axial("f6")

	# Play 3 half-moves so Cyan moving Q f5->f6 triggers 2-fold (and Magenta l4->l3 triggers ply-2 draw)
	var win_setup_2fold := [["l4", "l3"], ["f6", "f5"], ["l3", "l4"]]
	var win_2fold_setup_ok := true
	for step in win_setup_2fold:
		var step_mv := _find_legal_move(win_rep, step[0], step[1])
		if step_mv == null or not win_rep.execute_move(step_mv):
			win_2fold_setup_ok = false
			break

	var win_avoids_2fold := win_2fold_setup_ok
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var m_mv := ai.choose_move(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		if m_mv == null or m_mv.to == f6_hex:
			win_avoids_2fold = false
			break
	ai._rng.seed = 7
	var win_h2 := ai.choose_move(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 7
	var win_h2_async := await ai.choose_move_async(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		win_avoids_2fold
		and win_h2 != null and win_h2.to != f6_hex
		and win_h2_async != null and win_h2_async.to != f6_hex,
		"#32: Winning AI breaks 2-fold shuffling loop (avoids Q f5->f6) on Medium (10 seeds) & Hard (sync/async)"
	)

	# Complete 1 more cycle so Q f5->f6 is an IMMEDIATE 3-fold repetition
	var win_setup_3fold := [["f5", "f6"], ["l4", "l3"], ["f6", "f5"], ["l3", "l4"]]
	var win_3fold_setup_ok := true
	for step in win_setup_3fold:
		var step_mv := _find_legal_move(win_rep, step[0], step[1])
		if step_mv == null or not win_rep.execute_move(step_mv):
			win_3fold_setup_ok = false
			break
	var win_3fold_check := win_rep.clone_state()
	var win_3fold_mv := _find_legal_move(win_3fold_check, "f5", "f6")
	var win_avoids_3fold := (
		win_3fold_setup_ok
		and win_3fold_mv != null
		and win_3fold_check.execute_move(win_3fold_mv)
		and win_3fold_check.is_game_over
		and win_3fold_check.status_text == "DRAW - Threefold Repetition"
	)
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var m_mv := ai.choose_move(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		if m_mv == null or m_mv.to == f6_hex:
			win_avoids_3fold = false
			break
	ai._rng.seed = 9
	var win_h3 := ai.choose_move(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 9
	var win_h3_async := await ai.choose_move_async(win_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		win_avoids_3fold
		and win_h3 != null and win_h3.to != f6_hex
		and win_h3_async != null and win_h3_async.to != f6_hex,
		"#32: Winning AI avoids immediate 3-fold repetition Q f5->f6 on Medium (10 seeds) & Hard (sync/async)"
	)

	# 6b: Losing AI claims immediate threefold repetition (Easy, Medium, Hard 10 seeds + async)
	var lose_rep := GameRules.new()
	lose_rep.clear_pieces()
	lose_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	lose_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l4"))
	lose_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f5"))
	lose_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("l1"))
	lose_rep.current_turn = PieceData.Team.MAGENTA
	var a1_hex := GameRules.algebraic_to_axial("a1")
	var lose_steps := [
		["l4", "l3"], ["a1", "a2"], ["l3", "l4"], ["a2", "a1"],
		["l4", "l3"], ["a1", "a2"], ["l3", "l4"],
	]
	var lose_setup_ok := true
	for step in lose_steps:
		var step_mv := _find_legal_move(lose_rep, step[0], step[1])
		if step_mv == null or not lose_rep.execute_move(step_mv):
			lose_setup_ok = false
			break
	var lose_claims_ok := lose_setup_ok and AIPlayer.evaluate_board(lose_rep, PieceData.Team.CYAN) < -1000
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var le := ai.choose_move(lose_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY)
		ai._rng.seed = seed_val
		var lm := ai.choose_move(lose_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		ai._rng.seed = seed_val
		var lh := ai.choose_move(lose_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
		if (
			le == null or le.to != a1_hex
			or lm == null or lm.to != a1_hex
			or lh == null or lh.to != a1_hex
		):
			lose_claims_ok = false
			break
	ai._rng.seed = 4
	var lh_async := await ai.choose_move_async(lose_rep, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		lose_claims_ok and lh_async != null and lh_async.to == a1_hex,
		"#32: Losing AI claims immediate threefold repetition (K a2->a1) across Easy, Medium & Hard (10 seeds + async)"
	)

	# 6c: Losing AI must NOT treat a non-terminal 2-fold repetition at ply 1 as a draw when opponent has Mate-in-1
	var mate_trap := GameRules.new()
	mate_trap.clear_pieces()
	mate_trap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	mate_trap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c2"))
	mate_trap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("d7"))
	mate_trap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("b1"))
	mate_trap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("d3"))
	mate_trap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("i4"))
	mate_trap.current_turn = PieceData.Team.MAGENTA
	mate_trap.execute_move(_find_legal_move(mate_trap, "i4", "i5"))
	mate_trap.execute_move(_find_legal_move(mate_trap, "c2", "c3"))
	mate_trap.execute_move(_find_legal_move(mate_trap, "i5", "i4"))
	var c2_hex := GameRules.algebraic_to_axial("c2")
	# Confirm c3->c2 creates count==2 (not 3) and allows Magenta d3->a3# mate-in-1
	var trap_verify := mate_trap.clone_state()
	trap_verify.execute_move(_find_legal_move(trap_verify, "c3", "c2"))
	var trap_rep2 := trap_verify.get_repetition_count() == 2 and not trap_verify.is_game_over
	trap_verify.execute_move(_find_legal_move(trap_verify, "d3", "a3"))
	var trap_mates := trap_verify.is_game_over and trap_verify.status_text == "CHECKMATE - Magenta Wins!"
	ai._rng.seed = 12
	var trap_med := ai.choose_move(mate_trap, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	ai._rng.seed = 12
	var trap_hard := ai.choose_move(mate_trap, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	_assert(
		trap_rep2
		and trap_mates
		and trap_med != null and trap_med.to != c2_hex
		and trap_hard != null and trap_hard.to != c2_hex,
		"#32: Losing AI rejects non-terminal 2-fold move (R c3->c2) that walks into opponent Mate-in-1 (R d3->a3#)"
	)

	# 6d: Winning AI at halfmove_clock == 99 pushes pawn to reset 50-move clock instead of drawing
	var clock_ai := GameRules.new()
	clock_ai.clear_pieces()
	clock_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	clock_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("e3"))
	var clock_pawn := clock_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	clock_ai._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	clock_ai.current_turn = PieceData.Team.CYAN
	clock_ai.halfmove_clock = 99
	var f7_push := GameRules.algebraic_to_axial("f7")
	var clock_ai_ok := true
	for seed_val in range(1, 11):
		ai._rng.seed = seed_val
		var cm := ai.choose_move(clock_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
		if cm == null or cm.piece_id != clock_pawn.id or cm.to != f7_push:
			clock_ai_ok = false
			break
	ai._rng.seed = 5
	var ch := ai.choose_move(clock_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 5
	var ch_async := await ai.choose_move_async(clock_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		clock_ai_ok
		and ch != null and ch.piece_id == clock_pawn.id and ch.to == f7_push
		and ch_async != null and ch_async.piece_id == clock_pawn.id and ch_async.to == f7_push,
		"#32: Winning AI at halfmove_clock=99 pushes pawn f6->f7 to reset clock instead of drawing on 50-move rule"
	)

	# ------------------------------------------------------------------
	# 6e. Critique edge cases: clear_pieces(), insufficient material, mid-search Zobrist, EP threefold & AI draws
	# ------------------------------------------------------------------
	# clear_pieces() resets move_history, is_game_over, last_move, status_text & get_repetition_count() parity
	var clr_test := GameRules.new()
	clr_test.clear_pieces()
	clr_test._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f5"))
	clr_test._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	clr_test._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	clr_test.execute_move(_find_legal_move(clr_test, "f5", "e6"))
	var clr_was_over := clr_test.is_game_over and clr_test.move_history.size() == 1
	clr_test.clear_pieces()
	var clr_reset_ok := (
		clr_test.pieces.is_empty()
		and clr_test.move_history.is_empty()
		and not clr_test.is_game_over
		and clr_test.last_move == null
		and clr_test.status_text == "Cyan's Turn"
		and clr_test.halfmove_clock == 0
		and clr_test._position_history.is_empty()
	)
	clr_test._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	clr_test._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	clr_test._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	var clr_rep_parity := (
		clr_test.get_repetition_count() == 1
		and clr_test.get_repetition_count() == clr_test.clone_state().get_repetition_count()
	)
	_assert(
		clr_was_over and clr_reset_ok and clr_rep_parity,
		"#32: clear_pieces() resets move_history/game-over/status cleanly and get_repetition_count() matches clone_state() on custom setups"
	)

	# Additional insufficient-material negative cases (K+2N, K+N vs K+N, K+B vs K+N, same-shade K+2B, off-board King)
	var k2n := GameRules.new()
	k2n.clear_pieces()
	k2n._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	k2n._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d1"))
	k2n._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("h1"))
	k2n._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))

	var kn_kn := GameRules.new()
	kn_kn.clear_pieces()
	kn_kn._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kn_kn._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d1"))
	kn_kn._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kn_kn._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d9"))

	var kb_kn := GameRules.new()
	kb_kn.clear_pieces()
	kb_kn._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kb_kn._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kb_kn._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kb_kn._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KNIGHT, GameRules.algebraic_to_axial("d9"))

	var k2b_same_side := GameRules.new()
	k2b_same_side.clear_pieces()
	k2b_same_side._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	k2b_same_side._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	k2b_same_side._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f4"))
	k2b_same_side._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))

	var offboard_king := GameRules.new()
	offboard_king.clear_pieces()
	offboard_king._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	offboard_king._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.INVALID_HEX)
	_assert(
		not k2n.is_insufficient_material()
		and not kn_kn.is_insufficient_material()
		and not kb_kn.is_insufficient_material()
		and not k2b_same_side.is_insufficient_material()
		and not offboard_king.is_insufficient_material(),
		"#32: K+2N, K+N vs K+N, K+B vs K+N, same-shade K+2B vs K, and off-board King do NOT trigger insufficient material"
	)

	# Underpromoting K+P vs K to =B or =N triggers DRAW - Insufficient Material; =Q stays live
	var up_base := GameRules.new()
	up_base.clear_pieces()
	up_base._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	up_base._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	up_base._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	var up_mv_base := _find_legal_move(up_base, "f10", "f11")
	var up_b := up_base.clone_state()
	var up_b_mv := up_mv_base.duplicate_move()
	up_b_mv.promotion_type = PieceData.Type.BISHOP
	up_b.execute_move(up_b_mv)
	var up_n := up_base.clone_state()
	var up_n_mv := up_mv_base.duplicate_move()
	up_n_mv.promotion_type = PieceData.Type.KNIGHT
	up_n.execute_move(up_n_mv)
	var up_q := up_base.clone_state()
	var up_q_mv := up_mv_base.duplicate_move()
	up_q_mv.promotion_type = PieceData.Type.QUEEN
	up_q.execute_move(up_q_mv)
	_assert(
		up_b.is_game_over and up_b.status_text == "DRAW - Insufficient Material"
		and up_n.is_game_over and up_n.status_text == "DRAW - Insufficient Material"
		and not up_q.is_game_over,
		"#32: Underpromoting K+P vs K to =B or =N draws by insufficient material while =Q stays live"
	)

	# En-passant Zobrist: two candidate capturers (one pinned, one legal) still hashes EP target
	var ep_two := GameRules.new()
	ep_two.clear_pieces()
	ep_two._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	ep_two._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f1"))
	ep_two._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("f11"))
	ep_two._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	ep_two._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	ep_two._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("d5"))
	ep_two.current_turn = PieceData.Team.CYAN
	var ep_two_ok := ep_two.execute_move(_find_legal_move(ep_two, "e4", "e6"))
	var ep_two_ref := ep_two.clone_state()
	ep_two_ref.en_passant_target = GameRules.INVALID_HEX
	ep_two_ref.en_passant_pawn_id = -1
	_assert(
		ep_two_ok and ep_two.get_position_key() != ep_two_ref.get_position_key(),
		"#32: Position key still includes en_passant_target when one capturer (f6) is pinned but the other (d5) is legal"
	)

	# Threefold repetition with en-passant distinction: 1st occurrence has legal EP, so draw requires 4th board appearance
	var ep_rep := GameRules.new()
	ep_rep.clear_pieces()
	ep_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	ep_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	ep_rep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	ep_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	ep_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c8"))
	ep_rep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	ep_rep.current_turn = PieceData.Team.CYAN
	var ep_rep_ok := ep_rep.execute_move(_find_legal_move(ep_rep, "e4", "e6"))
	var ep_cycle_1 := [["c8", "c7"], ["c1", "c2"], ["c7", "c8"], ["c2", "c1"]]
	var ep_cycle_2 := [["c8", "c6"], ["c1", "c3"], ["c6", "c8"], ["c3", "c1"]]
	var ep_cycle_3 := [["c8", "c5"], ["c1", "c4"], ["c5", "c8"], ["c4", "c1"]]
	for step in ep_cycle_1:
		ep_rep_ok = ep_rep_ok and ep_rep.execute_move(_find_legal_move(ep_rep, step[0], step[1]))
	var ep_rep_after_2nd_board := ep_rep.get_repetition_count()
	for step in ep_cycle_2:
		ep_rep_ok = ep_rep_ok and ep_rep.execute_move(_find_legal_move(ep_rep, step[0], step[1]))
	var ep_rep_after_3rd_board := ep_rep.get_repetition_count()
	var ep_rep_live_at_3rd := not ep_rep.is_game_over
	for step in ep_cycle_3:
		ep_rep_ok = ep_rep_ok and ep_rep.execute_move(_find_legal_move(ep_rep, step[0], step[1]))
	_assert(
		ep_rep_ok
		and ep_rep_after_2nd_board == 1
		and ep_rep_after_3rd_board == 2
		and ep_rep_live_at_3rd
		and ep_rep.get_repetition_count() == 3
		and ep_rep.is_game_over
		and ep_rep.status_text == "DRAW - Threefold Repetition",
		"#32: Threefold repetition distinguishes legal-EP 1st occurrence (draws on 4th board appearance, not 3rd)"
	)

	# Mid-search (_search_depth > 0) incremental Zobrist hash parity & halfmove_clock resets on capture, EP, quiet promo, capture promo
	var z_cap := GameRules.new()
	z_cap.clear_pieces()
	z_cap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	z_cap._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f4"))
	z_cap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f6"))
	z_cap._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	z_cap.halfmove_clock = 17
	var z_cap_pre := z_cap.get_position_key()
	var z_cap_u := z_cap.push_search_move(_find_legal_move(z_cap, "f4", "f6"))
	var z_cap_parity := z_cap.halfmove_clock == 0 and z_cap.get_position_key() == z_cap.clone_state().get_position_key()
	z_cap.pop_search_move(z_cap_u)
	var z_cap_pop := z_cap.halfmove_clock == 17 and z_cap.get_position_key() == z_cap_pre

	var z_ep := GameRules.new()
	z_ep.clear_pieces()
	z_ep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	z_ep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	z_ep._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e4"))
	z_ep._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	z_ep.execute_move(_find_legal_move(z_ep, "e4", "e6"))
	z_ep.halfmove_clock = 15
	var z_ep_pre := z_ep.get_position_key()
	var z_ep_mv := _find_legal_move(z_ep, "f6", "e5")
	var z_ep_u := z_ep.push_search_move(z_ep_mv)
	var z_ep_parity := z_ep_mv.is_en_passant and z_ep.halfmove_clock == 0 and z_ep.get_position_key() == z_ep.clone_state().get_position_key()
	z_ep.pop_search_move(z_ep_u)
	var z_ep_pop := z_ep.halfmove_clock == 15 and z_ep.get_position_key() == z_ep_pre
	var z_ep_exec_ok := z_ep.execute_move(z_ep_mv) and z_ep.halfmove_clock == 0

	var z_qpromo := GameRules.new()
	z_qpromo.clear_pieces()
	z_qpromo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	z_qpromo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f10"))
	z_qpromo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	z_qpromo.halfmove_clock = 23
	var z_qp_pre := z_qpromo.get_position_key()
	var z_qp_mv := _find_legal_move(z_qpromo, "f10", "f11").duplicate_move()
	z_qp_mv.promotion_type = PieceData.Type.QUEEN
	var z_qp_u := z_qpromo.push_search_move(z_qp_mv)
	var z_qp_parity := z_qpromo.halfmove_clock == 0 and z_qpromo.get_position_key() == z_qpromo.clone_state().get_position_key()
	z_qpromo.pop_search_move(z_qp_u)
	var z_qp_pop := z_qpromo.halfmove_clock == 23 and z_qpromo.get_position_key() == z_qp_pre
	var z_qp_exec_ok := z_qpromo.execute_move(z_qp_mv) and z_qpromo.halfmove_clock == 0

	var z_cpromo := GameRules.new()
	z_cpromo.clear_pieces()
	z_cpromo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	z_cpromo._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("e10"))
	z_cpromo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("f11"))
	z_cpromo._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	z_cpromo.halfmove_clock = 31
	var z_cp_pre := z_cpromo.get_position_key()
	var z_cp_mv := _find_legal_move(z_cpromo, "e10", "f11").duplicate_move()
	z_cp_mv.promotion_type = PieceData.Type.KNIGHT
	var z_cp_u := z_cpromo.push_search_move(z_cp_mv)
	var z_cp_parity := z_cpromo.halfmove_clock == 0 and z_cpromo.get_position_key() == z_cpromo.clone_state().get_position_key()
	z_cpromo.pop_search_move(z_cp_u)
	var z_cp_pop := z_cpromo.halfmove_clock == 31 and z_cpromo.get_position_key() == z_cp_pre
	_assert(
		z_cap_parity and z_cap_pop
		and z_ep_parity and z_ep_pop and z_ep_exec_ok
		and z_qp_parity and z_qp_pop and z_qp_exec_ok
		and z_cp_parity and z_cp_pop,
		"#32: Mid-search incremental Zobrist hash & halfmove_clock stay exact across capture, en passant, quiet promo, and capture promo"
	)

	# push_search_move() seeded_root rollback on both empty (clear_pieces) and stale (pieces.clear) initial history
	var sr_empty := GameRules.new()
	sr_empty.clear_pieces()
	sr_empty._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	sr_empty._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	sr_empty._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	var sr_e_u := sr_empty.push_search_move(_find_legal_move(sr_empty, "c1", "c2"))
	var sr_e_mid := sr_empty._position_history.size() == 2
	sr_empty.pop_search_move(sr_e_u)
	var sr_e_end := sr_empty._position_history.is_empty() and sr_empty._position_counts.is_empty()

	var sr_stale := GameRules.new()
	var sr_stale_orig_key: int = sr_stale._position_history[0]
	sr_stale.pieces.clear()
	sr_stale._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	sr_stale._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("c1"))
	sr_stale._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	var sr_s_u := sr_stale.push_search_move(_find_legal_move(sr_stale, "c1", "c2"))
	var sr_s_mid := sr_stale._position_history.size() == 2 and sr_stale._position_history[0] != sr_stale_orig_key
	sr_stale.pop_search_move(sr_s_u)
	var sr_s_end := sr_stale._position_history.size() == 1 and sr_stale._position_history[0] == sr_stale_orig_key
	_assert(
		sr_e_mid and sr_e_end and sr_s_mid and sr_s_end,
		"#32: push_search_move()/pop_search_move() seeded_root cleanly rolls back both empty and stale initial histories"
	)

	# Stalemate on halfmove 100 takes precedence over 50-move draw
	var stale100 := GameRules.new()
	stale100.clear_pieces()
	stale100._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	stale100._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("c5"))
	stale100._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f5"))
	stale100.current_turn = PieceData.Team.CYAN
	stale100.halfmove_clock = 99
	var stale100_ok := stale100.execute_move(_find_legal_move(stale100, "c5", "c6"))
	_assert(
		stale100_ok
		and stale100.halfmove_clock == 100
		and stale100.is_game_over
		and stale100.status_text == "STALEMATE - Cyan 0.75 : 0.25 Magenta",
		"#32: Glinski stalemate on halfmove 100 takes precedence over 50-move draw"
	)

	# Direct _negamax() and _quiescence() score K+B vs K as 0 despite >+300 cp static material eval
	var kb_search := GameRules.new()
	kb_search.clear_pieces()
	kb_search._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("g1"))
	kb_search._spawn_piece(PieceData.Team.CYAN, PieceData.Type.BISHOP, GameRules.algebraic_to_axial("f1"))
	kb_search._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("g10"))
	kb_search.current_turn = PieceData.Team.CYAN
	var kb_static := AIPlayer.evaluate_board(kb_search, PieceData.Team.CYAN)
	var kb_nega := ai._negamax(kb_search, 1, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.CYAN, 1, false)
	var kb_quiesce := ai._quiescence(kb_search, -AIPlayer.INF_SCORE, AIPlayer.INF_SCORE, PieceData.Team.CYAN, 1, 1)
	_assert(
		kb_static > 300 and kb_nega == 0 and kb_quiesce == 0,
		"#32: _negamax() and _quiescence() score K+B vs K as 0 draw despite +%d cp static eval" % kb_static
	)

	# Winning AI prefers quiet Mate-in-1 on halfmove 100 over resetting clock with a pawn push
	var m100_ai := GameRules.new()
	m100_ai.clear_pieces()
	m100_ai._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	m100_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("d7"))
	m100_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("b1"))
	m100_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.ROOK, GameRules.algebraic_to_axial("d3"))
	m100_ai._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	m100_ai.current_turn = PieceData.Team.CYAN
	m100_ai.halfmove_clock = 99
	ai._rng.seed = 3
	var m100_med := ai.choose_move(m100_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	ai._rng.seed = 3
	var m100_hard := ai.choose_move(m100_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 3
	var m100_async := await ai.choose_move_async(m100_ai, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	var m100_all_mate := true
	for cand in [m100_med, m100_hard, m100_async]:
		var sim := m100_ai.clone_state()
		if cand == null or not sim.execute_move(cand) or not sim.is_game_over or sim.status_text != "CHECKMATE - Cyan Wins!" or sim.halfmove_clock != 100:
			m100_all_mate = false
			break
	_assert(
		m100_all_mate,
		"#32: Winning AI chooses quiet Mate-in-1 on halfmove 100 over pawn push (Medium & Hard sync/async)"
	)

	# Losing AI claims 50-move draw at halfmove_clock == 99 instead of resetting clock with pawn push
	var lose50 := GameRules.new()
	lose50.clear_pieces()
	lose50._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("a1"))
	var lose50_pawn := lose50._spawn_piece(PieceData.Team.CYAN, PieceData.Type.PAWN, GameRules.algebraic_to_axial("f6"))
	lose50._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("l4"))
	lose50._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.QUEEN, GameRules.algebraic_to_axial("f5"))
	lose50._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("l1"))
	lose50.current_turn = PieceData.Team.CYAN
	lose50.halfmove_clock = 99
	ai._rng.seed = 8
	var l50_e := ai.choose_move(lose50, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY)
	ai._rng.seed = 8
	var l50_m := ai.choose_move(lose50, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	ai._rng.seed = 8
	var l50_h := ai.choose_move(lose50, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD)
	ai._rng.seed = 8
	var l50_async := await ai.choose_move_async(lose50, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	var l50_sim := lose50.clone_state()
	var l50_draws := l50_h != null and l50_sim.execute_move(l50_h) and l50_sim.is_game_over and l50_sim.status_text == "DRAW - 50-Move Rule"
	_assert(
		l50_e != null and l50_e.piece_id != lose50_pawn.id
		and l50_m != null and l50_m.piece_id != lose50_pawn.id
		and l50_h != null and l50_h.piece_id != lose50_pawn.id
		and l50_async != null and l50_async.piece_id != lose50_pawn.id
		and l50_draws,
		"#32: Losing AI claims 50-move draw at halfmove_clock=99 across Easy, Medium & Hard (sync/async)"
	)

	# Also cover async on 6c mate-trap guard
	ai._rng.seed = 12
	var trap_async := await ai.choose_move_async(mate_trap, PieceData.Team.CYAN, AIPlayer.Difficulty.HARD, self)
	_assert(
		trap_async != null and trap_async.to != c2_hex,
		"#32: Losing AI (async Hard) also rejects non-terminal 2-fold move (R c3->c2) into opponent Mate-in-1"
	)

	# ------------------------------------------------------------------
	# 7. HUD neutral draw status color in Main._refresh_hud()
	# ------------------------------------------------------------------
	var main_hud: Control = MainScene.instantiate()
	root.add_child(main_hud)
	await process_frame
	main_hud.new_game_modal.visible = false
	main_hud.vector_board.rules.clear_pieces()
	main_hud.vector_board.rules._spawn_piece(PieceData.Team.CYAN, PieceData.Type.KING, GameRules.algebraic_to_axial("f5"))
	main_hud.vector_board.rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.ROOK, GameRules.algebraic_to_axial("e6"))
	main_hud.vector_board.rules._spawn_piece(PieceData.Team.MAGENTA, PieceData.Type.KING, GameRules.algebraic_to_axial("a6"))
	main_hud.vector_board.rules.current_turn = PieceData.Team.CYAN
	main_hud.vector_board.rules._update_game_status()
	var hud_cap := _find_legal_move(main_hud.vector_board.rules, "f5", "e6")
	main_hud.is_single_player = true
	main_hud.human_team = PieceData.Team.CYAN
	main_hud.vector_board.rules.execute_move(hud_cap)
	main_hud._on_move_executed(hud_cap, "")
	var draw_color_ok: bool = (
		main_hud.status_label.text == "DRAW - Insufficient Material"
		and main_hud.status_label.modulate == MainScript.COLOR_DRAW_STATUS
		and not main_hud._ai_thinking
	)
	main_hud.vector_board.rules.undo_last_move()
	main_hud._refresh_hud()
	var restored_color_ok: bool = (
		main_hud.status_label.text == "Cyan's Turn"
		and main_hud.status_label.modulate == VectorBoard.COLOR_CYAN
	)
	# Also verify DRAW - 50-Move Rule & DRAW - Threefold Repetition receive neutral draw status color
	main_hud.vector_board.rules.status_text = "DRAW - Threefold Repetition"
	main_hud.vector_board.rules.is_game_over = true
	main_hud._refresh_hud()
	var rep_color_ok: bool = main_hud.status_label.modulate == MainScript.COLOR_DRAW_STATUS
	main_hud.vector_board.rules.status_text = "DRAW - 50-Move Rule"
	main_hud._refresh_hud()
	var fifty_color_ok: bool = main_hud.status_label.modulate == MainScript.COLOR_DRAW_STATUS
	main_hud.free()
	_assert(
		draw_color_ok and restored_color_ok and rep_color_ok and fifty_color_ok,
		"#32: Main._refresh_hud() uses neutral COLOR_DRAW_STATUS on all draw types, skips 1P AI turn on draw, and restores team color on undo"
	)