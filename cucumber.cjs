// cucumber-js プロファイル定義。steps は CommonJS(.cjs)で実 bash プロセスを起動して検証する
// (実装言語は bash。Node はテストハーネスのビルド時依存であり、実行時のエアーギャップ制約に影響しない)
module.exports = {
  "tier-facade": {
    paths: ["facade/features/**/*.feature"],
    require: ["facade/features/steps/**/*.cjs"],
    format: ["progress"],
    strict: true,
  },
  "tier-worker": {
    paths: ["worker/features/**/*.feature"],
    require: ["worker/features/steps/**/*.cjs"],
    format: ["progress"],
    strict: true,
  },
  uc: {
    paths: ["features/uc/**/*.feature"],
    require: ["features/uc/steps/**/*.cjs"],
    format: ["progress"],
    strict: true,
  },
  atdd: {
    paths: ["features/atdd/**/*.feature"],
    require: ["features/atdd/steps/**/*.cjs"],
    format: ["progress"],
    strict: true,
  },
};
