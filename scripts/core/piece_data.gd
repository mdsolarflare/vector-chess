class_name PieceData
extends RefCounted
## Data model and Option A Low-Poly Faceted Silhouette ("Origami / Vector Staunton")
## geometry for Vector Chess pieces.
## Every piece is built from convex triangle/quad facets with per-facet lighting values
## and an outer vector silhouette contour — zero raster textures or text labels required.

enum Team {
	CYAN = 0,    # White / Bottom player (moves North: dr = -1)
	MAGENTA = 1  # Black / Top player (moves South: dr = +1)
}

enum Type {
	PAWN,
	KNIGHT,
	BISHOP,
	ROOK,
	QUEEN,
	KING
}

var id: int
var team: Team
var type: Type
## Axial hex coordinates (q, r) where max(|q|, |r|, |q + r|) <= 5
var grid_pos: Vector2i
## Interpolated axial coordinate for smooth movement animation
var visual_pos: Vector2
var has_moved: bool = false
var sides_count: int = 3


func _init(p_id: int, p_team: Team, p_type: Type, p_pos: Vector2i) -> void:
	id = p_id
	team = p_team
	type = p_type
	grid_pos = p_pos
	visual_pos = Vector2(p_pos)
	sides_count = get_polygon_sides(p_type)


func duplicate_piece() -> PieceData:
	var copy := PieceData.new(id, team, type, grid_pos)
	copy.visual_pos = visual_pos
	copy.has_moved = has_moved
	return copy


static func get_piece_name(p_type: Type) -> String:
	match p_type:
		Type.PAWN: return "Pawn"
		Type.KNIGHT: return "Knight"
		Type.BISHOP: return "Bishop"
		Type.ROOK: return "Rook"
		Type.QUEEN: return "Queen"
		Type.KING: return "King"
	return "Piece"


static func get_piece_short_code(p_type: Type) -> String:
	match p_type:
		Type.PAWN: return "P"
		Type.KNIGHT: return "N"
		Type.BISHOP: return "B"
		Type.ROOK: return "R"
		Type.QUEEN: return "Q"
		Type.KING: return "K"
	return "?"


static func get_polygon_sides(p_type: Type) -> int:
	match p_type:
		Type.PAWN: return 3
		Type.BISHOP: return 4
		Type.KNIGHT: return 5
		Type.ROOK: return 6
		Type.QUEEN: return 8
		Type.KING: return 12
	return 4


## Relative visual scale of each piece type inside a hex cell (establishing size hierarchy).
static func get_piece_scale(p_type: Type) -> float:
	match p_type:
		Type.PAWN: return 0.62
		Type.KNIGHT: return 0.72
		Type.BISHOP: return 0.72
		Type.ROOK: return 0.72
		Type.QUEEN: return 0.78
		Type.KING: return 0.80
	return 0.70


## Returns a dictionary describing the Option A Low-Poly Faceted Staunton silhouette:
## - "facets": Array[Dictionary] with {"poly": PackedVector2Array, "shade": float}
## - "outlines": Array[PackedVector2Array] closed polylines for glowing outer/inner silhouette edges
## - "accents": Array[PackedVector2Array] bright highlight polylines/gems
static func get_faceted_mesh(p_type: Type) -> Dictionary:
	var facets: Array[Dictionary] = []
	var outlines: Array[PackedVector2Array] = []
	var accents: Array[PackedVector2Array] = []

	match p_type:
		Type.PAWN:
			# Flared pedestal base (y: +0.52 to +0.76)
			_add_facet(facets, [Vector2(-0.56, 0.76), Vector2(-0.42, 0.52), Vector2(0.0, 0.52), Vector2(0.0, 0.76)], 0.65)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.52), Vector2(0.42, 0.52), Vector2(0.56, 0.76)], 0.28)
			# Conical body stem (y: -0.06 to +0.52)
			_add_facet(facets, [Vector2(-0.42, 0.52), Vector2(-0.20, -0.06), Vector2(0.0, -0.06), Vector2(0.0, 0.52)], 0.52)
			_add_facet(facets, [Vector2(0.0, 0.52), Vector2(0.0, -0.06), Vector2(0.20, -0.06), Vector2(0.42, 0.52)], 0.22)
			# Sharp collar ring (y: -0.18 to -0.06)
			_add_facet(facets, [Vector2(-0.34, -0.12), Vector2(0.0, -0.18), Vector2(0.0, -0.06), Vector2(-0.20, -0.06)], 0.82)
			_add_facet(facets, [Vector2(0.0, -0.18), Vector2(0.34, -0.12), Vector2(0.20, -0.06), Vector2(0.0, -0.06)], 0.45)
			# Low-poly crystal sphere head (center at (0.0, -0.44))
			var hc := Vector2(0.0, -0.44)
			var h_top := Vector2(0.0, -0.74)
			var h_ul := Vector2(-0.26, -0.60)
			var h_ll := Vector2(-0.28, -0.30)
			var h_bot := Vector2(0.0, -0.18)
			var h_lr := Vector2(0.28, -0.30)
			var h_ur := Vector2(0.26, -0.60)
			_add_facet(facets, [hc, h_top, h_ul], 0.95)
			_add_facet(facets, [hc, h_ul, h_ll], 0.75)
			_add_facet(facets, [hc, h_ll, h_bot], 0.52)
			_add_facet(facets, [hc, h_bot, h_lr], 0.26)
			_add_facet(facets, [hc, h_lr, h_ur], 0.38)
			_add_facet(facets, [hc, h_ur, h_top], 0.62)

			outlines.append(PackedVector2Array([
				Vector2(-0.56, 0.76), Vector2(-0.42, 0.52), Vector2(-0.20, -0.06),
				Vector2(-0.34, -0.12), h_ll, h_ul, h_top, h_ur, h_lr,
				Vector2(0.34, -0.12), Vector2(0.20, -0.06), Vector2(0.42, 0.52),
				Vector2(0.56, 0.76), Vector2(-0.56, 0.76)
			]))

		Type.ROOK:
			# Heavy fortress base (y: +0.52 to +0.76)
			_add_facet(facets, [Vector2(-0.64, 0.76), Vector2(-0.50, 0.52), Vector2(0.0, 0.52), Vector2(0.0, 0.76)], 0.68)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.52), Vector2(0.50, 0.52), Vector2(0.64, 0.76)], 0.26)
			# Tower shaft (3 vertical facets, y: -0.22 to +0.52)
			_add_facet(facets, [Vector2(-0.50, 0.52), Vector2(-0.40, -0.22), Vector2(-0.14, -0.22), Vector2(-0.18, 0.52)], 0.72)
			_add_facet(facets, [Vector2(-0.18, 0.52), Vector2(-0.14, -0.22), Vector2(0.14, -0.22), Vector2(0.18, 0.52)], 0.46)
			_add_facet(facets, [Vector2(0.18, 0.52), Vector2(0.14, -0.22), Vector2(0.40, -0.22), Vector2(0.50, 0.52)], 0.22)
			# Overhanging parapet corbel (y: -0.40 to -0.22)
			_add_facet(facets, [Vector2(-0.40, -0.22), Vector2(-0.56, -0.40), Vector2(0.0, -0.40), Vector2(0.0, -0.22)], 0.84)
			_add_facet(facets, [Vector2(0.0, -0.22), Vector2(0.0, -0.40), Vector2(0.56, -0.40), Vector2(0.40, -0.22)], 0.38)
			# 3 Castle Battlement Merlons (Left, Center, Right, y: -0.74 to -0.40)
			_add_facet(facets, [Vector2(-0.56, -0.40), Vector2(-0.56, -0.74), Vector2(-0.28, -0.74), Vector2(-0.28, -0.40)], 0.90)
			_add_facet(facets, [Vector2(-0.14, -0.40), Vector2(-0.14, -0.74), Vector2(0.14, -0.74), Vector2(0.14, -0.40)], 0.62)
			_add_facet(facets, [Vector2(0.28, -0.40), Vector2(0.28, -0.74), Vector2(0.56, -0.74), Vector2(0.56, -0.40)], 0.34)

			outlines.append(PackedVector2Array([
				Vector2(-0.64, 0.76), Vector2(-0.50, 0.52), Vector2(-0.40, -0.22),
				Vector2(-0.56, -0.40), Vector2(-0.56, -0.74), Vector2(-0.28, -0.74),
				Vector2(-0.28, -0.40), Vector2(-0.14, -0.40), Vector2(-0.14, -0.74),
				Vector2(0.14, -0.74), Vector2(0.14, -0.40), Vector2(0.28, -0.40),
				Vector2(0.28, -0.74), Vector2(0.56, -0.74), Vector2(0.56, -0.40),
				Vector2(0.40, -0.22), Vector2(0.50, 0.52), Vector2(0.64, 0.76),
				Vector2(-0.64, 0.76)
			]))

		Type.KNIGHT:
			# Pedestal base (y: +0.54 to +0.76)
			_add_facet(facets, [Vector2(-0.60, 0.76), Vector2(-0.44, 0.54), Vector2(0.0, 0.54), Vector2(0.0, 0.76)], 0.68)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.54), Vector2(0.48, 0.54), Vector2(0.60, 0.76)], 0.28)
			# Origami Warhorse Head & Neck facets
			var k_chest := Vector2(-0.44, 0.54)
			var k_throat := Vector2(-0.14, 0.10)
			var k_jaw := Vector2(-0.28, -0.04)
			var k_chin := Vector2(-0.58, -0.02)
			var k_nose := Vector2(-0.68, -0.22)
			var k_brow := Vector2(-0.32, -0.52)
			var k_ear_tip := Vector2(-0.04, -0.82)
			var k_ear_back := Vector2(0.18, -0.58)
			var k_mane_top := Vector2(0.42, -0.32)
			var k_mane_mid := Vector2(0.52, 0.08)
			var k_back := Vector2(0.48, 0.54)
			var k_core := Vector2(0.06, -0.20)
			var k_neck_mid := Vector2(0.12, 0.24)

			# Ear facet (brightest)
			_add_facet(facets, [k_brow, k_ear_tip, k_ear_back, k_core], 0.94)
			# Upper snout / nasal bridge (bright)
			_add_facet(facets, [k_nose, k_brow, k_core, k_jaw], 0.78)
			# Muzzle tip / chin (mid)
			_add_facet(facets, [k_chin, k_nose, k_jaw], 0.52)
			# Cheek / throat transition
			_add_facet(facets, [k_jaw, k_core, k_throat], 0.36)
			# Upper mane (shaded)
			_add_facet(facets, [k_core, k_ear_back, k_mane_top], 0.44)
			# Mid mane facet
			_add_facet(facets, [k_core, k_mane_top, k_mane_mid, k_neck_mid], 0.30)
			# Front chest (lit triangles)
			_add_facet(facets, [k_chest, k_throat, k_neck_mid], 0.68)
			_add_facet(facets, [k_throat, k_core, k_neck_mid], 0.58)
			# Lower back neck (deep shadow)
			_add_facet(facets, [k_chest, k_neck_mid, k_mane_mid, k_back], 0.22)

			outlines.append(PackedVector2Array([
				Vector2(-0.60, 0.76), k_chest, k_throat, k_jaw, k_chin,
				k_nose, k_brow, k_ear_tip, k_ear_back, k_mane_top,
				k_mane_mid, k_back, Vector2(0.60, 0.76), Vector2(-0.60, 0.76)
			]))
			# Glowing angular eye accent
			accents.append(PackedVector2Array([
				Vector2(-0.30, -0.34), Vector2(-0.16, -0.38), Vector2(-0.22, -0.26), Vector2(-0.30, -0.34)
			]))

		Type.BISHOP:
			# Pedestal base (y: +0.54 to +0.76)
			_add_facet(facets, [Vector2(-0.60, 0.76), Vector2(-0.44, 0.54), Vector2(0.0, 0.54), Vector2(0.0, 0.76)], 0.68)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.54), Vector2(0.44, 0.54), Vector2(0.60, 0.76)], 0.26)
			# Lower stem & collar (y: +0.20 to +0.54)
			_add_facet(facets, [Vector2(-0.44, 0.54), Vector2(-0.30, 0.20), Vector2(0.0, 0.20), Vector2(0.0, 0.54)], 0.56)
			_add_facet(facets, [Vector2(0.0, 0.54), Vector2(0.0, 0.20), Vector2(0.30, 0.20), Vector2(0.44, 0.54)], 0.24)
			# Pointed Mitre Dome with classic diagonal cleft cutout on upper right
			var b_apex := Vector2(0.0, -0.68)
			var b_ul := Vector2(-0.34, -0.36)
			var b_ll := Vector2(-0.42, -0.02)
			var b_cl := Vector2(-0.30, 0.20)
			var b_cr := Vector2(0.30, 0.20)
			var b_lr := Vector2(0.42, -0.02)
			var b_cleft_bot := Vector2(0.36, -0.22)
			var b_cleft_in := Vector2(0.06, -0.18)
			var b_cleft_top := Vector2(0.26, -0.44)
			var b_center := Vector2(0.0, 0.04)

			# Left mitre facets (bright, strict clockwise order)
			_add_facet(facets, [b_center, b_ul, b_apex, b_cleft_in], 0.90)
			_add_facet(facets, [b_center, b_ll, b_ul], 0.74)
			_add_facet(facets, [b_center, b_cl, b_ll], 0.60)
			# Upper right mitre above cleft
			_add_facet(facets, [b_apex, b_cleft_top, b_cleft_in], 0.52)
			# Lower right mitre below cleft
			_add_facet(facets, [b_center, b_cleft_in, b_cleft_bot, b_lr], 0.36)
			_add_facet(facets, [b_center, b_lr, b_cr], 0.24)
			# Finial diamond orb at top of mitre
			var f_bot := Vector2(0.0, -0.68)
			var f_left := Vector2(-0.10, -0.78)
			var f_top := Vector2(0.0, -0.88)
			var f_right := Vector2(0.10, -0.78)
			_add_facet(facets, [f_bot, f_left, f_top, f_right], 0.96)

			outlines.append(PackedVector2Array([
				Vector2(-0.60, 0.76), Vector2(-0.44, 0.54), b_cl, b_ll, b_ul,
				b_apex, f_left, f_top, f_right, b_apex, b_cleft_top,
				b_cleft_in, b_cleft_bot, b_lr, b_cr, Vector2(0.44, 0.54),
				Vector2(0.60, 0.76), Vector2(-0.60, 0.76)
			]))
			# Bright diagonal mitre slash highlight
			accents.append(PackedVector2Array([b_cleft_top, b_cleft_in, b_cleft_bot]))

		Type.QUEEN:
			# Regal pedestal base (y: +0.50 to +0.76)
			_add_facet(facets, [Vector2(-0.66, 0.76), Vector2(-0.50, 0.50), Vector2(0.0, 0.50), Vector2(0.0, 0.76)], 0.70)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.50), Vector2(0.50, 0.50), Vector2(0.66, 0.76)], 0.28)
			# Lower crown band (y: +0.22 to +0.50)
			_add_facet(facets, [Vector2(-0.50, 0.50), Vector2(-0.56, 0.22), Vector2(0.0, 0.22), Vector2(0.0, 0.50)], 0.58)
			_add_facet(facets, [Vector2(0.0, 0.50), Vector2(0.0, 0.22), Vector2(0.56, 0.22), Vector2(0.50, 0.50)], 0.24)

			# 5-Spiked Coronet (5 tall spikes + 4 inner valley facets, all non-degenerate triangles)
			var spikes: Array[Vector2] = [
				Vector2(-0.74, -0.34),
				Vector2(-0.38, -0.60),
				Vector2(0.0, -0.74),
				Vector2(0.38, -0.60),
				Vector2(0.74, -0.34),
			]
			var valleys: Array[Vector2] = [
				Vector2(-0.56, 0.22),
				Vector2(-0.34, -0.02),
				Vector2(-0.12, -0.08),
				Vector2(0.12, -0.08),
				Vector2(0.34, -0.02),
				Vector2(0.56, 0.22),
			]
			var base_pts: Array[Vector2] = [
				Vector2(-0.45, 0.22),
				Vector2(-0.23, 0.22),
				Vector2(0.0, 0.22),
				Vector2(0.23, 0.22),
				Vector2(0.45, 0.22),
			]
			for i in range(5):
				var v_left: Vector2 = valleys[i]
				var v_right: Vector2 = valleys[i + 1]
				var tip: Vector2 = spikes[i]
				var b_mid: Vector2 = base_pts[i]
				_add_facet(facets, [v_left, tip, b_mid], 0.88 - float(i) * 0.08)
				_add_facet(facets, [b_mid, tip, v_right], 0.42 - float(i) * 0.04)
				if i < 4:
					_add_facet(facets, [b_mid, v_right, base_pts[i + 1]], 0.52 - float(i) * 0.06)

				# Small diamond pearl at each spike tip
				var pr := 0.055
				var pearl := PackedVector2Array([
					tip + Vector2(0, -pr),
					tip + Vector2(pr, 0),
					tip + Vector2(0, pr),
					tip + Vector2(-pr, 0),
					tip + Vector2(0, -pr)
				])
				accents.append(pearl)

			outlines.append(PackedVector2Array([
				Vector2(-0.66, 0.76), Vector2(-0.50, 0.50), valleys[0],
				spikes[0], valleys[1], spikes[1], valleys[2], spikes[2],
				valleys[3], spikes[3], valleys[4], spikes[4], valleys[5],
				Vector2(0.50, 0.50), Vector2(0.66, 0.76), Vector2(-0.66, 0.76)
			]))

		Type.KING:
			# Broad imperial pedestal base (y: +0.52 to +0.76)
			_add_facet(facets, [Vector2(-0.68, 0.76), Vector2(-0.52, 0.52), Vector2(0.0, 0.52), Vector2(0.0, 0.76)], 0.72)
			_add_facet(facets, [Vector2(0.0, 0.76), Vector2(0.0, 0.52), Vector2(0.52, 0.52), Vector2(0.68, 0.76)], 0.28)
			# Stepped royal collar (y: +0.30 to +0.52)
			_add_facet(facets, [Vector2(-0.52, 0.52), Vector2(-0.46, 0.30), Vector2(0.0, 0.30), Vector2(0.0, 0.52)], 0.58)
			_add_facet(facets, [Vector2(0.0, 0.52), Vector2(0.0, 0.30), Vector2(0.46, 0.30), Vector2(0.52, 0.52)], 0.24)
			# Mitered Imperial Crown Body (y: -0.26 to +0.30)
			var c_ul := Vector2(-0.64, -0.16)
			var c_top_l := Vector2(-0.28, -0.32)
			var c_dip_l := Vector2(-0.14, -0.20)
			var c_apex := Vector2(0.0, -0.32)
			var c_dip_r := Vector2(0.14, -0.20)
			var c_top_r := Vector2(0.28, -0.32)
			var c_ur := Vector2(0.64, -0.16)
			var c_bl := Vector2(-0.46, 0.30)
			var c_bm := Vector2(0.0, 0.30)
			var c_br := Vector2(0.46, 0.30)

			# Left wing facet
			_add_facet(facets, [c_bl, c_ul, c_top_l, c_dip_l], 0.84)
			_add_facet(facets, [c_bl, c_dip_l, c_bm], 0.68)
			# Center diamond jewel facet
			_add_facet(facets, [c_bm, c_dip_l, c_apex, c_dip_r], 0.94)
			# Right wing facet
			_add_facet(facets, [c_bm, c_dip_r, c_br], 0.42)
			_add_facet(facets, [c_dip_r, c_top_r, c_ur, c_br], 0.30)

			# Bold Royal Cross (+) at the apex (y: -0.88 to -0.32)
			_add_facet(facets, [Vector2(-0.09, -0.32), Vector2(-0.09, -0.88), Vector2(0.09, -0.88), Vector2(0.09, -0.32)], 0.96)
			_add_facet(facets, [Vector2(-0.28, -0.56), Vector2(-0.28, -0.72), Vector2(0.28, -0.72), Vector2(0.28, -0.56)], 0.92)

			outlines.append(PackedVector2Array([
				Vector2(-0.68, 0.76), Vector2(-0.52, 0.52), c_bl, c_ul,
				c_top_l, c_dip_l, Vector2(-0.09, -0.32), Vector2(-0.09, -0.56),
				Vector2(-0.28, -0.56), Vector2(-0.28, -0.72), Vector2(-0.09, -0.72),
				Vector2(-0.09, -0.88), Vector2(0.09, -0.88), Vector2(0.09, -0.72),
				Vector2(0.28, -0.72), Vector2(0.28, -0.56), Vector2(0.09, -0.56),
				Vector2(0.09, -0.32), c_dip_r, c_top_r, c_ur, c_br,
				Vector2(0.52, 0.52), Vector2(0.68, 0.76), Vector2(-0.68, 0.76)
			]))

	return {
		"facets": facets,
		"outlines": outlines,
		"accents": accents,
	}


static func _add_facet(facets: Array[Dictionary], pts: Array, shade: float) -> void:
	var packed := PackedVector2Array()
	packed.resize(pts.size())
	for i in range(pts.size()):
		packed[i] = pts[i]
	facets.append({
		"poly": packed,
		"shade": shade,
	})
