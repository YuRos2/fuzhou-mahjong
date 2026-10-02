## 福州麻将 规则引擎
## ------------------------------------------------------------------
## 依据：《福州麻将游戏规则》（新修订）
##  · 和牌型：5 组面子（顺子/刻子） + 1 对将牌；庄 17 / 闲 16（含坎门）
##  · “金”即财神，可代任意一张牌组成顺子、刻子或将；金牌不能打出
##  · 特殊和牌（只算一种就高）：三金倒 +10、抢金 +20、金雀 +30、天胡 +40
##  · 计分：点炮底分 = 花番 + 金番 + 杠番 + 连庄番 + 特殊牌型番数
##          自摸分   =（花番 + 金番 + 杠番 + 连庄番）× 2 + 特殊牌型番数
##          无论点炮还是自摸，三家输家都扣分，赢家得三家之和
class_name Rules
extends RefCounted

enum Win {
	NORMAL,      ## 普通和牌
	SAN_JIN,     ## 三金倒（+10）
	QIANG_JIN,   ## 抢金（+20）
	JIN_QUE,     ## 金雀（+30）
	TIAN_HU,     ## 天胡（+40）
}

const WIN_NAME := {
	Win.NORMAL: "和牌",
	Win.SAN_JIN: "三金倒",
	Win.QIANG_JIN: "抢金",
	Win.JIN_QUE: "金雀",
	Win.TIAN_HU: "天胡",
}

## 特殊牌型番数（加算，只算一种就高）
const WIN_FAN := {
	Win.NORMAL: 0,
	Win.SAN_JIN: 10,
	Win.QIANG_JIN: 20,
	Win.JIN_QUE: 30,
	Win.TIAN_HU: 40,
}

# ---------------------------------------------------------------- 和牌判定
static func _key(counts: Array, jokers: int) -> String:
	var s := ""
	for i in Tiles.NUM_TILE_KINDS:
		s += str(counts[i])
	return s + "|" + str(jokers)

## counts 不含金；判断剩余牌能否全部拆成面子（金可补任意牌）
static func _sets_ok(counts: Array, jokers: int, memo: Dictionary) -> bool:
	var key := _key(counts, jokers)
	if memo.has(key):
		return memo[key]
	var k := -1
	for i in Tiles.NUM_TILE_KINDS:
		if counts[i] > 0:
			k = i
			break
	if k == -1:
		var ok := jokers % 3 == 0
		memo[key] = ok
		return ok
	var c: int = counts[k]
	# 刻子
	if c >= 3:
		counts[k] = c - 3
		if _sets_ok(counts, jokers, memo):
			counts[k] = c
			memo[key] = true
			return true
		counts[k] = c
	elif jokers >= 3 - c:
		counts[k] = 0
		if _sets_ok(counts, jokers - (3 - c), memo):
			counts[k] = c
			memo[key] = true
			return true
		counts[k] = c
	# 顺子（仅数字牌）
	if Tiles.is_number(k) and Tiles.rank(k) <= 7:
		var use_j := 0
		var s0: int = counts[k]
		var s1: int = counts[k + 1]
		var s2: int = counts[k + 2]
		for d in 3:
			var idx := k + d
			if counts[idx] > 0:
				counts[idx] -= 1
			else:
				use_j += 1
		if use_j <= jokers and _sets_ok(counts, jokers - use_j, memo):
			counts[k] = s0
			counts[k + 1] = s1
			counts[k + 2] = s2
			memo[key] = true
			return true
		counts[k] = s0
		counts[k + 1] = s1
		counts[k + 2] = s2
	memo[key] = false
	return false

## 和牌型：
##   (1)11+123×N  (2)11+123+111  (3)11+123+111×2 … (5)11+111×5
##   (6) 全对子型（如 14 张 = 7 对；17 张 = 8 对 + 单张）
static func can_hu(counts: Array, jokers: int) -> bool:
	var total := jokers
	for i in Tiles.NUM_TILE_KINDS:
		total += counts[i]
	if total < 2 or total % 3 != 2:
		return false
	if _pairs_hand(counts, jokers, total):
		return true
	var memo := {}
	# 将牌取法：对子 / 单张+金 / 双金
	for k in Tiles.NUM_TILE_KINDS:
		if counts[k] >= 2:
			counts[k] -= 2
			if _sets_ok(counts, jokers, memo):
				counts[k] += 2
				return true
			counts[k] += 2
	if jokers >= 1:
		for k in Tiles.NUM_TILE_KINDS:
			if counts[k] >= 1:
				counts[k] -= 1
				if _sets_ok(counts, jokers - 1, memo):
					counts[k] += 1
					return true
				counts[k] += 1
	if jokers >= 2:
		if _sets_ok(counts, jokers - 2, memo):
			return true
	return false

## 最少需要几张金作万能牌才能和牌（其余金只当本体使用）。
## 返回值 <= jokers 时说明存在「闲金」。
static func min_wildcards(counts: Array, jokers: int, joker_kind: int) -> int:
	if joker_kind < 0 or joker_kind >= Tiles.NUM_TILE_KINDS:
		return jokers
	for w in range(0, jokers + 1):
		var c := counts.duplicate()
		c[joker_kind] += jokers - w
		if can_hu(c, w):
			return w
	return jokers + 1

## 类型(6)：全对子（含金作对），余一张单张（总牌数为奇数时）
static func _pairs_hand(counts: Array, jokers: int, total: int) -> bool:
	var odd := 0
	for i in Tiles.NUM_TILE_KINDS:
		if counts[i] % 2 == 1:
			odd += 1
	var j := jokers
	var use := mini(odd, j)
	odd -= use
	j -= use
	var need_single := total % 2
	while odd < need_single and j >= 1:
		odd += 1
		j -= 1
	if odd != need_single:
		return false
	return j % 2 == 0

## 听牌：返回所有能和的牌种
static func winning_tiles(counts: Array, jokers: int) -> Array:
	var out: Array = []
	for k in Tiles.NUM_TILE_KINDS:
		if counts[k] >= 4:
			continue
		counts[k] += 1
		if can_hu(counts, jokers):
			out.append(k)
		counts[k] -= 1
	return out

## 金雀：和牌时用两张金作将牌
static func is_jin_que(counts: Array, jokers: int) -> bool:
	if jokers < 2:
		return false
	if not can_hu(counts, jokers):
		return false
	# 去掉两张金后仍需能将牌
	var total := jokers - 2
	for i in Tiles.NUM_TILE_KINDS:
		total += counts[i]
	if total % 3 != 0:
		return false
	return _sets_ok(counts, jokers - 2, {})

# ---------------------------------------------------------------- 向听/价值
## 最多能组成多少副完整面子（金可补牌），用于 AI 与听牌提示
static func max_sets(counts: Array, jokers: int) -> int:
	return _max_sets(counts, jokers, {})

static func _max_sets(counts: Array, jokers: int, memo: Dictionary) -> int:
	var key := _key(counts, jokers)
	if memo.has(key):
		return memo[key]
	var k := -1
	for i in Tiles.NUM_TILE_KINDS:
		if counts[i] > 0:
			k = i
			break
	if k == -1:
		var v := int(jokers / 3)
		memo[key] = v
		return v
	var best := 0
	var c: int = counts[k]
	if c >= 3:
		counts[k] = c - 3
		best = maxi(best, 1 + _max_sets(counts, jokers, memo))
		counts[k] = c
	elif jokers >= 3 - c:
		counts[k] = 0
		best = maxi(best, 1 + _max_sets(counts, jokers - (3 - c), memo))
		counts[k] = c
	if Tiles.is_number(k) and Tiles.rank(k) <= 7:
		var use_j := 0
		var s0: int = counts[k]
		var s1: int = counts[k + 1]
		var s2: int = counts[k + 2]
		for d in 3:
			if counts[k + d] > 0:
				counts[k + d] -= 1
			else:
				use_j += 1
		if use_j <= jokers:
			best = maxi(best, 1 + _max_sets(counts, jokers - use_j, memo))
		counts[k] = s0
		counts[k + 1] = s1
		counts[k + 2] = s2
	# 舍弃单张
	counts[k] = c - 1
	best = maxi(best, _max_sets(counts, jokers, memo))
	counts[k] = c
	memo[key] = best
	return best

## 单调“孤张”度量：越小越该打
static func isolation(counts: Array, kind: int) -> int:
	var s := Tiles.suit(kind)
	if s == Tiles.SUIT_HONOR or s == Tiles.SUIT_FLOWER:
		return counts[kind] * 4
	var r := Tiles.rank(kind)
	var v: int = int(counts[kind]) * 3
	for d in [-2, -1, 1, 2]:
		var dd: int = int(d)
		var nr: int = r + dd
		if nr >= 1 and nr <= 9:
			v += int(counts[kind + dd]) * (2 if absi(dd) == 1 else 1)
	return v

# ---------------------------------------------------------------- 副露判定
## 能否碰
static func can_peng(counts: Array, kind: int) -> bool:
	return counts[kind] >= 2

## 明杠（手中有三张）
static func can_gang_concealed(counts: Array, kind: int) -> bool:
	return counts[kind] >= 3

## 能否吃（仅限下家、仅数字牌）
static func chi_options(counts: Array, kind: int) -> Array:
	var out: Array = []
	if not Tiles.is_number(kind):
		return out
	var r: int = Tiles.rank(kind)
	for st in [r - 2, r - 1, r]:
		var start: int = int(st)
		if start < 1 or start > 7:
			continue
		var need: Array = []
		var ok := true
		for d in 3:
			var kk: int = kind - (r - start) + d
			if kk == kind:
				continue
			if counts[kk] > 0:
				need.append(kk)
			else:
				ok = false
				break
		if ok:
			var base: int = kind - (r - int(start))
			out.append([base, base + 1, base + 2])
	return out

# ---------------------------------------------------------------- 计分
## 杠番：明杠 +1，暗杠 +2
static func gang_fan(gang_ming: int, gang_an: int) -> int:
	return maxi(0, gang_ming) + maxi(0, gang_an) * 2

## 特殊牌型番数
static func special_fan(win_kind: int) -> int:
	return int(WIN_FAN.get(win_kind, 0))

## 每家输家应付的分数：
##   点炮：底分 = 花番 + 金番 + 杠番 + 连庄番 + 特殊牌型番数
##   自摸：自摸分 =（花番 + 金番 + 杠番 + 连庄番）× 2 + 特殊牌型番数
## 赢家得分 = 三个输家之和（即 core × 3）。
static func settle_core(win_kind: int, flowers_n: int, jokers: int,
		gang_ming: int, gang_an: int, lian_fan: int, self_draw: bool) -> int:
	var base: int = flowers_n + jokers + gang_fan(gang_ming, gang_an) + lian_fan
	if self_draw:
		return base * 2 + special_fan(win_kind)
	return base + special_fan(win_kind)
