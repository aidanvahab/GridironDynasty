extends Node3D
## Development harness: builds a stadium + players and saves screenshots.
## godot-gfx --path . res://tools/scenes/visual_test.tscn -- style=classic tod=day out=/tmp/x.png

func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(2))
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var style: String = args.get("style", "classic")
	var tod: String = args.get("tod", "day")
	var font: Font = load("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
	var stadium := StadiumBuilder.new()
	add_child(stadium)
	stadium.build(style, Color("#1E5AA8"), Color("#F4C95D"), Color("#E75A5A"), tod, 1.0)
	var field := FieldBuilder.new()
	add_child(field)
	field.build(Color("#1E5AA8"), Color("#B5462E"), "Gulls", "Coyotes", font)
	field.show_down_markers(35.0, 45.0, 1, 1, true)
	for i in 6:
		var r := PlayerRig.new()
		add_child(r)
		r.build(Color("#1E5AA8"), Color("#F5F0E5"), Color("#1E5AA8"), Color("#F4C95D"), Color("#C8CED6"), 10 + i * 7, i, 1.0 + i * 0.05, font)
		r.position = Vector3(-15.0 + i * 1.6, 0, -2.0 + (i % 2) * 1.5)
		r.rotation.y = -PI / 2
		r.set_pose([PlayerRig.Pose.IDLE, PlayerRig.Pose.STANCE3, PlayerRig.Pose.RUN, PlayerRig.Pose.THROW, PlayerRig.Pose.CATCH, PlayerRig.Pose.STANCE2][i])
		r.speed = 7.0 if i == 2 else 0.0
		r.set_meta("i", i)
	for i in 3:
		var r := PlayerRig.new()
		add_child(r)
		r.build(Color("#F5F0E5"), Color("#B5462E"), Color("#B5462E"), Color("#B5462E"), Color("#3A3F47"), 50 + i, 3, 1.2, font)
		r.position = Vector3(-12.0, 0, -1.0 + i * 1.4)
		r.rotation.y = PI / 2
		r.set_pose(PlayerRig.Pose.STANCE3)
	var cam := Camera3D.new()
	add_child(cam)
	var shot: String = args.get("cam", "play")
	if shot == "wide":
		cam.position = Vector3(-30, 32, 50)
		cam.look_at(Vector3(0, 0, 0))
		cam.fov = 60
	elif shot == "endzone":
		# From the field of play looking into the home end zone.
		cam.position = Vector3(-30, 14, 0)
		cam.look_at(Vector3(-55, 0, 0))
		cam.fov = 55
	elif shot == "close":
		cam.position = Vector3(-8, 2.2, 4)
		cam.look_at(Vector3(-12, 1.1, -0.5))
		cam.fov = 45
	else:
		cam.position = Vector3(-30, 11, 0)
		cam.look_at(Vector3(-8, 0, 0))
		cam.fov = 55
	cam.current = true
	for k in int(args.get("frames", "6")):
		for c in get_children():
			if c is PlayerRig:
				c.animate(1.0 / 30.0)
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(args.get("out", "/tmp/claude-0/shot.png"))
	print("crowd: ", stadium.crowd_count)
	get_tree().quit()
