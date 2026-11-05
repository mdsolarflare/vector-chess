class_name PieceData
extends RefCounted
## Data model and procedural polygon geometry for a Vector Chess piece.
## Purely geometric representation ("Polygon Pandemonium") on an axial hexagonal grid.

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
		Type.PAWN: return "Tri-Pawn"
		Type.KNIGHT: return "Vector-Knight"
		Type.BISHOP: return "Rhombus-Bishop"
		Type.ROOK: return "Hex-Rook"
		Type.QUEEN: return "Octa-Queen"
		Type.KING: return "Apex-King"
	return "Polygon"


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


## Returns an array of PackedVector2Array layers normalized to radius 1.0.
func get_normalized_polygons() -> Array[PackedVector2Array]:
	var layers: Array[PackedVector2Array] = []
	var forward_sign := -1.0 if team == Team.CYAN else 1.0
	var base_rot := PI * 0.5 * forward_sign

	match type:
		Type.PAWN:
			layers.append(_make_regular_polygon(3, 0.62, base_rot))
			layers.append(_make_regular_polygon(3, 0.30, -base_rot))

		Type.KNIGHT:
			var outer := PackedVector2Array([
				Vector2(0.0, 0.72 * forward_sign),
				Vector2(0.62, 0.10 * forward_sign),
				Vector2(0.42, -0.64 * forward_sign),
				Vector2(0.0, -0.35 * forward_sign),
				Vector2(-0.42, -0.64 * forward_sign),
				Vector2(-0.62, 0.10 * forward_sign),
			])
			var inner := PackedVector2Array([
				Vector2(0.0, 0.42 * forward_sign),
				Vector2(0.30, -0.10 * forward_sign),
				Vector2(0.0, -0.22 * forward_sign),
				Vector2(-0.30, -0.10 * forward_sign),
			])
			layers.append(outer)
			layers.append(inner)

		Type.BISHOP:
			# 3-way / 6-point diagonal star silhouette reflecting hex diagonal axes
			layers.append(_make_star_polygon(6, 0.72, 0.36, PI / 6.0))
			layers.append(_make_regular_polygon(3, 0.34, base_rot))

		Type.ROOK:
			# Flat-top hexagon fortress matching the 6 orthogonal hex edges
			layers.append(_make_regular_polygon(6, 0.72, 0.0))
			layers.append(_make_regular_polygon(6, 0.42, 0.0))

		Type.QUEEN:
			# 12-point star representing all 6 orthogonal + 6 diagonal hex axes
			layers.append(_make_star_polygon(12, 0.78, 0.46, 0.0))
			layers.append(_make_regular_polygon(6, 0.34, 0.0))

		Type.KING:
			# Heavy 6-sided crown + inner cross beacon
			layers.append(_make_regular_polygon(6, 0.78, 0.0))
			layers.append(_make_star_polygon(6, 0.66, 0.28, 0.0))
			layers.append(_make_regular_polygon(6, 0.24, PI / 6.0))

	return layers


static func _make_regular_polygon(sides: int, radius: float, angle_offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sides)
	for i in range(sides):
		var a := angle_offset + (TAU * float(i) / float(sides))
		pts[i] = Vector2(cos(a), sin(a)) * radius
	return pts


static func _make_star_polygon(points: int, outer_r: float, inner_r: float, angle_offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var total := points * 2
	pts.resize(total)
	for i in range(total):
		var a := angle_offset + (TAU * float(i) / float(total))
		var r := outer_r if (i % 2 == 0) else inner_r
		pts[i] = Vector2(cos(a), sin(a)) * r
	return pts
