import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  test: {
    environment: "jsdom",
    globals: true,
    exclude: ["e2e/**", "tests/backend/**/*.integration.test.ts", "node_modules/**", ".next/**"],
    setupFiles: ["./src/test/setup.ts"],
    coverage: { reporter: ["text", "html"] }
  }
});
