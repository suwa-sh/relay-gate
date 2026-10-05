# bats で stdout と stderr を分けて判定する方法と、開発機(macOS)の mktemp の差

## 何が起きたか

### 1. bats の `run` で stdout 0 行を確かめられなかった

- 内部障害のとき stdout を出さない(契約 `internal_failure`)ことを bats で判定しようとした。
- `run cmd 2>file` と書いても、bats の `run` は内側で `2>&1` を行うため、外側のリダイレクトが上書きされ、stdout と stderr が混ざった。
- `run --separate-stderr`(bats 1.5 以上)に変えると、`$output` が stdout だけ、`$stderr` が stderr だけになった。

### 2. macOS の mktemp がテンプレートの末尾以外の X を置き換えない

- 契約は一時ファイルの作業名を `relay-gate-XXXXXX.part`(mktemp のテンプレート)と定める。
- Linux(GNU coreutils)の mktemp はこの形を受け付ける。macOS(BSD)の mktemp は末尾の X しか置き換えず、テンプレートのままの名前でファイルを作った。
- 実装は、テンプレートのままの名前になったときだけ `relay-gate-<pid>-<乱数>.part` へ移してから使うフォールバックを入れた(前提 A-052)。
- 独立検証は、このフォールバックの mv が失敗すると元の作業ファイルが残ることを指摘した(minor F-004。実行環境の Linux では通らない経路)。

## 原因

- bats の `run` は出力を 1 本にまとめる設計で、リダイレクトの上書きはドキュメントを読まないと分からない。
- 契約は実行環境(オンプレ Linux)を前提に書かれ、開発機の差は仕様の対象外。開発機で動かすための分岐が実装に入ると、その分岐は検証の対象になる。

## 回避方法

- stdout と stderr を別々に判定する bats テストは、`bats_require_minimum_version 1.5.0` を宣言して `run --separate-stderr` を使う。
- 開発機向けの分岐は、削除対象の登録(trap)を新しい名前へ移す前に、元の名前も削除対象に残す。
- 開発機向けの分岐は、前提として記録し、実行環境では通らない経路であることを前提の本文に書く。検証者が severity を判定しやすくなる。

## 次回の対応

- 一時ファイルを使う他の機能でも、同じ mktemp のフォールバックと trap の部品を共有する。F-004 の残存(mv 失敗時に元の作業名を削除対象に残す)は、次の実装機会に直す。
- CI(Linux)でも bats を実行し、開発機の分岐が本番の経路を隠していないことを確かめる。
