## 福州麻将 总结算场景（一圈结束）
## ------------------------------------------------------------------
## 读取 MatchSummary 的四家总分，按高到低排名展示，可再来一圈或回主菜单。
extends Control

const W := 1400.0
const H := 1080.0

var tex: Dictionary = {}
var font_bold: Font
var font_ui: Font
var sfx: Sfx

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_assets()
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	if args.has("--demo") and not MatchSummary.has_data():
		_seed_demo()
	_build()
	if MatchSummary.has_data():
		var rank := MatchSummary.ranking()
		if rank.size() > 0 and int(rank[0]["seat"]) == 0:
			sfx.play("win")
		else:
			sfx.play("lose")
	queue_redraw()
	if args.has("--shot"):
		_run_shot(args)

## 演示数据（截图 / 无对局记录时预览）
func _seed_demo() -> void:
	MatchSummary.names = PackedStringArray(["我", "则徐", "葆桢", "徽因"])
	MatchSummary.scores = [36, 12, -18, -30]
	MatchSummary.is_ai = [false, true, true, true]
	MatchSummary.hands = 4

func _run_shot(args: Array) -> void:
	var path := "end.png"
	var frames := 30
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		path = args[i + 1]
	i = args.find("--frames")
	if i >= 0 and i + 1 < args.size():
		frames = int(args[i + 1])
	for f in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] ", path)
	get_tree().quit()

func _load_assets() -> void:
	font_bold = GameFonts.make(700)
	font_ui = GameFonts.make(400)
	for n in ["felt", "tile_blank", "btn_gold", "btn_gold_hl", "icon_coin"]:
		var p := "res://assets/generated/%s.png" % n
		if ResourceLoader.exists(p):
			tex[n] = load(p)

# ------------------------------------------------------------------ 构建
func _build() -> void:
	if tex.has("felt"):
		var bg := TextureRect.new()
		bg.texture = tex["felt"]
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.09, 0.09, 0.45)
	veil.size = Vector2(W, H)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_title("本圈结束", Vector2(W * 0.5, 150), 92, Color(1.0, 0.87, 0.42))
	var sub := "共 %d 局 · 四家总分" % MatchSummary.hands
	_title(sub, Vector2(W * 0.5, 240), 30, Color(0.86, 0.96, 0.92))

	# 计分板与按钮放进同一列，由容器负责排布，避免互相重叠
	var center := CenterContainer.new()
	center.name = "Console"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 300
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	var col := VBoxContainer.new()
	col.name = "SummaryColumn"
	col.add_theme_constant_override("separation", 28)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(col)

	var board := PanelContainer.new()
	board.name = "Board"
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.18, 0.17, 0.92)
	sb.border_color = Color(1.0, 0.85, 0.35, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	board.add_theme_stylebox_override("panel", sb)
	board.custom_minimum_size = Vector2(680, 0)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 14)
	board.add_child(vb)
	if MatchSummary.has_data():
		for row in MatchSummary.ranking():
			vb.add_child(_row(row))
	else:
		var empty := Label.new()
		empty.text = "暂无对局记录"
		empty.add_theme_font_override("font", font_bold)
		empty.add_theme_font_size_override("font_size", 30)
		empty.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
		empty.custom_minimum_size = Vector2(620, 60)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(empty)
	col.add_child(board)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(box)
	box.add_child(_menu_button("再来一圈", _on_again, "BtnAgain"))
	box.add_child(_menu_button("返回主菜单", _on_menu, "BtnMenu"))
	box.add_child(_menu_button("退出游戏", _on_quit, "BtnQuit"))

func _row(row: Dictionary) -> Control:
	var seat: int = int(row["seat"])
	var rank: int = int(row["rank"])
	var is_me := seat == 0
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.custom_minimum_size = Vector2(620, 64)

	var idx: int = mini(rank - 1, 3)
	var medal: String = ["冠 军", "亚 军", "季 军", "第 4 名"][idx]
	var colors: Array[Color] = [Color(1.0, 0.85, 0.35), Color(0.85, 0.90, 0.95),
		Color(0.86, 0.66, 0.42), Color(0.70, 0.78, 0.76)]
	var rk := Label.new()
	rk.text = medal
	rk.custom_minimum_size = Vector2(110, 0)
	rk.add_theme_font_override("font", font_bold)
	rk.add_theme_font_size_override("font_size", 26)
	rk.add_theme_color_override("font_color", colors[idx])
	rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(rk)

	var nm := Label.new()
	nm.text = ("%s%s" % [str(row["name"]), "（我）" if is_me else ""])
	nm.custom_minimum_size = Vector2(240, 0)
	nm.add_theme_font_override("font", font_bold)
	nm.add_theme_font_size_override("font_size", 30)
	nm.add_theme_color_override("font_color",
		Color(1.0, 0.93, 0.72) if is_me else Color(0.92, 0.98, 0.95))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(nm)

	var sc := Label.new()
	var score: int = int(row["score"])
	sc.text = "%+d" % score
	sc.custom_minimum_size = Vector2(200, 0)
	sc.add_theme_font_override("font", font_bold)
	sc.add_theme_font_size_override("font_size", 34)
	sc.add_theme_color_override("font_color",
		Color(0.62, 0.98, 0.66) if score > 0 else (Color(1.0, 0.55, 0.5) if score < 0 else Color(0.85, 0.9, 0.9)))
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(sc)
	return hb

func _title(text: String, center: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.12, 0.10, 0.9))
	l.add_theme_constant_override("outline_size", 8 if size >= 60 else 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(W, size * 1.8)
	l.position = Vector2(0, center.y - size * 0.9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _menu_button(text: String, cb: Callable, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(340, 70)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.20, 0.11, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.08, 0.02))
	var sb := StyleBoxTexture.new()
	var t: Texture2D = tex.get("btn_gold")
	if t:
		sb.texture = t
		sb.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var hl := StyleBoxTexture.new()
	var ht: Texture2D = tex.get("btn_gold_hl")
	if ht:
		hl.texture = ht
		hl.set_content_margin_all(10)
	b.add_theme_stylebox_override("hover", hl)
	b.add_theme_stylebox_override("pressed", hl)
	b.pressed.connect(cb)
	return b

# ------------------------------------------------------------------ 事件
func _on_again() -> void:
	if sfx:
		sfx.play("deal")
	MatchSummary.clear()
	get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")

func _on_menu() -> void:
	if sfx:
		sfx.play("click")
	MatchSummary.clear()
	get_tree().change_scene_to_file.call_deferred("res://scenes/Start.tscn")

func _on_quit() -> void:
	get_tree().quit()
