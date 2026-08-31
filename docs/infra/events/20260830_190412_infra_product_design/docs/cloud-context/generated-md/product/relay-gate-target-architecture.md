# relay-gate 並行稼働実行基盤 ターゲットアーキテクチャ(オンプレミス)

- workload_model: `product-relay-gate-workload-model`
- mapping: `product-relay-gate-mapping-onprem`
- impl_spec: `product-impl-onprem`
- generated_at: 2026-08-30T20:17:49

## ワークロード全体構成図

```mermaid
graph TD
  subgraph 実行ホストセグメント
    FACADE[facade / slot runner CLI]
    RAPID[rapid-crosscheck-runner・worker<br/>systemd常駐]
    HANG[hang-detector<br/>systemd timer 5分ごと]
    OPS[ops CLI 中止/リラン]
  end

  subgraph DBセグメント
    DB[(管理DB<br/>PostgreSQL 単一インスタンス<br/>rapid/finalスキーマ)]
    FINAL[final-crosscheck-worker<br/>systemd常駐]
  end

  subgraph 共通
    ART[[成果物ディレクトリ<br/>RAID1 ローカルディスク]]
    LOG[[実行ログ領域<br/>logrotate 3ヶ月]]
    CFG[[設定ファイル配置<br/>/etc/relay-gate 読取専用]]
    MAIL[Postfix satellite]
  end

  SCHED[組織既存ジョブスケジューラ] -->|同期起動| FACADE
  FACADE --> ART
  FACADE --> DB
  RAPID --> DB
  RAPID --> ART
  HANG --> DB
  HANG -->|異常検知| MAIL
  OPS --> DB
  FINAL --> DB
  FACADE --> LOG
  RAPID --> LOG
  FINAL --> LOG
  FACADE --> CFG
  RAPID --> CFG
  MAIL -->|組織内SMTP中継| SMTP[組織内メール中継]
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
    OP_MAIL[Postfix satellite]
    OP_MON[組織既存監視エージェント<br/>+ cron バックアップ]
  end

  OP_COMPUTE --> OP_DB
  OP_COMPUTE --> OP_STORAGE
  OP_COMPUTE --> OP_MAIL
  OP_DB --> OP_MON
  OP_COMPUTE --> OP_MON
```

## 適合性サマリ

`product-conformance-onprem` (23要件中: conformant 18, partial 5, non_conformant 0) を参照。
partial評価の5件はいずれも意図した設計判断(手動水平スケール・grepベースログ検索・既存監視統合の前提)であり、
運用開始前確認事項として `docs/todo.md` に記録する。
