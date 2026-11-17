#!/usr/bin/env node
// 長時間・大容量のテスト(bats の `# bats test_tags=heavy`)を「仕組みを変更したときだけ」流すための選択スクリプト。
// 通常の tdd ゲートは `bats -r --filter-tags '!heavy' test` で重いテストを除き、
// 重いテストはこのスクリプトが選んだファイルだけを `bats --filter-tags heavy <files>` で流す。
//
// 対応表: scripts/ci/heavy-tests.json(tier ごとのグループ { name, tests, sources }。パスは tier dir 相対)
//
// 使い方:
//   node scripts/ci/heavy-test-files.js <tier_dir> <base_ref>
//     <tier_dir> はリポジトリルート相対(例 facade)。<base_ref>...HEAD の差分と作業ツリーの未コミット変更
//     (追跡外の新規ファイルを含む)を合わせた変更ファイルから、sources か tests のどれかが変わったグループの
//     tests を重複なしで 1 行 1 ファイル(tier dir 相対)で出す。対応表かこのスクリプト自身が変わった場合は
//     その tier の全グループを出す。該当なしなら何も出さず exit 0。
//     <base_ref> が空・全桁 0(push で前の commit が無い場合)・解決できない場合は、変更を判定できないため
//     安全側に倒してその tier の全グループを出す(stderr に警告)。
//   node scripts/ci/heavy-test-files.js --check
//     heavy の印を持つ bats ファイルと対応表の tests が全 tier で一致すること、
//     対応表の sources / tests が実在することを検査する。不一致は内容を出して exit 1。
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..", "..");
const mapRelPath = "scripts/ci/heavy-tests.json";
const selfRelPath = "scripts/ci/heavy-test-files.js";
const HEAVY_TAG = "heavy";

function loadMap(root) {
  const map = JSON.parse(fs.readFileSync(path.join(root, mapRelPath), "utf8"));
  if (!map || typeof map.tiers !== "object" || map.tiers === null) {
    throw new Error(`${mapRelPath}: "tiers" object is required`);
  }
  return map;
}

// 変更ファイル(リポジトリルート相対)の集合から、tier の重いテストファイルを選ぶ(副作用なし)
function selectHeavyTestFiles(map, tierDir, changedFiles) {
  const groups = map.tiers[tierDir];
  if (!Array.isArray(groups)) {
    throw new Error(`unknown tier: ${tierDir} (not in ${mapRelPath})`);
  }
  const changed = new Set(changedFiles);
  const selectAll = changed.has(mapRelPath) || changed.has(selfRelPath);
  const out = [];
  const seen = new Set();
  for (const group of groups) {
    const files = [...(group.tests || []), ...(group.sources || [])];
    const hit = selectAll || files.some((f) => changed.has(`${tierDir}/${f}`));
    if (!hit) continue;
    for (const t of group.tests || []) {
      if (seen.has(t)) continue;
      seen.add(t);
      out.push(t);
    }
  }
  return out;
}

function git(args) {
  return execFileSync("git", args, { cwd: repoRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

// -z で区切る(非 ASCII のパスが引用符付きで出るのを避ける)
function splitZ(text) {
  return text.split("\0").filter((s) => s !== "");
}

function isResolvableCommit(ref) {
  if (!ref || /^0+$/.test(ref)) return false;
  try {
    git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]);
    return true;
  } catch {
    return false;
  }
}

function collectChangedFiles(baseRef) {
  const files = new Set();
  // rename は旧パスと新パスの両方を変更として数える
  for (const f of splitZ(git(["diff", "--name-only", "--no-renames", "-z", `${baseRef}...HEAD`]))) files.add(f);
  for (const f of splitZ(git(["diff", "--name-only", "--no-renames", "-z", "HEAD"]))) files.add(f);
  for (const f of splitZ(git(["ls-files", "--others", "--exclude-standard", "-z"]))) files.add(f);
  return [...files];
}

// bats の印: `# bats test_tags=a, b`(次の @test に付く)/ `# bats file_tags=a, b`(ファイル全体)
function hasHeavyMark(text) {
  const re = /^[ \t]*#[ \t]*bats[ \t]+(?:test_tags|file_tags)=(.*)$/gm;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m[1].split(",").some((t) => t.trim() === HEAVY_TAG)) return true;
  }
  return false;
}

function listBatsFiles(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listBatsFiles(p));
    else if (entry.isFile() && entry.name.endsWith(".bats")) out.push(p);
  }
  return out;
}

// test/ を持つ最上位ディレクトリを tier とみなす(対応表に載っていない tier の印も見逃さないため)
function discoverTierDirs(root) {
  return fs
    .readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith(".") && e.name !== "node_modules")
    .filter((e) => fs.existsSync(path.join(root, e.name, "test")))
    .map((e) => e.name);
}

function checkMap(root) {
  const map = loadMap(root);
  const problems = [];
  const tiers = new Set([...Object.keys(map.tiers), ...discoverTierDirs(root)]);
  const summary = [];
  for (const tier of [...tiers].sort()) {
    const groups = map.tiers[tier];
    const marked = new Set(
      listBatsFiles(path.join(root, tier, "test"))
        .filter((p) => hasHeavyMark(fs.readFileSync(p, "utf8")))
        .map((p) => path.relative(path.join(root, tier), p).split(path.sep).join("/")),
    );
    if (!Array.isArray(groups)) {
      for (const f of marked) problems.push(`${tier}: tier is not in ${mapRelPath} but has heavy-marked file ${f}`);
      continue;
    }
    const mapped = new Set();
    const names = new Set();
    for (const group of groups) {
      if (!group.name) problems.push(`${tier}: group without name`);
      else if (names.has(group.name)) problems.push(`${tier}: duplicate group name ${group.name}`);
      names.add(group.name);
      if (!Array.isArray(group.tests) || group.tests.length === 0) problems.push(`${tier}/${group.name}: tests is empty`);
      if (!Array.isArray(group.sources) || group.sources.length === 0) problems.push(`${tier}/${group.name}: sources is empty`);
      for (const kind of ["tests", "sources"]) {
        for (const f of group[kind] || []) {
          if (!fs.existsSync(path.join(root, tier, f))) problems.push(`${tier}/${group.name}: ${kind} entry does not exist: ${f}`);
        }
      }
      for (const t of group.tests || []) mapped.add(t);
    }
    for (const f of marked) if (!mapped.has(f)) problems.push(`${tier}: heavy-marked file is not in any group tests: ${f}`);
    for (const f of mapped) if (!marked.has(f)) problems.push(`${tier}: group tests entry has no heavy mark: ${f}`);
    summary.push(`${tier}=${marked.size}`);
  }
  return { problems, summary };
}

function main(argv) {
  if (argv[0] === "--check") {
    const { problems, summary } = checkMap(repoRoot);
    if (problems.length > 0) {
      for (const p of problems) process.stderr.write(`error: ${p}\n`);
      process.exit(1);
    }
    process.stdout.write(`ok: heavy marks match ${mapRelPath} (heavy files: ${summary.join(" ")})\n`);
    return;
  }
  if (argv.length !== 2) {
    process.stderr.write("usage: heavy-test-files.js <tier_dir> <base_ref> | --check\n");
    process.exit(2);
  }
  const [tierArg, baseRef] = argv;
  const tierDir = tierArg.replace(/\/+$/, "");
  const map = loadMap(repoRoot);
  let changed;
  if (isResolvableCommit(baseRef)) {
    changed = collectChangedFiles(baseRef);
  } else {
    process.stderr.write(`warn: base ref is not resolvable (${baseRef || "<empty>"}); selecting all heavy groups of ${tierDir}\n`);
    changed = [mapRelPath];
  }
  for (const f of selectHeavyTestFiles(map, tierDir, changed)) process.stdout.write(`${f}\n`);
}

if (require.main === module) {
  main(process.argv.slice(2));
}

module.exports = { selectHeavyTestFiles, hasHeavyMark, checkMap, loadMap };
