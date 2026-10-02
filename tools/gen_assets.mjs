#!/usr/bin/env node
/**
 * 福州麻将 素材生成器  (Fuzhou Mahjong asset generator)
 * ---------------------------------------------------------------
 * 参考: https://www.bilibili.com/video/BV1Ft1eYQE6A  (4399 福州麻将)
 * 用软光栅 (SDF + 超采样) 生成 PNG 素材，导入 Godot 项目。
 *
 * 运行:  node tools/gen_assets.mjs
 * 输出:  assets/generated/*.png
 */
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.resolve('assets/generated');
fs.mkdirSync(OUT, { recursive: true });

/* ------------------------------------------------------------------ PNG */
const CRC_T = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_T[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td), 0);
  return Buffer.concat([len, td, crc]);
}
function writePNG(file, w, h, rgba) {
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * stride, stride).copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
  return png.length;
}

/* ------------------------------------------------------- tiny rasterizer */
const SS = 3; // supersample factor
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const mix = (a, b, t) => a + (b - a) * t;
function hex(s) {
  const n = parseInt(s.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
// colour: [r,g,b] or [r,g,b,a] 0..255 / a 0..1
function C(c, a = 1) {
  const v = typeof c === 'string' ? hex(c) : c;
  return { r: v[0], g: v[1], b: v[2], a: v.length > 3 ? v[3] * a : a };
}

class Canvas {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.W = w * SS; this.H = h * SS;
    this.d = new Float32Array(this.W * this.H * 4);
  }
  /** paint with signed-distance coverage; sd(x,y) returns distance in *device* px */
  paint(sd, col) {
    const { W, H, d } = this;
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const s = sd((x + 0.5) / SS, (y + 0.5) / SS, x, y);
        if (s > 1.2) continue;
        const cov = Number.isFinite(s) ? clamp(0.5 - s, 0, 1) : 0;
        if (cov <= 0) continue;
        const c = C(typeof col === 'function' ? col((x + 0.5) / SS, (y + 0.5) / SS) : col);
        const a = c.a * cov;
        if (a <= 0) continue;
        const i = (y * W + x) * 4;
        d[i] = mix(d[i], c.r, a);
        d[i + 1] = mix(d[i + 1], c.g, a);
        d[i + 2] = mix(d[i + 2], c.b, a);
        d[i + 3] = clamp(d[i + 3] + a * 255, 0, 255);
      }
    }
  }
  /** full-canvas gradient / procedural fill (col returns [r,g,b,a]) */
  fillBg(fn) {
    const { W, H, d } = this;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const c = fn((x + 0.5) / SS, (y + 0.5) / SS);
      const i = (y * W + x) * 4;
      d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = c.length > 3 ? c[3] * 255 : 255;
    }
  }
  toRGBA() {
    const out = new Uint8Array(this.w * this.h * 4);
    const n = SS * SS;
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
        const i = ((y * SS + sy) * this.W + (x * SS + sx)) * 4;
        r += this.d[i]; g += this.d[i + 1]; b += this.d[i + 2]; a += this.d[i + 3];
      }
      const o = (y * this.w + x) * 4;
      const fin = (v) => (Number.isFinite(v) ? Math.max(0, Math.min(255, v / n)) : 0);
      out[o] = fin(r); out[o + 1] = fin(g); out[o + 2] = fin(b); out[o + 3] = fin(a);
    }
    return out;
  }
  save(name) {
    const bytes = writePNG(path.join(OUT, name), this.w, this.h, this.toRGBA());
    console.log(`  ${name.padEnd(26)} ${this.w}x${this.h}  ${(bytes / 1024).toFixed(1)} KB`);
  }
}

/* ------------------------------------------------------------------ SDFs */
function sdRoundRect(x, y, cx, cy, hw, hh, r) {
  const qx = Math.abs(x - cx) - (hw - r), qy = Math.abs(y - cy) - (hh - r);
  const ax = Math.max(qx, 0), ay = Math.max(qy, 0);
  return Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - r;
}
const sdCircle = (x, y, cx, cy, r) => Math.hypot(x - cx, y - cy) - r;
function sdRing(x, y, cx, cy, r, w) { return Math.abs(sdCircle(x, y, cx, cy, r)) - w / 2; }
/** n-point star, polar; inner/outer radius, smooth */
function sdStar(x, y, cx, cy, R, k, n, rot = 0) {
  const dx = x - cx, dy = y - cy;
  const th = Math.atan2(dy, dx) + rot;
  const rr = Math.hypot(dx, dy);
  const lim = R * (1 - k + k * Math.abs(Math.cos(n * th / 2)) ** 2.6);
  return rr - lim;
}

/* ============================================================ 1. 桌布 ==== */
function felt() {
  const W = 1920, H = 1080;
  const c = new Canvas(W, H);
  const base = hex('#00706e');       // 桌面主色
  const mid = hex('#00807b');
  const dark = hex('#005c5a');
  c.fillBg((x, y) => {
    const dx = (x - W / 2) / (W / 2), dy = (y - H / 2) / (H / 2);
    const d = Math.hypot(dx * 0.85, dy);
    let t = clamp(1 - d, 0, 1);
    let r = mix(dark[0], mid[0], Math.pow(t, 0.7));
    let g = mix(dark[1], mid[1], Math.pow(t, 0.7));
    let b = mix(dark[2], mid[2], Math.pow(t, 0.7));
    // 布料编织纹理
    const weave = (Math.sin(x * 2.1) + Math.sin(y * 2.1)) * 1.6
      + (Math.sin(x * 0.31 + y * 0.17) + Math.sin(y * 0.29 - x * 0.13)) * 2.2;
    r += weave; g += weave; b += weave;
    // 顶部高光
    const sheen = Math.max(0, 1 - Math.hypot((x - W * 0.42) / (W * 0.55), (y - H * 0.30) / (H * 0.42))) ** 2 * 12;
    r += sheen; g += sheen; b += sheen;
    const vig = clamp(1 - Math.hypot(dx, dy) * 0.55, 0, 1) ** 0.5;
    r *= mix(0.82, 1, vig); g *= mix(0.82, 1, vig); b *= mix(0.82, 1, vig);
    return [clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255), 1];
  });
  return c.save('felt.png');
}

/* ======================================================= 2. 牌 (tiles) ==== */
const TW = 72, TH = 96, TR = 7;   // 手牌尺寸 / 圆角

/** 分段渐变：stops = [[pos, '#rrggbb'], ...] */
function ramp(stops, t) {
  const cols = stops.map(s => [s[0], hex(s[1])]);
  for (let i = 0; i < cols.length - 1; i++) {
    const [p0, c0] = cols[i], [p1, c1] = cols[i + 1];
    if (t <= p1) {
      const k = p1 === p0 ? 0 : (t - p0) / (p1 - p0);
      return [mix(c0[0], c1[0], k), mix(c0[1], c1[1], k), mix(c0[2], c1[2], k), 1];
    }
  }
  const last = cols[cols.length - 1][1];
  return [last[0], last[1], last[2], 1];
}

/** 金色牌背：顶面亮金 + 底板深金（俯视，带顶/底棱） */
function tileBack() {
  const c = new Canvas(TW, TH);
  const edge = hex('#8A5C08');
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, TH / 2 + 2, TW / 2 - 1, TH / 2 - 1, TR + 1), [0, 0, 0, 0.28]);
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, TH / 2, TW / 2 - 1, TH / 2 - 1, TR),
    (x, y) => ramp([[0, '#FFF0B4'], [0.06, '#FFE58A'], [0.10, '#F0C542'],
      [0.55, '#E8B92C'], [0.86, '#C8901A'], [0.94, '#A9740E'], [1, '#8A5A08']], y / TH));
  // 左上斜向高光
  c.paint((x, y) => sdRoundRect(x, y, TW / 2 - 3, TH / 2 - 4, TW / 2 - 7, TH / 2 - 8, TR - 2),
    (x, y) => [255, 245, 200, clamp(0.40 - y / TH * 0.42, 0, 0.40)]);
  // 顶部亮棱
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, 5.0, TW / 2 - 4.0, 3.6, 3.2), [255, 250, 214, 0.95]);
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, TW / 2, TH / 2, TW / 2 - 1.2, TH / 2 - 1.2, TR)) - 0.8, edge);
  return c.save('tile_back.png');
}

/** 象牙白牌面（空白）：顶棱 → 白面 → 底灰棱 → 金边 */
function tileBlank() {
  const c = new Canvas(TW, TH);
  const edge = hex('#B5AA8E');
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, TH / 2 + 2, TW / 2 - 1, TH / 2 - 1, TR + 1), [0, 0, 0, 0.30]);
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, TH / 2, TW / 2 - 1, TH / 2 - 1, TR),
    (x, y) => ramp([[0, '#CFCBBE'], [0.05, '#DCD8CC'], [0.10, '#F7F6EF'], [0.20, '#FCFCF8'],
      [0.68, '#F4F3EC'], [0.76, '#E3E1D6'], [0.88, '#DBD8CB'], [0.92, '#F6D877'],
      [0.97, '#DE9E18'], [1, '#B87C08']], y / TH));
  // 面区微内凹
  c.paint((x, y) => sdRoundRect(x, y, TW / 2, TH / 2 - 2, TW / 2 - 5.0, TH / 2 - 8, TR - 3),
    (x, y) => [255, 255, 252, clamp(0.35 - y / TH * 0.35, 0, 0.35)]);
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, TW / 2, TH / 2, TW / 2 - 1.2, TH / 2 - 1.2, TR)) - 0.8, edge);
  return c.save('tile_blank.png');
}

/** 牌墙：竖排 (侧面视图) — 象牙白 + 右侧金条 */
function wallV() {
  const W = 34, H = 62;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 0.6, H / 2 - 1, 4), (x, y) => {
    const t = clamp((x - 3) / (W - 10), 0, 1);
    return [mix(206, 250, t), mix(203, 248, t), mix(193, 240, t), 1];
  });
  // 右侧金色牌背条
  c.paint((x, y) => sdRoundRect(x, y, W - 5.5, H / 2, 5, H / 2 - 1, 3), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(252, 196, t), mix(226, 146, t), mix(120, 22, t), 1];
  });
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 0.6, H / 2 - 1, 4)) - 0.6, hex('#9E947E'));
  return c.save('wall_v.png');
}
function wallVMirror() {
  const W = 34, H = 62;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 0.6, H / 2 - 1, 4), (x, y) => {
    const t = clamp((x - 8) / (W - 10), 0, 1);
    return [mix(252, 210, t), mix(249, 207, t), mix(240, 196, t), 1];
  });
  c.paint((x, y) => sdRoundRect(x, y, 5.5, H / 2, 5, H / 2 - 1, 3), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(252, 196, t), mix(226, 146, t), mix(120, 22, t), 1];
  });
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 0.6, H / 2 - 1, 4)) - 0.6, hex('#9E947E'));
  return c.save('wall_v_mirror.png');
}

/* ==================================================== 3. 面板 / 按钮 ==== */
function panelCenter() {
  const W = 620, H = 118;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 1.5, H / 2 - 1.5, 12), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(0, 3, t), mix(96, 62, t), mix(92, 58, t), 0.42];
  });
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 2.5, H / 2 - 2.5, 11)) - 1.4,
    (x, y) => [150, 226, 150, 0.42 + 0.25 * clamp(1 - y / H, 0, 1)]);
  return c.save('panel_center.png');
}
function panelPlayer() {
  const W = 220, H = 96;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, 6), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(1, 4, t), mix(92, 56, t), mix(88, 54, t), 0.55];
  });
  return c.save('panel_player.png');
}
function buttonGold(hl) {
  const W = 168, H = 62;
  const c = new Canvas(W, H);
  const top = hex(hl ? '#FFE9A0' : '#FFD974'), bot = hex(hl ? '#F0B12A' : '#DE9A18');
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2 + 2.5, W / 2 - 2, H / 2 - 2, 14), [0, 0, 0, 0.35]);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 2, H / 2 - 2, 14), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(top[0], bot[0], Math.pow(t, 0.8)), mix(top[1], bot[1], Math.pow(t, 0.8)), mix(top[2], bot[2], Math.pow(t, 0.8)), 1];
  });
  // 上高光
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H * 0.33, W / 2 - 8, H * 0.20, 8), [255, 255, 235, 0.55]);
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 3, H / 2 - 3, 12.5)) - 1.2, hex('#A9680A'));
  return c.save(hl ? 'btn_gold_hl.png' : 'btn_gold.png');
}

/** 中央倒计时：琥珀宝石 */
function badgeGem() {
  const W = 72, H = 72;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 2, H / 2 - 2, 16), [0, 0, 0, 0.4]);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 3.5, H / 2 - 3.5, 14), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(252, 176, t), mix(226, 108, t), mix(150, 22, t), 1];
  });
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H * 0.30, W / 2 - 12, H * 0.16, 10), [255, 250, 214, 0.62]);
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 4.5, H / 2 - 4.5, 13.5)) - 1.6, hex('#7C4A08'));
  return c.save('badge_gem.png');
}

/** 行动按钮上的连续光晕 (呼叫动画用) */
function starBurst(name, c1, c2) {
  const W = 320, H = 320, cx = W / 2, cy = H / 2;
  const c = new Canvas(W, H);
  const A = hex(c1), B = hex(c2);
  c.paint((x, y) => sdStar(x, y, cx, cy, 118, 0.78, 4, Math.PI / 4),
    (x, y) => [B[0], B[1], B[2], 0.95]);
  c.paint((x, y) => sdStar(x, y, cx, cy, 132, 0.72, 4, Math.PI / 4),
    (x, y) => {
      const r = Math.hypot(x - cx, y - cy) / 140;
      return [A[0], A[1], A[2], clamp(0.75 - r * 0.7, 0, 0.75)];
    });
  c.paint((x, y) => sdStar(x, y, cx, cy, 96, 0.66, 4, Math.PI / 4),
    (x, y) => {
      const r = Math.hypot(x - cx, y - cy) / 100;
      return [255, 255, 255, clamp(0.5 - r * 0.45, 0, 0.5)];
    });
  return c.save(name);
}

/* ============================================================ 4. 图标 ==== */
function iconCoin() {
  const W = 32, H = 32;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdCircle(x, y, W / 2, H / 2, 13.5), hex('#B47C06'));
  c.paint((x, y) => sdCircle(x, y, W / 2, H / 2, 12), (x, y) => {
    const t = clamp((x + y) / (W + H), 0, 1);
    return [mix(255, 214, t), mix(232, 156, t), mix(110, 24, t), 1];
  });
  c.paint((x, y) => sdCircle(x, y, W / 2 - 3.5, H / 2 - 4, 4.2), [255, 255, 220, 0.7]);
  return c.save('icon_coin.png');
}
function iconFlower() {
  const W = 34, H = 34, cx = W / 2, cy = H / 2;
  const c = new Canvas(W, H);
  for (let i = 0; i < 5; i++) {
    const a = -Math.PI / 2 + i * Math.PI * 2 / 5;
    c.paint((x, y) => sdCircle(x, y, cx + Math.cos(a) * 8.4, cy + Math.sin(a) * 8.4, 6.4),
      (x, y) => [mix(255, 226, (y / H)), mix(120, 60, (y / H)), mix(196, 140, (y / H)), 1]);
  }
  c.paint((x, y) => sdCircle(x, y, cx, cy, 4.6), hex('#E23A4E'));
  c.paint((x, y) => sdCircle(x, y, cx - 1.2, cy - 1.4, 1.5), [255, 220, 220, 0.85]);
  return c.save('icon_flower.png');
}
function windBadge() {
  const W = 56, H = 56;
  const c = new Canvas(W, H);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2 + 1.5, W / 2 - 3, H / 2 - 3, 6), [0, 0, 0, 0.45]);
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 3, H / 2 - 3, 6), [255, 255, 253, 1]);
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 4, H / 2 - 4, 5)) - 1.4, hex('#2A2A2A'));
  return c.save('wind_badge.png');
}
/** 柔和光晕 */
function glow(name, col, R = 64) {
  const W = R * 2, H = R * 2;
  const c = new Canvas(W, H);
  const A = hex(col);
  c.fillBg((x, y) => {
    const t = clamp(1 - Math.hypot(x - R, y - R) / R, 0, 1);
    return [A[0], A[1], A[2], Math.pow(t, 2.2)];
  });
  return c.save(name);
}

/* =========================================================== 5. 头像 ==== */
function avatar(name, opt) {
  const W = 84, H = 84, cx = W / 2;
  const c = new Canvas(W, H);
  const skin = hex(opt.skin), hair = hex(opt.hair), bg1 = hex(opt.bg[0]), bg2 = hex(opt.bg[1]);
  // 背景
  c.paint((x, y) => sdRoundRect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, 8), (x, y) => {
    const t = clamp(y / H, 0, 1);
    return [mix(bg1[0], bg2[0], t), mix(bg1[1], bg2[1], t), mix(bg1[2], bg2[2], t), 1];
  });
  // 装饰射线
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4 + 0.3;
    c.paint((x, y) => {
      const dx = x - cx, dy = y - W / 2, t = Math.atan2(dy, dx);
      let da = Math.abs(((t - a + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
      const r = Math.hypot(dx, dy);
      return Math.max(r - 52, da * 22 - 4, 26 - r);
    }, [255, 255, 255, 0.16]);
  }
  // 脖颈 + 身体
  c.paint((x, y) => sdRoundRect(x, y, cx, H - 6, 22, 16, 8), opt.cloth ? hex(opt.cloth) : hex('#E9EDF2'));
  c.paint((x, y) => sdRoundRect(x, y, cx, H - 16, 9, 8, 4), [skin[0] * 0.92, skin[1] * 0.92, skin[2] * 0.92, 1]);
  // 头
  c.paint((x, y) => sdCircle(x, y, cx, 38, 24), skin);
  // 头发
  if (opt.style === 'bob') {
    c.paint((x, y) => sdCircle(x, y, cx, 34, 25), hair);
    c.paint((x, y) => sdCircle(x, y, cx, 44, 20), skin);
    c.paint((x, y) => sdRoundRect(x, y, cx - 22, 52, 6, 16, 5), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx + 22, 52, 6, 16, 5), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx - 13, 30, 6, 12, 4), hair);
  } else if (opt.style === 'long') {
    c.paint((x, y) => sdCircle(x, y, cx, 33, 26), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx, 40, 19, 13, 9), skin);
    c.paint((x, y) => sdRoundRect(x, y, cx - 25, 58, 6, 22, 5), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx + 25, 58, 6, 22, 5), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx, 26, 20, 8, 6), hair);
  } else if (opt.style === 'bun') {
    c.paint((x, y) => sdCircle(x, y, cx, 36, 25), hair);
    c.paint((x, y) => sdCircle(x, y, cx, 22, 8, ), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx, 46, 20, 13, 9), skin);
    c.paint((x, y) => sdRoundRect(x, y, cx - 20, 30, 6, 9, 4), hair);
    c.paint((x, y) => sdRoundRect(x, y, cx + 20, 30, 6, 9, 4), hair);
  } else { // rabbit
    c.paint((x, y) => sdRoundRect(x, y, cx - 11, 16, 5.5, 15, 5), hex('#FDFDFD'));
    c.paint((x, y) => sdRoundRect(x, y, cx + 11, 16, 5.5, 15, 5), hex('#FDFDFD'));
    c.paint((x, y) => sdRoundRect(x, y, cx - 11, 17, 2.4, 11, 2), hex('#F7C2CF'));
    c.paint((x, y) => sdRoundRect(x, y, cx + 11, 17, 2.4, 11, 2), hex('#F7C2CF'));
    c.paint((x, y) => sdCircle(x, y, cx, 40, 25), hex('#FDFDFD'));
    c.paint((x, y) => sdCircle(x, y, cx - 9, 40, 3.4), hex('#2A2A2A'));
    c.paint((x, y) => sdCircle(x, y, cx + 9, 40, 3.4), hex('#2A2A2A'));
    c.paint((x, y) => sdCircle(x, y, cx, 47, 3.0), hex('#E8879B'));
    c.paint((x, y) => sdCircle(x, y, cx - 16, 47, 5), [245, 170, 186, 0.55]);
    c.paint((x, y) => sdCircle(x, y, cx + 16, 47, 5), [245, 170, 186, 0.55]);
    c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, 8)) - 1.2, hex('#28323C'));
    return c.save(name);
  }
  // 眼
  c.paint((x, y) => sdCircle(x, y, cx - 9, 40, 3.2), hex('#2A2A2A'));
  c.paint((x, y) => sdCircle(x, y, cx + 9, 40, 3.2), hex('#2A2A2A'));
  c.paint((x, y) => sdCircle(x, y, cx - 10.2, 38.8, 1.2), [255, 255, 255, 0.9]);
  c.paint((x, y) => sdCircle(x, y, cx + 7.8, 38.8, 1.2), [255, 255, 255, 0.9]);
  // 腮红 + 嘴
  c.paint((x, y) => sdCircle(x, y, cx - 15, 46, 4.4), [244, 150, 168, 0.45]);
  c.paint((x, y) => sdCircle(x, y, cx + 15, 46, 4.4), [244, 150, 168, 0.45]);
  c.paint((x, y) => sdCircle(x, y, cx, 48, 2.6), hex('#D4636F'));
  c.paint((x, y) => Math.abs(sdRoundRect(x, y, W / 2, H / 2, W / 2 - 1, H / 2 - 1, 8)) - 1.2, hex('#28323C'));
  return c.save(name);
}

/* =============================================================== main ==== */
console.log('生成福州麻将素材 →', OUT);
felt();
tileBack();
tileBlank();
wallV();
wallVMirror();
panelCenter();
panelPlayer();
buttonGold(false);
buttonGold(true);
badgeGem();
starBurst('burst_magenta.png', '#E24BE0', '#8A16A8');
starBurst('burst_cyan.png', '#41D8F5', '#0E6FA8');
starBurst('burst_gold.png', '#FFD86B', '#C87A0A');
iconCoin();
iconFlower();
windBadge();
glow('glow_white.png', '#FFFFFF', 64);
glow('glow_gold.png', '#FFD460', 64);
glow('glow_green.png', '#8CF08C', 80);
// 电脑玩家：则徐（林则徐）/ 葆桢（沈葆桢）/ 徽因（林徽因）
avatar('avatar_zexu.png', { style: 'bob', skin: '#F6D6C0', hair: '#3A2A32', bg: ['#D8402F', '#F2E6D0'], cloth: '#F0F2F6' });
avatar('avatar_baozhen.png', { style: 'bun', skin: '#E8C49E', hair: '#2C2620', bg: ['#E4C08A', '#F6E8CE'], cloth: '#B0463C' });
avatar('avatar_huiyin.png', { style: 'long', skin: '#F8DCC8', hair: '#8A4A2A', bg: ['#F6C6D8', '#FDF1F4'], cloth: '#EFA9BE' });
avatar('avatar_me.png', { style: 'rabbit', skin: '#FFFFFF', hair: '#FFFFFF', bg: ['#DCE6F2', '#F4F8FC'] });
console.log('完成。');
