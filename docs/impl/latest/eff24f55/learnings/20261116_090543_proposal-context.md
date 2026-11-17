# CLAUDE.md / dev-rules への提案(relay-gate)

既存の CLAUDE.md と `docs/dev-rules/` は変更していない。取り込むかどうかは保守者が判断する。

## 提案 1: 重いテストの運用を `docs/dev-rules/test-strategy.md` にも書く

- 現状: 重いテスト(`# bats test_tags=heavy`)の運用は、CLAUDE.md(「distillery-impl 実装ハーネス規約」の節)、`docs/impl/latest/impl-config.yaml` の `commands.test` の注記、CI だけに書かれている。`docs/dev-rules/` には bats のタグ・重いテストの記載が無い。
- 問題: CLAUDE.md は詳細規約の正本を `docs/dev-rules/` とする。テストの書き方を dev-rules から読む実装者・検証者は、印の付け方と対応表への追加を知らないまま重いテストを足し、CI の `--check` で初めて気付く。
- 提案: `test-strategy.md` に次の 4 行を足す(CLAUDE.md の記載と同じ内容。どちらかを正本にし、もう一方は参照にする)。
  1. 1 件で 2 秒以上かかるテスト・MB 級の入力を作るテストは、`@test` の直前に `# bats test_tags=heavy` を付ける。
  2. 重いテストを足したら `scripts/ci/heavy-tests.json` に、テストのファイルと、それが確かめる仕組みのソースを足す。
  3. 重いテストは、仕組みを変えたときだけ `node scripts/ci/heavy-test-files.js <tier_dir> <base_ref>` が選んだファイルを流す。
  4. 時間を確かめるテストは「この入力なら、この時間以内に終わる」の確認で、性能の目標(目標値であり合否の検査ではない)の合否にしない。

## 提案 2: 出力を変えない変更の確かめ方(差分テスト)を `docs/dev-rules/test-strategy.md` に書く

- 現状: 2026-11-16 の性能改善では、実装者と独立した検証がそれぞれ独自のスクリプトで、変更前と変更後の実装の出力を比べた(実装者 139 入力、検証者 896 比較 × 2 OS、差 0)。手順はどこにも書かれていない。
- 問題: 同じ種類の変更(他の検証種別の性能改善、リファクタリング)で、確かめ方が人によって変わる。出力の一部しか確かめない既存テストだけで「出力は変えていない」と書いてしまうおそれがある。
- 提案: 次の手順を書く(`learnings/20261116_090543_output-preserving-perf-change-differential-test.md` の「回避方法」と同じ)。
  - 変更前の実装は `git show <base>:<path>` で一時ディレクトリへ取り出す(`git stash` を使わない)
  - 同じ入力・同じパス・同じ引数・同じ環境で実行し、終了コードと stdout・stderr の sha256 を比べる
  - ロケール 3 通り(`LC_ALL=C` / `LANG=C.UTF-8` / 未設定)と、開発機と Linux コンテナの両方で比べる
  - 件数と差の数を S4 done に記録する

## 提案 3: 性能の比べ方の基準環境を CLAUDE.md に書く

- 現状: 実測は macOS(開発機)と Linux コンテナ(`relay-gate-ci:ubuntu24`)の両方で行っているが、目標との差をどちらの値で見るかは決まっていない。同じ実装でも、多くの入力で macOS のほうが遅い(例: 制御文字だらけの job_id の 4,999 行で Linux 8.1 秒・macOS 11.3 秒。BSD sed と bash の文字列の扱いによる)。
- 提案: 仕様側の変更要求(今回の feedback の draft の CR-eff24f55-008 の 2 点目)が承認されたら、CLAUDE.md の実装規約に「性能の目標との差は、実行環境と同じ Linux コンテナの、負荷の小さい回の実測で記録する。macOS の値は参考」を 1 行足す。却下されたら足さない。
