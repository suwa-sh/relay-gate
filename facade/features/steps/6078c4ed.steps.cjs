const { defineStep } = require("@cucumber/cucumber");

// 6078c4ed の tier-facade BDD step は S4 で実装するまで明示的に失敗させる。
function notImplemented() {
  throw new Error("未実装: 6078c4ed tier-facade BDD step");
}

defineStep(/.*/, notImplemented);
