import test from "node:test";
import assert from "node:assert/strict";

globalThis.chrome = {
  action: {
    onClicked: {
      addListener() {}
    },
    setBadgeText() {},
    setTitle() {}
  },
  runtime: {
    connectNative() {
      throw new Error("not implemented");
    },
    onMessage: {
      addListener() {}
    }
  },
  scripting: {
    executeScript() {
      throw new Error("not implemented");
    }
  }
};

const { describeNativeHostFailure } = await import("../src/background.js");

test("native host exit maps to browser service tooltip", () => {
  assert.equal(
    describeNativeHostFailure(new Error("Native host has exited.")),
    "TaskTrace browser service is not running."
  );
});

test("non-service native host failures keep their original message", () => {
  assert.equal(
    describeNativeHostFailure(new Error("Specified native messaging host not found.")),
    "Specified native messaging host not found."
  );
});
