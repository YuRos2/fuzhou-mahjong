# 福州麻将规则 → 代码映射与核对表

规则原文：**《福州麻将游戏规则》（新修订）**。

下表按原文条款逐条列出本项目的实现位置与状态，便于核对与回归。
所有断言可在 `tests/test_rules.gd` 中复现（`godot --headless --path . --script tests/test_rules.gd`）。

状态说明：**已实现** / 部分实现 / 未实现（有意偏离见 §11）。

---

## 一、用牌构成

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 总牌数 144 张 | `Tiles.WALL_SIZE` + 单测 `test_wall()` | 已实现 |
| 万 / 饼 / 条 各 36 张（共 108） | `Tiles.SUIT_WAN/SUIT_TONG/SUIT_SUO`（kind 0..26） | 已实现 |
| 字牌 东南西北中发白 共 28 张（只计分） | `Tiles.SUIT_HONOR`（27..33） | 已实现 |
| 花牌 春夏秋冬、梅兰竹菊 共 8 张（只计分） | `Tiles.SUIT_FLOWER`（34..41） | 已实现 |
| 字牌与花牌只计分、不参与牌型 | `Tiles.is_flower_in()`；补花后手牌只剩万/筒/索 | 已实现 |

单测：`test_wall()`、`test_flower_definition()`、`test_flower_modes()`。

> 兼容开关 `--honors-tiles`：参考实机（4399）变体，只把彩花 8 张当花牌，字牌留在手牌可组刻子。

---

## 二、开局与摸牌

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 4 人游戏，东南西北各坐一方 | `GameState.players` / `SEAT_SELF..SEAT_LEFT` | 已实现 |
| 首局随机定庄 | `new_match()` → `rng.randi_range(0, 3)` | 已实现 |
| 之后胡牌连庄 | `_finish()`：庄家和牌 → `dealer_tenure_wins += 1` | 已实现 |
| 流局连庄 | `_draw_game()`：庄家不变、`dealer_tenure_wins += 1` | 已实现 |
| 庄家 17 张（含坎门多摸一张） | `hand_size = 16` + `players[dealer].append(_draw_front())` | 已实现 |
| 闲家 16 张 | `start_hand()` 每人 `hand_size` 张 | 已实现 |

单测：`test_hand16()`、`test_zhanding()`、`test_draw_game_lianzhuang()`。

---

## 三、补花

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 摸到花牌与字牌必须亮出 | `_deal_flowers()` / `do_draw()` 中 `is_flower_tile()` | 已实现 |
| 从牌尾补牌 | `_draw_back()` | 已实现 |
| 补牌又摸到花，须等四家补完后再继续补 | `_deal_flowers()` 多轮：庄家为首，未补进花者跳过 | 已实现 |
| 补花按庄家开始 | `order = [(dealer + i) % 4 for i in 4]` | 已实现 |

单测：`test_flower_rounds()`。

---

## 四、开金（财神牌）

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 补花结束后从牌尾翻第一张非花牌作金 | `_open_joker()` | 已实现 |
| 金可代任意牌组成顺子 / 刻子 / 将 | `Rules.can_hu(counts, jokers)` / `_sets_ok()` | 已实现 |
| 翻到花牌则归庄家补花后再翻 | `_open_joker()` 循环 + `_dealer_bonus_from_flower()` | 已实现 |
| 金的位置随补花、杠牌前移 | `TableView._joker_target_pos()`（倒数第 9 墩起，平滑滑动） | 已实现 |

单测：`test_kaijin_flower_loop()`。

---

## 五、吃、碰、杠

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 吃：仅限上家打出的牌组成顺子 | `_collect_claims()`：仅 `off == 1` 生成 `chi`；`Rules.chi_options()` | 已实现 |
| 碰 / 杠优先于吃 | `prio`：胡 3 / 碰・杠 2 / 吃 1 | 已实现 |
| 明杠①：碰后补第四张 | `do_bu_gang()` / `human_bugang_tiles()` | 已实现 |
| 明杠②：手中三张碰别人一张 | `c[tile] >= 3` → `MELD_GANG_MING` | 已实现 |
| 暗杠：手中四张 | `do_an_gang()` → `MELD_GANG_AN` | 已实现 |
| 杠后从牌尾补牌 | `_gang_draw()` 使用 `_draw_back()` | 已实现 |

单测：`test_chi()`、`test_bugang()`。

---

## 六、金牌相关特殊规则

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| **金牌不能打出** | `discard()` 拒绝 `tile == joker_kind`；手牌 UI 不可点选（`_hit_test`） | 已实现 |
| 金牌不能被吃 / 碰 / 杠 / 和 | `_collect_claims()` 开头跳过；`_can_ron()` 返回 false | 已实现 |
| 手上只剩金时自动结算，避免无法出牌 | `_prepare_discard_phase()` → `_has_discardable()` | 已实现 |

单测：`test_joker_no_discard()`。

---

## 七、胡牌牌型（基础）

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 5 组面子（顺子 / 刻子）+ 1 对将牌 | `Rules.can_hu()` / `_sets_ok()` | 已实现 |
| 面子可用金替代 | `can_hu()` 中 `jokers` 参与补牌 | 已实现 |
| 全对子型（旧版保留，原文未列） | `Rules._pairs_hand()` | 已实现（见 §11） |

单测：`test_hu()`、`test_joker()`、`test_hand16()`。

---

## 八、特色胡法（重点）

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| **三金倒 +10**：集齐三张金直接胡，不需牌型 | `jokers_in(seat) >= 3` → `Rules.Win.SAN_JIN` | 已实现 |
| **抢金 +20**：开金翻出的金能直接胡时立即胡，优先于普通胡牌 | `_opening_best()` / `_opening_can_hu()` / `_opening_can_hu_dealer()` | 已实现 |
| **金雀 +30**：以两张金作将牌胡牌 | `Rules.is_jin_que()`；多人听时优先截和 `_is_jin_que_claim()` | 已实现 |
| **天胡 +40**：庄家起手即胡 | `_check_opening_wins()` → `Rules.Win.TIAN_HU` | 已实现 |
| 特殊牌型只算一种，就高计番 | `_opening_best()` 取最高番；`_classify()`（金雀 > 三金倒） | 已实现 |
| 截和：多人听同一张按逆时针最近者和 | `_resolve_claims()` + `_seat_dist()` | 已实现 |

单测：`test_dealer_qiangjin()`、`test_settlement_three_pay()`、`test_scoring()`。

---

## 九、计分

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 花番：每张花 +1 | `Rules.settle_core(flowers_n = ...)`；统计 `players[w].flowers.size()` | 已实现 |
| 金番：每张金 +1 | `settle_core(jokers = jokers_in(winner))` | 已实现 |
| 杠番：明杠 +1、暗杠 +2 | `Rules.gang_fan()` | 已实现 |
| 连庄番：庄家每连庄 +1（首连庄「站顶」不计） | `lian_fan = lian_zhuang if winner == dealer else 0` | 已实现 |
| 点炮：底分 = 花番 + 金番 + 杠番 + 连庄番 + 特殊牌型番数 | `Rules.settle_core(..., self_draw = false)` | 已实现 |
| 自摸：自摸分 =（花番 + 金番 + 杠番 + 连庄番）× 2 + 特殊牌型番数 | `Rules.settle_core(..., self_draw = true)` | 已实现 |
| 无论点炮还是自摸，三个输家都扣分；赢家得三家之和 | `_finish()`：三家各 `-= core`，赢家 `+= core × 3` | 已实现 |
| 特殊牌型番数：三金倒 +10 / 抢金 +20 / 金雀 +30 / 天胡 +40，只算一种就高 | `Rules.WIN_FAN` / `Rules.special_fan()` | 已实现 |

单测：`test_scoring()`、`test_fan_rules()`、`test_settlement_three_pay()`、`test_zhanding()`。

---

## 十、流局（和局）

| 原文 | 实现 | 状态 |
| --- | --- | --- |
| 保留 18 张基本留牌 | `GameState.reserved = 18` | 已实现 |
| 每有明杠 +1 张留牌 | `required_reserve()`：`gang_ming * 1` | 已实现 |
| 每有暗杠 +2 张留牌 | `required_reserve()`：`gang_an * 2` | 已实现 |
| 抓到最后 4 张时不再补花、不再出牌，只能自摸 | `last_group_size()` / `_draw_last_group()` / `Phase.WAIT_LAST` | 已实现 |
| 4 人均没自摸即流局 | `_draw_game()` | 已实现 |
| 流局连庄 | `_draw_game()`：庄家不变、连庄数照算 | 已实现 |

单测：`test_reserve()`、`test_last_group()`、`test_draw_game_lianzhuang()`。

---

## 十一、与原文的差异（有意为之）

| 项 | 原文 | 本作 | 原因 |
| --- | --- | --- | --- |
| 全对子型 | 只列「5 组面子 + 1 对将」 | 保留全对子型可和 | 旧版已有、与新规则不冲突，保留可玩性 |
| 补花分轮 | 补牌又摸到花须等四家补完 | 开局按多轮实现；对局中摸花即时补到非花 | 对局中轮转补花会造成长时间停顿 |
| 对家手牌 | — | 默认隐藏，`T` 可透视 | 参考实机展示习惯 |
| 13 张手牌模式 | — | `--hand13` 可选 | 兼容参考实机的简化玩法 |

**已按新规则移除**（旧版曾有）：平和 / 平和一张花 / 金龙 特殊和牌、
「打金后只能自摸」与「闲金只能自摸」限制、四同花额外留牌；
抢金不再奖罚加倍（改为 +10/+20/+30/+40 的固定加番）；点炮与自摸均三家同赔。
