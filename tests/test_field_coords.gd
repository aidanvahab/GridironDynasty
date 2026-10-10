extends TestCase

func test_world_roundtrip_both_directions() -> void:
	for dir in [1, -1]:
		for b in [0.0, 12.5, 50.0, 99.0, 105.0]:
			for lat in [-10.0, 0.0, 7.5]:
				var w := FieldCoords.to_world(b, lat, dir)
				var f := FieldCoords.to_field(w, dir)
				near(f.x, b, 0.0001)
				near(f.y, lat, 0.0001)

func test_goal_lines_are_at_plus_minus_fifty() -> void:
	eq(FieldCoords.world_x(100.0, 1), 50.0)
	eq(FieldCoords.world_x(100.0, -1), -50.0)
	eq(FieldCoords.world_x(0.0, 1), -50.0)

func test_forward_matches_increasing_ball_on() -> void:
	for dir in [1, -1]:
		var p := FieldCoords.to_world(30.0, 0.0, dir)
		var q := p + FieldCoords.forward(dir) * 5.0
		near(FieldCoords.to_field(q, dir).x, 35.0, 0.0001)

func test_offense_right_is_positive_lateral() -> void:
	for dir in [1, -1]:
		var p := FieldCoords.to_world(30.0, 0.0, dir) + FieldCoords.offense_right(dir) * 3.0
		near(FieldCoords.to_field(p, dir).y, 3.0, 0.0001)
		# Right-hand rule: forward x up = right in Godot's coordinate system.
		var fwd := FieldCoords.forward(dir)
		var right := fwd.cross(Vector3.UP)
		near(right.dot(FieldCoords.offense_right(dir)), 1.0, 0.0001)

func test_spot_description() -> void:
	eq(FieldCoords.describe_spot(25.0, "AAA", "BBB"), "AAA 25")
	eq(FieldCoords.describe_spot(50.0, "AAA", "BBB"), "50")
	eq(FieldCoords.describe_spot(70.0, "AAA", "BBB"), "BBB 30")
	eq(FieldCoords.flip(30.0), 70.0)

func test_bounds() -> void:
	check(FieldCoords.is_in_bounds(Vector3(0, 0, 26.0)))
	check(not FieldCoords.is_in_bounds(Vector3(0, 0, 26.8)))
	check(not FieldCoords.is_in_bounds(Vector3(60.5, 0, 0)))
