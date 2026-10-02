## 福州麻将 HUD
## ------------------------------------------------------------------
## 中央动作按钮（吃 / 碰 / 杠 / 胡 / 过 / 出牌）、残局结算面板、日志与帮助。
class_name HudLayer
extends CanvasLayer

var game: GameState
var table: TableView
var sfx: Sfx
var tex: Dictionary = {}
var font_bold: Font
var font_ui: Font

var root: Control
var action_bar: HBoxContainer
var result_box: PanelContainer
var result_label: RichTextLabel
var help_box: PanelContainer
var log_label: Label
var status_label: Label
var _actions_claim := false   ## 当前动作条是「叫牌决策」还是「己方回合常驻」
var _ready_button: Button
## 一圈局数（由 main 注入）：当前局为最后一局时，准备按钮改为「总成绩」
var hands_per_match := 4
## 由 main 注入：返回 true 表示「本圈已结束，已切换到总结算场景」
var on_ready_request: Callable = Callable()

func _ready() -> void:
	font_bold = GameFonts.make(700)
	font_ui = GameFonts.make(400)
	for n in ["btn_gold", "btn_gold_hl", "panel_player", "panel_center", "icon_coin", "icon_flower"]:
		var p := "res://assets/generated/%s.png" % n
		if ResourceLoader.exists(p):
			tex[n] = load(p)
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	set_process(true)

func set_game(gs: GameState, tv: TableView) -> void:
	game = gs
	table = tv
	game.state_changed.connect(_refresh)
	game.log_line.connect(_on_log)
	_refresh()

# ------------------------------------------------------------------ 构建
func _build() -> void:
	action_bar = HBoxContainer.new()
	action_bar.name = "ActionBar"
	action_bar.add_theme_constant_override("separation", 14)
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(action_bar)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.add_theme_font_override("font", font_bold)
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.95))
	status_label.position = Vector2(0, 12)
	status_label.size = Vector2(1400, 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

	# 顶部状态条背板（不与牌桌元素重叠）
	var bar := ColorRect.new()
	bar.name = "StatusBar"
	bar.color = Color(0.0, 0.20, 0.19, 0.55)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1400, 50)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	root.move_child(bar, 0)

	result_box = _build_result_panel()
	help_box = _build_help_panel()
	help_box.visible = false

	# 结算面板底部的常驻按钮：随时可结束本圈查看总成绩
	var quit_btn := _make_button("结束对局", Vector2(150, 44))
	quit_btn.name = "EndMatchButton"
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.pressed.connect(func():
		if on_ready_request.is_valid():
			on_ready_request.call(true))
	quit_btn.position = Vector2(12, 60)
	root.add_child(quit_btn)

func _stylebox() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var t: Texture2D = tex.get("btn_gold")
	if t:
		sb.texture = t
		sb.set_content_margin_all(10)
	return sb

func _make_button(text: String, size: Vector2 = Vector2(148, 62)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.20, 0.11, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.35, 0.08, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.05, 0.0))
	b.add_theme_stylebox_override("normal", _stylebox())
	var hover := StyleBoxTexture.new()
	var ht: Texture2D = tex.get("btn_gold_hl")
	if ht:
		hover.texture = ht
		hover.set_content_margin_all(10)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b

func _build_result_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "ResultPanel"
	pc.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.22, 0.21, 0.96)
	sb.border_color = Color(1.0, 0.85, 0.35, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(24)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(580, 210)
	result_label.add_theme_font_override("normal_font", font_ui)
	result_label.add_theme_font_override("bold_font", font_bold)
	result_label.add_theme_font_override("italics_font", font_ui)
	result_label.add_theme_font_override("mono_font", font_ui)
	result_label.add_theme_font_size_override("normal_font_size", 26)
	vb.add_child(result_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var again := _make_button("准 备", Vector2(210, 68))
	again.name = "ReadyButton"
	again.pressed.connect(_on_ready)
	_ready_button = again
	hb.add_child(again)
	var help := _make_button("玩法", Vector2(150, 68))
	help.name = "HelpButton"
	help.pressed.connect(func():
		if sfx:
			sfx.play("click", -10.0)
		help_box.visible = not help_box.visible)
	hb.add_child(help)
	root.add_child(pc)
	return pc

func _build_help_panel() -> PanelContainer:
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
	pc.custom_minimum_size = Vector2(780, 900)
	# 规则文本较长：放入可滚动容器，避免面板超出屏幕
	var sc := ScrollContainer.new()
	sc.name = "HelpScroll"
	sc.custom_minimum_size = Vector2(728, 860)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(704, 0)
	rt.add_theme_font_override("normal_font", font_ui)
	rt.add_theme_font_override("bold_font", font_bold)
	rt.add_theme_font_size_override("normal_font_size", 20)
	rt.text = _help_text()
	sc.add_child(rt)
	root.add_child(pc)
	return pc

func _help_text() -> String:
	return RulesText.help()

# ------------------------------------------------------------------ 刷新
func _refresh() -> void:
	if game == null or game.players.is_empty():
		return
	_rebuild_actions()
	var r: Dictionary = game.result
	if game.finished and not r.is_empty():
		result_box.visible = true
		result_label.text = _result_text(r)
	else:
		result_box.visible = false
	if _ready_button:
		_ready_button.text = "总成绩" if is_match_final_hand() else "准 备"
	status_label.text = _status_text()
	if log_label:
		log_label.text = ""

func _status_text() -> String:
	if game == null or game.players.is_empty():
		return ""
	var p: Dictionary = game.players[GameState.SEAT_SELF]
	var ting := game.human_ting_hint()
	var o: Dictionary = game.players[(game.turn + 4) % 4]
	var s := "手牌 %d 张 · 金 %d 张 · 花 %d 朵 · 余牌 %d · 轮到 %s" % [
		p["hand"].size(), game.jokers_in(GameState.SEAT_SELF), p["flowers"].size(),
		game.remaining(), o["name"]]
	var left := game.discards_remaining()
	if left > 1:
		s += "   [开金补花：还需打出 %d 张]" % left
	if not ting.is_empty():
		s += "   [听牌中]"
	return s

func _result_text(r: Dictionary) -> String:
	var win: int = r.get("winner", -1)
	if win < 0:
		return "[center][b][color=#ffe08a]和局[/color][/b]\n\n%s[/center]" % r.get("detail", "")
	var p: Dictionary = game.players[win]
	var head := "[center][b][color=#ffe08a]%s  %s[/color][/b]\n\n" % [p["name"], r.get("win_name", "")]
	head += "得分 [color=#ffd94a]%+d[/color]    %s\n" % [r.get("points", 0), r.get("detail", "")]
	if r.get("self_draw", false):
		head += "（自摸 ×2，三家各付 %d）" % int(r.get("core", 0))
	else:
		var loser: int = r.get("loser", -1)
		if loser >= 0:
			head += "（点炮：%s，三家各付 %d）" % [game.players[loser]["name"], int(r.get("core", 0))]
	head += "\n\n[color=#b9f5c0]本局手牌[/color]："
	var cards := PackedStringArray()
	for t in p["hand"]:
		cards.append(Tiles.kind_name(t))
	for m in p["melds"]:
		cards.append("[" + ",".join(m["tiles"].map(func(t): return Tiles.kind_name(t))) + "]")
	head += " ".join(cards) + "\n"
	var scores := PackedStringArray()
	for q in game.players:
		scores.append("%s %d" % [q["name"], q["score"]])
	head += "[color=#b9f5c0]总分[/color]：" + "   ".join(scores) + "[/center]"
	return head

func _rebuild_actions() -> void:
	for c in action_bar.get_children():
		c.queue_free()
	action_bar.visible = false
	if game == null or game.finished:
		_layout_action_bar()
		return
	var btns: Array = []
	_actions_claim = not game.human_options.is_empty()
	if _actions_claim:
		var seen := {}
		for cl in game.human_options:
			var a: String = cl["action"]
			if a == "chi":
				var parts := PackedStringArray()
				for t in cl["tiles"]:
					parts.append(Tiles.short_name(int(t)))
				var label: String = "吃 " + ",".join(parts)
				btns.append({"text": label, "act": "chi", "tiles": cl["tiles"]})
				continue
			if seen.has(a):
				continue
			seen[a] = true
			var txt: String = str({"hu": "胡", "peng": "碰", "gang": "杠"}.get(a, a))
			btns.append({"text": txt, "act": a, "tiles": []})
		btns.append({"text": "过", "act": "pass", "tiles": []})
	elif game.human_selectable():
		for k in game.human_bugang_tiles():
			btns.append({"text": "补杠 " + Tiles.short_name(k), "act": "bugang", "tiles": [k]})
		for k in game.human_angang_tiles():
			btns.append({"text": "暗杠 " + Tiles.short_name(k), "act": "angang", "tiles": [k]})
		btns.append({"text": "出牌", "act": "discard", "tiles": []})
	if btns.is_empty():
		_layout_action_bar()
		return
	action_bar.visible = true
	for b in btns:
		var btn := _make_button(b["text"])
		btn.name = "Btn_" + b["act"]
		btn.pressed.connect(_on_action.bind(b["act"], b["tiles"]))
		action_bar.add_child(btn)
	action_bar.reset_size()
	_layout_action_bar()

func _layout_action_bar() -> void:
	if action_bar == null:
		return
	var w := action_bar.get_combined_minimum_size().x
	if _actions_claim:
		# 叫牌决策（吃/碰/杠/胡/过）：桌面中央、自家弃牌区上方，限时 6 秒
		action_bar.position = Vector2(700 - w * 0.5, 648)
	else:
		# 己方回合常驻按钮（出牌/补杠/暗杠）：右下角，避开自家信息牌
		action_bar.position = Vector2(1332 - w, 836)
	if result_box and result_box.visible:
		result_box.reset_size()
		var s := result_box.get_combined_minimum_size()
		result_box.position = Vector2(700 - s.x * 0.5, 540 - s.y * 0.5)
	if help_box and help_box.visible:
		help_box.reset_size()
		var hs := help_box.get_combined_minimum_size()
		help_box.position = Vector2(700 - hs.x * 0.5, 540 - hs.y * 0.5)

func _process(_delta: float) -> void:
	_layout_action_bar()

# ------------------------------------------------------------------ 事件
func _on_action(act: String, tiles: Array) -> void:
	if game == null:
		return
	if sfx:
		sfx.play("click", -10.0)
	match act:
		"pass":
			game.resolve_human_claim("pass")
		"chi":
			game.resolve_human_claim("chi", tiles)
		"hu", "peng", "gang":
			game.resolve_human_claim(act, tiles)
		"angang":
			if tiles.size() > 0:
				game.do_an_gang(GameState.SEAT_SELF, tiles[0])
		"bugang":
			if tiles.size() > 0:
				game.do_bu_gang(GameState.SEAT_SELF, tiles[0])
		"discard":
			if table:
				table.discard_selected()
	_refresh()

func _on_ready() -> void:
	if game == null:
		return
	if sfx:
		sfx.play("deal", -9.0)
	# 本圈最后一局结束后由 main 接管（切换到总结算场景）
	if on_ready_request.is_valid() and bool(on_ready_request.call()):
		return
	game.start_hand()
	result_box.visible = false
	_refresh()

## 是否已是本圈最后一局（准备按钮显示为「总成绩」）
func is_match_final_hand() -> bool:
	return game != null and game.hand_no >= hands_per_match

func _on_log(t: String) -> void:
	pass

func toggle_help() -> void:
	help_box.visible = not help_box.visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		toggle_help()
	elif event.is_action_pressed("ui_cancel"):
		if help_box.visible:
			help_box.visible = false
		elif result_box.visible:
			pass
	elif event.is_action_pressed("ui_accept"):
		if game and game.human_selectable() and table:
			table.discard_selected()
