# macOS で全ゲート green でも Linux CI で落ちる 3 パターン(UTF-8 ロケールの read / SIGPIPE 無視 / 性能差)

## 何が起きたか

- 2026-09-23 に承認した実装(bats 334 / tier BDD 41 / UC BDD 36 / ATDD 2 がすべて macOS で pass)を PR #11 に出したところ、Linux CI(ubuntu-latest)で bats が 5 件失敗した。
- 失敗は 3 種類に分かれた。

| # | 症状 | 失敗したテスト |
|---|---|---|
| 1 | 行末が切れた UTF-8 の先頭バイトを含む行で、`encoding is not utf-8` の行番号が 1 ずれる | 不正 UTF-8 の行番号検証 |
| 2 | 事前走査 `tr \| sed` が `internal command failed commands=tr` になり終了コード 6 | sed 失敗時の帰属テスト |
| 3 | 5,000 行の性能テスト(NFR B.2.1.1 の 10 秒)が超過 | 性能テスト(通常 / verbose) |

- 修正後、独立検証が同じ系統の blocker を 1 件追加で見つけた(F-001: Unicode 空白を含む値の `key=value` / `key: value` 区切りが `LANG=C.UTF-8` でだけ変わる)。これも同じ attempt 内で直した。

## 原因

### 1. UTF-8 ロケールの bash `read` が不完全なマルチバイトを次行と結合する

- Linux CI は `LANG=C.UTF-8`。bash の `read` は UTF-8 ロケールでマルチバイト単位に読み、行末に不完全な先頭バイト(例: `\xE3` だけ)があると次の改行までを 1 行として扱う。
- macOS の bats 実行は既定が C ロケールのため再現しなかった。
- 結果として、行番号のカウントがずれた。

### 2. CI runner は SIGPIPE を無視する(`SIG_IGN` のまま子プロセスへ継承)

- `tr | sed` で sed が入力を読み切らずに終わると、tr は書き込み先を失う。
- 通常の端末では tr が SIGPIPE で終わる(終了状態 141)。実装は 141 を「tr の派生エラー」として無視していた。
- SIGPIPE を無視する環境では tr は `write error` で終了状態 1 になる。実装はこれを tr 自身の失敗と判定した。

### 3. 性能は CPU とツールの実装差で 2 倍以上変わる

- macOS(Apple Silicon)で 3.5 秒だった 5,000 行の処理が、GitHub Actions の runner では 10 秒を超えた。
- 実装側に O(n²) の文字列連結、1 セルごとの CSV 状態機械、行ごとの `setlocale` 相当の `local LC_ALL=C` があり、行数に対して非線形または定数倍の大きい処理が残っていた。

### 4. `[[:space:]]` は現在のロケールで評価される(F-001)

- `[[ $value == *[[:space:]]* ]]` は UTF-8 ロケールで U+2003 や U+3000 にも一致する。C ロケールでは一致しない。
- macOS の C ロケールの実行と Linux の `C.UTF-8` の実行で、同じ入力の stdout の区切りが変わった。

## 回避方法

- **外部入力を読む箇所はロケールを `LC_ALL=C` に固定する**(`read` / `[[:space:]]` / `tr` / `sed`)。バイト単位の仕様(行番号、制御文字の範囲)はバイト単位で実装する。
- **パイプラインの終了状態は「後段が失敗したら前段は見ない」**。前段の 141 と 1 を区別しない。`PIPESTATUS` の判定は後段から順に行う。
- **性能テストは線形の実装を選び、Linux コンテナで実測する**。CSV は IFS 分割の高速経路 + 長行だけ状態機械、連結は配列、`setlocale` は呼び出し元で 1 回。
- **PR を出す前に Linux コンテナで bats を実行する**。`docker run --rm -e LANG=C.UTF-8 -v "$PWD:/work" -w /work/facade relay-gate-ci:ubuntu24 bats -r test` を delivery 前のゲートに含める。独立検証もこのコマンドで Linux 側を実測した。
- **ロケール差の検証は 3 通り**(`LANG` 未設定 / `LANG=C.UTF-8` / `LC_ALL=C`)で stdout・stderr・終了コードがバイト一致することを確かめる。

## 次回の対応

- 他の tier(rapid-crosscheck / final-crosscheck / ops)の実装でも、同じ 3 パターンを着手前のチェックリストに入れる。
- bats の性能テストは、閾値に余裕(目標の 50% 以下)を持たせた実装にする。runner の性能は開発機の半分以下として見積もる。
- 「macOS で green」を承認の根拠にしない。承認前の S6 / S7 の記録に Linux コンテナの bats 実行結果(`linux_equivalent_check`)を残す(今回の S6 / S7 done で開始した)。
