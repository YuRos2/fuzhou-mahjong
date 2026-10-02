## 福州麻将 牌局状态机
## ------------------------------------------------------------------
## 流程： 发牌 → 补花 → 开金 → (天和/抢金/三金倒 判定)
##        → 摸牌 → 补花 → 出牌 → 他家 吃/碰/杠/胡 → 下一家 …
## 手牌张数：13（与参考视频一致）或 16（福州传统），hand_size 可配。
class_name GameState
extends RefCounted

signal state_changed
signal log_line(text: String)
signal hand_finished(result: Dictionary)
signal speech(seat: int, text: String)

enum Phase { SETUP, DISCARD, CLAIM, WAIT_LAST, OVER }

enum { MELD_CHI, MELD_PENG, MELD_GANG_MING, MELD_GANG_AN }

const SEAT_SELF := 0
const SEAT_RIGHT := 1
const SEAT_TOP := 2
const SEAT_LEFT := 3

## 座位顺序：我 / 则徐（林则徐）/ 葆桢（沈葆桢）/ 徽因（林徽因）—— 皆为福州名人
const SEAT_NAMES := ["我", "则徐", "葆桢", "徽因"]
const HONOR_WIND := ["東", "南", "西", "北"]

var hand_size: int = 13
## 花牌模式（详见 Tiles.is_flower_in）
##   true （默认，按百科《用牌》主表）花牌 = 東南西北中發白(28) + 春夏秋冬梅蘭竹菊(8) = 36 张，
##        全部只用作记分、全部触发补花 → 补花后四家手牌只剩 万 / 筒 / 索
##   false（参考实机 4399 的变体）只有彩花 8 张补牌，字牌可入手牌组刻子
var honors_as_flowers: bool = true
var rng := RandomNumberGenerator.new()

var players: Array = []
var wall: Array = []
var front: int = 0
var back: int = 0
var joker_kind: int = -1
var joker_shown: bool = false
var reserved: int = 18          ## 和局需保留的墩数（福州麻将留 18 张）

var dealer: int = 0
var round_wind: int = 0
var lian_zhuang: int = 0
var hand_no: int = 0
## 「站顶」：玩家第一次做庄后胜的第一庄不算连庄底数
var dealer_tenure_wins: int = 0

var phase: int = Phase.SETUP
var turn: int = 0
## 刚摸进的牌在手牌数组中的下标（-1 = 无）。新摸的牌排在数组末尾、不参与牌列排序，
## 打出 / 副露 / 补花后清零并重新排序，界面上把它单独挥在右侧。
var drawn_index: Array = [-1, -1, -1, -1]
var last_discard: int = -1
var last_discard_by: int = -1
var first_go_around: bool = true
var pending_claims: Array = []
var human_options: Array = []
var turn_timer: float = 0.0
var turn_limit: float = 30.0     ## 出牌思考时间（按需求翻倍）
var claim_timer: float = 0.0
var claim_limit: float = 12.0    ## 吃碰杠胡决策时间（按需求翻倍）
var event_fx: Dictionary = {}
## 当前回合还需打出几张牌（正常为 1；开金补花后庄家可能多出若干张）
var must_discard: Array = [0, 0, 0, 0]
var finished: bool = false
var result: Dictionary = {}
var last_action: Dictionary = {}
var log_lines: Array = []
var autoplay: bool = false      ## 托管：人类席位也由 AI 代打

var _ai_delay: float = 0.0
var _last_group_draws: int = 0
var _dealer_bonus_discards: int = 0
var _over_timer: float = 0.0

func _init(p_hand_size: int = 13) -> void:
	hand_size = p_hand_size
	rng.randomize()

func _mk_player(i: int) -> Dictionary:
	return {
		"seat": i, "name": SEAT_NAMES[i], "hand": [], "melds": [], "discards": [],
		"flowers": [], "score": 0, "is_ai": i != SEAT_SELF,
		"gang_ming": 0, "gang_an": 0,
	}

func new_match(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	players.clear()
	for i in 4:
		players.append(_mk_player(i))
	dealer = rng.randi_range(0, 3)
	round_wind = 0
	lian_zhuang = 0
	dealer_tenure_wins = 0
	hand_no = 0
	start_hand()

# ------------------------------------------------------------------ 开局
func start_hand() -> void:
	hand_no += 1
	finished = false
	result = {}
	last_discard = -1
	last_discard_by = -1
	drawn_index = [-1, -1, -1, -1]
	first_go_around = true
	_last_group_draws = 0
	_dealer_bonus_discards = 0
	must_discard = [1, 1, 1, 1]
	_ting_said = [false, false, false, false]
	pending_claims.clear()
	human_options.clear()
	last_action = {}
	event_fx = {}
	joker_shown = false
	joker_kind = -1
	for p in players:
		p["hand"] = []
		p["melds"] = []
		p["discards"] = []
		p["flowers"] = []
		p["gang_ming"] = 0
		p["gang_an"] = 0
	wall = Tiles.build_wall(rng)
	front = 0
	back = wall.size() - 1
	for r in hand_size:
		for i in 4:
			var seat := (dealer + i) % 4
			players[seat]["hand"].append(_draw_front())
	players[dealer]["hand"].append(_draw_front())
	emit_log("第 %d 局 · 庄家 %s · 东风圈" % [hand_no, players[dealer]["name"]])
	for i in 4:
		say(i, Dialogue.on_deal(rng, i, i == dealer))
	_deal_flowers()
	_open_joker()
	turn = dealer
	turn_timer = turn_limit
	turn = dealer
	must_discard[dealer] = 1 + _dealer_bonus_discards
	if _check_opening_wins():
		state_changed.emit()
		return
	phase = Phase.DISCARD
	_prepare_discard_phase()

func _draw_front() -> int:
	if front > back:
		return -1
	var t = wall[front]
	front += 1
	return t

func _draw_back() -> int:
	if front > back:
		return -1
	var t = wall[back]
	back -= 1
	return t

func remaining() -> int:
	return maxi(0, back - front + 1)

func drawable() -> bool:
	return remaining() > required_reserve()

## 和局需保留的张数：基本留牌 18 张，每有明杠 +1，暗杠 +2
func required_reserve() -> int:
	var extra := 0
	for p in players:
		extra += int(p["gang_ming"]) * 1 + int(p["gang_an"]) * 2
	return reserved + extra

## 最后一组（可抓的张数：4 减去因杠/四同花多留的张数）
func last_group_size() -> int:
	return maxi(0, 4 - (required_reserve() - reserved))

## 最后一组——不再补花、不再出牌，能和则按自摸自动和
func in_last_group() -> bool:
	var n := last_group_size()
	if n <= 0:
		return true
	return remaining() <= required_reserve() + n

## 该牌种在本局是否算「花」（需补牌）
func is_flower_tile(kind: int) -> bool:
	return Tiles.is_flower_in(kind, honors_as_flowers)

## 本局花牌总数（36 / 8）
func flower_pool_size() -> int:
	return 36 if honors_as_flowers else 8

func _find_flower(hand: Array) -> int:
	for i in hand.size():
		if is_flower_tile(hand[i]):
			return i
	return -1

## 开局补花（按规则：自庄家开始、从牌尾补、每轮各补一次手里已有的花）
##  「如果补花牌过程中仍抓进花牌，须等本轮四家都补过花牌后再行补牌，
##    再次补花牌的顺序仍然以庄家为首开始，但上一次补花没抓进花牌的玩家则跳过。」
func _deal_flowers() -> void:
	var order: Array = []
	for i in 4:
		order.append((dealer + i) % 4)
	var round_no := 0
	while not order.is_empty() and round_no < 16:
		round_no += 1
		var next_round: Array = []
		for seat in order:
			var p: Dictionary = players[seat]
			var held: Array = []
			for t in p["hand"]:
				if is_flower_tile(t):
					held.append(t)
			if held.is_empty():
				continue
			for t in held:
				_remove_n(p["hand"], t, 1)
				p["flowers"].append(t)
				emit_log("%s 补花 %s" % [p["name"], Tiles.kind_name(t)])
				say(seat, Dialogue.on_buhua(rng, seat, Tiles.kind_name(t)))
				var nt := _draw_back()
				if nt < 0:
					break
				p["hand"].append(nt)
			# 本轮又补进花牌 → 下一轮继续（对手未补进花的玩家直接跳过）
			if _find_flower(p["hand"]) >= 0:
				next_round.append(seat)
		order = next_round
	for p in players:
		Tiles.sort_hand(p["hand"])
	drawn_index = [-1, -1, -1, -1]

## 记录「新摸进的牌」的下标（不在手牌中则 -1）
func _set_drawn(seat: int, idx: int) -> void:
	drawn_index[seat] = idx if idx >= 0 and idx < players[seat]["hand"].size() else -1

## 该家新摸的牌（无则返回 -1）
func drawn_tile(seat: int) -> int:
	var idx: int = int(drawn_index[seat])
	var hand: Array = players[seat]["hand"]
	if idx >= 0 and idx < hand.size():
		return int(hand[idx])
	return -1

## 合并新摸的牌：清除标记并把手牌排好序
func merge_drawn(seat: int) -> void:
	if int(drawn_index[seat]) >= 0:
		drawn_index[seat] = -1
		Tiles.sort_hand(players[seat]["hand"])

func has_joker() -> bool:
	return joker_kind >= 0 and joker_kind < Tiles.NUM_TILE_KINDS

## 开金：补完花后从牌尾翻第一张定为「金」。
## 「如果开金时开出的为花，则算庄家的，为庄家补完花后，重新从牌尾翻开一张牌为金」
## —— 开出花牌 → 归庄家 → 庄家从牌尾补花（补到非花为止）→ 再翻金；仍是花则再循环。
func _open_joker() -> void:
	var guard := 0
	while guard < 96 and front <= back:
		guard += 1
		var t := _draw_back()
		if t < 0:
			break
		if is_flower_tile(t):
			players[dealer]["flowers"].append(t)
			emit_log("开金开出花牌 %s，归庄家" % Tiles.kind_name(t))
			say(dealer, Dialogue.on_joker_flower(rng, dealer, Tiles.kind_name(t)))
			_dealer_bonus_from_flower()
			continue
		joker_kind = t
		joker_shown = true
		emit_log("开金 → %s（可代任意牌）" % Tiles.kind_name(t))
		say(dealer, Dialogue.on_kaijin(rng, dealer, Tiles.kind_name(t)))
		return
	joker_kind = -1
	joker_shown = false

## 庄家因开金开花而补花：从牌尾补，补到非花为止；
## 每一张「开金花」都会让庄家多拿一张牌，故开局需多打出同样多的牌来恢复手牌张数。
func _dealer_bonus_from_flower() -> void:
	var p: Dictionary = players[dealer]
	var got := false
	while front <= back:
		var r := _draw_back()
		if r < 0:
			break
		if is_flower_tile(r):
			p["flowers"].append(r)
			emit_log("庄家补花 %s" % Tiles.kind_name(r))
			continue
		p["hand"].append(r)
		Tiles.sort_hand(p["hand"])
		got = true
		break
	if got:
		_dealer_bonus_discards += 1
		emit_log("金花归庄，庄家补一张（本局需多打 %d 张）" % _dealer_bonus_discards)

# ------------------------------------------------------------------ 判定
func jokers_in(seat: int) -> int:
	return Tiles.count_jokers(players[seat]["hand"], joker_kind)

## 不含金的手牌计数
func counts_no_joker(seat: int) -> Array:
	var c := Tiles.counts_of(players[seat]["hand"])
	if has_joker():
		c[joker_kind] = 0
	return c

func concealed_need(seat: int) -> int:
	return hand_size + 1 - 3 * int(players[seat]["melds"].size())

func is_winning_hand(seat: int) -> bool:
	var p: Dictionary = players[seat]
	if p["hand"].size() != concealed_need(seat):
		return false
	var n := jokers_in(seat)
	if n >= 3:
		return true
	return Rules.can_hu(counts_no_joker(seat), n)

## 开局特殊和牌：按座次（庄家为首）判定，同一家多种特殊和牌「只算一种就高」
##   天胡 40 > 金雀 30 > 抢金 20 > 三金倒 10
func _check_opening_wins() -> bool:
	for off in [0, 1, 2, 3]:
		var seat: int = (dealer + off) % 4
		var kind := _opening_best(seat)
		if kind < 0:
			continue
		match kind:
			Rules.Win.TIAN_HU: say(seat, Dialogue.on_tianhu(rng, seat))
			Rules.Win.JIN_QUE: say(seat, Dialogue.on_jinque(rng, seat))
			Rules.Win.QIANG_JIN: say(seat, Dialogue.on_qiangjin(rng, seat))
			_: say(seat, Dialogue.on_sanjindao(rng, seat))
		_finish(seat, kind, true, -1)
		return true
	return false

## 开局某家适用的最高番特殊和牌（无则 -1）
func _opening_best(seat: int) -> int:
	var cands: Array = []
	if jokers_in(seat) >= 3:
		cands.append(Rules.Win.SAN_JIN)
	if _opening_can_hu(seat):
		# 把开出的金抓进即可和：庄家为天胡，闲家为抢金
		cands.append(Rules.Win.TIAN_HU if seat == dealer else Rules.Win.QIANG_JIN)
		if has_joker():
			var c := Tiles.counts_of(players[seat]["hand"])
			var n: int = c[joker_kind]
			c[joker_kind] = n - 1
			if Rules.is_jin_que(c, n - 1):
				cands.append(Rules.Win.JIN_QUE)
	elif seat == dealer and _opening_can_hu_dealer():
		# 庄家抢金：打出一张没用的牌，把开出的金换进即可和
		cands.append(Rules.Win.QIANG_JIN)
	var best := -1
	var best_fan := 0
	for kind in cands:
		var f: int = Rules.special_fan(int(kind))
		if f > best_fan:
			best_fan = f
			best = int(kind)
	return best

## 庄家抢金：手上打掉任意一张非金牌后，换进开出的金即可和
func _opening_can_hu_dealer() -> bool:
	if not has_joker():
		return false
	var p: Dictionary = players[dealer]
	var c := Tiles.counts_of(p["hand"])
	var j: int = c[joker_kind]
	c[joker_kind] = 0
	for t in Tiles.NUM_TILE_KINDS:
		if c[t] <= 0:
			continue
		c[t] -= 1
		var ok := Rules.can_hu(c, j + 1)
		c[t] += 1
		if ok:
			return true
	return false

## 把“金”当成一张普通牌抓进来即可和牌 → 天和 / 抢金
func _opening_can_hu(seat: int) -> bool:
	if not has_joker():
		return false
	var p: Dictionary = players[seat]
	var c := Tiles.counts_of(p["hand"])
	var n: int = c[joker_kind]
	if n <= 0:
		return false
	c[joker_kind] = n - 1
	return Rules.can_hu(c, n - 1)

# ------------------------------------------------------------------ 出牌
func _prepare_discard_phase() -> void:
	phase = Phase.DISCARD
	turn_timer = turn_limit
	if must_discard[turn] <= 0:
		must_discard[turn] = 1
	human_options = []
	last_action = {}
	# 金牌不能打出：若手上只剩金牌（已成金雀 / 三金倒），直接结算，避免无法出牌
	if players[turn]["hand"].size() > 0 and not _has_discardable(turn):
		_finish(turn, _classify(turn), true, -1)
		return
	state_changed.emit()

## 该家是否有可打出的牌（金牌不能打出）
func _has_discardable(seat: int) -> bool:
	for t in players[seat]["hand"]:
		if not (has_joker() and int(t) == joker_kind):
			return true
	return false

func set_action(seat: int, kind: String, text: String) -> void:
	last_action = {"seat": seat, "kind": kind, "text": text}

func say(seat: int, text: String) -> void:
	if text.strip_edges() == "":
		return
	speech.emit(seat, text)

var _ting_said: Array = [false, false, false, false]

func _maybe_say_ting(seat: int, hint: Array) -> void:
	if hint.is_empty() or _ting_said[seat]:
		return
	_ting_said[seat] = true
	say(seat, Dialogue.on_ting(rng, seat))

func emit_log(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 40:
		log_lines.pop_front()
	log_line.emit(t)

## 摸牌
func do_draw(seat: int) -> void:
	if finished:
		return
	turn = seat
	var p: Dictionary = players[seat]
	if in_last_group():
		_draw_last_group(seat)
		return
	if not drawable():
		_draw_game()
		return
	var t := _draw_front()
	if t < 0:
		_draw_game()
		return
	var appended := -1
	if is_flower_tile(t):
		p["flowers"].append(t)
		emit_log("%s 补花 %s" % [p["name"], Tiles.kind_name(t)])
		say(seat, Dialogue.on_buhua(rng, seat, Tiles.kind_name(t)))
		var ok := false
		while drawable():
			var nt := _draw_back()
			if nt < 0:
				break
			if is_flower_tile(nt):
				p["flowers"].append(nt)
				continue
			p["hand"].append(nt)
			appended = p["hand"].size() - 1
			ok = true
			break
		if not ok:
			_draw_game()
			return
	else:
		p["hand"].append(t)
		appended = p["hand"].size() - 1
		set_action(seat, "draw", "")
	# 新摸的牌不并入牌列：留在数组末尾，由界面单独展示
	_set_drawn(seat, appended)
	event_fx = {"type": "draw", "seat": seat}
	if jokers_in(seat) >= 3:
		_finish(seat, Rules.Win.SAN_JIN, true, -1)
		return
	if is_winning_hand(seat):
		_finish(seat, _classify(seat), true, -1)
		return
	_maybe_say_ting(seat, Rules.winning_tiles(counts_no_joker(seat), jokers_in(seat)))
	_prepare_discard_phase()

## 出牌（金牌不能打出）
func discard(seat: int, tile: int) -> bool:
	if finished or phase != Phase.DISCARD or turn != seat:
		return false
	if tile == joker_kind and has_joker():
		emit_log("%s 试图打出金牌——金牌不能打出" % players[seat]["name"])
		say(seat, Dialogue.on_joker_blocked(rng, seat))
		return false
	var p: Dictionary = players[seat]
	var idx: int = p["hand"].find(tile)
	if idx < 0:
		return false
	p["hand"].remove_at(idx)
	# 出牌后新摸的牌并入牌列（重新排序）
	drawn_index[seat] = -1
	Tiles.sort_hand(p["hand"])
	p["discards"].append(tile)
	last_discard = tile
	last_discard_by = seat
	emit_log("%s 打出 %s" % [p["name"], Tiles.kind_name(tile)])
	set_action(seat, "discard", Tiles.short_name(tile))
	event_fx = {"type": "discard", "seat": seat, "tile": tile}
	must_discard[seat] = maxi(0, int(must_discard[seat]) - 1)
	if must_discard[seat] > 0:
		# 开金补花后庄家多出的牌：继续由该家出牌，不转交吃碰
		turn_timer = turn_limit
		state_changed.emit()
		return true
	_collect_claims(seat, tile)
	state_changed.emit()
	return true

# ------------------------------------------------------------------ 吃碰杠胡
func _collect_claims(from_seat: int, tile: int) -> void:
	pending_claims.clear()
	human_options = []
	if is_flower_tile(tile) or tile == joker_kind:
		_advance_turn(from_seat)
		return
	for off in [1, 2, 3]:
		var seat: int = (from_seat + off) % 4
		var p: Dictionary = players[seat]
		var c := Tiles.counts_of(p["hand"])
		if has_joker():
			c[joker_kind] = 0
		var mine: Array = []
		if _can_ron(seat, tile):
			mine.append({"seat": seat, "action": "hu", "prio": 3, "tiles": [tile], "shanten": 0})
		if c[tile] >= 3:
			mine.append({"seat": seat, "action": "gang", "prio": 2, "tiles": [tile, tile, tile, tile]})
		elif c[tile] >= 2:
			mine.append({"seat": seat, "action": "peng", "prio": 2, "tiles": [tile, tile, tile]})
		if off == 1 and Tiles.is_number(tile):
			for opt in Rules.chi_options(c, tile):
				mine.append({"seat": seat, "action": "chi", "prio": 1, "tiles": opt})
		if mine.is_empty():
			continue
		if p["is_ai"] or autoplay:
			for cl in mine:
				if ai_claim_decision(cl):
					pending_claims.append(cl)
		else:
			for cl in mine:
				pending_claims.append(cl)
				human_options.append(cl)
	if pending_claims.is_empty():
		_advance_turn(from_seat)
		return
	phase = Phase.CLAIM
	claim_timer = 0.0
	if human_options.is_empty():
		_resolve_claims()
	else:
		state_changed.emit()

func _can_ron(seat: int, tile: int) -> bool:
	var p: Dictionary = players[seat]
	if p["hand"].size() + 1 != concealed_need(seat):
		return false
	if tile == joker_kind:
		return false
	var c := counts_no_joker(seat)
	c[tile] += 1
	return Rules.can_hu(c, jokers_in(seat))

## 人类玩家选择 / 放弃
func resolve_human_claim(action: String, tiles: Array = []) -> void:
	if phase != Phase.CLAIM:
		return
	if action == "pass":
		for i in range(pending_claims.size() - 1, -1, -1):
			if pending_claims[i]["seat"] == SEAT_SELF:
				pending_claims.remove_at(i)
		human_options = []
		_resolve_claims()
		return
	for cl in pending_claims:
		if cl["seat"] == SEAT_SELF and cl["action"] == action:
			if action != "chi" or cl["tiles"] == tiles:
				_apply_claim(cl)
				return
	resolve_human_claim("pass")

func _resolve_claims() -> void:
	if finished:
		return
	if pending_claims.is_empty():
		_advance_turn(last_discard_by)
		return
	var best: Dictionary = pending_claims[0]
	for cl in pending_claims:
		if cl["prio"] > best["prio"]:
			best = cl
		elif cl["prio"] == best["prio"] and cl["action"] == "hu":
			var cl_que := _is_jin_que_claim(cl["seat"], last_discard)
			var best_que := _is_jin_que_claim(best["seat"], last_discard)
			if cl_que and not best_que:
				best = cl
			elif cl_que == best_que and _seat_dist(last_discard_by, cl["seat"]) < _seat_dist(last_discard_by, best["seat"]):
				best = cl
	_apply_claim(best)

## 金雀优先截和：用两张金做将牌的和牌优先
func _is_jin_que_claim(seat: int, tile: int) -> bool:
	if jokers_in(seat) < 2 or tile == joker_kind:
		return false
	var c := counts_no_joker(seat)
	c[tile] += 1
	return Rules.is_jin_que(c, jokers_in(seat))

static func _seat_dist(from_seat: int, seat: int) -> int:
	return (seat - from_seat + 4) % 4

func _apply_claim(cl: Dictionary) -> void:
	pending_claims.clear()
	human_options = []
	var seat: int = cl["seat"]
	var p: Dictionary = players[seat]
	var action: String = cl["action"]
	var tile: int = last_discard
	match action:
		"hu":
			_finish(seat, _classify(seat), false, last_discard_by)
		"peng":
			_remove_n(p["hand"], tile, 2)
			merge_drawn(seat)
			p["melds"].append({"type": MELD_PENG, "tiles": [tile, tile, tile], "from": last_discard_by})
			_pull_discard(tile)
			set_action(seat, "peng", "碰")
			emit_log("%s 碰 %s" % [p["name"], Tiles.kind_name(tile)])
			say(seat, Dialogue.on_peng(rng, seat, Tiles.kind_name(tile)))
			event_fx = {"type": "call", "seat": seat, "text": "碰"}
			turn = seat
			_after_call(seat)
		"gang":
			_remove_n(p["hand"], tile, 3)
			merge_drawn(seat)
			p["melds"].append({"type": MELD_GANG_MING, "tiles": [tile, tile, tile, tile], "from": last_discard_by})
			p["gang_ming"] += 1
			_pull_discard(tile)
			set_action(seat, "gang", "杠")
			emit_log("%s 杠 %s" % [p["name"], Tiles.kind_name(tile)])
			say(seat, Dialogue.on_gang(rng, seat, Tiles.kind_name(tile)))
			event_fx = {"type": "call", "seat": seat, "text": "杠"}
			turn = seat
			_gang_draw(seat)
		"chi":
			var grp: Array = cl["tiles"]
			for t in grp:
				if t != tile:
					_remove_n(p["hand"], t, 1)
			merge_drawn(seat)
			p["melds"].append({"type": MELD_CHI, "tiles": grp.duplicate(), "from": last_discard_by})
			_pull_discard(tile)
			set_action(seat, "chi", "吃")
			emit_log("%s 吃 %s" % [p["name"], Tiles.kind_name(tile)])
			say(seat, Dialogue.on_chi(rng, seat, Tiles.kind_name(tile), last_discard_by))
			event_fx = {"type": "call", "seat": seat, "text": "吃"}
			turn = seat
			_after_call(seat)

## 最后一组：轮流抓牌，能自摸则和，四家都没和即和局
func _draw_last_group(seat: int) -> void:
	if last_group_size() <= 0 or _last_group_draws >= last_group_size() or remaining() <= 0:
		_draw_game()
		return
	var p: Dictionary = players[seat]
	var t := _draw_front()
	if t < 0:
		_draw_game()
		return
	if is_flower_tile(t):
		p["flowers"].append(t)     # 最后一组不再补花
	else:
		p["hand"].append(t)
		_set_drawn(seat, p["hand"].size() - 1)
	set_action(seat, "draw", "末张")
	emit_log("%s 抓最后一张" % p["name"])
	if jokers_in(seat) >= 3:
		_finish(seat, Rules.Win.SAN_JIN, true, -1)
		return
	if is_winning_hand(seat):
		_finish(seat, _classify(seat), true, -1)
		return
	_last_group_draws += 1
	if _last_group_draws >= last_group_size() or remaining() <= 0:
		_draw_game()
		return
	# 不出牌，直接轮下家（最后 4 张节奏快一些）
	first_go_around = false
	turn_timer = 4.0
	phase = Phase.WAIT_LAST
	state_changed.emit()

func _pull_discard(tile: int) -> void:
	var d: Array = players[last_discard_by]["discards"]
	if not d.is_empty() and d[d.size() - 1] == tile:
		d.remove_at(d.size() - 1)

func _after_call(seat: int) -> void:
	_prepare_discard_phase()

func _gang_draw(seat: int) -> void:
	var p: Dictionary = players[seat]
	var ok := false
	while drawable():
		var t := _draw_back()
		if t < 0:
			break
		if is_flower_tile(t):
			p["flowers"].append(t)
			emit_log("%s 杠上补花 %s" % [p["name"], Tiles.kind_name(t)])
			continue
		p["hand"].append(t)
		_set_drawn(seat, p["hand"].size() - 1)
		ok = true
		break
	if not ok:
		_draw_game()
		return
	if jokers_in(seat) >= 3:
		_finish(seat, Rules.Win.SAN_JIN, true, -1)
		return
	if is_winning_hand(seat):
		_finish(seat, _classify(seat), true, -1)
		return
	_prepare_discard_phase()

## 补杠：碰过的牌又摸到第四张
func human_bugang_tiles_for(seat: int) -> Array:
	var out: Array = []
	if finished or phase != Phase.DISCARD or turn != seat:
		return out
	var p: Dictionary = players[seat]
	for m in p["melds"]:
		if int(m["type"]) == MELD_PENG and p["hand"].has(m["tiles"][0]):
			out.append(int(m["tiles"][0]))
	return out

func human_bugang_tiles() -> Array:
	if not human_selectable():
		return []
	return human_bugang_tiles_for(SEAT_SELF)

func do_bu_gang(seat: int, tile: int) -> void:
	if finished or phase != Phase.DISCARD or turn != seat:
		return
	var p: Dictionary = players[seat]
	if not p["hand"].has(tile):
		return
	var idx := -1
	for i in p["melds"].size():
		if int(p["melds"][i]["type"]) == MELD_PENG and int(p["melds"][i]["tiles"][0]) == tile:
			idx = i
			break
	if idx < 0:
		return
	_remove_n(p["hand"], tile, 1)
	merge_drawn(seat)
	p["melds"][idx]["type"] = MELD_GANG_MING
	p["melds"][idx]["tiles"] = [tile, tile, tile, tile]
	p["gang_ming"] += 1
	set_action(seat, "bugang", "补杠")
	emit_log("%s 补杠 %s" % [p["name"], Tiles.kind_name(tile)])
	say(seat, Dialogue.on_bugang(rng, seat, Tiles.kind_name(tile)))
	event_fx = {"type": "call", "seat": seat, "text": "杠"}
	_gang_draw(seat)

## 暗杠
func do_an_gang(seat: int, tile: int) -> void:
	if finished or phase != Phase.DISCARD or turn != seat:
		return
	var p: Dictionary = players[seat]
	if p["hand"].count(tile) < 4:
		return
	_remove_n(p["hand"], tile, 4)
	merge_drawn(seat)
	p["melds"].append({"type": MELD_GANG_AN, "tiles": [tile, tile, tile, tile], "from": seat})
	p["gang_an"] += 1
	set_action(seat, "angang", "暗杠")
	emit_log("%s 暗杠" % p["name"])
	say(seat, Dialogue.on_angang(rng, seat))
	event_fx = {"type": "call", "seat": seat, "text": "暗杠"}
	_gang_draw(seat)

static func _remove_n(arr: Array, tile: int, n: int) -> void:
	for i in n:
		var idx := arr.find(tile)
		if idx >= 0:
			arr.remove_at(idx)

func _advance_turn(from_seat: int) -> void:
	first_go_around = false
	pending_claims.clear()
	human_options = []
	do_draw((from_seat + 1) % 4)

# ------------------------------------------------------------------ 结算
## 特殊和牌「只算一种就高」：金雀 30 > 三金倒 10；三金倒在摸牌时已直接触发
func _classify(seat: int) -> int:
	var n := jokers_in(seat)
	if n >= 2 and Rules.is_jin_que(counts_no_joker(seat), n):
		return Rules.Win.JIN_QUE
	if n >= 3:
		return Rules.Win.SAN_JIN
	return Rules.Win.NORMAL

func _finish(winner: int, win_kind: int, self_draw: bool, loser: int) -> void:
	if finished:
		return
	finished = true
	phase = Phase.OVER
	_over_timer = 0.0
	var p: Dictionary = players[winner]
	var n := jokers_in(winner)
	var flowers_n: int = p["flowers"].size()
	var gm: int = p["gang_ming"]
	var ga: int = p["gang_an"]
	# 连庄番：庄家每连庄 +1（首连庄「站顶」不计，lian_zhuang 已扣除）；仅庄家和牌时计入
	var lian_fan: int = lian_zhuang if winner == dealer else 0
	match win_kind:
		Rules.Win.JIN_QUE:
			say(winner, Dialogue.on_jinque(rng, winner))
		Rules.Win.SAN_JIN:
			say(winner, Dialogue.on_sanjindao(rng, winner))
		Rules.Win.TIAN_HU:
			say(winner, Dialogue.on_tianhu(rng, winner))
		Rules.Win.QIANG_JIN:
			say(winner, Dialogue.on_qiangjin(rng, winner))
		_:
			say(winner, Dialogue.on_win(rng, winner, self_draw))
	if not self_draw and loser >= 0:
		say(loser, Dialogue.on_lose_ron(rng, loser))
	# 无论点炮还是自摸，三家输家都扣分；赢家得分 = 三家之和
	var core := Rules.settle_core(win_kind, flowers_n, n, gm, ga, lian_fan, self_draw)
	var total := core * 3
	p["score"] += total
	for i in 4:
		if i != winner:
			players[i]["score"] -= core
	if winner == dealer:
		dealer_tenure_wins += 1
		lian_zhuang = maxi(0, dealer_tenure_wins - 1)   # 第一庄为「站顶」，不计连庄
	else:
		dealer = (dealer + 1) % 4
		lian_zhuang = 0
		dealer_tenure_wins = 0
		if dealer == 0:
			round_wind = (round_wind + 1) % 4
	var special := Rules.special_fan(win_kind)
	result = {
		"winner": winner,
		"win_kind": win_kind,
		"win_name": Rules.WIN_NAME.get(win_kind, "和牌"),
		"self_draw": self_draw,
		"loser": loser,
		"points": total,
		"core": core,
		"flower_fan": flowers_n,
		"gang_fan": Rules.gang_fan(gm, ga),
		"jokers": n,
		"lian_fan": lian_fan,
		"special_fan": special,
		"detail": "%s · 花 %d · 金 %d · 杠 %d · 连庄 %d%s" % [
			"自摸" if self_draw else "点炮", flowers_n, n, Rules.gang_fan(gm, ga), lian_fan,
			" · 特殊 +%d" % special if special > 0 else ""],
	}
	emit_log("%s %s！%+d 分" % [p["name"], result["win_name"], total])
	event_fx = {"type": "win", "seat": winner, "text": result["win_name"]}
	state_changed.emit()
	hand_finished.emit(result)

func _draw_game() -> void:
	if finished:
		return
	finished = true
	phase = Phase.OVER
	_over_timer = 0.0
	result = {"winner": -1, "win_kind": -1, "win_name": "和局", "self_draw": false,
		"loser": -1, "points": 0, "core": 0, "flower_fan": 0, "gang_fan": 0,
		"jokers": 0, "lian_fan": 0, "special_fan": 0,
		"detail": "牌墙已尽（保留 %d 张）" % reserved}
	emit_log("和局：牌墙已尽，庄家连庄")
	for i in 4:
		say(i, Dialogue.on_draw_game(rng, i))
	# 流局连庄：庄家继续坐庄，连庄数照算（首庄仍为「站顶」不计）
	dealer_tenure_wins += 1
	lian_zhuang = maxi(0, dealer_tenure_wins - 1)
	event_fx = {"type": "draw_game", "seat": -1, "text": "和局"}
	state_changed.emit()
	hand_finished.emit(result)

# ------------------------------------------------------------------ 查询
## 当前玩家还需打出几张（>1 表示开金补花后庄家要多打）
func discards_remaining() -> int:
	if finished:
		return 0
	return maxi(1, int(must_discard[turn]))

func human_selectable() -> bool:
	return (not finished) and (not autoplay) and turn == SEAT_SELF and phase == Phase.DISCARD

func human_can_angang(tile: int) -> bool:
	if not human_selectable():
		return false
	if tile == joker_kind:
		return false
	return players[SEAT_SELF]["hand"].count(tile) >= 4

func human_angang_tiles() -> Array:
	var out: Array = []
	if not human_selectable():
		return out
	var c := Tiles.counts_of(players[SEAT_SELF]["hand"])
	for k in Tiles.NUM_TILE_KINDS:
		if c[k] >= 4 and k != joker_kind:
			out.append(k)
	return out

func human_ting_hint() -> Array:
	var p: Dictionary = players[SEAT_SELF]
	if p["hand"].size() % 3 != 1:
		return []
	return Rules.winning_tiles(counts_no_joker(SEAT_SELF), jokers_in(SEAT_SELF))

# ------------------------------------------------------------------ 推进
func tick(delta: float) -> void:
	if finished:
		# 托管模式下自动开下一局（无人值守验证用）
		if autoplay:
			_over_timer += delta
			if _over_timer >= 3.0:
				_over_timer = 0.0
				start_hand()
		return
	if phase == Phase.CLAIM:
		claim_timer += delta
		if not human_options.is_empty():
			if claim_timer > claim_limit:
				resolve_human_claim("pass")
			return
		_resolve_claims()
		return
	if phase == Phase.WAIT_LAST:
		turn_timer = maxf(0.0, turn_timer - delta)
		if turn_timer <= 0.0:
			_ai_delay = 0.0
			_draw_last_group((turn + 1) % 4)
		return
	if phase != Phase.DISCARD:
		return
	turn_timer = maxf(0.0, turn_timer - delta)
	if turn == SEAT_SELF and not autoplay:
		if turn_timer <= 0.0:
			var t := choose_ai_discard(SEAT_SELF)
			if t >= 0:
				discard(SEAT_SELF, t)
		return
	_ai_delay += delta
	# AI 思考间隔也翻倍，与人类节奏一致
	if _ai_delay >= 1.0 or turn_timer <= 0.0:
		_ai_delay = 0.0
		ai_act()

# ------------------------------------------------------------------ 调试钩子
## 直接和牌（用于验证胜利路径）
func debug_force_win() -> void:
	if finished:
		return
	players[SEAT_SELF]["hand"] = [0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31, 31]
	players[SEAT_SELF]["melds"] = []
	players[SEAT_SELF]["flowers"] = [34, 35]   # 保证得分非零，便于断言
	phase = Phase.DISCARD
	turn = SEAT_SELF
	_finish(SEAT_SELF, _classify(SEAT_SELF), true, -1)

## 构造一个人类可碰的机会（用于验证碰/过 按钮）
func debug_force_claim() -> void:
	if finished:
		return
	players[SEAT_SELF]["hand"] = [0, 0, 1, 2, 3, 12, 13, 14, 24, 25, 26, 31, 31]
	last_discard = 0
	last_discard_by = SEAT_LEFT
	players[SEAT_LEFT]["discards"].append(0)
	var cl := {"seat": SEAT_SELF, "action": "peng", "prio": 2, "tiles": [0, 0, 0]}
	pending_claims.clear()
	human_options.clear()
	pending_claims.append(cl)
	human_options.append(cl)
	phase = Phase.CLAIM
	claim_timer = 0.0
	state_changed.emit()

## 直接和局（用于验证失败/结束路径）
func debug_force_draw_game() -> void:
	_draw_game()

# ------------------------------------------------------------------ AI
func ai_act() -> void:
	if finished or phase != Phase.DISCARD:
		return
	var seat := turn
	var p: Dictionary = players[seat]
	if jokers_in(seat) >= 3:
		_finish(seat, Rules.Win.SAN_JIN, true, -1)
		return
	if is_winning_hand(seat):
		_finish(seat, _classify(seat), true, -1)
		return
	var ang := human_angang_tiles_for(seat)
	if not ang.is_empty():
		do_an_gang(seat, ang[0])
		return
	var bu := human_bugang_tiles_for(seat)
	if not bu.is_empty():
		do_bu_gang(seat, bu[0])
		return
	var t := choose_ai_discard(seat)
	if t >= 0:
		discard(seat, t)

func human_angang_tiles_for(seat: int) -> Array:
	var out: Array = []
	var c := Tiles.counts_of(players[seat]["hand"])
	for k in Tiles.NUM_TILE_KINDS:
		if c[k] >= 4 and k != joker_kind:
			out.append(k)
	return out

## 选择要打出的牌：最大化剩余手牌面子数，并优先舍弃孤张
func choose_ai_discard(seat: int) -> int:
	var hand: Array = players[seat]["hand"]
	if hand.is_empty():
		return -1
	var n := jokers_in(seat)
	var full := Tiles.counts_of(hand)
	var best_tile: int = -1
	var best_score: float = -1e9
	var seen := {}
	for t in hand:
		if seen.has(t):
			continue
		seen[t] = true
		if t == joker_kind:
			continue   # 金牌不能打出
		var c := full.duplicate()
		c[t] -= 1
		if joker_kind >= 0:
			c[joker_kind] = 0
		var sc := float(Rules.max_sets(c, n)) * 10.0 - float(Rules.isolation(full, t)) * 0.30
		if Rules.winning_tiles(c, n).size() > 0:
			sc += 25.0
		if sc > best_score:
			best_score = sc
			best_tile = t
	return best_tile   # <0 表示手上只剩金（已近和牌），无牌可打

## AI 是否响应他家弃牌
func ai_claim_decision(cl: Dictionary) -> bool:
	var seat: int = cl["seat"]
	var action: String = cl["action"]
	var tile: int = last_discard
	if action == "hu":
		return true
	if action == "gang":
		return true
	var c := Tiles.counts_of(players[seat]["hand"])
	if has_joker():
		c[joker_kind] = 0
	if action == "peng":
		return c[tile] >= 2 and players[seat]["melds"].size() < 4
	if action == "chi":
		var before := Rules.max_sets(c, jokers_in(seat))
		var grp: Array = cl["tiles"]
		for t in grp:
			if t != tile and c[t] > 0:
				c[t] -= 1
		var after := Rules.max_sets(c, jokers_in(seat))
		return after > before
	return false
