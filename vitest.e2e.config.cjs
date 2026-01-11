const { defineConfig } = require("vitest/config");

module.exports = defineConfig({
  test: {
    include: ["test/**/*.e2e.test.ts"],
    setupFiles: ["test/setup.ts"],
    exclude: [
      "dist/**",
      "apps/macos/**",
      "apps/macos/.build/**",
      "**/vendor/**",
      "dist/Clawdbot.app/**",
    ],
  },
});
