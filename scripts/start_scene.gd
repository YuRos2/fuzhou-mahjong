## 福州麻将 开始场景（主菜单）
## ------------------------------------------------------------------
## 标题 + 装饰牌面 + 开始 / 玩法 / 音效 / 退出。
## 带命令行开发参数（--shot/--auto/--selftest/--state …）时直接转入牌桌场景，
## 保证原有截图与自测流程不受菜单影响。
extends Control

const W := 1400.0
const H := 1080.0

var tex: Dictionary = {}
var font_bold: Font
var font_ui: Font
var sfx: Sfx
var help_box: Control
var sound_btn: Button

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_assets()
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	_build()
	queue_redraw()
	# --menu 强制停在菜单（供截图用）；其余开发参数直接进牌桌
	if not args.has("--menu") and _has_dev_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")
		return
	if args.has("--shot"):
		_run_shot(args)

func _has_dev_args() -> bool:
	for a in OS.get_cmdline_user_args():
		if a in ["--shot", "--auto", "--selftest", "--state", "--exit-after", "--help"]:
			return true
	return false

## 菜单截图（开发验收用）
func _run_shot(args: Array) -> void:
	var path := "menu.png"
	var frames := 30
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		path = args[i + 1]
	i = args.find("--frames")
	if i >= 0 and i + 1 < args.size():
		frames = int(args[i + 1])
	if args.has("--help"):
		_on_help()
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
	for n in ["felt", "tile_blank", "btn_gold", "btn_gold_hl"]:
		var p := "res://assets/generated/%s.png" % n
		if ResourceLoader.exists(p):
			tex[n] = load(p)

# ------------------------------------------------------------------ 构建
func _build() -> void:
	if tex.has("felt"):
		var bg := TextureRect.new()
		bg.name = "Bg"
		bg.texture = tex["felt"]
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	# 顶部渐暗，突出标题
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.10, 0.10, 0.35)
	veil.position = Vector2(0, 0)
	veil.size = Vector2(W, H)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_label("福州麻将", Vector2(W * 0.5, 168), 108, Color(1.0, 0.87, 0.42), 10)
	_label("福州本地玩法 · 144 张 · 金牌财神", Vector2(W * 0.5, 268), 30, Color(0.86, 0.96, 0.92), 0)

	var box := VBoxContainer.new()
	box.name = "Menu"
	box.add_theme_constant_override("separation", 18)
	box.position = Vector2(W * 0.5 - 170, 650)
	box.custom_minimum_size = Vector2(340, 0)
	add_child(box)
	box.add_child(_menu_button("开始游戏", _on_start, "BtnStart"))
	box.add_child(_menu_button("玩法说明", _on_help, "BtnHelp"))
	sound_btn = _menu_button("音效：开", _on_toggle_sound, "BtnSound")
	box.add_child(sound_btn)
	box.add_child(_menu_button("退出游戏", _on_quit, "BtnQuit"))

	var tip := _label("鼠标点击出牌 · H 帮助 · A 托管 · 空格出牌", Vector2(W * 0.5, H - 44), 22,
		Color(0.78, 0.90, 0.88, 0.85), 0)
	tip.name = "Tip"

	# 装饰牌面：用子 Control 绘制，才能盖在背景 / 遮罩之上
	var decor := Control.new()
	decor.name = "Decor"
	decor.set_anchors_preset(Control.PRESET_FULL_RECT)
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decor)
	decor.draw.connect(_draw_decor.bind(decor))
	move_child(decor, 2)

	help_box = _build_help()
	help_box.visible = false
	add_child(help_box)

func _label(text: String, center: Vector2, size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0.06, 0.12, 0.10, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(W, size * 1.8)
	l.position = Vector2(0, center.y - size * 0.9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _menu_button(text: String, cb: Callable, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(340, 74)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", Color(0.20, 0.11, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.08, 0.02))
	b.add_theme_stylebox_override("normal", _style("btn_gold"))
	b.add_theme_stylebox_override("hover", _style("btn_gold_hl"))
	b.add_theme_stylebox_override("pressed", _style("btn_gold_hl"))
	b.pressed.connect(cb)
	return b

func _style(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var t: Texture2D = tex.get(name)
	if t:
		sb.texture = t
		sb.set_content_margin_all(10)
	return sb

func _build_help() -> Control:
	var overlay := Control.new()
	overlay.name = "HelpOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var pc := PanelContainer.new()
	pc.name = "HelpPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.16, 0.16, 0.97)
	sb.border_color = Color(1.0, 0.85, 0.35, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(820, 920)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(768, 880)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(744, 0)
	rt.add_theme_font_override("normal_font", font_ui)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 20)
	rt.text = RulesText.intro() + "\n\n" + RulesText.help()
	sc.add_child(rt)
	pc.reset_size()
	var s := pc.get_combined_minimum_size()
	pc.position = Vector2(W * 0.5 - s.x * 0.5, 60)
	overlay.add_child(pc)
	var close := _menu_button("返回", _on_help, "BtnCloseHelp")
	close.custom_minimum_size = Vector2(180, 56)
	close.add_theme_font_size_override("font_size", 26)
	close.position = Vector2(W * 0.5 - 90, 60 + s.y + 12)
	overlay.add_child(close)
	return overlay

# ------------------------------------------------------------------ 装饰
func _draw_decor(ci: CanvasItem) -> void:
	# 一排装饰牌面（含轻微投影，增加质感）
	var kinds := [0, 10, 20, 27, 29, 31, 32, 33, 34, 41]
	var tw := 86.0
	var th := 114.0
	var pitch := 96.0
	var total: float = pitch * kinds.size() - (pitch - tw)
	var x: float = W * 0.5 - total * 0.5
	var y := 356.0
	for k in kinds:
		var r := Rect2(Vector2(x, y), Vector2(tw, th))
		ci.draw_rect(Rect2(r.position + Vector2(2, 5), r.size), Color(0, 0.06, 0.05, 0.35), true)
		TileGlyphs.draw_face(ci, r, int(k), tex.get("tile_blank"), font_ui, font_bold)
		x += pitch

# ------------------------------------------------------------------ 事件
func _on_start() -> void:
	if sfx:
		sfx.play("deal")
	MatchSummary.clear()
	get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")

func _on_help() -> void:
	if sfx:
		sfx.play("click")
	help_box.visible = not help_box.visible

func _on_toggle_sound() -> void:
	if sfx == null:
		return
	sfx.set_enabled(not sfx.enabled)
	sound_btn.text = "音效：开" if sfx.enabled else "音效：关"
	if sfx.enabled:
		sfx.play("click")

func _on_quit() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and help_box and help_box.visible:
		help_box.visible = false
		get_viewport().set_input_as_handled()
