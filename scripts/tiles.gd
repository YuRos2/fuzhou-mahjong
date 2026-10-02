## 福州麻将 牌张定义
## ------------------------------------------------------------------
## 144 张：万 / 筒 / 索 各 36 张（1-9 各 4 张）= 108
##         字牌 東南西北中發白 各 4 张 = 28
##         花牌 春夏秋冬 梅蘭竹菊 各 1 张 = 8
class_name Tiles
extends RefCounted

const SUIT_WAN := 0
const SUIT_TONG := 1
const SUIT_SUO := 2
const SUIT_HONOR := 3
const SUIT_FLOWER := 4

const K_WAN_1 := 0            # 0..8   一萬..九萬
const K_TONG_1 := 9           # 9..17  一筒..九筒
const K_SUO_1 := 18           # 18..26 一索..九索
const K_EAST := 27            # 27..30 東 南 西 北
const K_RED := 31             # 31     中
const K_GREEN := 32           # 32     發
const K_WHITE := 33           # 33     白
const K_FLOWER_1 := 34        # 34..41 春 夏 秋 冬 梅 蘭 竹 菊
const K_FLOWER_LAST := 41
const KINDS := 42
const NUM_TILE_KINDS := 34    # 参与胡牌计算的牌种（不含花）
const WALL_SIZE := 144

const NAME_HONOR := ["東", "南", "西", "北"]
const NAME_FLOWER := ["春", "夏", "秋", "冬", "梅", "蘭", "竹", "菊"]
const NUM_CN := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

static func suit(kind: int) -> int:
	if kind < 9:
		return SUIT_WAN
	if kind < 18:
		return SUIT_TONG
	if kind < 27:
		return SUIT_SUO
	if kind < 34:
		return SUIT_HONOR
	return SUIT_FLOWER

## 1..9（数字牌）/ 1..4（风牌）/ 1..3（箭牌）/ 1..8（花牌）
static func rank(kind: int) -> int:
	var s := suit(kind)
	match s:
		SUIT_WAN, SUIT_TONG, SUIT_SUO:
			return kind % 9 + 1
		SUIT_HONOR:
			return kind - 27 + 1
		_:
			return kind - 34 + 1

static func is_number(kind: int) -> bool:
	return kind >= 0 and kind < 27

static func is_honor(kind: int) -> bool:
	return kind >= 27 and kind < 34

## 花牌 =「字牌花」28 + 「彩花」8 = 36 张（只用作记分）
##   字牌花：東南西北中發白 各 4 张
##   彩花：  春 夏 秋 冬 梅 蘭 竹 菊 各 1 张
static func is_flower(kind: int) -> bool:
	return kind >= 27

## 仅彩花 8 张
static func is_paint_flower(kind: int) -> bool:
	return kind >= 34

## 花牌构成（供界面/文档展示）
static func flower_breakdown() -> Dictionary:
	return {
		"honor_flowers": 28,   # 東南西北中發白 各 4
		"paint_flowers": 8,    # 春夏秋冬梅蘭竹菊 各 1
		"total": 36,
	}

## 兼容开关：参考实机（4399）把 東南西北中發白 当作「字」牌、不补牌。
##   honors_as_flowers = true （默认，按百科《用牌》主表）
##       36 张花牌全部触发补花，补花后四家手牌只剩 万 / 筒 / 索
##   honors_as_flowers = false（参考实机变体）
##       只有彩花 8 张补牌，字牌留在手牌中可组刻子 / 将牌
static func is_flower_in(kind: int, honors_as_flowers: bool) -> bool:
	if kind < 0:
		return false
	if kind >= 34:
		return true
	return honors_as_flowers and is_honor(kind)

static func is_terminal(kind: int) -> bool:
	if is_honor(kind):
		return true
	var r := rank(kind)
	return r == 1 or r == 9

static func kind_name(kind: int) -> String:
	if kind < 27:
		var s := suit(kind)
		var unit := "萬"
		if s == SUIT_TONG:
			unit = "筒"
		elif s == SUIT_SUO:
			unit = "索"
		return NUM_CN[rank(kind) - 1] + unit
	if kind < 34:
		if kind < 31:
			return NAME_HONOR[kind - 27]
		return ["中", "發", "白"][kind - 31]
	if kind >= 34 and kind <= K_FLOWER_LAST:
		return NAME_FLOWER[kind - 34]
	return "?"

static func short_name(kind: int) -> String:
	if kind < 27:
		return "%d%s" % [rank(kind), ["万", "筒", "索"][suit(kind)]]
	return kind_name(kind)

## 洗好的整副牌
static func build_wall(rng: RandomNumberGenerator) -> Array:
	var wall: Array = []
	for kind in NUM_TILE_KINDS:
		for i in 4:
			wall.append(kind)
	for f in range(K_FLOWER_1, K_FLOWER_LAST + 1):
		wall.append(f)
	# Fisher-Yates
	for i in range(wall.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = wall[i]
		wall[i] = wall[j]
		wall[j] = t
	return wall

static func counts_of(hand: Array) -> Array:
	var c := []
	c.resize(NUM_TILE_KINDS)
	c.fill(0)
	for t in hand:
		if t < NUM_TILE_KINDS:
			c[t] += 1
	return c

static func sort_hand(hand: Array) -> void:
	hand.sort()

## 金牌张数
static func count_jokers(hand: Array, joker_kind: int) -> int:
	if joker_kind < 0:
		return 0
	var n := 0
	for t in hand:
		if t == joker_kind:
			n += 1
	return n
