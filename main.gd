extends Node3D

@onready var ball: Ball = $Ball
@onready var level_root: Node3D = $Level
@onready var camera: Camera3D = $Camera3D
@onready var label: Label = $UI/Label
@onready var world_env: WorldEnvironment = $WorldEnvironment

const SEG_LEN := 6.0
const MAX_LEVEL := 30

var level := 1
var coins := 0
var coins_total := 0
var finished := false
var hint_shown := false

var flash_label: Label
var pause_btn: Button
var result_panel: PanelContainer
var result_title: Label
var result_stars: Label
var result_coins: Label
var next_button: Button
var generated_sounds := {}

func _ready() -> void:
	level = Save.current_level
	ball.fell.connect(_on_fell)
	if OS.has_feature("mobile"):
		$DirectionalLight3D.shadow_enabled = false
	_make_stars()
	_build_ui()
	_init_sounds()
	start_level()

func _process(delta: float) -> void:
	var goal := ball.global_position + Vector3(0, 4.5, 7)
	camera.global_position = camera.global_position.lerp(goal, 5.0 * delta)
	camera.look_at(ball.global_position + Vector3(0, 0, -4))


# ---------- الواجهة ----------

func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 90)
	b.add_theme_font_size_override("font_size", 36)
	b.pressed.connect(handler)
	return b


func _build_ui() -> void:
	$UI.process_mode = Node.PROCESS_MODE_ALWAYS   # الأزرار تعمل أثناء الإيقاف المؤقت

	var back := Button.new()
	back.text = "القائمة"
	back.position = Vector2(20, 100)
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(_to_menu)
	$UI.add_child(back)

	pause_btn = Button.new()
	pause_btn.text = "إيقاف"
	pause_btn.position = Vector2(540, 100)
	pause_btn.add_theme_font_size_override("font_size", 28)
	pause_btn.pressed.connect(_toggle_pause)
	$UI.add_child(pause_btn)

	flash_label = Label.new()
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.add_theme_font_size_override("font_size", 52)
	flash_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	flash_label.offset_top = 300
	flash_label.offset_bottom = 400
	flash_label.modulate.a = 0.0
	$UI.add_child(flash_label)

	result_panel = PanelContainer.new()
	result_panel.visible = false
	result_panel.custom_minimum_size = Vector2(580, 0)
	$UI.add_child(result_panel)
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	result_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	margin.add_child(vb)

	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 48)
	vb.add_child(result_title)

	result_stars = Label.new()
	result_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stars.add_theme_font_size_override("font_size", 96)
	vb.add_child(result_stars)

	result_coins = Label.new()
	result_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_coins.add_theme_font_size_override("font_size", 36)
	vb.add_child(result_coins)

	next_button = _make_button("المرحلة التالية", _go_next)
	vb.add_child(next_button)
	vb.add_child(_make_button("إعادة المرحلة", _replay))
	vb.add_child(_make_button("القائمة", _to_menu))


func _update_hud() -> void:
	label.text = "المرحلة %d     العملات: %d" % [level, coins]


func _flash(text: String) -> void:
	flash_label.text = text
	flash_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(flash_label, "modulate:a", 0.0, 0.6)

func _make_tone(f_start: float, f_end: float, duration: float,
		volume := 0.5, noise := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += TAU * lerpf(f_start, f_end, t) / rate
		var s := sin(phase)
		if noise > 0.0:
			s = lerpf(s, randf_range(-1.0, 1.0), noise)
		var env := minf(t * 30.0, 1.0) * (1.0 - t)   # بداية ناعمة ثم تلاشٍ
		var v := int(clampf(s * env * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _init_sounds() -> void:
	generated_sounds = {
		"coin": _make_tone(900.0, 1800.0, 0.15, 0.4),
		"hit": _make_tone(220.0, 70.0, 0.30, 0.6, 0.8),
		"fall": _make_tone(700.0, 120.0, 0.60, 0.4),
		"win": _make_tone(500.0, 1600.0, 0.50, 0.4),
	}



func _play_sound(sound_name: String) -> void:
	if not Save.sound_on:
		return
	var stream: AudioStream = null
	# ملف حقيقي في مجلد sounds له الأولوية إن وُجد
	for ext in ["ogg", "wav", "mp3"]:
		var path := "res://sounds/%s.%s" % [sound_name, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null:
		stream = generated_sounds.get(sound_name)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -4.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	
func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_btn.text = "استئناف" if get_tree().paused else "إيقاف"


# ---------- الجو العام ----------

func _apply_theme(n: int) -> void:
	var env := world_env.environment
	if env == null:
		return
	var bg := Color.from_hsv(fmod(0.55 + n * 0.1, 1.0), 0.7, 0.12)
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.fog_enabled = true
	env.fog_light_color = bg
	env.fog_density = 0.02


func _make_stars() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 6
	sphere.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	m.disable_fog = true
	sphere.material = m

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = 120
	for i in 120:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.05, 1), randf_range(-1, -0.2)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, dir * randf_range(60, 80)))

	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	camera.add_child(inst)


# ---------- إدارة المراحل ----------

func start_level() -> void:
	finished = false
	result_panel.visible = false
	for c in level_root.get_children():
		c.queue_free()
	coins = 0
	_apply_theme(level)
	build_level(level)
	ball.freeze = false
	ball.forward_speed = minf(8.0 + level * 0.6, 16.0)
	ball.reset_to(Vector3(0, 1, 0))
	camera.global_position = Vector3(0, 5.5, 7)
	_update_hud()
	if level == 2 and not hint_shown:
		hint_shown = true
		_flash("اسحب للأعلى للقفز!")


func _on_fell() -> void:
	if finished:
		return
	_play_sound("fall")
	Input.vibrate_handheld(200)
	_flash("سقطت!")
	_restart.call_deferred()


func _on_hazard(body: Node3D) -> void:
	if body == ball and not finished:
		_play_sound("hit")
		Input.vibrate_handheld(150)
		_flash("اصطدمت!")
		_restart.call_deferred()


func _on_finish(body: Node3D) -> void:
	if body == ball and not finished:
		_finish.call_deferred()


func _on_coin(body: Node3D, area: Area3D) -> void:
	if body == ball and not area.is_queued_for_deletion():
		coins += 1
		_update_hud()
		_play_sound("coin")
		area.queue_free()


func _restart() -> void:
	start_level()


func _finish() -> void:
	if finished:
		return
	finished = true
	ball.running = false
	ball.freeze = true

	var ratio := 1.0 if coins_total == 0 else float(coins) / coins_total
	var star_count := 1
	if ratio >= 0.5:
		star_count = 2
	if ratio >= 0.9:
		star_count = 3
	Save.complete(level, coins, star_count)
	_play_sound("win")

	result_title.text = "أحسنت! المرحلة %d" % level
	result_stars.text = "★".repeat(star_count) + "☆".repeat(3 - star_count)
	result_coins.text = "العملات: %d / %d" % [coins, coins_total]
	next_button.visible = level < MAX_LEVEL
	result_panel.visible = true


func _go_next() -> void:
	level += 1
	Save.current_level = level
	start_level()


func _replay() -> void:
	start_level()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------- بناء المرحلة بالكود ----------

func build_level(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919
	var crng := RandomNumberGenerator.new()
	crng.seed = n * 104729
	coins_total = 0

	var width := clampf(5.0 - n * 0.3, 2.4, 5.0)
	var segments := 10 + n * 2
	var hazard_chance := clampf(0.05 + n * 0.06, 0.0, 0.7)
	var max_shift := width * 0.6 * clampf(0.2 + n * 0.1, 0.0, 1.0)
	var moving_chance := clampf((n - 3) * 0.1, 0.0, 0.6)

	# الفجوات تبدأ من المرحلة 2 وتزداد وتتسع تدريجياً
	var gap_chance := 0.0 if n < 2 else clampf(0.10 + (n - 2) * 0.02, 0.0, 0.3)
	var gap_len := 3.0 + minf(n * 0.08, 1.5)
	var prev_gap := false

	var cx := 0.0
	for i in segments:
		var z := -i * SEG_LEN
		if i > 1:
			cx += rng.randf_range(-max_shift, max_shift)

		var after_gap := prev_gap
		var is_gap := i > 3 and not after_gap and rng.randf() < gap_chance
		prev_gap = is_gap

		var hue := fmod(0.55 + i * 0.015 + n * 0.1, 1.0)
		var color := Color.from_hsv(hue, 0.55, 0.95)

		if is_gap:
			# قطعتان قصيرتان بينهما فراغ
			var part := (SEG_LEN - gap_len) / 2.0
			_block(StaticBody3D.new(),
					Vector3(cx, -0.25, z + SEG_LEN / 2.0 - part / 2.0),
					Vector3(width, 0.5, part), color)
			_block(StaticBody3D.new(),
					Vector3(cx, -0.25, z - SEG_LEN / 2.0 + part / 2.0),
					Vector3(width, 0.5, part), color)
			_coin(Vector3(cx, 1.7, z))      # عملة في الهواء مكافأة للقفز
			continue

		_block(StaticBody3D.new(), Vector3(cx, -0.25, z),
				Vector3(width, 0.5, SEG_LEN), color)

		var has_hazard := false
		if i > 2 and not after_gap and rng.randf() < hazard_chance:
			has_hazard = true
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var hazard := Area3D.new()
			if rng.randf() < moving_chance:
				_block(hazard, Vector3(cx, 0.6, z),
						Vector3(width * 0.35, 1.2, 1.0), Color(1, 0.2, 0.8), 1.5)
				var t := maxf(1.6 - n * 0.05, 0.8)
				var tw := hazard.create_tween().set_loops()
				tw.tween_property(hazard, "position:x", cx + width * 0.3, t) \
						.set_trans(Tween.TRANS_SINE)
				tw.tween_property(hazard, "position:x", cx - width * 0.3, t) \
						.set_trans(Tween.TRANS_SINE)
			else:
				_block(hazard, Vector3(cx + side * width * 0.25, 0.6, z),
						Vector3(width * 0.5, 1.2, 1.0), Color(1, 0.15, 0.2), 1.5)
			hazard.body_entered.connect(_on_hazard)

		if not has_hazard and i > 0 and crng.randf() < 0.55:
			_coin(Vector3(cx + crng.randf_range(-width * 0.3, width * 0.3), 0.9, z))

	var zf := -segments * SEG_LEN
	_block(StaticBody3D.new(), Vector3(cx, -0.25, zf),
			Vector3(width + 2.0, 0.5, SEG_LEN), Color(0.9, 0.9, 0.9))
	var finish := Area3D.new()
	_block(finish, Vector3(cx, 0.2, zf),
			Vector3(width + 2.0, 0.4, 2.0), Color(0.2, 1.0, 0.4), 2.0)
	finish.body_entered.connect(_on_finish)


func _coin(pos: Vector3) -> void:
	coins_total += 1
	var area := Area3D.new()

	var pivot := Node3D.new()
	area.add_child(pivot)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.08
	mesh.mesh = cyl
	mesh.material_override = _mat(Color(1, 0.85, 0.1), 1.5)
	mesh.rotation_degrees = Vector3(90, 0, 0)
	pivot.add_child(mesh)

	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	shape.shape = sph
	area.add_child(shape)

	area.position = pos
	level_root.add_child(area)
	area.body_entered.connect(_on_coin.bind(area))

	var tw := area.create_tween().set_loops()
	tw.tween_property(pivot, "rotation_degrees:y", 360.0, 1.2).from(0.0)


func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _block(body: CollisionObject3D, pos: Vector3, size: Vector3,
		color: Color, glow := 0.0) -> CollisionObject3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color, glow)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = size
	shape.shape = bshape
	body.add_child(shape)

	body.position = pos
	level_root.add_child(body)
	return body
