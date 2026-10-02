## 福州麻将 音效
## ------------------------------------------------------------------
## 运行时用简单合成（正弦 / 噪声 / 包络）生成 AudioStreamWAV，无需外部音频素材。
## 用法： Sfx.play("discard") ；音量 -12~-4 dB，多路复用避免互相打断。
class_name Sfx
extends Node

const RATE := 22050
const VOICES := 12

var enabled := true
var _players: Array = []
var _next := 0
var _streams: Dictionary = {}

func _ready() -> void:
	_ensure()

## 惰性初始化：保证任何调用时机（含自动化测试）都能拿到波形与播放器
func _ensure() -> void:
	if _streams.is_empty():
		_build_streams()
	if _players.is_empty():
		for i in VOICES:
			var p := AudioStreamPlayer.new()
			p.name = "Voice%d" % i
			add_child(p)
			_players.append(p)

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		for p in _players:
			p.stop()

## 播放音效；name 见 _build_streams
func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not enabled or not is_inside_tree():
		return
	_ensure()
	if not _streams.has(name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func has(name: String) -> bool:
	_ensure()
	return _streams.has(name)

# ------------------------------------------------------------------ 波形合成
func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(maxi(1, int(RATE * seconds)))
	a.fill(0.0)
	return a

## 叠加一段带包络的正弦（可含泛音）
func _sine(buf: PackedFloat32Array, at: float, dur: float, freq: float, vol: float,
		decay: float = 8.0, attack: float = 0.004, harmonics: Array = []) -> void:
	var s0 := int(at * RATE)
	var n := int(dur * RATE)
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var env: float = minf(t / maxf(attack, 1e-4), 1.0) * exp(-decay * t)
		var v: float = sin(TAU * freq * t)
		for h in harmonics:
			v += sin(TAU * freq * float(h[0]) * t) * float(h[1])
		buf[idx] += v * vol * env

## 叠加一段低通噪声（木牌敲击的“啪”）
func _noise(buf: PackedFloat32Array, at: float, dur: float, vol: float,
		decay: float = 45.0, lp: float = 0.35) -> void:
	var s0 := int(at * RATE)
	var n := int(dur * RATE)
	var prev := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var raw := randf() * 2.0 - 1.0
		prev = prev + lp * (raw - prev)     # 一阶低通
		var t := float(i) / RATE
		buf[idx] += prev * vol * exp(-decay * t)

## 频率滑音（“唰”）
func _sweep(buf: PackedFloat32Array, at: float, dur: float, f0: float, f1: float,
		vol: float, decay: float = 10.0) -> void:
	var s0 := int(at * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var f: float = lerpf(f0, f1, t / maxf(dur, 1e-4))
		phase += TAU * f / RATE
		buf[idx] += sin(phase) * vol * exp(-decay * t)

func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

# ------------------------------------------------------------------ 音色表
func _build_streams() -> void:
	# 界面点击
	var b := _buf(0.09)
	_sine(b, 0.0, 0.07, 1500.0, 0.32, 55.0)
	_streams["click"] = _to_stream(b)

	# 选牌
	b = _buf(0.1)
	_sine(b, 0.0, 0.08, 980.0, 0.30, 40.0)
	_streams["select"] = _to_stream(b)

	# 摸牌：轻噪 + 短音
	b = _buf(0.16)
	_noise(b, 0.0, 0.05, 0.30, 70.0, 0.5)
	_sine(b, 0.01, 0.10, 620.0, 0.20, 30.0)
	_streams["draw"] = _to_stream(b)

	# 出牌：木牌落桌
	b = _buf(0.22)
	_noise(b, 0.0, 0.10, 0.55, 48.0, 0.45)
	_sine(b, 0.0, 0.09, 260.0, 0.30, 40.0)
	_sine(b, 0.0, 0.06, 780.0, 0.16, 60.0)
	_streams["discard"] = _to_stream(b)

	# 碰：两下连击
	b = _buf(0.3)
	_noise(b, 0.0, 0.09, 0.5, 55.0, 0.45)
	_noise(b, 0.085, 0.10, 0.5, 48.0, 0.45)
	_sine(b, 0.0, 0.07, 300.0, 0.24, 45.0)
	_sine(b, 0.085, 0.08, 340.0, 0.24, 45.0)
	_streams["peng"] = _to_stream(b)

	# 杠：更低沉的两下
	b = _buf(0.36)
	_noise(b, 0.0, 0.12, 0.6, 40.0, 0.4)
	_noise(b, 0.11, 0.13, 0.6, 34.0, 0.4)
	_sine(b, 0.0, 0.14, 170.0, 0.34, 28.0)
	_sine(b, 0.11, 0.16, 150.0, 0.34, 26.0)
	_streams["gang"] = _to_stream(b)

	# 吃：上行两音
	b = _buf(0.22)
	_sine(b, 0.0, 0.09, 660.0, 0.26, 26.0)
	_sine(b, 0.08, 0.11, 880.0, 0.26, 24.0)
	_streams["chi"] = _to_stream(b)

	# 和牌：C-E-G-C 琶音
	b = _buf(0.5)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_sine(b, i * 0.075, 0.28, notes[i], 0.30, 9.0, 0.004,
			[[2.0, 0.18], [3.0, 0.08]])
	_streams["hu"] = _to_stream(b)

	# 特色大牌 / 胜利：更华丽的琶音 + 和弦
	b = _buf(1.0)
	for i in notes.size():
		_sine(b, i * 0.085, 0.5, notes[i], 0.30, 5.5, 0.004, [[2.0, 0.2], [3.0, 0.1]])
	for f in [523.25, 659.25, 783.99]:
		_sine(b, 0.34, 0.6, f, 0.16, 4.0, 0.01, [[2.0, 0.15]])
	_streams["win"] = _to_stream(b)

	# 失利 / 流局：下行
	b = _buf(0.5)
	_sine(b, 0.0, 0.18, 440.0, 0.26, 8.0)
	_sine(b, 0.12, 0.2, 349.23, 0.26, 8.0)
	_sine(b, 0.24, 0.26, 261.63, 0.28, 7.0)
	_streams["lose"] = _to_stream(b)

	# 开金：清脆闪音
	b = _buf(0.6)
	for i in 3:
		_sine(b, i * 0.07, 0.3, [1318.5, 1568.0, 2093.0][i], 0.26, 10.0, 0.003, [[2.0, 0.25]])
	_streams["kaijin"] = _to_stream(b)

	# 补花：柔和铃音
	b = _buf(0.4)
	_sine(b, 0.0, 0.34, 1046.5, 0.24, 7.0, 0.006, [[2.0, 0.3], [3.01, 0.12]])
	_streams["flower"] = _to_stream(b)

	# 发牌：连续轻响
	b = _buf(0.4)
	for i in 4:
		_noise(b, i * 0.07, 0.05, 0.28, 80.0, 0.5)
	_streams["deal"] = _to_stream(b)
