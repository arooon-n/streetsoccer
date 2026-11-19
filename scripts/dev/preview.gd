extends Node3D
## Dev harness: builds a venue + posed players and writes a screenshot.
## Usage: godot --path . -- --preview <venue> <time> <weather> <cam> <out.png>

var args: Array = []
var frames := 0
var cam: Camera3D
var players: Array = []
var ball: Ball
var stadium: Stadium


func _ready() -> void:
	var venue: String = args[0] if args.size() > 0 else "harbor"
	var tod: String = args[1] if args.size() > 1 else "night"
	var weather: String = args[2] if args.size() > 2 else "clear"
	var view: String = args[3] if args.size() > 3 else "broadcast"
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(venue, tod, weather)
	ball = Ball.new()
	ball.stadium = stadium
	add_child(ball)
	ball.place(Vector3(10.6, 0.11, 4.2))
	var home = Game.kit_colors(Game.TEAMS[0].home)
	var away = Game.kit_colors(Game.TEAMS[1].home)
	var gk := {"shirt": Color("8E6CF0"), "shirt2": Color("20163F"), "pattern": 0, "shorts": Color("20163F"), "socks": Color("8E6CF0")}
	var spots := [
		[Vector3(10, 0, 4), 0.6, home, "", 9, 5.5],
		[Vector3(13.5, 0, 3.0), -1.8, away, "", 4, 3.0],
		[Vector3(6, 0, -6), 1.2, home, "", 10, 7.5],
		[Vector3(18, 0, -2), -1.6, away, "", 5, 2.0],
		[Vector3(2, 0, 9), 1.0, home, "", 8, 0.0],
		[Vector3(22, 0, 8), -2.0, away, "", 2, 4.0],
		[Vector3(30, 0, 1), -1.6, away, "", 3, 1.0],
		[Vector3(stadium.L - 1.2, 0, 0.5), -PI / 2, away, "keeper", 1, 0.0],
	]
	if view == "closeup":
		spots = [
			[Vector3(0, 0, 0), PI, home, "", 9, 0.0],
			[Vector3(1.4, 0, 0.6), 0.4, home, "kick", 10, 0.0],
			[Vector3(-1.4, 0, 0.3), -0.3, away, "", 7, 4.0],
			[Vector3(2.9, 0, -0.8), 0.0, away, "dive", 1, 0.0],
			[Vector3(-3.0, 0, -1.0), 2.4, home, "slide", 6, 0.0],
			[Vector3(-0.5, 0, -2.4), PI, away, "header", 11, 0.0],
		]
		ball.place(Vector3(1.8, 0.11, 1.2))
	var i := 0
	for s in spots:
		var p := Footballer.new()
		p.number = s[4]
		p.keeper = s[3] == "keeper" or s[3] == "dive"
		p.setup(s[2], Color(Game.SKIN_TONES[i % 8]), Color(Game.HAIR[i % 8]), Color("151515"), gk)
		add_child(p)
		p.pos = s[0]
		p.yaw = s[1]
		var spd: float = s[5]
		p.vel = p.forward() * spd
		p.phase = i * 1.3
		if s[3] in ["kick", "dive", "slide", "header"]:
			p.play_action(s[3], 10.0, 2.0)
			p.action_t = {"kick": 0.45, "dive": 0.5, "slide": 0.4, "header": 0.48}[s[3]]
		if s[3] == "keeper":
			p.ready_amt = 1.0
		players.append(p)
		i += 1
	cam = Camera3D.new()
	add_child(cam)
	match view:
		"broadcast":
			cam.fov = 38
			var focus := Vector3(12, 0, 2)
			cam.position = Vector3(focus.x * 0.9, 17.0 if not stadium.is_cage else 12.0, stadium.W + (26.0 if not stadium.is_cage else 13.0))
			cam.look_at(focus, Vector3.UP)
		"wide":
			cam.fov = 50
			cam.position = Vector3(-stadium.L * 0.9, stadium.W * 0.65, stadium.W * 1.25)
			cam.look_at(Vector3(5, 0, -3), Vector3.UP)
		"goal":
			cam.fov = 48
			cam.position = Vector3(stadium.L - 22, 2.0, 6.0)
			cam.look_at(Vector3(stadium.L, 1.1, 0), Vector3.UP)
		"closeup":
			cam.fov = 45
			cam.position = Vector3(0.3, 1.5, 6.5)
			cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	ball.set_camera(cam)
	Game.apply_viewport_settings()


func _process(delta: float) -> void:
	frames += 1
	for p in players:
		if p.action == "":
			p.phase += delta * (p.speed() / (1.3 + 0.27 * p.speed())) * TAU
	if frames == 40:
		var out: String = args[4] if args.size() > 4 else "user://preview.png"
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("SAVED ", out, " fps=", Engine.get_frames_per_second())
		get_tree().quit()
