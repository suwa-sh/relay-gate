# infra 変換推論根拠

event_id: `20260830_190412_infra_product_design`
入力: `docs/arch/latest/arch-design.yaml`(event: `20260830_184457_initial_arch`)、
`docs/nfr/latest/nfr-grade.yaml`(event: `20260830_183726_initial_nfr`)

## Arch → product-input.yaml のマッピング

| product-input.yaml フィールド | 推論元 | 根拠 |
|---|---|---|
| `workload.target_clouds: [onprem]` | プロダクト前提(要求入力に明記) | オンプレミス限定・エアーギャップ環境。クラウドベンダー選択は問わない |
| `deployment_constraints` | arch-design.yaml technology_context.constraints、CTP-002/CTP-005/CTP-006 | エアーギャップ、SSHリモート実行、DBセグメント分離の制約をそのまま転記 |
| `workload_type: batch` | arch-design.yaml system_architecture(UC構成: facade同期起動 + worker常駐/定期実行) | UI画面・HTTP APIが無く、ジョブスケジューラから起動されるバッチ系構成であるため |
| `availability_target.sla: 99%` | nfr-grade.yaml A.2.1〜A.2.6(可用性グレード) | 単一インスタンス+部品冗長化(電源・ディスク)、手動フェイルオーバーの評価 |
| `recovery_target.rpo/rto` | nfr-grade.yaml A.2.5.1(ストレージ冗長化)、C.1.x(運用・保守性) | 日次フル+差分バックアップから RPO 4h、手順書ベース復旧から RTO 12h と推定 |
| `data_sensitivity.encryption: in_transit_only` | nfr-grade.yaml E.5.x(セキュリティ)、foundation.identity.no_secret_values_in_config | PIIを扱わない内部データのため保管時暗号化を必須としない一方、SSH経路は暗号化必須 |
| `observability_needs` | nfr-grade.yaml C.1.3.1(監視範囲)、C.1.1〜C.1.2(運用・保守性) | 監視範囲Lv3を既存監視エージェントで満たす方針、ログ保管3ヶ月(C.6.1.1相当) |
| `cost_posture: cost_optimized` | nfr-grade.yaml E.8.x(環境・エコロジー)、foundation.billing.capex_shared_hosts | 既存ホストへの相乗り前提、追加コスト最小化 |
| `traffic_pattern.type: scheduled` | arch-design.yaml BUC構成(業務ジョブ facade / 確報クロスチェック / ハング検知定期ジョブ) | ジョブスケジューラ起動のスケジュール実行が主体 |
| `consistency_needs.type: strong` | arch-design.yaml CTP-004(多重実行防止)、CTP-006(排他制御) | run_id一意性・claim/lease排他をトランザクションで保証する要求 |

## foundation-context.yaml の生成根拠

mcl-foundation-design 未実施のため、dist-infrastructure がプロジェクト前提(要求入力に明記のオンプレミス限定・
エアーギャップ・UI画面なし・CLIと定期ジョブのみ)から最小構成として生成した。identity/network/policy/logging/billing の
各ガードレールは arch-design.yaml の CTP-002(SSHリモート実行)、CTP-005(閉域ネットワーク)、CTP-006(排他制御)、
および nfr-grade.yaml E.5〜E.8 系のセキュリティ・環境グレードから抽出した。

## MCL product-design 実行(Phase2)での補完

Step4a では workload-model と mapping-onprem のみ生成済みだった。Phase2 継続実行(Step4b冒頭)で以下を追加生成した:

- `product-impl-onprem.yaml`: mapping-onprem の各 canonical_element に対し、systemd/PostgreSQL/ローカルディスク/
  Postfix/cronの具体configurationとvalidation_rulesを記述
- `product-observability.yaml`: workload-model.observability_needs(metrics/logs/sli/alerting)をSLI/SLO/ログ/
  トレーシング/ダッシュボード/アラートルールに具体化
- `product-cost-hints.yaml`: cost_posture: cost_optimizedを既存ホスト相乗り・オートスケール非導入等の6カテゴリの
  推奨事項に具体化
- decision-record 5件: mapping-onprem の alternatives 欄で複数選択肢が存在した箇所(実行基盤/DBエンジン/
  成果物ストレージ/メールMTA/バックアップ監視)を decision_refs と対応させて記録
- conformance report: workload-model の23requirement全件をimpl-onpremと突き合わせ、partial評価5件
  (手動水平スケール・grepベースログ検索・既存監視統合の前提)を明記
- IaC スケルトン: Terraform はホスト/セグメントの論理定義(provider未確定のためプレースホルダ)、
  Ansible は5ロール(runtime/postgresql/config/mail/backup)で実装仕様のconfigurationを反映

## 未確定事項(todo.md 登録対象)

- `REQ-OPS-002`(組織既存のホスト監視エージェントへの統合)は組織側の監視有無が未確定。confidence: low の
  仮採用として `docs/todo.md` に登録する(下記 Phase4 参照)。
