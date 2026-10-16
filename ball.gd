class_name Ball
extends RigidBody3D

signal fell

@export var forward_speed := 8.0
@export var side_speed := 6.0
@export var jump_speed := 9.0

var steer := 0.0
var running := false

var _has_reset := false
var _reset_pos := Vector3.ZERO
var _touching := false
var _press_y := 0.0
var _swiped := false
var _jump_time := 0.0       # مدة بقاء طلب القفز صالحاً (يسامح التأخر بجزء من الثانية)
var _on_ground := false
var _trail_mat: StandardMaterial3D


func _ready() -> void:
	can_sleep = false
	gravity_scale = 2.0          # جاذبية أقوى = قفز أسرع وأوضح
	contact_monitor = true       # لنعرف هل الكرة تلمس الأرض
	max_contacts_reported = 4
	_make_trail()
	apply_skin(Save.skin_color())


func apply_skin(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.4
	$MeshInstance3D.material_override = mat
	$OmniLight3D.light_color = color
	if _trail_mat:
		_trail_mat.albedo_color = color
		_trail_mat.emission = color


func _make_trail() -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3.ZERO

	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve

	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.emission_enabled = true
	_trail_mat.emission_energy_multiplier = 2.0
	sphere.material = _trail_mat
	p.mesh = sphere
	add_child(p)


func reset_to(pos: Vector3) -> void:
	running = false
	_reset_pos = pos
	_has_reset = true


# ---------- الإدخال ----------

func _input(event: InputEvent) -> void:
	# رفع الإصبع أو الفأرة (يصلنا دائماً حتى فوق الأزرار)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_touching = false


func _unhandled_input(event: InputEvent) -> void:
	# الأحداث التي لم تأخذها الأزرار فقط
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_touching = true
		_press_y = event.position.y
		_swiped = false
	elif event is InputEventMouseMotion and _touching and not _swiped:
		if _press_y - event.position.y > 90.0:     # سحب للأعلى = قفز
			_swiped = true
			_jump_time = 0.15
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_UP or event.keycode == KEY_W:
			_jump_time = 0.15


func _get_steer() -> float:
	var s := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		s = -1.0
	if Input.is_key_pressed(KEY_D):
		s = 1.0
	if _touching:
		var half := get_viewport().get_visible_rect().size.x / 2.0
		s = -1.0 if get_viewport().get_mouse_position().x < half else 1.0
	return s


# ---------- الفيزياء ----------

func _physics_process(_delta: float) -> void:
	steer = _get_steer()
	if running and global_position.y < -6.0:
		running = false
		fell.emit()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _has_reset:
		state.transform = Transform3D(Basis.IDENTITY, _reset_pos)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_has_reset = false
		_jump_time = 0.0
		running = true
		return

	# هل الكرة تلمس أرضاً؟ (ميل السطح رأسي تقريباً)
	_on_ground = false
	for i in state.get_contact_count():
		if absf(state.get_contact_local_normal(i).y) > 0.5:
			_on_ground = true
			break

	_jump_time = maxf(_jump_time - state.step, 0.0)

	if not running:
		_jump_time = 0.0
		return

	var v := state.linear_velocity
	v.z = -forward_speed
	v.x = lerp(v.x, steer * side_speed, 8.0 * state.step)
	if _jump_time > 0.0 and _on_ground:
		v.y = jump_speed
		_jump_time = 0.0
	state.linear_velocity = v
