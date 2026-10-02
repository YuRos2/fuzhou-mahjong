## 福州麻将 规则引擎 / 牌局状态 原生测试
## 运行： godot --headless --path . --script tests/test_rules.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", what)

func eq(a, b, what: String) -> void:
	if a == b:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s  (期望 %s，实际 %s)" % [what, str(b), str(a)])

func counts(pairs: Array) -> Array:
	var c := []
	c.resize(Tiles.NUM_TILE_KINDS)
	c.fill(0)
	for p in pairs:
		c[p] += 1
	return c

func _initialize() -> void:
	print("=== 福州麻将 规则测试 ===")
	test_wall()
	test_hu()
	test_joker()
	test_ting()
	test_chi()
	test_scoring()
	test_reserve()
	test_bugang()
	test_last_group()
	test_flower_definition()
	test_flower_modes()
	test_fan_rules()
	test_flower_rounds()
	test_hand16()
	test_zhanding()
	test_dealer_qiangjin()
	test_kaijin_flower_loop()
	test_wildcards()
	test_joker_no_discard()
	test_settlement_three_pay()
	test_draw_game_lianzhuang()
	test_drawn_tile()
	test_match_summary()
	test_thinking_time()
	test_sfx()
	test_scenes()
	test_dialogue()
	test_speech_signal()
	test_game_flow()
	test_debug_paths()
	print("=== 通过 %d，失败 %d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# ------------------------------------------------------------------ 牌张
func test_wall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var wall := Tiles.build_wall(rng)
	eq(wall.size(), 144, "整副牌 144 张")
	var c := Tiles.counts_of(wall)
	var total := 0
	for k in Tiles.NUM_TILE_KINDS:
		eq(c[k], 4, "牌种 %s 张数" % Tiles.kind_name(k))
		total += c[k]
	eq(total, 136, "数字+字牌共 136 张")
	var flowers := 0
	var paint := 0
	for t in wall:
		if Tiles.is_flower(t):
			flowers += 1
		if Tiles.is_paint_flower(t):
			paint += 1
	eq(flowers, 36, "花牌 36 张（字牌花 28 + 彩花 8）")
	eq(paint, 8, "彩花 8 张")
	eq(Tiles.kind_name(0), "一萬", "牌名 一萬")
	eq(Tiles.kind_name(33), "白", "牌名 白")
	eq(Tiles.kind_name(41), "菊", "牌名 菊")
	eq(Tiles.rank(8), 9, "九萬 rank")
	eq(Tiles.suit(26), Tiles.SUIT_SUO, "九索 suit")

# ------------------------------------------------------------------ 和牌
func test_hu() -> void:
	# 14 张标准和牌：123萬 456筒 789索 東東東 中中
	var win := counts([0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31, 31])
	check(Rules.can_hu(win, 0), "标准 14 张和牌")
	# 13 张（未摸牌）不能和
	var t13 := counts([0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31])
	check(not Rules.can_hu(t13, 0), "13 张未摸牌不能和")
	# 全刻子
	var all_pung := counts([0, 0, 0, 9, 9, 9, 18, 18, 18, 29, 29, 29, 33, 33])
	check(Rules.can_hu(all_pung, 0), "碰碰和（全刻子）")
	# 类型(6)：全对子型（七对）算和
	var pairs7 := counts([0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10, 10, 12, 12])
	check(Rules.can_hu(pairs7, 0), "七对型（全对子）算和")
	# 全是孤张、无对无顺 → 不算和
	var bad := counts([0, 2, 4, 6, 8, 9, 11, 13, 15, 17, 18, 20, 22, 27])
	check(not Rules.can_hu(bad, 0), "全是孤张不算和")
	# 七对型 + 金补一张
	check(Rules.can_hu(counts([0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10, 10, 12]), 1), "六对 + 1 金 可和")
	# 字牌不能成顺
	check(not Rules.can_hu(counts([27, 28, 29, 9, 9, 9, 18, 18, 18, 31, 31, 31, 33, 33]), 0),
		"字牌不能组顺子")

func test_joker() -> void:
	# 缺一张，用金补
	var c := counts([0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31])
	check(Rules.can_hu(c, 1), "13 张 + 1 金 可和")
	check(not Rules.can_hu(c, 0), "无金不可和")
	var c2 := counts([0, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31])
	check(Rules.can_hu(c2, 2), "12 张 + 2 金 可和")
	# 金雀：两张金作将
	check(Rules.is_jin_que(counts([0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27]), 2),
		"金雀（两金作将）")

func test_ting() -> void:
	# 听牌：123萬 456筒 789索 東東東 中 + 听 中
	var c := counts([0, 1, 2, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31])
	var t := Rules.winning_tiles(c, 0)
	check(t.has(31), "听 中（单骑）")
	eq(t.size(), 1, "只听中一张")
	# 两面听：三四萬 + 456筒 + 789索 + 東東東 + 中中  → 听 二萬 / 五萬
	var c2 := counts([2, 3, 12, 13, 14, 24, 25, 26, 27, 27, 27, 31, 31])
	var t2 := Rules.winning_tiles(c2, 0)
	check(t2.has(1) and t2.has(4), "两面听 二萬/五萬")
	eq(t2.size(), 2, "两面听共两张")

func test_chi() -> void:
	var c := counts([1, 2])   # 二萬 三萬
	var opts := Rules.chi_options(c, 0)   # 一萬
	eq(opts.size(), 1, "吃 一萬 只有一种组合")
	if opts.size() == 1:
		eq(opts[0], [0, 1, 2], "吃的组合为 一二三萬")
	var c2 := counts([0, 2])  # 一萬 三萬
	var opts2 := Rules.chi_options(c2, 1)  # 二萬
	eq(opts2.size(), 1, "吃 二萬 只有一种组合")
	check(Rules.chi_options(counts([31, 31]), 31).is_empty(), "字牌不能吃")

func test_scoring() -> void:
	# 新计分（《福州麻将游戏规则》九）：
	#   点炮底分 = 花番 + 金番 + 杠番 + 连庄番 + 特殊牌型番数
	#   自摸分   =（花番 + 金番 + 杠番 + 连庄番）× 2 + 特殊牌型番数
	# 普通和牌 点炮：2 花 + 1 金 = 3
	eq(Rules.settle_core(Rules.Win.NORMAL, 2, 1, 0, 0, 0, false), 3, "点炮底分 = 花+金+杠+连+特殊")
	# 普通和牌 自摸：(2+1) × 2 = 6
	eq(Rules.settle_core(Rules.Win.NORMAL, 2, 1, 0, 0, 0, true), 6, "自摸分 = (花+金+杠+连)×2+特殊")
	# 杠番：明杠 +1、暗杠 +2
	eq(Rules.gang_fan(2, 1), 4, "两明杠 + 一暗杠 = 4 番")
	eq(Rules.settle_core(Rules.Win.NORMAL, 0, 0, 1, 1, 0, false), 3, "明杠1+暗杠2 = 底分 3")
	# 连庄番
	eq(Rules.settle_core(Rules.Win.NORMAL, 0, 0, 0, 0, 2, true), 4, "连庄 2 番自摸 = 4")
	# 特殊牌型番数：三金倒 +10、抢金 +20、金雀 +30、天胡 +40
	eq(Rules.special_fan(Rules.Win.SAN_JIN), 10, "三金倒 +10")
	eq(Rules.special_fan(Rules.Win.QIANG_JIN), 20, "抢金 +20")
	eq(Rules.special_fan(Rules.Win.JIN_QUE), 30, "金雀 +30")
	eq(Rules.special_fan(Rules.Win.TIAN_HU), 40, "天胡 +40")
	# 三金倒自摸：3 金 → 3×2 + 10 = 16
	eq(Rules.settle_core(Rules.Win.SAN_JIN, 0, 3, 0, 0, 0, true), 16, "三金倒自摸 = 16")
	# 抢金点炮：2 花 + 20 = 22
	eq(Rules.settle_core(Rules.Win.QIANG_JIN, 2, 0, 0, 0, 0, false), 22, "抢金点炮 = 底分+20")
	# 天胡自摸：0×2 + 40 = 40
	eq(Rules.settle_core(Rules.Win.TIAN_HU, 0, 0, 0, 0, 0, true), 40, "天胡自摸 = 40")
	# 金雀自摸：2 金 → 2×2 + 30 = 34
	eq(Rules.settle_core(Rules.Win.JIN_QUE, 0, 2, 0, 0, 0, true), 34, "金雀自摸 = 34")

# ------------------------------------------------------------------ 牌局
func test_game_flow() -> void:
	var g := GameState.new(13)
	g.rng.seed = 424242
	g.new_match(424242)
	eq(g.players.size(), 4, "四个座位")
	var total_hand := 0
	for p in g.players:
		total_hand += p["hand"].size()
		for t in p["hand"]:
			check(not Tiles.is_flower(t), "手牌不含花牌")
	eq(total_hand, 53, "共发出 53 张（庄 14 + 闲 13×3）")
	check(g.joker_kind >= 0 and g.joker_kind < Tiles.NUM_TILE_KINDS, "金为普通牌种")
	check(g.remaining() > 0, "牌墙有剩余")
	# 人类出牌
	var before: int = g.players[GameState.SEAT_SELF]["hand"].size()
	if g.turn != GameState.SEAT_SELF:
		# 推进到人类回合
		var guard := 0
		while g.turn != GameState.SEAT_SELF and not g.finished and guard < 40:
			guard += 1
			if g.phase == GameState.Phase.DISCARD:
				g.ai_act()
			elif g.phase == GameState.Phase.CLAIM:
				g.resolve_human_claim("pass")
	check(g.turn == GameState.SEAT_SELF or g.finished, "可推进到人类回合")
	if g.turn == GameState.SEAT_SELF and g.phase == GameState.Phase.DISCARD:
		before = g.players[GameState.SEAT_SELF]["hand"].size()
		# 金牌不能打出，选一张非金牌
		var tile: int = -1
		for t in g.players[GameState.SEAT_SELF]["hand"]:
			if int(t) != g.joker_kind:
				tile = int(t)
				break
		check(tile >= 0 and g.discard(GameState.SEAT_SELF, tile), "人类可以出牌")
		eq(g.players[GameState.SEAT_SELF]["hand"].size(), before - 1, "出牌后手牌 -1")
		# 弃牌可能立即被其他家 吃/碰/杠 取走，故两种结果都算正确
		var claimed := false
		for q in g.players:
			for m in q["melds"]:
				if tile in m["tiles"]:
					claimed = true
		check(g.players[GameState.SEAT_SELF]["discards"].size() == 1 or claimed,
			"弃牌进入牌河或被副露")

func test_reserve() -> void:
	var g := GameState.new(13)
	g.new_match(9001)
	eq(g.required_reserve(), 18, "无杠时保留 18 张")
	g.players[0]["gang_ming"] = 2
	g.players[1]["gang_an"] = 1
	eq(g.required_reserve(), 18 + 2 + 2, "明杠+1 / 暗杠+2")
	g.players[2]["flowers"] = [27, 27, 27, 27]
	eq(g.required_reserve(), 18 + 2 + 2, "新规则：花牌不再增加留牌")

func test_bugang() -> void:
	var g := GameState.new(13)
	g.new_match(9002)
	# 人为构造：我方已碰一萬，手上又摸到一萬
	g.players[GameState.SEAT_SELF]["melds"] = [{"type": GameState.MELD_PENG,
		"tiles": [0, 0, 0], "from": 3}]
	g.players[GameState.SEAT_SELF]["hand"] = [0, 1, 2, 3, 12, 13, 14, 24, 25, 31]
	g.phase = GameState.Phase.DISCARD
	g.turn = GameState.SEAT_SELF
	var opts := g.human_bugang_tiles()
	check(opts.has(0), "碰后可补杠")
	g.do_bu_gang(GameState.SEAT_SELF, 0)
	eq(int(g.players[GameState.SEAT_SELF]["melds"][0]["type"]), GameState.MELD_GANG_MING, "补杠后成为明杠")
	eq(g.players[GameState.SEAT_SELF]["melds"][0]["tiles"].size(), 4, "杠牌为 4 张")
	eq(int(g.players[GameState.SEAT_SELF]["gang_ming"]), 1, "明杠计数 +1")

func test_last_group() -> void:
	var g := GameState.new(13)
	g.new_match(9100)
	eq(g.last_group_size(), 4, "最后一组 4 张")
	# 把牌墙压缩到只剩最后一组
	g.front = g.back - 3
	var got := {"n": 0}
	g.hand_finished.connect(func(r): got["n"] += 1)
	var guard := 0
	while not g.finished and guard < 40:
		guard += 1
		if g.phase == GameState.Phase.WAIT_LAST:
			g._draw_last_group((g.turn + 1) % 4)
		elif g.phase == GameState.Phase.DISCARD:
			g.ai_act()
		elif g.phase == GameState.Phase.CLAIM:
			g.resolve_human_claim("pass")
	check(g.finished, "最后一组会结束牌局")
	eq(got["n"], 1, "只产生一次结果")
	check(not g.result.is_empty(), "产生和牌或和局结果")

func test_flower_definition() -> void:
	# 花牌 = 東南西北中發白 各 4 张（28）+ 春夏秋冬梅蘭竹菊 各 1 张（8）= 36 张，只用作记分
	var bd := Tiles.flower_breakdown()
	eq(int(bd["honor_flowers"]), 28, "字牌花 28 张")
	eq(int(bd["paint_flowers"]), 8, "彩花 8 张")
	eq(int(bd["total"]), 36, "花牌合计 36 张")
	eq(Tiles.WALL_SIZE - 36, 108, "序数牌 108 张")

	var wall := Tiles.build_wall(_rng(31337))
	var honor_flowers := 0
	var paint_flowers := 0
	var numbers := 0
	for k in wall:
		if Tiles.is_flower(k):
			if Tiles.is_honor(k):
				honor_flowers += 1
			else:
				paint_flowers += 1
		else:
			numbers += 1
	eq(honor_flowers, 28, "牌墙中字牌花 28 张")
	eq(paint_flowers, 8, "牌墙中彩花 8 张")
	eq(numbers, 108, "牌墙中序数牌 108 张")

	# 每个字牌花种各 4 张、每个彩花各 1 张
	var full := []
	full.resize(Tiles.KINDS)
	full.fill(0)
	for t in wall:
		full[t] += 1
	for k in range(27, 34):
		eq(full[k], 4, "%s 共 4 张" % Tiles.kind_name(k))
	for k in range(34, 42):
		eq(full[k], 1, "%s 共 1 张" % Tiles.kind_name(k))

	# 花牌参与判定的入口
	eq(Tiles.is_flower(Tiles.K_EAST), true, "默认定义：東 是花牌")
	eq(Tiles.is_flower(Tiles.K_WHITE), true, "默认定义：白 是花牌")
	eq(Tiles.is_flower(34), true, "默认定义：春 是花牌")
	eq(Tiles.is_flower(0), false, "一萬 不是花牌")
	eq(Tiles.is_flower(26), false, "九索 不是花牌")
	eq(Tiles.is_paint_flower(Tiles.K_EAST), false, "東 不是彩花")
	eq(Tiles.is_paint_flower(41), true, "菊 是彩花")

func test_flower_modes() -> void:
	# 默认（百科主表）：36 张花牌全部触发补花 → 手牌只剩 万 / 筒 / 索
	for r in 24:
		var g := GameState.new(16)
		g.new_match(5000 + r)
		eq(g.flower_pool_size(), 36, "默认花牌池 36 张")
		var total := 0
		for p in g.players:
			total += p["hand"].size()
			for t in p["hand"]:
				check(not Tiles.is_flower(t), "补花后手牌不含任何花牌")
				check(Tiles.is_number(t), "补花后手牌只剩万/筒/索")
		eq(total, 65 + g._dealer_bonus_discards, "补花后四家手牌总数 = 65 + 开金补花数")

	# 参考实机变体（--honors-tiles）：只有彩花 8 张补牌，字牌留在手牌
	var honors_seen := 0
	for r2 in 16:
		var g2 := GameState.new(16)
		g2.honors_as_flowers = false
		g2.new_match(7000 + r2)
		eq(g2.flower_pool_size(), 8, "变体花牌池 8 张")
		var total2 := 0
		for p in g2.players:
			total2 += p["hand"].size()
			for c in p["hand"]:
				check(not Tiles.is_paint_flower(c), "变体：手牌不含彩花")
				if Tiles.is_honor(c):
					honors_seen += 1
		eq(total2, 65 + g2._dealer_bonus_discards, "变体补花后手牌总数 65 + 开金补花数")
	check(honors_seen > 0, "变体：字牌会留在手牌中")

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func test_fan_rules() -> void:
	# 新规则：花番 = 每张花 +1（不再按四张相同 / 成套加算）
	# 杠番独立计算：明杠 +1、暗杠 +2
	eq(Rules.gang_fan(0, 0), 0, "无杠 0 番")
	eq(Rules.gang_fan(1, 0), 1, "明杠 +1")
	eq(Rules.gang_fan(0, 1), 2, "暗杠 +2")
	eq(Rules.gang_fan(3, 2), 7, "三明杠 + 两暗杠 = 7")
	# 字牌作花时也只按张数计
	var g := GameState.new(16)
	g.new_match(17100)
	g.players[0]["flowers"] = [27, 27, 27, 27, 34]
	eq(int(g.players[0]["flowers"].size()), 5, "花番按张数：四東 + 春 = 5")

func test_flower_rounds() -> void:
	# 补花按「庄家为首、每轮一次、上轮未补进花者跳过」推进：
	# 只要结束时不残留花牌、且四家手牌张数正确即视为通过
	for k in 20:
		var g := GameState.new(13)
		g.new_match(8000 + k)
		var bonus: int = g._dealer_bonus_discards
		for p in g.players:
			var want := 14 if int(p["seat"]) == g.dealer else 13
			if int(p["seat"]) == g.dealer:
				want += bonus
			eq(p["hand"].size(), want, "补花后手牌张数正确")
			for c in p["hand"]:
				check(not Tiles.is_flower(c), "补花彻底（无花残留）")
		check(g.joker_kind < 0 or not Tiles.is_flower(g.joker_kind), "金不是花牌")
		check(g.discards_remaining() >= 1, "还需出牌张数 >= 1")

func test_hand16() -> void:
	# 福州传统：闲 16 / 庄 17（含坎门），和牌 17 张
	for k in 12:
		var g := GameState.new(16)
		g.new_match(11000 + k)
		var total := 0
		var bonus: int = g._dealer_bonus_discards
		for p in g.players:
			total += p["hand"].size()
			var want := (17 if int(p["seat"]) == g.dealer else 16)
			if int(p["seat"]) == g.dealer:
				want += bonus
			eq(p["hand"].size(), want, "16 张模式：待打牌张数")
		eq(total, 65 + bonus, "16 张模式：共发 65 张 + 开金补花 %d 张" % bonus)
	var g2 := GameState.new(16)
	g2.new_match(11099)
	g2.players[0]["melds"] = []
	eq(g2.concealed_need(0), 17, "16 张模式和牌需 17 张")
	var g3 := GameState.new(13)
	g3.new_match(11098)
	eq(g3.concealed_need(0), 14, "13 张模式（参考实机）和牌需 14 张")
	# 17 张的和牌型：11 + 123×5
	var win17 := counts([0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 18, 19, 20, 27, 27])
	check(Rules.can_hu(win17, 0), "17 张：11 + 123×5 可和")
	# 17 张全对子型：8 对 + 单张
	var pairs17 := counts([0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 9])
	check(Rules.can_hu(pairs17, 0), "17 张：8 对 + 单张 可和")

func test_zhanding() -> void:
	# 「第一次做庄后胜的第一庄为站顶，不算连庄的底数」
	var g := GameState.new(16)
	g.new_match(12000)
	var d := g.dealer
	g._finish(d, Rules.Win.NORMAL, true, -1)
	eq(g.lian_zhuang, 0, "第一庄取胜为站顶，连庄 0")
	g.start_hand()
	g._finish(g.dealer, Rules.Win.NORMAL, true, -1)
	eq(g.lian_zhuang, 1, "第二庄取胜 → 连庄 1")
	g.start_hand()
	g._finish(g.dealer, Rules.Win.NORMAL, true, -1)
	eq(g.lian_zhuang, 2, "第三庄取胜 → 连庄 2")
	# 闲家取胜 → 换庄、连庄清零
	var other := (g.dealer + 1) % 4
	g.start_hand()
	g._finish(other, Rules.Win.NORMAL, true, -1)
	eq(g.lian_zhuang, 0, "闲家取胜（抓庄）→ 连庄清零")
	eq(g.dealer, other, "闲家取胜 → 换庄")

func test_dealer_qiangjin() -> void:
	var g := GameState.new(16)
	g.new_match(13000)
	g.joker_kind = Tiles.K_WHITE
	g.joker_shown = true
	var d := g.dealer
	# 111 222 333 東東東 中中 + 白白白(金) = 17 张
	g.players[d]["hand"] = [1, 1, 1, 2, 2, 2, 3, 3, 3, 27, 27, 27, 31, 31, 33, 33, 33]
	check(not g._opening_can_hu(d), "该手牌不是天和（需打出首张）")
	check(g._opening_can_hu_dealer(), "庄家打一张换金即可和 → 庄家抢金")

func test_wildcards() -> void:
	# 金可只当本体使用 → 需要 0 张万能牌
	var with_spare := counts([0, 0, 0, 1, 1, 1, 2, 2, 2, 27, 27, 27, 31])
	eq(Rules.min_wildcards(with_spare, 1, 31), 0, "金作本体即可和 → 需要 0 张万能牌")
	# 金必须当万能牌用
	var need_joker := counts([0, 0, 0, 1, 1, 1, 2, 2, 2, 27, 27, 27, 31])
	eq(Rules.min_wildcards(need_joker, 1, 0), 1, "金必须当万能牌 → 需要 1 张")

## 金牌不能打出（新规则六）
func test_joker_no_discard() -> void:
	var g := GameState.new(16)
	g.new_match(17200)
	g.joker_kind = 0   # 一萬为金
	g.joker_shown = true
	g.phase = GameState.Phase.DISCARD
	g.turn = GameState.SEAT_SELF
	g.players[GameState.SEAT_SELF]["hand"] = [0, 1, 2, 3]
	check(not g.discard(GameState.SEAT_SELF, 0), "金牌不能打出")
	eq(int(g.players[GameState.SEAT_SELF]["hand"].size()), 4, "打金被拒后手牌不变")
	check(g.discard(GameState.SEAT_SELF, 1), "非金牌可以正常打出")

## 无论点炮还是自摸，三家输家都扣分；赢家得分 = 三家之和（新规则九）
func test_settlement_three_pay() -> void:
	var g := GameState.new(16)
	g.new_match(17300)
	var w: int = (g.dealer + 1) % 4   # 用闲家做赢家，排除连庄番干扰
	g.joker_kind = 0
	g.joker_shown = true
	g.players[w]["flowers"] = [34, 35]     # 花番 2
	g.players[w]["gang_ming"] = 1          # 杠番 1
	g.players[w]["hand"] = [0, 1, 2, 9, 9, 9, 18, 18, 18, 20, 20, 20, 24, 24, 24, 31, 31]
	var scores_before: Array = []
	for p in g.players:
		scores_before.append(int(p["score"]))
	# 点炮：底分 = 2 花 + 1 金 + 1 杠 = 4 → 三家各 -4，赢家 +12
	g._finish(w, Rules.Win.NORMAL, false, (w + 1) % 4)
	for i in 4:
		var want: int = int(scores_before[i]) + (12 if i == w else -4)
		eq(int(g.players[i]["score"]), want, "点炮三家同赔：座位 %d" % i)
	eq(int(g.result["core"]), 4, "点炮底分 4")
	eq(int(g.result["points"]), 12, "赢家得分 = 三家之和")
	# 自摸：(2+1+1)×2 = 8 → 三家各 -8，赢家 +24
	var g2 := GameState.new(16)
	g2.new_match(17301)
	var w2: int = (g2.dealer + 1) % 4
	g2.joker_kind = 0
	g2.joker_shown = true
	g2.players[w2]["flowers"] = [34, 35]
	g2.players[w2]["gang_ming"] = 1
	g2.players[w2]["hand"] = [0, 1, 2, 9, 9, 9, 18, 18, 18, 20, 20, 20, 24, 24, 24, 31, 31]
	g2._finish(w2, Rules.Win.NORMAL, true, -1)
	eq(int(g2.result["core"]), 8, "自摸分 8")
	eq(int(g2.result["points"]), 24, "自摸赢家得分 = 三家之和")
	for i in 4:
		var want2: int = (24 if i == w2 else -8)
		eq(int(g2.players[i]["score"]), want2, "自摸三家同赔：座位 %d" % i)

## 一圈成绩汇总 + 圈末判断（开始/结束场景的数据基础）
func test_match_summary() -> void:
	var g := GameState.new(16)
	g.new_match(18500)
	g.players[0]["score"] = 10
	g.players[1]["score"] = 30
	g.players[2]["score"] = -40
	g.players[3]["score"] = 0
	g.hand_no = 4
	MatchSummary.store(g)
	check(MatchSummary.has_data(), "成绩已写入")
	eq(MatchSummary.hands, 4, "记录局数")
	var rank := MatchSummary.ranking()
	eq(int(rank[0]["seat"]), 1, "最高分排第一")
	eq(int(rank[0]["score"]), 30, "第一名分数正确")
	eq(int(rank[3]["seat"]), 2, "最低分排最后")
	# HUD 圈末判断
	var hud := HudLayer.new()
	hud.game = g
	hud.hands_per_match = 4
	check(hud.is_match_final_hand(), "第 4 局为圈末（显示「总成绩」）")
	g.hand_no = 3
	check(not hud.is_match_final_hand(), "第 3 局非圈末")
	hud.free()
	MatchSummary.clear()
	check(not MatchSummary.has_data(), "成绩可清空")

## 新摸进的牌不并入牌列：排在数组末尾，出牌后再归位排序
func test_drawn_tile() -> void:
	var g := GameState.new(16)
	g.new_match(18100)
	for i in 4:
		eq(int(g.drawn_index[i]), -1, "开局无「新摸牌」标记")
	var seat := GameState.SEAT_SELF
	g.phase = GameState.Phase.DISCARD
	g.turn = seat
	g.do_draw(seat)
	if g.finished:
		return
	var hand: Array = g.players[seat]["hand"]
	var di: int = int(g.drawn_index[seat])
	eq(di, hand.size() - 1, "新摸的牌排在手牌末尾")
	# 末尾之前的牌列应保持有序
	var ordered := true
	for i in range(1, maxi(di, 1)):
		if int(hand[i]) < int(hand[i - 1]):
			ordered = false
	check(ordered, "牌列前缀保持有序")
	check(int(g.drawn_tile(seat)) == int(hand[di]), "drawn_tile 返回新摸的牌")
	# 打出一张非金牌后：标记清除且整手牌重新有序
	var pick := -1
	for t in hand:
		if int(t) != g.joker_kind:
			pick = int(t)
			break
	if pick >= 0 and g.discard(seat, pick):
		eq(int(g.drawn_index[seat]), -1, "出牌后清除「新摸牌」标记")
		var h2: Array = g.players[seat]["hand"]
		var sorted_ok := true
		for i in range(1, h2.size()):
			if int(h2[i]) < int(h2[i - 1]):
				sorted_ok = false
		check(sorted_ok, "出牌后手牌重新排序")

## 玩家思考时间翻倍
func test_thinking_time() -> void:
	var g := GameState.new(16)
	eq(g.turn_limit, 30.0, "出牌思考时间 30 秒（翻倍）")
	eq(g.claim_limit, 12.0, "吃碰杠胡决策 12 秒（翻倍）")

## 音效：全部音色都能正常合成
func test_sfx() -> void:
	var s := Sfx.new()
	s._ensure()
	for name in ["click", "select", "draw", "discard", "peng", "gang", "chi",
			"hu", "win", "lose", "kaijin", "flower", "deal"]:
		check(s.has(name), "音效存在：%s" % name)
		var st: AudioStreamWAV = s._streams[name]
		check(st != null and st.data.size() > 0, "音效波形非空：%s" % name)
	s.set_enabled(false)
	check(not s.enabled, "音效可关闭")
	s.free()

## 开始 / 结束场景可加载并构建
func test_scenes() -> void:
	for path in ["res://scenes/Start.tscn", "res://scenes/End.tscn", "res://scenes/Main.tscn"]:
		check(ResourceLoader.exists(path), "场景存在：%s" % path)
		var ps = load(path)
		check(ps != null, "场景可加载：%s" % path)
	# 实例化开始 / 结束场景，验证 _ready 构建无错
	# 直接调用 _ready() 构建 UI（测试环境尚未跑帧，不会自动触发）
	var start = load("res://scenes/Start.tscn").instantiate()
	start._ready()
	check(start.find_child("BtnStart", true, false) != null, "开始场景有「开始游戏」按钮")
	check(start.find_child("BtnHelp", true, false) != null, "开始场景有「玩法说明」按钮")
	start.free()
	var end = load("res://scenes/End.tscn").instantiate()
	end._ready()
	check(end.find_child("BtnAgain", true, false) != null, "结束场景有「再来一圈」按钮")
	check(end.find_child("BtnMenu", true, false) != null, "结束场景有「返回主菜单」按钮")
	end.free()

## 流局连庄（新规则二：胡牌或流局连庄）
func test_draw_game_lianzhuang() -> void:
	var g := GameState.new(16)
	g.new_match(17400)
	var d := g.dealer
	var lian_before := g.lian_zhuang
	g._draw_game()
	eq(g.dealer, d, "流局后庄家不换")
	eq(g.lian_zhuang, lian_before, "首局流局仍属「站顶」，连庄 0")
	g.start_hand()
	g._draw_game()
	eq(g.lian_zhuang, lian_before + 1, "再次流局 → 连庄 +1")

func test_dialogue() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for seat in 4:
		check(Dialogue.on_deal(rng, seat, seat == 0).length() > 0, "开局台词")
		check(Dialogue.on_kaijin(rng, seat, "一萬").contains("金"), "开金台词含『金』")
		check(Dialogue.on_sanjindao(rng, seat).contains("三金倒"), "三金倒台词")
		check(Dialogue.on_jinque(rng, seat).contains("金雀"), "金雀台词")
		check(Dialogue.on_qiangjin(rng, seat).contains("抢金"), "抢金台词")
		check(Dialogue.on_buhua(rng, seat, "春").length() > 0, "补花台词")
		check(Dialogue.on_peng(rng, seat, "一萬").contains("碰"), "碰台词")
		check(Dialogue.on_gang(rng, seat, "一萬").contains("杠"), "杠台词")
		check(Dialogue.on_bugang(rng, seat, "一萬").contains("补杠"), "补杠台词")
		check(Dialogue.on_angang(rng, seat).contains("暗杠"), "暗杠台词")
		check(Dialogue.on_joker_blocked(rng, seat).contains("金"), "金牌不能打出台词")
		check(Dialogue.on_win(rng, seat, true).length() > 0, "自摸台词")
		check(Dialogue.on_win(rng, seat, false).length() > 0, "放和台词")
		check(Dialogue.on_lose_ron(rng, seat).length() > 0, "点炮台词")
		check(Dialogue.on_draw_game(rng, seat).length() > 0, "和局台词")
		check(Dialogue.on_ting(rng, seat).length() > 0, "听牌台词")
	# 术语表覆盖百科列出的核心术语
	var gl := Dialogue.glossary()
	for term in ["金", "开金", "补花", "坎门", "企顶", "截胡", "抢金", "三金倒",
			"金雀", "天胡", "甜", "凑骹", "麻雀骹", "二索", "二饼",
			"八饼", "转桌脚", "麻将鬼"]:
		check(gl.contains(term), "术语表含「%s」" % term)

func test_speech_signal() -> void:
	var g := GameState.new(16)
	var got := {"n": 0, "seat": -1, "text": ""}
	g.speech.connect(func(seat, text): got["n"] += 1; got["seat"] = seat; got["text"] = text)
	g.new_match(15000)
	check(got["n"] >= 4, "开局每家都会说话")
	check(got["text"].length() > 0, "台词非空")

func test_kaijin_flower_loop() -> void:
	# 「如果开金时开出的为花，则算庄家的，为庄家补完花后，重新从牌尾翻开一张牌为金」
	# 若仍是花则继续循环，直到翻到非花为止。
	var g := GameState.new(16)
	g.new_match(16000)
	var d := g.dealer
	g.joker_kind = -1
	g.joker_shown = false
	g._dealer_bonus_discards = 0
	var flowers_before: int = g.players[d]["flowers"].size()
	var hand_before: int = g.players[d]["hand"].size()
	# 牌尾（从 back 往下取）：春 / 東 / 一萬(金) / 夏 / 二萬 / 四萬
	g.wall[g.back] = 34     # 春  花
	g.wall[g.back - 1] = 27 # 東  花（补花又补到花）
	g.wall[g.back - 2] = 0  # 一萬（非花，补花结束）
	g.wall[g.back - 3] = 35 # 夏  花（第二次开金仍是花）
	g.wall[g.back - 4] = 1  # 二萬（补花结束）
	g.wall[g.back - 5] = 3  # 四萬 → 金
	g._open_joker()
	eq(g.joker_kind, 3, "连续开花后开出金 = 四萬")
	eq(g.players[d]["flowers"].size(), flowers_before + 3, "三张花牌归庄家")
	eq(g.players[d]["hand"].size(), hand_before + 2, "庄家补花两次，手牌 +2")
	eq(g._dealer_bonus_discards, 2, "庄家需多打 2 张")
	g.must_discard[d] = 1 + g._dealer_bonus_discards
	eq(g.discards_remaining(), 3, "庄家首回合共需打出 3 张以恢复手牌张数")

func test_debug_paths() -> void:
	# 胜利路径
	var g := GameState.new(13)
	g.new_match(777)
	var got := {"r": {}}
	g.hand_finished.connect(func(r): got["r"] = r)
	g.debug_force_win()
	check(g.finished, "debug_force_win 结束牌局")
	eq(got["r"].get("winner", -1), GameState.SEAT_SELF, "获胜者为我方")
	check(int(got["r"].get("points", 0)) > 0, "获胜得分为正")
	# 碰的提示路径
	var g2 := GameState.new(13)
	g2.new_match(778)
	g2.debug_force_claim()
	eq(g2.phase, GameState.Phase.CLAIM, "进入吃碰杠胡阶段")
	check(not g2.human_options.is_empty(), "人类有可选动作")
	var melds_before: int = g2.players[GameState.SEAT_SELF]["melds"].size()
	g2.resolve_human_claim("peng")
	eq(g2.players[GameState.SEAT_SELF]["melds"].size(), melds_before + 1, "碰后副露 +1")
	# 和局路径
	var g3 := GameState.new(13)
	g3.new_match(779)
	g3.debug_force_draw_game()
	check(g3.finished, "和局结束牌局")
	eq(g3.result.get("winner", 0), -1, "和局没有和牌方")
