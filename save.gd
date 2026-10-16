extends Node

const PATH := "user://save.cfg"

# أشكال الكرة: الاسم، اللون، السعر
const SKINS := [
	{"name": "برتقالي", "color": Color(1.0, 0.55, 0.1), "price": 0},
	{"name": "أزرق", "color": Color(0.2, 0.6, 1.0), "price": 20},
	{"name": "أخضر", "color": Color(0.2, 1.0, 0.4), "price": 40},
	{"name": "وردي", "color": Color(1.0, 0.3, 0.7), "price": 60},
	{"name": "ذهبي", "color": Color(1.0, 0.85, 0.2), "price": 100},
	{"name": "أبيض", "color": Color(0.95, 0.95, 1.0), "price": 150},
]

var unlocked := 1
var current_level := 1
var total_coins := 0
var stars := {}                 # رقم المرحلة -> أفضل عدد نجوم
var owned_skins: Array = [0]    # الأشكال المملوكة
var skin := 0                   # الشكل المختار
var sound_on := true


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	unlocked = cfg.get_value("progress", "unlocked", 1)
	total_coins = cfg.get_value("progress", "coins", 0)
	owned_skins = cfg.get_value("shop", "owned", [0])
	skin = cfg.get_value("shop", "selected", 0)
	sound_on = cfg.get_value("settings", "sound", true)
	if cfg.has_section("stars"):
		for k in cfg.get_section_keys("stars"):
			stars[int(k)] = cfg.get_value("stars", k)


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "coins", total_coins)
	cfg.set_value("shop", "owned", owned_skins)
	cfg.set_value("shop", "selected", skin)
	cfg.set_value("settings", "sound", sound_on)
	for k in stars:
		cfg.set_value("stars", str(k), stars[k])
	cfg.save(PATH)


func complete(level: int, earned: int, star_count: int) -> void:
	total_coins += earned
	if level >= unlocked:
		unlocked = level + 1
	if star_count > get_stars(level):
		stars[level] = star_count
	save_data()


func get_stars(level: int) -> int:
	return stars.get(level, 0)


# شراء شكل أو اختياره إن كان مملوكاً. ترجع true عند النجاح
func buy_or_select(i: int) -> bool:
	if i in owned_skins:
		skin = i
		save_data()
		return true
	var price: int = SKINS[i]["price"]
	if total_coins >= price:
		total_coins -= price
		owned_skins.append(i)
		skin = i
		save_data()
		return true
	return false


func skin_color() -> Color:
	return SKINS[skin]["color"]
