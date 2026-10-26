# 推論根拠サマリ

- event_id: 20261010_202000_feedback_impl_feedback_dcd8234d
- trigger_event: rdra:20261010_200000_feedback_impl_feedback_dcd8234d, nfr:20261010_201000_feedback_impl_feedback_dcd8234d

## direct work unit(CR-dcd8234d-001 / CR-dcd8234d-003): validate-config.sh のティア間共有と名前空間

### 入力の確認

- CLI 契約(参照のみ): validate-config.sh のエントリポイント所有ティアは tier-facade。検証オプションは `--feature-flag`(tier-facade)/ `--job-map`(tier-facade)/ `--crosscheck-job-map`(tier-rapid-crosscheck)/ `--target-catalog`(tier-final-crosscheck)。feature-flag.env と job-map.csv は facade が自身で検証している。
- クロスチェック簡素化(前段 CR-dcd8234d-007)で、クロスチェックジョブマップ CSV と対象カタログ CSV が廃止され、速報の比較ツール起動コマンドは速報クロスチェック設定(env)の 1 キーになった。残る速報の検証は「起動コマンドが絶対パスで存在し実行可能」「{job_id} を含む」の 2 点で、CSV クォート解析を要さない。
- したがって `--crosscheck-job-map` / `--target-catalog` の委譲(owner_tier が速報・確報ティア)は不要になり、facade が既存 env 検証と同じ方式で単独検証できる。

### 推論

- 委譲を無くす構成(案1)が、既存 env 検証と同じ方式で結合面を最小化し、簡素化の帰結として自然。委譲を残す案2 は共有すべき CSV 解析関数が消えた今、必然性がない。
- 同一プロセスの名前衝突(実装で target_catalog_repo_load の後勝ち上書きが終了コード 6 の内部障害を起こした)は委譲撤廃で live な主体が消えるが、将来のティア追加に備えた一般規則は安価な保険として CTR-007 に残す。
- 配置: ティア間(cross-tier)の関心のため system_architecture の cross_tier_rules に CTR-007 を新設し、速報ティアのレイヤー間規則 CLP-003 から参照する。方針資料は validate-config.sh の内部構成を定めず、本決定と矛盾しない。

## causal work unit(CR-dcd8234d-007): 簡素化の追従

- RDRA 差分 `docs/rdra/events/20261010_200000_feedback_impl_feedback_dcd8234d/_changes.md` と NFR 差分 `docs/nfr/events/20261010_201000_feedback_impl_feedback_dcd8234d/_changes.md` を正本に、arch latest の廃止構造(クロスチェックジョブマップ・対象カタログ・比較結果(comparison_result)・成果物 URI の受け渡し・確報の business_date / カタログ版)への言及を除去した。
- 比較ツール起動コマンドは速報クロスチェック設定・確報クロスチェック worker 設定が持ち、比較対象は比較ツール側(適用側)が定義する構成へ合わせた。worker は依頼レコードの値で起動コマンドの {job_id} を置換し、stdout / stderr / exit_code を依頼レコードの列へ保存する。
- データモデルは E-007 / E-008 / E-018 を削除し、E-006 / E-015 / E-016 / E-017 / E-019 / E-020 / E-027 を属性・関係レベルで追従。owned_entity_ids のクロスリファレンスを BC-002 / BC-005 で更新した。
- グレード値・ティア構成・レイヤリング・依存ルールの骨格は不変。方針資料(tmp/RelayGateのしくみ.md 42 / 261 / 595〜625 行、tmp/RelayGateの利用イメージ.md 326 行)と一致する。

## causal work unit(CR-dcd8234d-002): 受け入れ基準の振る舞い限定

- arch は受け入れ基準・UC の E2E 完了条件(Then)を記述しないため、本 CR は arch に影響しない(not_impacted)。UC 仕様の Then の書き換え(「同じ CSV クォート解析関数が使われ」の実装構造を外す)は下流 spec の責務。CTR-007 により委譲自体が消えるため、その実装構造への依存も解消される。

## 網羅率

- RDRA 網羅率 100%(アクター 2 / 外部システム 6 / 情報 24 / 状態 5 / 条件 47 / BUC 5)、NFR 重要メトリクス網羅率 100%(43/43)。廃止エンティティ削除で情報は 24 に減少。
