#!/usr/bin/env node
// CI の ATDD ゲートで実行する Scenario を「完了済み UC に対応づけられた受け入れ基準」だけに絞る。
// features/atdd/ には全 SPEC の Scenario が bootstrap で生成済みだが、step が実装されるのは
// 各 UC の完了時(S7)なので、全件を strict 実行すると未着手 UC 分が undefined で fail する。
// 選択は dev-rules(test-strategy.md)どおり一意タグ `@atdd_{SPEC-ID}-{連番}` の完全一致で行う。
//
// 入力: docs/impl/latest/uc-map.yaml(use_cases[].atdd_scenarios)と
//       docs/impl/latest/{uc_id}/status.yaml(state: completed の UC だけを対象)
// 出力: cucumber-js の --tags 式(例 "@atdd_SPEC-001-01-4 or @atdd_SPEC-002-01-1")を stdout に 1 行。
//       対象 0 件なら空行を出して exit 0(呼び出し側で実行をスキップする)。
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const YAML = require("yaml");

const repoRoot = path.resolve(__dirname, "..", "..");
const latest = path.join(repoRoot, "docs", "impl", "latest");
const ucMapPath = path.join(latest, "uc-map.yaml");

if (!fs.existsSync(ucMapPath)) {
  process.stdout.write("\n");
  process.exit(0);
}

const ucMap = YAML.parse(fs.readFileSync(ucMapPath, "utf8"));
const tags = new Set();
for (const uc of ucMap.use_cases || []) {
  // uc_id は 8 桁 hex で、数字だけの id を YAML が数値に読むため文字列化する
  const statusPath = path.join(latest, String(uc.uc_id), "status.yaml");
  if (!fs.existsSync(statusPath)) continue;
  const status = YAML.parse(fs.readFileSync(statusPath, "utf8"));
  if (status.state !== "completed") continue;
  for (const name of uc.atdd_scenarios || []) tags.add(`@atdd_${name}`);
}

process.stdout.write(`${[...tags].sort().join(" or ")}\n`);
