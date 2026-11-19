class_name MenuBackdrop
extends Node3D
## Live 3D stadium behind the menus: slow camera drift, players warming up.

var stadium: Stadium
var cam: Camera3D
var players: Array = []
var ball: Ball
var t := 0.0
var venue := "harbor"
var tod := "night"


func _ready() -> void:
	stadium = Stadium.new()
	add_child(stadium)
	stadium.build(venue, tod, "clear")
	ball = Ball.new()
	ball.stadium = stadium
	add_child(ball)
	ball.place(Vector3(3.0, BallSim.R, 1.5))
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	ball.set_camera(cam)
	var home := Game.kit_colors(Game.save.club.home)
	var away := Game.kit_colors(Game.TEAMS[1].home)
	var spots := [Vector3(4, 0, 2), Vector3(-2, 0, -3), Vector3(8, 0, -6), Vector3(-6, 0, 5), Vector3(12, 0, 3), Vector3(1, 0, 8)]
	for i in spots.size():
		var p := Footballer.new()
		p.number = [9, 10, 7, 4, 11, 8][i]
		p.setup(home if i % 2 == 0 else away, Color(Game.SKIN_TONES[i]), Color(Game.HAIR[i]), Color("151515"))
		add_child(p)
		p.pos = spots[i]
		p.yaw = randf() * TAU
		players.append(p)
	stadium.set_crowd_colors(home.shirt, away.shirt)
	stadium.set_excitement(0.15)


func _process(delta: float) -> void:
	t += delta
	var a := t * 0.05 + 2.4
	var r := 34.0
	cam.position = Vector3(cos(a) * r + 6.0, 9.5 + sin(t * 0.13) * 1.5, sin(a) * r * 0.62)
	cam.look_at(Vector3(5.0, 1.0, 0.0), Vector3.UP)
	for i in players.size():
		var p: Footballer = players[i]
		var ph := t * 0.35 + i * 1.7
		var target := Vector3(4.0 + cos(ph) * (6.0 + i), 0, sin(ph * 1.3) * (4.0 + i * 0.6))
		var d := target - p.pos
		p.desired = d.normalized() * min(3.2, d.length()) if d.length() > 0.5 else Vector3.ZERO
		p.tick(delta)
	var lead: Footballer = players[0]
	ball.holder = lead
	ball.held_in_hands = false
