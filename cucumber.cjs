// cucumber-js 設定(ルートと tier dir の両方から使う。P6 bootstrap 生成)。
// 引数の feature パスで step 定義の読込先を切り替える:
//   features/uc   → features/uc/steps(UC BDD、リポルート cwd)
//   features/atdd → features/atdd/steps(ATDD、リポルート cwd)
//   それ以外       → features/steps(tier BDD、tier dir cwd。`--config ../cucumber.cjs features`)
// step 定義は JavaScript(CommonJS)のみ。TS / ts-node は使わない。
const argv = process.argv.slice(2);
let requireGlob = "features/steps/**/*.js";
if (argv.some((a) => a === "features/uc" || a.startsWith("features/uc/"))) {
  requireGlob = "features/uc/steps/**/*.js";
} else if (argv.some((a) => a === "features/atdd" || a.startsWith("features/atdd/"))) {
  requireGlob = "features/atdd/steps/**/*.js";
}
module.exports = {
  default: {
    require: [requireGlob],
    format: ["progress"],
    publish: false,
    strict: true,
  },
};
