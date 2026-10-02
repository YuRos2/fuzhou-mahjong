## 字体工厂：优先使用系统中文字体（微软雅黑 / 黑体 / 思源黑体）
## 参考游戏使用繁体字形（萬/發/東），此处同样使用繁体字模。
class_name GameFonts
extends RefCounted

const CJK_FONTS := [
	"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",
	"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "WenQuanYi Zen Hei",
	"sans-serif",
]

static func make(weight: int = 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(CJK_FONTS)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.allow_system_fallback = true
	f.multichannel_signed_distance_field = false
	if f.get("font_weight") != null:
		f.set("font_weight", weight)
	return f
