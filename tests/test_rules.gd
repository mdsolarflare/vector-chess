extends SceneTree
## Headless unit test runner for Vector Chess (Glinski's Hexagonal Chess).
## Run with: godot --headless -s res://tests/test_rules.gd

const MainScript = preload("res://scripts/main.gd")
const MainScene = preload("res://scenes/main.tscn")

var _tests_run: int = 0
var _tests_failed: int = 0


func _init() -> void:
	print("=== Vector Chess Headless Test Suite ===")
	_test_board_geometry_and_coordinates()
	_test_initial_glinski_setup()
	_test_pawn_double_step_and_en_passant()
	_test_pawn_promotion()
	_test_bishop_three_color_invariance()
	_test_check_checkmate_and_stalemate()
	_test_move_execution_and_undo()
	_test_search_push_pop_consistency()
	_test_piece_faceted_meshes()
	_test_ai_player_move_selection()
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


func _test_pawn_promotion() -> void:
	print("\n-- Pawn Promotion --")
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
	print("\n-- Check & Checkmate Detection --")
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
	print("\n-- AIPlayer Move Selection --")
	var rules := GameRules.new()
	var ai := AIPlayer.new()
	var easy_mv := ai.choose_move(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.EASY)
	var med_mv := ai.choose_move(rules, PieceData.Team.CYAN, AIPlayer.Difficulty.MEDIUM)
	_assert(easy_mv != null, "AIPlayer (Easy) selects a valid opening move")
	_assert(med_mv != null, "AIPlayer (Medium) selects a valid opening move")


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
	_assert(
		board.selected_piece != null and not board.legal_moves.is_empty(),
		"Selecting a piece populates legal_moves from cache"
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
