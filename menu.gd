extends Control

const TOTAL_LEVELS := 30

var coins_label: Label
var sound_btn: Button
var shop_panel: PanelContainer
var shop_vb: VBoxContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0b1026")
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 30)

	var title := Label.new()
	title.text = "لعبة الكرة"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)

	coins_label = Label.new()
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", 36)
	box.add_child(coins_label)
	_update_coins()


	# صف الأزرار: المتجر والصوت
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	row.add_child(_btn("المتجر", _open_shop))
	sound_btn = _btn("", _toggle_sound)
	row.add_child(sound_btn)
	_update_sound_text()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	for i in range(1, TOTAL_LEVELS + 1):
		var b := Button.new()
		var s := Save.get_stars(i)
		b.text = "%d\n%s%s" % [i, "★".repeat(s), "☆".repeat(3 - s)]
		b.custom_minimum_size = Vector2(150, 170)
		b.add_theme_font_size_override("font_size", 40)
		if i <= Save.unlocked:
			b.pressed.connect(_play.bind(i))
		else:
			b.disabled = true
		grid.add_child(b)


	_build_shop()


func _btn(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 90)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(handler)
	return b


func _update_coins() -> void:
	coins_label.text = "العملات: %d" % Save.total_coins


func _update_sound_text() -> void:
	sound_btn.text = "الصوت: " + ("يعمل" if Save.sound_on else "متوقف")


func _toggle_sound() -> void:
	Save.sound_on = not Save.sound_on
	Save.save_data()
	_update_sound_text()


func _play(level: int) -> void:
	Save.current_level = level
	get_tree().change_scene_to_file("res://main.tscn")



# ---------- المتجر ----------

func _build_shop() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.visible = false
	add_child(shop_panel)
	shop_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 50)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 25)
	shop_panel.add_child(margin)

	shop_vb = VBoxContainer.new()
	shop_vb.add_theme_constant_override("separation", 16)
	margin.add_child(shop_vb)


func _open_shop() -> void:
	_refresh_shop()
	shop_panel.visible = true


func _close_shop() -> void:
	shop_panel.visible = false
	_update_coins()


func _refresh_shop() -> void:
	for c in shop_vb.get_children():
		shop_vb.remove_child(c)
		c.queue_free()


	var t := Label.new()
	t.text = "المتجر      العملات: %d" % Save.total_coins
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	shop_vb.add_child(t)

	for i in Save.SKINS.size():
		var s: Dictionary = Save.SKINS[i]
		var text: String
		if i == Save.skin:
			text = "%s   ✔ مستخدم" % s["name"]
		elif i in Save.owned_skins:
			text = "%s   (اختيار)" % s["name"]
		else:
			text = "%s   — %d عملة" % [s["name"], s["price"]]
		var b := _btn(text, _on_skin.bind(i))
		b.custom_minimum_size = Vector2(0, 100)
		b.add_theme_color_override("font_color", s["color"])
		b.add_theme_color_override("font_hover_color", s["color"])
		b.add_theme_color_override("font_pressed_color", s["color"])
		shop_vb.add_child(b)

	shop_vb.add_child(_btn("إغلاق", _close_shop))


func _on_skin(i: int) -> void:
	Save.buy_or_select(i)
	_refresh_shop()
