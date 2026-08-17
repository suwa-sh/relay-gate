const { defineStep } = require("@cucumber/cucumber");

// 6078c4ed の UC BDD step は S6 で実装するまで明示的に失敗させる。
function notImplemented() {
  throw new Error("未実装: 6078c4ed UC BDD step");
}

defineStep(/.*/, notImplemented);
