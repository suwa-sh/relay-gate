# データ可視化設計仕様（RelayGate）

> 前提: RelayGate の指標データは実行結果・比較結果・検知記録が中心であり、いずれも運用者による状況把握・異常検知のための
> 可視化が主目的である。マーケティング/BI的なダッシュボードではなく、少人数運用者向けの状態確認ツールとして設計する。

## 可視化対象

| 画面 | 指標/データ | 用途 | チャート種別 |
|------|-----------|------|-----------|
| 並行稼働実行結果確認画面 | slot種別（blue/green）ごとのRunner実行結果件数（RUNNING/SUCCEEDED/FAILED/ABORTED） | Composition（構成比） | 積み上げ棒グラフ（slot × 状態） |
| 速報クロスチェック結果確認画面 | 速報比較依頼のOK/NG判定件数の時系列推移、差分件数 | Trend（傾向） | 折れ線グラフ（日次OK/NG件数） |
| 確報クロスチェック結果確認画面 | 確報比較依頼のSUCCEEDED/FAILED件数（日次） | Comparison（比較） | 棒グラフ（日次SUCCEEDED/FAILED件数） |
| background実行異常検知画面 | 異常検知種別（ハング疑い/background実行エラー/速報クロスチェック異常）ごとの検知件数 | Composition（構成比） | 円グラフまたは積み上げ棒グラフ |
| リラン対象選定画面 | 状態別（SUCCEEDED/FAILED/ABORTED）の対象件数 | Comparison（比較） | 棒グラフ（フィルターと連動） |

## チャート選定ガイドライン

（`references/specs/data-visualization-rules.md` を参照して適用した）

### 観点別チャート選定

| 観点 | 推奨チャート | 使用場面 |
|------|-----------|---------|
| Comparison（比較） | 棒グラフ | 確報クロスチェックの日次SUCCEEDED/FAILED件数比較、リラン対象の状態別件数比較 |
| Composition（構成比） | 積み上げ棒グラフ、円グラフ | slot（blue/green）× 実行状態の内訳、異常検知種別の内訳 |
| Relationship（関連性） | 該当なし | RDRAモデル上、指標間の相関を示す2変量データは検出されなかったため対象外 |
| Distribution（分布） | 該当なし | 情報.tsvに分布分析が必要な連続値属性（実行時間分布等）は明示されていないため対象外 |
| Trend（傾向） | 折れ線グラフ | 速報クロスチェックのOK/NG判定件数の日次推移、ハング検知件数の推移 |

## ダッシュボード設計原則

### 情報の階層化

- **全体サマリー**: 現在の運用モード（バリエーション: 運用モード）、直近の並行稼働実行状態（blue/green別）、直近の速報/確報クロスチェック判定結果（OK/NG, SUCCEEDED/FAILED）をトップに配置する
- **ドリルダウン**: サマリーのStatusBadgeクリック（将来ダッシュボード）または対応するCLIサブコマンド実行により、CrossCheckRequestRow一覧・RunnerResultPanel詳細へ遷移する
- **フィルター**: slot種別（blue/green）、状態（RUNNING/SUCCEEDED/FAILED/ABORTED、またはREQUESTED〜ABORTEDの速報/確報比較依頼状態）、対象日（確報クロスチェック）で絞り込む

### データストーリーテリング

- **ナラティブ**: 「blue/greenの並行稼働が正常に進行しているか」「段階的切替の判断材料が揃っているか」を一貫した文脈で提示する
- **比較軸**: blue実装 vs green実装（slot間比較）、速報 vs 確報（粒度・タイミングの異なる2種のクロスチェック結果比較）
- **アクション**: FAILED/NG検出時は速やかに障害調査担当者・リリース判断者へエスカレーションし、必要に応じて中止フロー（blue中止/green中止/速報比較中止/確報比較中止）またはリランフローへ誘導する

## 認知負荷への配慮

- ワーキングメモリの限界（4-5項目）を考慮し、サマリー表示は状態区分（RUNNING/SUCCEEDED/FAILED/ABORTED、OK/NG）を超えない範囲の項目数に絞る
- Data-Ink Ratio を意識し、RunnerResultPanel・ResultTableでは装飾的な罫線・背景色を排し、状態色（StatusBadge）とテキストのみで情報を伝える
- ゲシュタルトの法則に基づき、blue/green・速報/確報など対になる情報は近接配置し、CrossCheckRequestRowのvariant（rapid/final）で視覚的にグルーピングする
