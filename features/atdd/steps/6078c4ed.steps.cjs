const { defineStep } = require("@cucumber/cucumber");

// 6078c4ed に紐づく ATDD step は S7 で実装するまで明示的に失敗させる。
function notImplemented() {
  throw new Error("未実装: 6078c4ed ATDD step");
}

defineStep(/.*/, notImplemented);
