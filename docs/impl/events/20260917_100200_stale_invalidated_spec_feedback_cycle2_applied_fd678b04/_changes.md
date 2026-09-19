# 20260917_100200_stale_invalidated_spec_feedback_cycle2_applied_fd678b04

dist-pipeline の feedback 還流 2 サイクル目(spec event 20260917_100000)で spec.md / tier-facade.md / _api-summary.yaml / cli-command-contract.yaml が変わり(確報制御キーの拒否範囲 = `FINAL_` 接頭辞、境界 Scenario 追加)、input-manifest 再計算後の projection 照合で全 done が stale。S1〜S9 と attempt-2 の tier-facade S4/S5(assumptions / findings 含む)を invalidated/ へ退避し、同一 attempt で S1 から再実行する。
