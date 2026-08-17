#!/usr/bin/env bats

@test "relaygate_concurrent_run_select_slot_実行ファイルが未提供の場合_未実装であること" {
  # Arrange
  local project_root
  project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  local command_path="$project_root/facade/bin/relaygate"

  # Act & Assert
  if [[ ! -x "$command_path" ]]; then
    echo "未実装: relaygate concurrent-run select-slot" >&2
    return 1
  fi
}
