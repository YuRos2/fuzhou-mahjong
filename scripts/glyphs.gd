## 牌面绘制（万/筒/索/字/花）
## 参考帧: 4399《福州麻将》 —— 象牙白牌面、金字底棱、圆点(筒)、竹节(索)、
##          汉字(萬) 上字下萬；字牌单字；花牌彩绘。
## 设计目标：高对比、大字号、统一的色彩语义（筒=蓝/绿/红按行/角分色，
##          索=绿为主红色点缀），小尺寸（弃牌 44px）下也能一眼辨认。
class_name TileGlyphs
extends RefCounted

const C_RED := Color(0.80, 0.14, 0.13)
const C_BLUE := Color(0.10, 0.20, 0.62)
const C_GREEN := Color(0.10, 0.50, 0.20)
const C_DOT_BLUE := Color(0.11, 0.24, 0.68)
const C_DOT_GREEN := Color(0.10, 0.54, 0.22)
const C_DOT_RED := Color(0.82, 0.16, 0.14)
const C_IVORY := Color(0.99, 0.98, 0.94)

# 归一化点位（x, y, 颜色索引 0=蓝 1=绿 2=红）
# 筒与索共用同一套点位，仅配色规则不同。
const DOT_PAL := [C_DOT_BLUE, C_DOT_GREEN, C_DOT_RED]
const LAYOUT_1 := [[0.5, 0.5, 0]]
const LAYOUT_2 := [[0.32, 0.18, 1], [0.68, 0.82, 2]]
const LAYOUT_3 := [[0.26, 0.14, 0], [0.5, 0.5, 2], [0.74, 0.86, 1]]
const LAYOUT_4 := [[0.28, 0.22, 0], [0.72, 0.22, 1], [0.28, 0.78, 1], [0.72, 0.78, 0]]
const LAYOUT_5 := [[0.27, 0.19, 0], [0.73, 0.19, 1], [0.5, 0.5, 2], [0.27, 0.81, 1], [0.73, 0.81, 0]]
const LAYOUT_6 := [[0.30, 0.14, 2], [0.70, 0.14, 2], [0.30, 0.5, 1], [0.70, 0.5, 1], [0.30, 0.86, 0], [0.70, 0.86, 0]]
const LAYOUT_7 := [[0.30, 0.12, 2], [0.70, 0.12, 2], [0.22, 0.5, 1], [0.5, 0.5, 2], [0.78, 0.5, 1],
	[0.30, 0.88, 0], [0.70, 0.88, 0]]
const LAYOUT_8 := [[0.30, 0.09, 0], [0.70, 0.09, 0], [0.30, 0.36, 1], [0.70, 0.36, 1],
	[0.30, 0.64, 1], [0.70, 0.64, 1], [0.30, 0.91, 0], [0.70, 0.91, 0]]
const LAYOUT_9 := [[0.22, 0.11, 0], [0.5, 0.11, 0], [0.78, 0.11, 0],
	[0.22, 0.5, 1], [0.5, 0.5, 1], [0.78, 0.5, 1],
	[0.22, 0.89, 2], [0.5, 0.89, 2], [0.78, 0.89, 2]]
# 二索为竖排双竹（与筒的斜排不同）
const SUO_LAYOUT_2 := [[0.5, 0.19, 0], [0.5, 0.81, 1]]

static func layout_for(rank: int) -> Array:
	match rank:
		1: return LAYOUT_1
		2: return LAYOUT_2
		3: return LAYOUT_3
		4: return LAYOUT_4
		5: return LAYOUT_5
		6: return LAYOUT_6
		7: return LAYOUT_7
		8: return LAYOUT_8
		_: return LAYOUT_9

# ------------------------------------------------------------------ 基础
static func _text(ci: CanvasItem, font: Font, text: String, center: Vector2, size: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	var pos := Vector2(center.x - ts.x * 0.5, center.y + (asc - desc) * 0.5)
	font.draw_string(ci.get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## 带柔和投影的文字：先画深色偏移，再画主体，提升牌面对比度
static func _text_shaded(ci: CanvasItem, font: Font, text: String, center: Vector2, size: int, color: Color) -> void:
	var off := maxf(1.2, size * 0.055)
	_text(ci, font, text, center + Vector2(0, off), size, Color(0.10, 0.08, 0.05, 0.28))
	_text(ci, font, text, center, size, color)

## 点位换算到像素坐标（suo=true 时二索使用竖排布局）
static func _layout_points(inner: Rect2, rank: int, suo: bool) -> Array:
	var pts := layout_for(rank)
	if suo and rank == 2:
		pts = SUO_LAYOUT_2
	var out: Array = []
	for p in pts:
		out.append({
			"pos": inner.position + Vector2(inner.size.x * float(p[0]), inner.size.y * float(p[1])),
			"col": int(p[2]),
		})
	return out

## 点位之间的最小间距（px），用于约束圆点尺寸，避免相互粘连
static func _min_gap(pts: Array) -> float:
	var best := 1e9
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d: float = (pts[i]["pos"] as Vector2).distance_to(pts[j]["pos"])
			if d < best:
				best = d
	return best

## 水平 / 垂直方向的最小间距（px），用于分别约束竹节的宽与高
static func _axis_gaps(pts: Array, unit: float) -> Vector2:
	var gx := unit * 2.0
	var gy := unit * 2.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var a: Vector2 = pts[i]["pos"]
			var b: Vector2 = pts[j]["pos"]
			var dx := absf(a.x - b.x)
			var dy := absf(a.y - b.y)
			if dx > 0.5 and dx < gx:
				gx = dx
			if dy > 0.5 and dy < gy:
				gy = dy
	return Vector2(gx, gy)

## 经典同心圆筒子：深色外圈 → 本色环 → 白隔圈 → 本色芯，小尺寸下依旧清晰
static func _dot(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col.darkened(0.45), true, -1.0, true)
	ci.draw_circle(c, r * 0.88, col, true, -1.0, true)
	ci.draw_circle(c, r * 0.62, C_IVORY, true, -1.0, true)
	ci.draw_circle(c, r * 0.46, col, true, -1.0, true)
	ci.draw_circle(c + Vector2(-r * 0.14, -r * 0.16), r * 0.13, Color(1, 1, 1, 0.55), true, -1.0, true)

## 竹节：胶囊外形 + 中间节环 + 高光，绿色为主 / 红色点缀
static func _stick(ci: CanvasItem, c: Vector2, w: float, h: float, col: Color) -> void:
	var dark := col.darkened(0.42)
	var hw := w * 0.5
	var hh := h * 0.5
	# 外轮廓（深色胶囊）
	ci.draw_circle(Vector2(c.x, c.y - hh + hw), hw, dark, true, -1.0, true)
	ci.draw_circle(Vector2(c.x, c.y + hh - hw), hw, dark, true, -1.0, true)
	ci.draw_rect(Rect2(c.x - hw, c.y - hh + hw, w, h - w), dark, true)
	# 内芯（本色）
	var iw := w * 0.68
	var ihw := iw * 0.5
	var inset := (w - iw) * 0.5
	var ihh := hh - inset
	ci.draw_circle(Vector2(c.x, c.y - ihh + ihw), ihw, col, true, -1.0, true)
	ci.draw_circle(Vector2(c.x, c.y + ihh - ihw), ihw, col, true, -1.0, true)
	ci.draw_rect(Rect2(c.x - ihw, c.y - ihh + ihw, iw, (ihh - ihw) * 2.0), col, true)
	# 节环
	var jw := maxf(1.2, h * 0.06)
	ci.draw_rect(Rect2(c.x - ihw, c.y - jw * 0.5, iw, jw), dark, true)
	ci.draw_rect(Rect2(c.x - ihw, c.y - jw * 0.5 - 1.0, iw, 1.0), Color(1, 1, 1, 0.35), true)
	# 纵向高光
	ci.draw_rect(Rect2(c.x - ihw * 0.55, c.y - ihh + ihw * 0.6, iw * 0.28, (ihh - ihw * 0.6) * 2.0),
		Color(1, 1, 1, 0.30), true)

## 简笔“鸟”造型（一条 / 索）
static func _bird(ci: CanvasItem, inner: Rect2) -> void:
	var c := inner.get_center()
	var s := minf(inner.size.x, inner.size.y)
	var body := Color(0.10, 0.48, 0.22)
	var wing := Color(0.18, 0.62, 0.30)
	var beak := Color(0.88, 0.50, 0.06)
	var tail := Color(0.78, 0.16, 0.16)
	# 尾羽
	for i in 3:
		var a := -2.55 + i * 0.26
		var p0 := c + Vector2(cos(a), sin(a)) * (s * 0.08)
		var p1 := c + Vector2(cos(a), sin(a)) * (s * 0.47)
		ci.draw_line(p0, p1, tail, maxf(1.8, s * 0.06), true)
	# 身体
	ci.draw_circle(c + Vector2(-s * 0.02, s * 0.10), s * 0.20, body, true, -1.0, true)
	# 翅膀
	var w := PackedVector2Array([
		c + Vector2(-s * 0.16, -s * 0.02),
		c + Vector2(s * 0.12, -s * 0.17),
		c + Vector2(s * 0.17, s * 0.07),
	])
	ci.draw_colored_polygon(w, wing)
	# 头
	ci.draw_circle(c + Vector2(-s * 0.24, -s * 0.20), s * 0.125, body, true, -1.0, true)
	# 冠
	ci.draw_line(c + Vector2(-s * 0.26, -s * 0.31), c + Vector2(-s * 0.30, -s * 0.40), tail, maxf(1.4, s * 0.04), true)
	# 喙
	var b := PackedVector2Array([
		c + Vector2(-s * 0.34, -s * 0.22),
		c + Vector2(-s * 0.52, -s * 0.16),
		c + Vector2(-s * 0.33, -s * 0.12),
	])
	ci.draw_colored_polygon(b, beak)
	# 眼
	ci.draw_circle(c + Vector2(-s * 0.27, -s * 0.23), maxf(1.3, s * 0.03), Color(0.05, 0.05, 0.05), true, -1.0, true)
	ci.draw_circle(c + Vector2(-s * 0.28, -s * 0.24), maxf(0.6, s * 0.012), Color(1, 1, 1, 0.9), true, -1.0, true)
	# 足
	ci.draw_line(c + Vector2(-s * 0.02, s * 0.28), c + Vector2(-s * 0.10, s * 0.44), beak, maxf(1.5, s * 0.045), true)
	ci.draw_line(c + Vector2(s * 0.04, s * 0.28), c + Vector2(s * 0.12, s * 0.44), beak, maxf(1.5, s * 0.045), true)

## 花牌彩绘：五瓣花 + 茎 + 叶
static func _flower(ci: CanvasItem, inner: Rect2, petal: Color) -> void:
	var c := inner.get_center()
	var s := minf(inner.size.x, inner.size.y)
	# 茎与叶
	ci.draw_line(c + Vector2(0, s * 0.06), c + Vector2(-s * 0.10, s * 0.50), Color(0.16, 0.44, 0.20), maxf(2.0, s * 0.06), true)
	var leaf := PackedVector2Array([
		c + Vector2(-s * 0.04, s * 0.30),
		c + Vector2(s * 0.22, s * 0.20),
		c + Vector2(s * 0.02, s * 0.42),
	])
	ci.draw_colored_polygon(leaf, Color(0.20, 0.52, 0.24))
	# 花瓣（双层：描边色 + 本色）
	for i in 5:
		var a: float = -PI * 0.5 + i * TAU / 5.0
		var pc := c + Vector2(cos(a), sin(a)) * (s * 0.22)
		ci.draw_circle(pc, s * 0.18, petal.darkened(0.3), true, -1.0, true)
		ci.draw_circle(pc, s * 0.145, petal, true, -1.0, true)
		ci.draw_circle(pc + Vector2(-s * 0.04, -s * 0.04), s * 0.055, Color(1, 1, 1, 0.5), true, -1.0, true)
	# 花心
	ci.draw_circle(c, s * 0.11, Color(0.85, 0.55, 0.05), true, -1.0, true)
	ci.draw_circle(c, s * 0.08, Color(0.98, 0.80, 0.18), true, -1.0, true)

# ------------------------------------------------------------------ 牌面
## 在 rect 内绘制 kind 的牌面（rect 为整张牌）
static func draw_face(ci: CanvasItem, rect: Rect2, kind: int, tex_blank: Texture2D,
		font: Font, font_bold: Font) -> void:
	if tex_blank:
		ci.draw_texture_rect(tex_blank, rect, false)
	# 绘制区：避开牌面四边的棱与底部金边，尽量铺满以提高辨识度
	var inner := Rect2(
		rect.position + Vector2(rect.size.x * 0.10, rect.size.y * 0.085),
		rect.size - Vector2(rect.size.x * 0.20, rect.size.y * 0.21))
	var s := Tiles.suit(kind)
	match s:
		Tiles.SUIT_WAN:
			_draw_wan(ci, inner, Tiles.rank(kind), font_bold)
		Tiles.SUIT_TONG:
			_draw_tong(ci, inner, Tiles.rank(kind))
		Tiles.SUIT_SUO:
			_draw_suo(ci, inner, Tiles.rank(kind))
		Tiles.SUIT_HONOR:
			_draw_honor(ci, inner, kind, font_bold)
		_:
			_draw_flower_tile(ci, inner, kind, font_bold)

static func _draw_wan(ci: CanvasItem, inner: Rect2, rank: int, font_bold: Font) -> void:
	var num_s := int(minf(inner.size.y * 0.44, inner.size.x * 0.74))
	var wan_s := int(minf(inner.size.y * 0.56, inner.size.x * 1.04))
	var top := Vector2(inner.get_center().x, inner.position.y + inner.size.y * 0.20)
	var bot := Vector2(inner.get_center().x, inner.position.y + inner.size.y * 0.70)
	_text_shaded(ci, font_bold, Tiles.NUM_CN[rank - 1], top, num_s, C_BLUE)
	_text_shaded(ci, font_bold, "萬", bot, wan_s, C_RED)

static func _draw_tong(ci: CanvasItem, inner: Rect2, rank: int) -> void:
	var pts := _layout_points(inner, rank, false)
	if rank == 1:
		# 大筒：蓝外环 → 白圈 → 红芯，视觉锚点
		var c: Vector2 = pts[0]["pos"]
		var r := minf(inner.size.x, inner.size.y) * 0.46
		ci.draw_circle(c, r, C_DOT_BLUE.darkened(0.45), true, -1.0, true)
		ci.draw_circle(c, r * 0.90, C_DOT_BLUE, true, -1.0, true)
		ci.draw_circle(c, r * 0.64, C_IVORY, true, -1.0, true)
		ci.draw_circle(c, r * 0.48, C_DOT_RED, true, -1.0, true)
		ci.draw_circle(c + Vector2(-r * 0.15, -r * 0.17), r * 0.14, Color(1, 1, 1, 0.6), true, -1.0, true)
		return
	var gap := _min_gap(pts)
	var r := minf(gap * 0.56, minf(inner.size.x, inner.size.y) * 0.36)
	for p in pts:
		_dot(ci, p["pos"], r, DOT_PAL[p["col"]])

static func _draw_suo(ci: CanvasItem, inner: Rect2, rank: int) -> void:
	if rank == 1:
		_bird(ci, inner)
		return
	var pts := _layout_points(inner, rank, true)
	var unit := minf(inner.size.x, inner.size.y)
	var gaps := _axis_gaps(pts, unit)
	var stick_h := minf(gaps.y * 0.82, unit * 0.54)
	var stick_w := clampf(gaps.x * 0.52, 3.5, minf(stick_h * 0.55, unit * 0.30))
	for p in pts:
		# 传统索子配色：与筒共用蓝 / 绿 / 红点位
		_stick(ci, p["pos"], stick_w, stick_h, DOT_PAL[p["col"]])

static func _draw_honor(ci: CanvasItem, inner: Rect2, kind: int, font_bold: Font) -> void:
	if kind == Tiles.K_WHITE:
		# 白板：双线蓝框，加粗并带圆角感（内外两圈）
		var r := Rect2(inner.position + inner.size * 0.08, inner.size * 0.84)
		var w1 := maxf(2.5, inner.size.y * 0.085)
		ci.draw_rect(r, C_BLUE, false, w1, true)
		var r2 := r.grow(-(w1 + maxf(2.0, inner.size.y * 0.07)))
		ci.draw_rect(r2, C_BLUE, false, maxf(1.5, inner.size.y * 0.045), true)
		return
	var col := C_BLUE
	var txt := Tiles.kind_name(kind)
	if kind == Tiles.K_RED:
		col = C_RED
	elif kind == Tiles.K_GREEN:
		col = C_GREEN
	var size := int(minf(inner.size.y * 0.98, inner.size.x * 1.08))
	_text_shaded(ci, font_bold, txt, inner.get_center(), size, col)

static func _draw_flower_tile(ci: CanvasItem, inner: Rect2, kind: int, font_bold: Font) -> void:
	var top := Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.54))
	# 四季偏玫红，四君子偏紫红，便于区分
	var petal := Color(0.92, 0.40, 0.54) if kind < Tiles.K_FLOWER_1 + 4 else Color(0.72, 0.40, 0.78)
	_flower(ci, top, petal)
	var size := int(minf(inner.size.y * 0.46, inner.size.x * 0.95))
	_text_shaded(ci, font_bold, Tiles.kind_name(kind),
		Vector2(inner.get_center().x, inner.position.y + inner.size.y * 0.82), size, C_GREEN)

## 牌背（金背）
static func draw_back(ci: CanvasItem, rect: Rect2, tex_back: Texture2D) -> void:
	if tex_back:
		ci.draw_texture_rect(tex_back, rect, false)

## 高亮描边（可选牌 / 选中）
static func draw_highlight(ci: CanvasItem, rect: Rect2, color: Color, width: float = 3.0) -> void:
	ci.draw_rect(rect.grow(-width * 0.5), color, false, width, true)
