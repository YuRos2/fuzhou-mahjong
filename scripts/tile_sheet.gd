## 牌面总览（素材复核用）
## 运行： godot --path . --resolution 760x880 -- --shot out.png
## 用法：把 42 种牌面画成一张对照表，便于与参考视频逐张比对。
extends Node2D

const COLS := 7
const CELL := Vector2(104, 128)
const TILE := Vector2(72, 96)
const MARGIN := Vector2(16, 16)

var tex: Dictionary = {}
var font_ui: Font
var font_bold: Font

func _ready() -> void:
	for n in ["tile_blank", "tile_back"]:
		var p := "res://assets/generated/%s.png" % n
		if ResourceLoader.exists(p):
			tex[n] = load(p)
	font_ui = GameFonts.make(400)
	font_bold = GameFonts.make(700)
	var path := "user://tilesheet.png"
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		path = args[i + 1]
	queue_redraw()
	for f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] ", path)
	get_tree().quit()

func _draw() -> void:
	for k in Tiles.KINDS:
		var col := k % COLS
		var row := k / COLS
		var r := Rect2(MARGIN + Vector2(col * CELL.x, row * CELL.y), TILE)
		TileGlyphs.draw_face(self, r, k, tex.get("tile_blank"), font_ui, font_bold)
		var label := Tiles.kind_name(k)
		var fs := 15
		var ts := font_ui.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		font_ui.draw_string(get_canvas_item(),
			Vector2(r.position.x + TILE.x * 0.5 - ts.x * 0.5, r.position.y + TILE.y + 20),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
