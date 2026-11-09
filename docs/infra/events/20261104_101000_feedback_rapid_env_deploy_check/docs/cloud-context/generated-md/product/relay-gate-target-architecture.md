# relay-gate 並行稼働実行基盤 ターゲットアーキテクチャ(オンプレミス)

- workload_model: `product-relay-gate-workload-model`
- mapping: `product-relay-gate-mapping-onprem`
- impl_spec: `product-impl-onprem`
- generated_at: 2026-09-07T12:40:00

## ワークロード全体構成図

```mermaid
graph TD
  subgraph 実行ホストセグメント
    FACADE[facade / slot runner CLI]
    RAPID[rapid-crosscheck-runner・worker<br/>systemd常駐]
    HANG[hang-detector<br/>ジョブスケジューラの定期ジョブ 5分ごと]
    HK[housekeep<br/>ジョブスケジューラの定期ジョブ 1日1回]
    OPS[ops CLI 中止/リラン]
  end

  subgraph DBセグメント
    DB[(管理DB<br/>PostgreSQL 単一インスタンス<br/>rapid/finalスキーマ)]
    FINAL[final-crosscheck-worker<br/>systemd常駐]
    CFGDB[[確報クロスチェック worker 設定<br/>/etc/relay-gate/final-crosscheck.env 読取専用<br/>確報を使う設置だけ置き、使わない設置では消す<br/>DB セグメントに置く設定はこれだけ]]
  end

  subgraph 共通
    ART[[成果物ディレクトリ<br/>RAID1 ローカルディスク<br/>exitcode.txt / aborted.txt が状態の正本<br/>通知済みの印と削除待ちの置き場を同じ FS に置く]]
    LOG[[実行ログ領域<br/>logrotate 3ヶ月<br/>日時はホストのローカル TZ]]
    CFG[[設定ファイル配置<br/>/etc/relay-gate 読取専用<br/>feature-flag.env / *.csv / hang-detector.env / ハウスキープ設定 / rapid-crosscheck.env<br/>final-crosscheck.env 確報を使う設置だけ・確報 runner が読む<br/>全ホストを構築手順で配る]]
  end

  SCHED[組織既存ジョブスケジューラ] -->|同期起動| FACADE
  SCHED -->|定期起動| HANG
  SCHED -->|定期起動| HK
  OPER[運用者]
  FACADE --> ART
  FACADE --> DB
  RAPID -->|中止済み run 判定 parallel_run と slot_executions<br/>CLAIMED から RUNNING は条件付き UPDATE| DB
  RAPID --> ART
  HANG --> DB
  HANG --> ART
  HANG --> CFG
  HANG -->|終了結果 正常・警告・失敗と標準エラー| SCHED
  SCHED -->|障害通知| OPER
  HK -->|置き場へ rename して削除| ART
  HK -->|専用ロール housekeep_del で行を削除<br/>管理 DB を一切使わない設置だけ接続しない| DB
  HK --> CFG
  OPS -->|abort-rapid-crosscheck は REQUESTED・CLAIMED・RUNNING 依頼を ABORTED<br/>abort-blue・abort-green は未着手依頼を ABORTED 保険| DB
  OPS -->|aborted.txt| ART
  FINAL --> DB
  FINAL -->|起動のたびに読む 確報比較ツールの起動コマンドと接続参照名| CFGDB
  FACADE --> LOG
  RAPID --> LOG
  FINAL --> LOG
  FACADE --> CFG
  RAPID --> CFG
```

## リクエストフロー図

```mermaid
sequenceDiagram
  participant Sched as ジョブスケジューラ
  participant Facade as facade
  participant Impl as 実装スクリプト実行ホスト
  participant DB as 管理DB
  participant Art as 成果物ディレクトリ

  Sched->>Facade: 業務ジョブ起動(同期)
  Facade->>DB: 速報比較依頼レコード作成(run_id主キー)
  Facade->>Impl: SSH公開鍵認証でリモート実行
  Impl-->>Facade: stdout/stderr/exitcode
  Facade->>Art: 一時ファイル書き込み→rename確定
  Facade->>DB: 実行結果を記録(claim解放)
  Facade-->>Sched: 終了コードを返却
```

## オートスケーリング構成図

```mermaid
graph LR
  TRIGGER[queue_depth増加<br/>手動監視] -->|判断| ADD[workerホスト追加]
  ADD -->|同一systemd unit配置| WORKER2[rapid-worker #2]
  ADD -->|同一systemd unit配置| WORKER3[final-crosscheck-worker #2]
  NOTE1[自動スケールは無し<br/>product-decision-001参照]
```

## ベンダー別デプロイメント図

```mermaid
graph TD
  subgraph onprem[オンプレミス]
    OP_COMPUTE[Linux VM/物理サーバ<br/>systemd + cron]
    OP_DB[PostgreSQL 16<br/>セルフホスト]
    OP_STORAGE[ローカルディスク RAID1<br/>NFS v4 任意]
    OP_SCHED[組織既存ジョブスケジューラ<br/>定期ジョブと障害通知]
    OP_MON[組織既存監視エージェント<br/>+ cron バックアップ]
  end

  OP_COMPUTE --> OP_DB
  OP_COMPUTE --> OP_STORAGE
  OP_SCHED --> OP_COMPUTE
  OP_DB --> OP_MON
  OP_COMPUTE --> OP_MON
```

## 適合性サマリ

`product-conformance-onprem` (26要件中: conformant 22, partial 4, non_conformant 0) を参照。
partial評価の4件はいずれも意図した設計判断(手動水平スケール・grepベースログ検索・既存監視統合の前提・ジョブスケジューラ製品による警告終了の扱い)であり、
運用開始前確認事項として `docs/todo.md` に記録する。
