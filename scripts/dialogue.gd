## 福州麻将 · 牌桌对话（福州方言术语）
## ------------------------------------------------------------------
## 术语来源：百度百科《福州麻将》「特色术语 / 福州方言与文化术语」。
## 注音为百科所载国际音标简写，保留在台词里以体现方言味。
class_name Dialogue
extends RefCounted

## 每位角色的说话风格（seat 顺序 = 我 / 则徐 / 葆桢 / 徽因）
const PERSONA := [
	{"tag": "我", "style": "casual"},
	{"tag": "则徐", "style": "lively"},
	{"tag": "葆桢", "style": "steady"},
	{"tag": "徽因", "style": "folksy"},
]

static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return str(arr[rng.randi_range(0, arr.size() - 1)])

static func _persona(seat: int) -> String:
	return str(PERSONA[seat % 4]["tag"])

# ---------------------------------------------------------------- 开局
static func on_deal(rng: RandomNumberGenerator, seat: int, is_dealer: bool) -> String:
	if is_dealer:
		return _pick(rng, [
			"我来坐庄，企顶（kie53 ling33）！",
			"站庄了，莫走开，冲散旺势就无解。",
			"我坐庄，先开金再看牌。",
		])
	return _pick(rng, [
		"凑骹（cau55 ka55）凑齐了，开打！",
		"麻雀骹（ma21 cuok21 ka55）到齐，摸牌摸牌。",
		"十八墩摆好，慢慢来。",
		"今天手气看着还行。",
	])

static func on_buhua(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"补花 %s，重新摸一张。" % tile_name,
		"哎哟又摸到花，牌尾补一张。",
		"%s 只是记分，换一张实用的。" % tile_name,
	])

static func on_kaijin(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"开金 → %s！金（ging55）就是财神。" % tile_name,
		"金是 %s，几张金加几朵花。" % tile_name,
		"开金开出 %s，大家看好啦。" % tile_name,
	])

static func on_joker_flower(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"开出花牌 %s，算庄家的，重新开金。" % tile_name,
		"翻到花，归庄，再翻一张。",
	])

# ---------------------------------------------------------------- 特殊和牌
static func on_tianhu(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, ["天胡！取完牌就胡，+40 番。", "天胡！不用打牌，先谢过三家。"])

static func on_qiangjin(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"抢金（cuong21 nging55）！+20 番。",
		"开出的金直接胡，抢金了！",
		"抢金抢到手，比普通胡牌优先哦。",
	])

static func on_sanjindao(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"三金倒（sang55 lau55 ling55）！三张金，不用讲牌型。",
		"三金倒！三头金到手，我倒了！",
	])

static func on_jinque(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"金雀（ging53 cuok24）！两只金做将。",
		"金雀！截胡我也优先。",
	])

static func on_win(rng: RandomNumberGenerator, seat: int, self_draw: bool) -> String:
	if self_draw:
		return _pick(rng, [
			"自摸！×3，三家一起给。",
			"自己摸到，自摸最实在。",
			"自摸和牌，多谢各位。",
		])
	return _pick(rng, [
		"和了！这盘的点炮请认领。",
		"多谢这张牌，和啦。",
		"截胡在手，和牌。",
	])

static func on_lose_ron(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"哎呀放和了，这张不该出。",
		"daing242（硬），早知不出这张。",
		"我这张是生张，活该点炮。",
	])

static func on_draw_game(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"牌墙见底，和局，重新来过。",
		"最后四张没人自摸，和局。",
		"十八墩留够了，和局算了。",
	])

# ---------------------------------------------------------------- 副露
static func on_chi(rng: RandomNumberGenerator, seat: int, tile_name: String, from_seat: int) -> String:
	var sweet := rng.randf() < 0.5
	if sweet:
		return _pick(rng, [
			"吃 %s，上家这张真甜（dieng55）。" % tile_name,
			"吃！上家喂得刚好。",
		])
	return _pick(rng, [
		"吃 %s，勉强凑一副。" % tile_name,
		"吃进 %s，先把顺子摆好。" % tile_name,
	])

static func on_peng(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"碰 %s！" % tile_name,
		"碰！%s 我要了。" % tile_name,
		"碰 %s，亮明摆好。" % tile_name,
	])

static func on_gang(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"杠 %s！明杠 +1 番。" % tile_name,
		"杠！牌尾补一张。",
		"明杠 %s，多留一张。" % tile_name,
	])

static func on_angang(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, ["暗杠！暗杠 +2 番。", "暗杠，不亮牌。"])

static func on_bugang(rng: RandomNumberGenerator, seat: int, tile_name: String) -> String:
	return _pick(rng, [
		"补杠 %s，碰过的又摸到了。" % tile_name,
		"补杠！这张我等很久了。",
	])

# ---------------------------------------------------------------- 出牌 / 听牌
static func on_joker_blocked(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"金牌不能打出，留在手上才有用。",
		"金是财神，哪能打出去。",
		"打金？使不得使不得。",
	])

static func on_ting(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"我听牌了，来一张就好。",
		"伓是亲戚，无拍三七——莫怪我扣牌。",
		"听牌，尽量不出生张。",
		"这就是「捉五」的听法。",
	])

static func on_idle(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"摸二索（ni53 looh24）也行。",
		"八饼（beik24 biang33）这种脸就别来了。",
		"这盘手气一般，先走闲张。",
		"莫急，慢慢看牌。",
		"打一天输赢也就 -500~+500。",
	])

static func on_bad_luck(rng: RandomNumberGenerator, seat: int) -> String:
	return _pick(rng, [
		"转桌脚、转桌脚，运气转过来。",
		"要不要买牌换换手气？",
		"今天怕是遇到麻将鬼了。",
		"脱裤子改改摸牌顺序试试。",
	])

# ---------------------------------------------------------------- 术语表（帮助面板用）
static func glossary() -> String:
	return """[b][color=#ffe08a]福州麻将术语[/color][/b]

[b]金[/b]（ging55）—— 财神，可代任意牌；开金后从牌尾翻出。
[b]开金[/b] —— 补完花后从牌尾翻第一张定为金；翻到花牌则归庄家重翻。
[b]补花[/b] —— 拿到花牌后自庄家开始从牌尾补抓；补进新花须等本轮四家补完再补。
[b]坎门[/b] —— 四家拿完牌后，庄家额外多拿的那一张。
[b]企顶 / 站庄[/b]（kie53 ling33）—— 庄家和牌后继续连庄。
[b]截胡[/b] —— 多人听同一张牌，按逆时针最近者胡，金雀除外。
[b]抢金[/b]（cuong21 nging55）—— 开金翻出的金牌能直接胡牌时立即胡，+20 番，优先于普通胡牌。
[b]三金倒 / 三头金[/b]（sang55 lau55 ling55）—— 集齐三张金即可胡，不看牌型，+10 番。
[b]金雀[/b]（ging53 cuok24）—— 用两张金做将牌，+30 番；多人听同一张时优先胡。
[b]天胡[/b] —— 庄家起手即胡，+40 番。
[b]特殊牌型[/b] —— 三金倒 / 抢金 / 金雀 / 天胡同时成立时只算一种，就高计番。
[b]甜[/b]（dieng55）／[b]daing242[/b]（硬）—— 形容上家给的牌好 / 不好。
[b]凑骹[/b]（cau55 ka55）—— 三缺一，再找一个人凑数。
[b]麻雀骹[/b]（ma21 cuok21 ka55）—— 一起打麻将的朋友。
[b]二索[/b]（ni53 looh24）＝二条　[b]二饼[/b]（ni53 biang33）＝二筒
[b]八饼[/b]（beik24 biang33）—— 福州话里形容人脸长得难看。
[b]伓是亲戚，无拍三七[/b] —— 不会轻易给下家好牌吃。
[b]转桌脚 / 脱裤子 / 买牌[/b] —— 手气差时的民间改运做法。
[b]麻将鬼[/b] —— 既指嗜麻如命的人，也指「麻将有鬼」的运气说法。"""
