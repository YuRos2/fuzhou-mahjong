## 本圈对战成绩（跨场景传递）
## ------------------------------------------------------------------
## 牌桌结束时把四家姓名 / 总分写入静态字段，总结算场景读取展示。
class_name MatchSummary
extends RefCounted

static var names: PackedStringArray = PackedStringArray()
static var scores: Array = []
static var hands: int = 0
static var is_ai: Array = []

static func store(game) -> void:
	names = PackedStringArray()
	scores = []
	is_ai = []
	hands = int(game.hand_no)
	for p in game.players:
		names.append(str(p["name"]))
		scores.append(int(p["score"]))
		is_ai.append(bool(p["is_ai"]))

static func clear() -> void:
	names = PackedStringArray()
	scores = []
	is_ai = []
	hands = 0

static func has_data() -> bool:
	return scores.size() == 4

## 按分数从高到低返回 [{seat, name, score, rank}]
static func ranking() -> Array:
	var order: Array = []
	for i in scores.size():
		order.append(i)
	order.sort_custom(func(a, b): return int(scores[a]) > int(scores[b]))
	var out: Array = []
	for r in order.size():
		var seat: int = int(order[r])
		out.append({"seat": seat, "name": names[seat], "score": int(scores[seat]), "rank": r + 1})
	return out
