# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold 生成。uc_id=dcd8234d)
Feature: クロスチェックのジョブマップと比較定義を定義する - 確報クロスチェックティア

  Scenario: 妥当な対象カタログを検証する
    Given /etc/relay-gate/target-catalog.csv がヘッダー + `v1,table,SALES_DAILY,key=sales_id,column=business_date` + `v1,file,/data/out/summary_{business_date}.tsv,-,filename` の 2 行である
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 終了コード 0 で stdout に `rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` が出る

  Scenario: 版を追加しても既存版は検証を通る
    Given 上記に `v2,table,SALES_DAILY,key=sales_id,column=business_date` を追加する
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 終了コード 0 で stdout に `catalog_versions=v1,v2` が出る

  Scenario: target_type が不正
    Given 3 行目の target_type が `view` である
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 終了コード 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る

  Scenario: 同一版内で対象が重複
    Given 妥当な対象カタログの 3 行目を `v1,table,SALES_DAILY,key=sales_id,column=business_date` に置き換え、2 行目と 3 行目が `v1,table,SALES_DAILY` で始まる
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 終了コード 2 で stderr に `error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3` が出る(初出行 2 を含む)
