## 福州麻将 桌面视图
## ------------------------------------------------------------------
## 布局按 4399《福州麻将》实机帧（1920×1080 抽帧像素测量）等比换算到 1400×1080 画布：
##   · 青色台呢；四面牌墙（横墙显示金背，纵墙显示象牙侧面）
##   · 下方为我方手牌（正面大牌），对家手牌默认隐藏（与实机一致，可用 T 键透视）
##   · 四家副露（吃碰杠）贴在各自牌墙内侧
##   · 中央十字弃牌区 + 中央信息面板（倒计时 / 倍数 / 风圈 / 余牌）
##   · 四角玩家信息牌（头像 / 字风 / 铜钱分 / 花数）
class_name TableView
extends Node2D

const TABLE_W := 1400.0
const TABLE_H := 1080.0

# ---- 牌墙
const WALL_TOP_RECT := Rect2(74, 110, 1252, 80)
const WALL_BOTTOM_RECT := Rect2(74, 1046, 1252, 80)
const WALL_LEFT_X := 18.0
const WALL_RIGHT_X := 1348.0
const WALL_SIDE_Y0 := 190.0
const WALL_SIDE_N := 14
const WALL_SIDE_PITCH := 58.0
const JOKER_POS := Vector2(206, 150)

# ---- 我方手牌
const TILE_W := 72.0
const TILE_H := 92.0
const SELF_Y := 930.0
const SELF_PITCH := 78.0
const SELF_ROW_MAX := 1092.0   ## 手牌行最大宽度（16 张时需要压缩间距）

# ---- 对家牌 / 副露
const OPP_TILE_W := 52.0
const OPP_TILE_H := 68.0
const OPP_PITCH := 56.0
const OPP_REVEAL_PITCH := 30.0
const TOP_ROW_X := 390.0
const TOP_ROW_Y := 214.0
const SIDE_COL_Y := 240.0
const SIDE_MELD_X := 56.0
const SIDE_MELD_XR := 1240.0

# ---- 弃牌
const DIS_W := 44.0
const DIS_H := 56.0
const DIS_PITCH_X := 52.0
const DIS_PITCH_Y := 56.0

# ---- 中央面板 / 玩家信息牌
const PANEL_RECT := Rect2(420, 486, 560, 100)
const PINFO_SIZE := Vector2(220, 96)
const PINFO_POS := [Vector2(600, 790), Vector2(1010, 240), Vector2(150, 230), Vector2(150, 700)]

const C_TEXT := Color(0.96, 0.98, 0.95)
const C_TEXT_DIM := Color(0.78, 0.88, 0.85)
const C_GOLD := Color(1.0, 0.85, 0.35)

var game: GameState
var sfx: Sfx
var tex: Dictionary = {}
var font_ui: Font
var font_bold: Font

var selected_index: int = -1
var hover_index: int = -1
var show_opponent_hands: bool = false
var _flash: Dictionary = {}
var _flash_t: float = 0.0
var _pulse: float = 0.0
var _bubbles: Array = [{}, {}, {}, {}]
var _bubble_style: StyleBoxFlat
var _shadow_style: StyleBoxFlat
var _zone_style: StyleBoxFlat
var _plaque_style: StyleBoxFlat
var _joker_shown_at := Vector2(-1, -1)

func _ready() -> void:
	_load_assets()
	font_ui = GameFonts.make(400)
	font_bold = GameFonts.make(700)
	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = Color(0.98, 0.98, 0.94, 0.96)
	_bubble_style.border_color = Color(0.16, 0.34, 0.32, 0.9)
	_bubble_style.set_border_width_all(2)
	_bubble_style.set_corner_radius_all(10)
	_bubble_style.set_content_margin_all(10)
	# 牌张柔和投影
	_shadow_style = StyleBoxFlat.new()
	_shadow_style.bg_color = Color(0.0, 0.10, 0.09, 0.30)
	_shadow_style.set_corner_radius_all(8)
	_shadow_style.shadow_color = Color(0.0, 0.08, 0.07, 0.35)
	_shadow_style.shadow_size = 4
	_shadow_style.shadow_offset = Vector2(1, 3)
	# 弃牌区衬底（比台呢略深，圈出每家弃牌范围）
	_zone_style = StyleBoxFlat.new()
	_zone_style.bg_color = Color(0.0, 0.22, 0.20, 0.35)
	_zone_style.border_color = Color(1.0, 1.0, 1.0, 0.07)
	_zone_style.set_border_width_all(1)
	_zone_style.set_corner_radius_all(12)
	# 提示信息底板
	_plaque_style = StyleBoxFlat.new()
	_plaque_style.bg_color = Color(0.0, 0.16, 0.15, 0.72)
	_plaque_style.border_color = Color(1.0, 0.85, 0.35, 0.55)
	_plaque_style.set_border_width_all(1)
	_plaque_style.set_corner_radius_all(14)
	_plaque_style.set_content_margin_all(8)
	_plaque_style.shadow_color = Color(0, 0, 0, 0.35)
	_plaque_style.shadow_size = 5
	_plaque_style.shadow_offset = Vector2(0, 2)
	set_process(true)

func _load_assets() -> void:
	var names := ["felt", "tile_back", "tile_blank", "wall_v", "wall_v_mirror",
		"panel_center", "panel_player", "btn_gold", "btn_gold_hl", "badge_gem",
		"burst_magenta", "burst_cyan", "burst_gold",
		"icon_coin", "icon_flower", "wind_badge", "glow_white", "glow_gold", "glow_green",
		"avatar_zexu", "avatar_baozhen", "avatar_huiyin", "avatar_me"]
	for n in names:
		var path := "res://assets/generated/%s.png" % n
		if ResourceLoader.exists(path):
			tex[n] = load(path)
		else:
			push_warning("缺少素材: %s" % path)

func set_game(gs: GameState) -> void:
	game = gs
	game.state_changed.connect(_on_state_changed)
	game.speech.connect(_on_speech)
	queue_redraw()

## 牌桌对话：显示在说话者信息牌旁的气泡里
func _on_speech(seat: int, text: String) -> void:
	if seat < 0 or seat > 3:
		return
	_bubbles[seat] = {"text": text, "t": 3.4}
	queue_redraw()

func _on_state_changed() -> void:
	var t: String = str(game.event_fx.get("type", ""))
	if t in ["call", "win", "draw_game"]:
		_flash = game.event_fx.duplicate()
		_flash_t = 1.2
	selected_index = -1
	queue_redraw()

func _process(delta: float) -> void:
	_pulse += delta
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
	for i in 4:
		if not _bubbles[i].is_empty():
			_bubbles[i]["t"] = maxf(0.0, float(_bubbles[i]["t"]) - delta)
			if float(_bubbles[i]["t"]) <= 0.0:
				_bubbles[i] = {}
	# 金牌位置随牌尾消耗平滑前移
	var target := _joker_target_pos()
	if _joker_shown_at.x < 0.0:
		_joker_shown_at = target
	else:
		_joker_shown_at = _joker_shown_at.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	queue_redraw()

# ================================================================== 布局
## 手牌行间距：张数多时自动压缩，保证 16 张也能排在牌墙之内
func self_pitch() -> float:
	if game == null or game.players.is_empty():
		return SELF_PITCH
	var p: Dictionary = game.players[GameState.SEAT_SELF]
	var n: int = p["hand"].size()
	for m in p["melds"]:
		n += m["tiles"].size()
	var gaps: float = MELD_GAP * p["melds"].size()
	if int(game.drawn_index[GameState.SEAT_SELF]) >= 0:
		gaps += DRAWN_GAP   # 新摸的牌与牌列之间留出空隙
	if n <= 0:
		return SELF_PITCH
	return minf(SELF_PITCH, maxf(40.0, (SELF_ROW_MAX - gaps) / float(n)))

func self_slot_rects() -> Array:
	var out: Array = []
	if game == null or game.players.is_empty():
		return out
	var p: Dictionary = game.players[GameState.SEAT_SELF]
	var n: int = p["hand"].size()
	var meld_tiles := 0
	for m in p["melds"]:
		meld_tiles += m["tiles"].size()
	var pitch := self_pitch()
	var drawn: int = int(game.drawn_index[GameState.SEAT_SELF])
	var gap_extra: float = DRAWN_GAP if drawn >= 0 else 0.0
	var total: float = (n + meld_tiles) * pitch + MELD_GAP * p["melds"].size() + gap_extra
	var x: float = TABLE_W * 0.5 - total * 0.5
	for i in n:
		if i == drawn:
			x += DRAWN_GAP   # 新摸的牌不并入牌列，单独捺在右侧
		out.append({"rect": Rect2(x, SELF_Y, TILE_W, TILE_H), "kind": p["hand"][i], "meld": -1, "index": i, "drawn": i == drawn})
		x += pitch
	for mi in p["melds"].size():
		x += MELD_GAP
		for t in p["melds"][mi]["tiles"]:
			out.append({"rect": Rect2(x, SELF_Y, TILE_W, TILE_H), "kind": t, "meld": mi, "index": -1})
			x += pitch
	return out

const MELD_GAP := 14.0
const DRAWN_GAP := 22.0   ## 新摸的牌与牌列之间的间隔

# ================================================================== 绘制
func _draw() -> void:
	if game == null or game.players.is_empty():
		return
	_draw_walls()
	_draw_joker_wall()
	_draw_self_hand()
	_draw_opponents()
	_draw_discards()
	_draw_center_panel()
	_draw_player_infos()
	_draw_flash()
	_draw_ting_hint()
	_draw_bubbles()

# ---------------------------------------------------------------- 牌墙
func _draw_walls() -> void:
	var back: Texture2D = tex.get("tile_back")
	var wv: Texture2D = tex.get("wall_v")
	var wvm: Texture2D = tex.get("wall_v_mirror")
	var tw := 62.0
	var th := 78.0
	var pitch := 64.0
	var n := int(WALL_TOP_RECT.size.x / pitch)
	for i in n:
		TileGlyphs.draw_back(self, Rect2(WALL_TOP_RECT.position + Vector2(i * pitch, 0), Vector2(tw, th)), back)
		TileGlyphs.draw_back(self, Rect2(WALL_BOTTOM_RECT.position + Vector2(i * pitch, 0), Vector2(tw, th)), back)
	for i in WALL_SIDE_N:
		var y := WALL_SIDE_Y0 + i * WALL_SIDE_PITCH
		if wv:
			draw_texture_rect(wv, Rect2(WALL_LEFT_X, y, 34, 62), false)
		if wvm:
			draw_texture_rect(wvm, Rect2(WALL_RIGHT_X, y, 34, 62), false)

## 「金牌开出后移动到倒数第 9 墩牌上正面显示。
##   游戏中如果出现杠牌或补花，则金牌显示的位置要相应前移。」
func _joker_target_pos() -> Vector2:
	if game == null or not game.joker_shown:
		return JOKER_POS
	var span: int = maxi(1, game.back - game.front)
	var idx: int = clampi(game.back - 16, game.front, game.back)   # 一墩 2 张 → 倒数第 9 墩
	var t: float = float(idx - game.front) / float(span)
	# 牌尾在右侧：t 越小越靠“前”，即向左移动
	var x: float = WALL_TOP_RECT.position.x + (1.0 - t) * (WALL_TOP_RECT.size.x - 68.0)
	return Vector2(x + 34.0, JOKER_POS.y)

func _draw_joker_wall() -> void:
	if not game.joker_shown or game.joker_kind < 0:
		return
	var pos := _joker_shown_at if _joker_shown_at.x >= 0.0 else JOKER_POS
	var glow: Texture2D = tex.get("glow_gold")
	if glow:
		var g := 150.0 + sin(_pulse * 3.0) * 10.0
		draw_texture_rect(glow, Rect2(pos - Vector2(g, g) * 0.5, Vector2(g, g)), false, Color(1, 1, 1, 0.8))
	var r := Rect2(pos - Vector2(34, 46), Vector2(68, 92))
	TileGlyphs.draw_face(self, r, game.joker_kind, tex.get("tile_blank"), font_ui, font_bold)
	TileGlyphs.draw_highlight(self, r, C_GOLD, 3.0)
	_text_center_outlined("金", pos + Vector2(0, 68), 26, C_GOLD, Color(0.06, 0.05, 0.0))

# ---------------------------------------------------------------- 我方手牌
func _draw_self_hand() -> void:
	var ting := game.human_ting_hint()
	var selectable := game.human_selectable()
	var made := {}
	for k in ting:
		made[k] = true
	for s in self_slot_rects():
		var r: Rect2 = s["rect"]
		var idx: int = int(s["index"])
		var is_sel: bool = idx >= 0 and idx == selected_index
		var is_hover: bool = idx >= 0 and idx == hover_index and not is_sel and game.human_selectable()
		var is_drawn: bool = bool(s.get("drawn", false))
		# 新摸的牌轻微上浮 + 柔光，提示「刚摸进、尚未入列」
		if is_drawn and not is_sel and not is_hover:
			r.position.y -= 6.0
			var gw: Texture2D = tex.get("glow_white")
			if gw:
				var gsz := Vector2(TILE_W * 1.5, TILE_H * 1.4)
				draw_texture_rect(gw, Rect2(r.get_center() - gsz * 0.5, gsz), false, Color(1, 1, 1, 0.22))
		# 柔和投影（抬起的牌投影更深更大）
		var sh := _shadow_style.duplicate() as StyleBoxFlat
		if is_sel or is_hover or is_drawn:
			sh.shadow_size = 8
			sh.shadow_offset = Vector2(2, 6)
		draw_style_box(sh, r)
		if is_sel:
			r.position.y -= 18.0
		elif is_hover:
			r.position.y -= 8.0
		TileGlyphs.draw_face(self, r, int(s["kind"]), tex.get("tile_blank"), font_ui, font_bold)
		if is_sel:
			TileGlyphs.draw_highlight(self, r.grow(2.0), Color(1.0, 0.92, 0.35), 4.0)
		elif is_hover:
			TileGlyphs.draw_highlight(self, r.grow(1.5), Color(1.0, 1.0, 1.0, 0.65), 2.5)
		elif selectable and game.human_can_angang(int(s["kind"])):
			TileGlyphs.draw_highlight(self, r.grow(1.0), Color(0.55, 1.0, 0.55, 0.9), 2.5)
		elif idx >= 0 and selectable and made.has(int(s["kind"])):
			TileGlyphs.draw_highlight(self, r.grow(1.0), Color(0.45, 0.95, 1.0, 0.75), 2.0)
		# 金牌不能打出：加金边与「金」角标，提示玩家留在手上
		if idx >= 0 and game.has_joker() and int(s["kind"]) == game.joker_kind:
			TileGlyphs.draw_highlight(self, r.grow(0.5), Color(1.0, 0.85, 0.35, 0.95), 2.5)
			_text_center_outlined("金", r.position + Vector2(r.size.x - 15, 18), 18, C_GOLD, Color(0.30, 0.18, 0.0))
		elif is_drawn:
			# 新摸的牌下沿描一道亮线
			draw_rect(Rect2(r.position + Vector2(4, r.size.y - 4), Vector2(r.size.x - 8, 2.5)),
				Color(1.0, 0.97, 0.78, 0.85), true)

# ---------------------------------------------------------------- 对家
func _draw_opponents() -> void:
	_draw_top_seat()
	_draw_side_seat(GameState.SEAT_LEFT)
	_draw_side_seat(GameState.SEAT_RIGHT)

func _draw_top_seat() -> void:
	var p: Dictionary = game.players[GameState.SEAT_TOP]
	var x := TOP_ROW_X
	if show_opponent_hands:
		for t in p["hand"]:
			TileGlyphs.draw_face(self, Rect2(x, TOP_ROW_Y + 6, OPP_TILE_W, OPP_TILE_H),
				t, tex.get("tile_blank"), font_ui, font_bold)
			x += OPP_REVEAL_PITCH
		x = 800.0
	for mi in p["melds"].size():
		x += MELD_GAP
		for t in p["melds"][mi]["tiles"]:
			TileGlyphs.draw_face(self, Rect2(x, TOP_ROW_Y, OPP_TILE_W, OPP_TILE_H),
				t, tex.get("tile_blank"), font_ui, font_bold)
			x += OPP_PITCH

func _draw_side_seat(seat: int) -> void:
	var p: Dictionary = game.players[seat]
	var left := seat == GameState.SEAT_LEFT
	var x: float = SIDE_MELD_X if left else SIDE_MELD_XR
	var rot: float = -PI * 0.5 if left else PI * 0.5
	var y := SIDE_COL_Y
	if show_opponent_hands:
		for t in p["hand"]:
			_draw_rotated(Rect2(x, y + 6, OPP_TILE_H, OPP_TILE_W), t, rot)
			y += OPP_REVEAL_PITCH
		y = 620.0
	for mi in p["melds"].size():
		y += MELD_GAP
		for t in p["melds"][mi]["tiles"]:
			_draw_rotated(Rect2(x, y, OPP_TILE_H, OPP_TILE_W), t, rot)
			y += OPP_PITCH

## 旋转 90° 绘制一张牌（rect 为旋转前的外接矩形）
func _draw_rotated(rect: Rect2, kind: int, rot: float) -> void:
	var c := rect.get_center()
	draw_set_transform(c, rot, Vector2.ONE)
	var inner := Rect2(-Vector2(OPP_TILE_W, OPP_TILE_H) * 0.5, Vector2(OPP_TILE_W, OPP_TILE_H))
	TileGlyphs.draw_face(self, inner, kind, tex.get("tile_blank"), font_ui, font_bold)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- 弃牌
## 每家弃牌区的衬底范围（紧贴实际弃牌占用的行列）
func _discard_zone_rect(seat: int, count: int) -> Rect2:
	var pad := 8.0
	var n := maxi(count, 1)
	var cols := mini(n, 6)
	var rows := int(ceil(n / 6.0))
	var span_x: float = (cols - 1) * DIS_PITCH_X + DIS_W + pad * 2
	var span_y: float = (rows - 1) * DIS_PITCH_Y + DIS_H + pad * 2
	match seat:
		GameState.SEAT_SELF:
			return Rect2(544 - pad, 600 - pad, span_x, span_y)
		GameState.SEAT_TOP:
			return Rect2(544 - pad, 300 - pad, span_x, span_y)
		GameState.SEAT_LEFT:
			# 左右两家的“列”沿垂直方向展开
			var v: float = (cols - 1) * DIS_PITCH_Y + DIS_H + pad * 2
			var h: float = (rows - 1) * DIS_PITCH_X + DIS_W + pad * 2
			return Rect2(330 - (rows - 1) * DIS_PITCH_X - DIS_W - pad, 340 - pad, h, v)
		_:
			var v: float = (cols - 1) * DIS_PITCH_Y + DIS_H + pad * 2
			var h: float = (rows - 1) * DIS_PITCH_X + DIS_W + pad * 2
			return Rect2(1026 - pad, 340 - pad, h, v)

func _discard_rect(seat: int, i: int) -> Rect2:
	var col := i % 6
	var row := i / 6
	match seat:
		GameState.SEAT_SELF:
			return Rect2(544 + col * DIS_PITCH_X, 600 + row * DIS_PITCH_Y, DIS_W, DIS_H)
		GameState.SEAT_TOP:
			return Rect2(544 + col * DIS_PITCH_X, 300 + row * DIS_PITCH_Y, DIS_W, DIS_H)
		GameState.SEAT_LEFT:
			return Rect2(330 - row * DIS_PITCH_X, 340 + col * DIS_PITCH_Y, DIS_W, DIS_H)
		_:
			return Rect2(1026 + row * DIS_PITCH_X, 340 + col * DIS_PITCH_Y, DIS_W, DIS_H)

func _draw_discards() -> void:
	# 每家弃牌区先铺一层深色衬底（有弃牌才显示，随弃牌数增长）
	for seat in 4:
		var n: int = game.players[seat]["discards"].size()
		if n > 0:
			draw_style_box(_zone_style, _discard_zone_rect(seat, n))
	for seat in 4:
		var d: Array = game.players[seat]["discards"]
		for i in d.size():
			var r := _discard_rect(seat, i)
			if seat == GameState.SEAT_SELF or seat == GameState.SEAT_TOP:
				TileGlyphs.draw_face(self, r, d[i], tex.get("tile_blank"), font_ui, font_bold)
			else:
				var rot: float = -PI * 0.5 if seat == GameState.SEAT_LEFT else PI * 0.5
				draw_set_transform(r.get_center(), rot, Vector2.ONE)
				TileGlyphs.draw_face(self, Rect2(-r.size * 0.5, r.size), d[i], tex.get("tile_blank"), font_ui, font_bold)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if d.size() > 0 and seat == game.last_discard_by and game.last_discard >= 0:
			TileGlyphs.draw_highlight(self, _discard_rect(seat, d.size() - 1).grow(1.5),
				Color(1, 0.85, 0.3, 0.95), 3.0)

# ---------------------------------------------------------------- 中央面板
func _draw_center_panel() -> void:
	var panel: Texture2D = tex.get("panel_center")
	if panel:
		draw_texture_rect(panel, PANEL_RECT, false)
	else:
		draw_rect(PANEL_RECT, Color(0, 0.35, 0.33, 0.5), true)
	var grect := Rect2(PANEL_RECT.position + Vector2(14, 18), Vector2(64, 64))
	var gem: Texture2D = tex.get("badge_gem")
	if gem:
		draw_texture_rect(gem, grect, false)
	var secs := 0
	if not game.finished and game.phase != GameState.Phase.OVER:
		secs = int(ceil(maxf(0.0, game.turn_timer)))
	_text_center(str(secs) if secs > 0 else "--", grect.get_center() + Vector2(0, 2), 36, C_GOLD)
	var right := PANEL_RECT.position + Vector2(PANEL_RECT.size.x - 26, 0)
	_text_right("连庄  %d" % game.lian_zhuang, right + Vector2(0, 28), 30, C_TEXT)
	_text_right(str(GameState.HONOR_WIND[game.round_wind]) + "风圈", right + Vector2(0, 70), 27, C_TEXT_DIM)
	var lx := PANEL_RECT.position.x + 96
	_text_left("余 %d" % game.remaining(), Vector2(lx, PANEL_RECT.position.y + 30), 21, C_TEXT_DIM)
	_draw_turn_arrow()

## 中央面板边缘的金色箭头，指向当前行动的玩家（带呼吸脉动）
func _draw_turn_arrow() -> void:
	if game.finished or game.phase == GameState.Phase.OVER:
		return
	var c := PANEL_RECT.get_center()
	var dir := Vector2.DOWN
	match game.turn:
		GameState.SEAT_TOP: dir = Vector2.UP
		GameState.SEAT_LEFT: dir = Vector2.LEFT
		GameState.SEAT_RIGHT: dir = Vector2.RIGHT
		_: dir = Vector2.DOWN
	var pulse := 0.5 + 0.5 * sin(_pulse * 5.0)
	var base := c + dir * Vector2(PANEL_RECT.size.x * 0.5 + 6, PANEL_RECT.size.y * 0.5 + 6)
	# 取较短边方向偏移，避免斜向
	base = c + dir * ((PANEL_RECT.size * 0.5) + Vector2(8, 8))
	var tip := base + dir * (26.0 + pulse * 8.0)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, base + side * 13.0, base - side * 13.0])
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.35, 0.55 + pulse * 0.45))
	var glow: Texture2D = tex.get("glow_gold")
	if glow:
		var g := 56.0 + pulse * 14.0
		draw_texture_rect(glow, Rect2(tip - Vector2(g, g) * 0.5, Vector2(g, g)), false, Color(1, 1, 1, 0.35 + pulse * 0.3))

# ---------------------------------------------------------------- 玩家信息
func _draw_player_infos() -> void:
	for seat in 4:
		var p: Dictionary = game.players[seat]
		var pos: Vector2 = PINFO_POS[seat]
		var rect := Rect2(pos, PINFO_SIZE)
		var pnl: Texture2D = tex.get("panel_player")
		if pnl:
			draw_texture_rect(pnl, rect, false)
		else:
			draw_rect(rect, Color(0, 0.3, 0.28, 0.6), true)
		if seat == game.turn and not game.finished:
			var pulse := 0.5 + 0.5 * sin(_pulse * 4.0)
			var gg: Texture2D = tex.get("glow_green")
			if gg:
				var gs := PINFO_SIZE * (1.6 + pulse * 0.25)
				draw_texture_rect(gg, Rect2(rect.get_center() - gs * 0.5, gs), false, Color(1, 1, 1, 0.30 + pulse * 0.25))
			draw_rect(rect.grow(-2.0), Color(0.62, 0.96, 0.58, 0.95), false, 2.0)
		var av_names := ["avatar_me", "avatar_zexu", "avatar_baozhen", "avatar_huiyin"]
		var av: Texture2D = tex.get(av_names[seat])
		var avr := Rect2(pos + Vector2(8, 8), Vector2(72, 72))
		if av:
			draw_texture_rect(av, avr, false)
		else:
			draw_rect(avr, Color(0.9, 0.9, 0.9), true)
		var wb: Texture2D = tex.get("wind_badge")
		var wr := Rect2(pos + Vector2(54, 54), Vector2(40, 40))
		if wb:
			draw_texture_rect(wb, wr, false)
		var wind_char: String = str(GameState.HONOR_WIND[(seat - game.dealer + 4) % 4])
		_text_center(wind_char, wr.get_center() + Vector2(0, 2), 28, Color(0.1, 0.1, 0.1))
		var cx := pos.x + 94
		var coin: Texture2D = tex.get("icon_coin")
		if coin:
			draw_texture_rect(coin, Rect2(cx, pos.y + 14, 26, 26), false)
		_text_left(str(p["score"]), Vector2(cx + 32, pos.y + 36), 27, C_TEXT)
		_text_left(str(p["name"]), Vector2(cx, pos.y + 68), 23, C_TEXT_DIM)
		var fl: Texture2D = tex.get("icon_flower")
		if fl:
			draw_texture_rect(fl, Rect2(pos.x + 154, pos.y + 52, 22, 22), false)
		_text_left(str(p["flowers"].size()), Vector2(pos.x + 180, pos.y + 70), 21, C_TEXT_DIM)
		if seat == game.dealer:
			_text_center_outlined("庄", pos + Vector2(20, 18), 22, C_GOLD, Color(0.05, 0.05, 0.05))

# ---------------------------------------------------------------- 特效 / 提示
func _draw_flash() -> void:
	if _flash_t <= 0.0 or _flash.is_empty():
		return
	var t: float = _flash_t / 1.2
	var kind: String = str(_flash.get("type", ""))
	var text: String = str(_flash.get("text", ""))
	if text == "":
		return
	var seat: int = int(_flash.get("seat", 0))
	var center := Vector2(TABLE_W * 0.5, 700)
	match seat:
		GameState.SEAT_TOP: center = Vector2(700, 300)
		GameState.SEAT_LEFT: center = Vector2(230, 700)
		GameState.SEAT_RIGHT: center = Vector2(1170, 700)
		_: center = Vector2(700, 700)
	var burst_name := "burst_magenta"
	if kind == "win" or kind == "draw_game":
		burst_name = "burst_gold"
	var b: Texture2D = tex.get(burst_name)
	var size := Vector2(220, 220) * (1.0 + (1.0 - t) * 0.40)
	if b:
		draw_texture_rect(b, Rect2(center - size * 0.5, size), false, Color(1, 1, 1, clampf(t * 1.7, 0, 1)))
	var fs := int(64 * (0.88 + 0.12 * t))
	_text_center_outlined(text, center, fs, Color(1, 1, 1), Color(0.34, 0.05, 0.44))

func _draw_ting_hint() -> void:
	var hint := game.human_ting_hint()
	if hint.is_empty():
		return
	var names := PackedStringArray()
	for k in hint:
		names.append(Tiles.short_name(k))
	var txt := "听 " + " ".join(names)
	var fs := 26
	var ts := font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plaque := Rect2(Vector2(TABLE_W * 0.5 - ts.x * 0.5 - 18, 906 - 21), Vector2(ts.x + 36, 42))
	draw_style_box(_plaque_style, plaque)
	_text_center_outlined(txt, Vector2(TABLE_W * 0.5, 906), fs,
		Color(1, 0.96, 0.72), Color(0.04, 0.26, 0.23))

# ---------------------------------------------------------------- 台词气泡
func _bubble_anchor(seat: int) -> Vector2:
	var pos: Vector2 = PINFO_POS[seat]
	match seat:
		GameState.SEAT_SELF:
			return pos + Vector2(110, -14)
		GameState.SEAT_TOP:
			return pos + Vector2(110, PINFO_SIZE.y + 40)
		GameState.SEAT_LEFT:
			return pos + Vector2(PINFO_SIZE.x + 130, 48)
		_:
			return pos + Vector2(-130, 48)
	return pos

func _draw_bubbles() -> void:
	for seat in 4:
		var b: Dictionary = _bubbles[seat]
		if b.is_empty():
			continue
		var life: float = float(b["t"])
		var alpha: float = clampf(life / 0.55, 0.0, 1.0)
		var text: String = str(b["text"])
		var max_w := 300.0
		var fs := 20
		var ts := font_ui.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs)
		var box := Rect2(Vector2.ZERO, Vector2(minf(ts.x, max_w) + 24, ts.y + 20))
		var anchor := _bubble_anchor(seat)
		box.position = anchor - Vector2(box.size.x * 0.5, box.size.y)
		box.position.x = clampf(box.position.x, 8, TABLE_W - box.size.x - 8)
		box.position.y = clampf(box.position.y, 56, TABLE_H - box.size.y - 8)
		var st := _bubble_style.duplicate() as StyleBoxFlat
		st.bg_color = Color(0.98, 0.98, 0.94, 0.96 * alpha)
		st.border_color = Color(0.16, 0.34, 0.32, 0.9 * alpha)
		draw_style_box(st, box)
		font_ui.draw_multiline_string(get_canvas_item(),
			box.position + Vector2(12, 10 + font_ui.get_ascent(fs)),
			text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, -1,
			Color(0.06, 0.14, 0.13, alpha))

# ---------------------------------------------------------------- 文本工具
func _text_left(s: String, pos: Vector2, size: int, col: Color) -> void:
	font_bold.draw_string(get_canvas_item(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _text_center(s: String, center: Vector2, size: int, col: Color) -> void:
	var ts := font_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := font_bold.get_ascent(size)
	var desc := font_bold.get_descent(size)
	font_bold.draw_string(get_canvas_item(),
		Vector2(center.x - ts.x * 0.5, center.y + (asc - desc) * 0.5),
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _text_right(s: String, pos: Vector2, size: int, col: Color) -> void:
	var ts := font_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	font_bold.draw_string(get_canvas_item(), Vector2(pos.x - ts.x, pos.y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _text_center_outlined(s: String, center: Vector2, size: int, col: Color, out_col: Color) -> void:
	var ts := font_bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := font_bold.get_ascent(size)
	var desc := font_bold.get_descent(size)
	var pos := Vector2(center.x - ts.x * 0.5, center.y + (asc - desc) * 0.5)
	for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3),
			Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
		font_bold.draw_string(get_canvas_item(), pos + off, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, out_col)
	font_bold.draw_string(get_canvas_item(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# ================================================================== 输入
func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.players.is_empty():
		return
	if event is InputEventMouseMotion:
		hover_index = _hit_test(to_local(event.position))
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var idx := _hit_test(to_local(event.position))
			if idx >= 0:
				if selected_index == idx:
					_try_discard(idx)
				else:
					selected_index = idx
					_play("select", -14.0)
					queue_redraw()
			elif selected_index >= 0:
				selected_index = -1
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected_index = -1
			queue_redraw()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			show_opponent_hands = not show_opponent_hands
			print("[MJ] 透视对家手牌 = ", show_opponent_hands)

func _hit_test(p: Vector2) -> int:
	if not game.human_selectable():
		return -1
	var slots := self_slot_rects()
	for i in range(slots.size() - 1, -1, -1):
		if int(slots[i]["index"]) < 0:
			continue
		# 金牌不能打出，不可选
		if game.has_joker() and int(slots[i]["kind"]) == game.joker_kind:
			continue
		if (slots[i]["rect"] as Rect2).has_point(p):
			return int(slots[i]["index"])
	return -1

func _try_discard(index: int) -> void:
	if not game.human_selectable():
		return
	var hand: Array = game.players[GameState.SEAT_SELF]["hand"]
	if index < 0 or index >= hand.size():
		return
	if not game.discard(GameState.SEAT_SELF, hand[index]):
		_play("click", -10.0)   # 例：金牌不能打出
	selected_index = -1

func _play(name: String, vol: float = -8.0) -> void:
	if sfx:
		sfx.play(name, vol)

func discard_selected() -> void:
	if selected_index >= 0:
		_try_discard(selected_index)
		return
	# 未选中时默认打出最后一张非金牌（金牌不能打出）
	var hand: Array = game.players[GameState.SEAT_SELF]["hand"]
	for i in range(hand.size() - 1, -1, -1):
		if not (game.has_joker() and int(hand[i]) == game.joker_kind):
			_try_discard(i)
			return
