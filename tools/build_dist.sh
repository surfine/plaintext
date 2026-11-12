#!/usr/bin/env bash
# 打包《明文 Plaintext》的运行时交付包。
# 用法：bash tools/build_dist.sh [输出目录]   （默认 ./dist）
set -euo pipefail

# ---------- 路径 ----------
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$script_dir/.." && pwd)
out="${1:-$root/dist}"

# 转成绝对路径，避免 cd 之后相对路径失效
case "$out" in
  /*) out_abs="$out" ;;
  *)  out_abs="$PWD/$out" ;;
esac

echo "[build] 项目根目录：$root"
echo "[build] 输出目录：$out_abs"

# ---------- 1. 清空并重建输出目录 ----------
if [ -e "$out_abs" ]; then
  rm -rf "$out_abs"
fi
mkdir -p "$out_abs/art" 2>/dev/null || true
rmdir "$out_abs/art" 2>/dev/null || true
mkdir -p "$out_abs/story"

# ---------- 2. 复制运行时文件 ----------
# ais6-bridge.js、desk.js、app.manifest.json：嵌入宿主桌面与独立运行共用，原样复制不去注释
runtime_files=(index.html style.css rules.js story-init.js art.js portrait2.js audio.js engine.js ais6-bridge.js desk.js app.manifest.json)
for f in "${runtime_files[@]}"; do
  if [ -f "$root/$f" ]; then
    cp "$root/$f" "$out_abs/$f"
    echo "[copy] $f"
  else
    echo "[warn] 缺少运行时文件：$f" >&2
  fi
done

# story/ 下所有非 _ 开头的 .js 文件
story_count=0
for p in "$root"/story/*.js; do
  [ -e "$p" ] || continue
  base=$(basename "$p")
  case "$base" in
    _*) continue ;;
  esac
  cp "$p" "$out_abs/story/$base"
  story_count=$((story_count + 1))
  echo "[copy] story/$base"
done
echo "[build] 复制 story 文件 $story_count 个"

# 位图资源（真结局的手绘灯塔丘等）：整个 img/ 原样复制，缺了就跳过
if [ -d "$root/img" ]; then
  mkdir -p "$out_abs/img"
  img_count=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    rel="${p#"$root"/}"
    mkdir -p "$out_abs/$(dirname "$rel")"
    cp "$p" "$out_abs/$rel"
    echo "[copy] $rel"
    img_count=$((img_count + 1))
  done < <(find "$root/img" -type f | sort)
  echo "[build] 复制 img 文件 $img_count 个"
else
  echo "[warn] 缺少 img/ 目录，跳过位图资源" >&2
fi

# ---------- 3. 去掉 story/*.js 里的注释（保留字符串字面量） ----------
strip_comments() {
  # $1 = 目标文件
  node - "$1" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const src = fs.readFileSync(file, 'utf8');
let out = '';
let i = 0;
const n = src.length;

// 小状态机：只删除字符串字面量之外的 // 行注释 与 /* */ 块注释。
// 单引号 / 双引号 / 反引号模板串内部原样保留，正确跳过转义字符。
while (i < n) {
  const c = src[i];
  const d = i + 1 < n ? src[i + 1] : '';

  // 字符串字面量：原样搬走整段
  if (c === '"' || c === "'" || c === '`') {
    const quote = c;
    out += c;
    i++;
    while (i < n) {
      const ch = src[i];
      if (ch === '\\') {           // 转义：连同下一个字符一起搬
        out += ch;
        if (i + 1 < n) { out += src[i + 1]; i += 2; } else { i++; }
        continue;
      }
      if (ch === quote) { out += ch; i++; break; }
      out += ch;
      i++;
    }
    continue;
  }

  // 行注释
  if (c === '/' && d === '/') {
    i += 2;
    while (i < n && src[i] !== '\n') { i++; }
    // 保留换行（若无换行则到文件末尾）
    continue;
  }

  // 块注释
  if (c === '/' && d === '*') {
    i += 2;
    while (i < n && !(src[i] === '*' && src[i + 1] === '/')) { i++; }
    i += 2; // 跳过 */
    continue;
  }

  out += c;
  i++;
}

fs.writeFileSync(file, out);
NODE
}

if [ "$story_count" -gt 0 ]; then
  for p in "$out_abs"/story/*.js; do
    [ -e "$p" ] || continue
    strip_comments "$p"
    echo "[strip] ${p#"$out_abs"/}"
  done
fi

# 运行时 JS：只删整行注释与行首块注释（避开正则字面量风险）；CSS：删全部块注释
safe_strip_js() {
  node - "$1" <<'NODE'
const fs = require('fs'); const f = process.argv[2];
const lines = fs.readFileSync(f, 'utf8').split('\n'); const out = []; let inBlock = false;
for (const ln of lines) {
  const t = ln.trim();
  if (inBlock) { if (t.includes('*/')) { inBlock = false; const rest = ln.slice(ln.indexOf('*/') + 2); if (rest.trim()) out.push(rest); } continue; }
  if (t.startsWith('//')) continue;
  if (t.startsWith('/*')) { if (!t.includes('*/')) { inBlock = true; continue; } const rest = ln.slice(ln.indexOf('*/') + 2); if (rest.trim()) out.push(rest); continue; }
  out.push(ln);
}
fs.writeFileSync(f, out.join('\n'));
NODE
}
strip_css() {
  node - "$1" <<'NODE'
const fs = require('fs'); const f = process.argv[2];
fs.writeFileSync(f, fs.readFileSync(f, 'utf8').replace(/\/\*[\s\S]*?\*\//g, ''));
NODE
}
for js in rules.js art.js portrait2.js audio.js engine.js; do
  [ -f "$out_abs/$js" ] || continue
  safe_strip_js "$out_abs/$js"; node --check "$out_abs/$js"; echo "[strip-safe] $js 语法 OK"
done
[ -f "$out_abs/style.css" ] && { strip_css "$out_abs/style.css"; echo "[strip] style.css"; }

# 语法自检
for p in "$out_abs"/story/*.js; do
  [ -e "$p" ] || continue
  node --check "$p"
  echo "[check] ${p#"$out_abs"/} 语法 OK"
done

# ---------- 4. 文件清单与字节数 ----------
echo ""
echo "======== 交付清单 ========"
total_bytes=0
file_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  rel="${f#"$out_abs"/}"
  bytes=$(wc -c < "$f" | tr -d ' ')
  total_bytes=$((total_bytes + bytes))
  file_count=$((file_count + 1))
  printf '%10s  %s\n' "$bytes" "$rel"
done < <(find "$out_abs" -type f | sort)

echo "--------------------------"
echo "文件数：$file_count"
echo "总字节：$total_bytes"
echo "[build] 完成：$out_abs"
exit 0
