## 福州麻将 主入口
## ------------------------------------------------------------------
## 负责：背景台呢铺满、桌面视图定位、牌局推进、命令行截图 / 托管调试开关。
##   godot --path . -- --shot out.png --frames 240
##   godot --path . -- --auto --frames 900
extends Node2D

const TABLE_SIZE := Vector2(1400, 1080)

@onready var felt: Sprite2D = $Felt
@onready var table: TableView = $Table
@onready var hud: HudLayer = $HUD

var game: GameState

var _shot_path := ""
var _shot_frames := 120
var _shot_series := 1
var _shot_gap := 30
var _autoplay := false
var _exit_frames := -1
var _frame := 0
var _selftest := false
var _honors_tiles := false
var _hand13 := false
var _force_state := ""
var _show_help := false
var _hands_per_match := 4     ## 一圈 = 4 局（四家轮流坐庄）
var _sfx: Sfx
var _ending := false
var _to_end := false          ## 调试：直接跳到总结算场景

func _ready() -> void:
	_parse_args()
	_load_felt()
	# 手牌张数：16 = 福州传统（闲 16 / 庄 17，含坎门），13 = 参考实机（4399 简化版）
	game = GameState.new(13 if _hand13 else 16)
	game.honors_as_flowers = not _honors_tiles
	game.autoplay = _autoplay
	_sfx = Sfx.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	table.sfx = _sfx
	hud.sfx = _sfx
	hud.hands_per_match = _hands_per_match
	hud.on_ready_request = _on_ready_request
	table.set_game(game)
	hud.set_game(game, table)
	game.log_line.connect(_on_log)
	game.log_line.connect(_on_sfx_log)
	game.hand_finished.connect(_on_hand_finished)
	game.state_changed.connect(_on_sfx_state)
	game.new_match()
	get_viewport().size_changed.connect(_layout)
	_layout()
	print("[MJ] 开局完成，庄家=%s，金=%s，手牌=%d张，花牌模式=%s，金牌不可打出" % [
		game.players[game.dealer]["name"],
		Tiles.kind_name(game.joker_kind) if game.joker_kind >= 0 else "无",
		game.hand_size,
		"36 张花牌（字牌花28+彩花8）" if game.honors_as_flowers else "8 张彩花（实机变体）"])
	if _to_end:
		MatchSummary.store(game)
		get_tree().change_scene_to_file.call_deferred("res://scenes/End.tscn")
		return
	if _force_state != "":
		_apply_force_state(_force_state)
	if _show_help:
		hud.toggle_help()
	if _selftest:
		_run_selftest()
	elif _shot_path != "":
		_run_shots()

func _apply_force_state(name: String) -> void:
	match name:
		"claim":
			game.debug_force_claim()
		"win":
			game.debug_force_win()
		"draw_game":
			game.debug_force_draw_game()
	print("[MJ] 强制状态 = ", name)

func _on_log(t: String) -> void:
	print("[MJ] ", t)

# ------------------------------------------------------------------ 音效
func _on_sfx_state() -> void:
	if _sfx == null or game == null:
		return
	var t: String = str(game.event_fx.get("type", ""))
	match t:
		"draw":
			_sfx.play("draw", -14.0)
		"discard":
			_sfx.play("discard", -9.0)
		"call":
			match str(game.event_fx.get("text", "")):
				"碰": _sfx.play("peng")
				"杠", "暗杠": _sfx.play("gang")
				"吃": _sfx.play("chi")
		"win":
			var k: int = int(game.result.get("win_kind", Rules.Win.NORMAL))
			_sfx.play("win" if k in [Rules.Win.SAN_JIN, Rules.Win.QIANG_JIN, Rules.Win.JIN_QUE, Rules.Win.TIAN_HU] else "hu")
		"draw_game":
			_sfx.play("lose")

func _on_sfx_log(t: String) -> void:
	if _sfx == null:
		return
	if t.contains("开金 →"):
		_sfx.play("kaijin")
	elif t.begins_with("我 补花") or t.begins_with("庄家补花"):
		_sfx.play("flower", -13.0)

func _on_hand_finished(r: Dictionary) -> void:
	print("[MJ-RESULT] ", JSON.stringify(r))
	if _sfx == null:
		return
	if int(r.get("winner", -1)) == -1:
		return
	if int(r.get("loser", -1)) == GameState.SEAT_SELF and not bool(r.get("self_draw", true)):
		_sfx.play("lose", -8.0)

## 结算面板「准备 / 总成绩」：一圈结束则切到总结算场景
func _on_ready_request(force_end: bool = false) -> bool:
	if game == null or _ending:
		return false
	if force_end or game.hand_no >= _hands_per_match:
		_ending = true
		if _sfx:
			_sfx.play("click")
		MatchSummary.store(game)
		get_tree().change_scene_to_file.call_deferred("res://scenes/End.tscn")
		return true
	return false

func _load_felt() -> void:
	var p := "res://assets/generated/felt.png"
	if ResourceLoader.exists(p):
		felt.texture = load(p)
		felt.centered = true
		felt.z_index = -100

func _layout() -> void:
	var vp := get_viewport_rect().size
	if felt.texture:
		felt.position = vp * 0.5
		var ts: Vector2 = felt.texture.get_size()
		var s := maxf(vp.x / ts.x, vp.y / ts.y)
		felt.scale = Vector2(s, s)
	var origin := ((vp - TABLE_SIZE) * 0.5).round()
	table.position = origin
	if hud.root:
		hud.root.position = origin

func _process(delta: float) -> void:
	_frame += 1
	if game:
		game.tick(delta)
	if _exit_frames > 0 and _frame >= _exit_frames:
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_autoplay"):
		if game:
			game.autoplay = not game.autoplay
			print("[MJ] 托管 = ", game.autoplay)
	elif event.is_action_pressed("force_win"):
		if game:
			game.debug_force_win()

# ------------------------------------------------------------------ 交互自测
## 用真实输入事件驱动：选牌 → 打出 → 碰牌按钮 → 结算面板
func _run_selftest() -> void:
	var tally := {"pass": 0, "fail": 0}
	var step := func(ok: bool, what: String) -> void:
		if ok:
			tally["pass"] += 1
			print("[TEST-PASS] ", what)
		else:
			tally["fail"] += 1
			print("[TEST-FAIL] ", what)

	for f in 30:
		await get_tree().process_frame

	# 1) 碰提示按钮
	game.debug_force_claim()
	for f in 6:
		await get_tree().process_frame
	var btn := hud.find_child("Btn_peng", true, false) as Button
	step.call(btn != null, "碰按钮已生成")
	if btn:
		var melds_before: int = game.players[GameState.SEAT_SELF]["melds"].size()
		btn.pressed.emit()
		step.call(game.players[GameState.SEAT_SELF]["melds"].size() == melds_before + 1, "点击碰后副露 +1")
	for f in 6:
		await get_tree().process_frame

	# 2) 推进到人类回合（AI 自动打牌）
	game.autoplay = false
	var guard := 0
	while not game.human_selectable() and guard < 900:
		guard += 1
		await get_tree().process_frame
	step.call(game.human_selectable(), "推进到人类出牌回合")
	if game.human_selectable():
		var slots := table.self_slot_rects()
		step.call(slots.size() > 0, "手牌槽位已生成")
		var rect: Rect2 = slots[0]["rect"]
		var origin := table.position
		var click_pos := origin + rect.get_center()
		_click(click_pos)
		for f in 3:
			await get_tree().process_frame
		step.call(table.selected_index == 0, "鼠标点击选中手牌")
		var hand_before: int = game.players[GameState.SEAT_SELF]["hand"].size()
		_click(click_pos)
		for f in 3:
			await get_tree().process_frame
		step.call(game.players[GameState.SEAT_SELF]["hand"].size() == hand_before - 1, "再次点击打出该牌")

	# 3) 结果面板
	game.debug_force_win()
	for f in 6:
		await get_tree().process_frame
	step.call(hud.result_box.visible, "结算面板已显示")
	var ready_btn := hud.find_child("ReadyButton", true, false) as Button
	step.call(ready_btn != null, "准备按钮已生成")
	if ready_btn:
		ready_btn.pressed.emit()
		for f in 4:
			await get_tree().process_frame
		step.call(not game.finished and game.players[GameState.SEAT_SELF]["hand"].size() > 0, "点击准备开始下一局")

	print("[TEST-SUMMARY] pass=%d fail=%d" % [tally["pass"], tally["fail"]])
	get_tree().quit(1 if int(tally["fail"]) > 0 else 0)

func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)

# ------------------------------------------------------------------ 截图
func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--shot":
				i += 1
				_shot_path = args[i] if i < args.size() else ""
			"--frames":
				i += 1
				_shot_frames = int(args[i]) if i < args.size() else 120
			"--series":
				i += 1
				_shot_series = int(args[i]) if i < args.size() else 1
			"--gap":
				i += 1
				_shot_gap = int(args[i]) if i < args.size() else 30
			"--auto":
				_autoplay = true
			"--honors-tiles":
				_honors_tiles = true
			"--hand13":
				_hand13 = true
			"--selftest":
				_selftest = true
				_autoplay = false
			"--state":
				i += 1
				_force_state = args[i] if i < args.size() else ""
			"--scene":
				i += 1   # 兼容菜单跳转的占位参数
			"--exit-after":
				i += 1
				_exit_frames = int(args[i]) if i < args.size() else -1
			"--help":
				_show_help = true
			"--hands":
				i += 1
				_hands_per_match = int(args[i]) if i < args.size() else 4
			"--to-end":
				_to_end = true
		i += 1

func _run_shots() -> void:
	for f in _shot_frames:
		await get_tree().process_frame
	for s in _shot_series:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := _shot_path
		if _shot_series > 1:
			path = "%s_%02d.png" % [_shot_path.get_basename(), s]
		img.save_png(path)
		print("[SHOT] ", path, " frame=", _frame, " phase=", game.phase)
		if s < _shot_series - 1:
			for f in _shot_gap:
				await get_tree().process_frame
	get_tree().quit()
