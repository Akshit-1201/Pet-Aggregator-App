import {defineConfig} from "vitest/config";

// Emulator-only suite (npm run test:emulator). Kept out of the default
// `vitest run`, which must pass with no emulator running.
export default defineConfig({
  test: {include: ["emulator/**/*.emu.ts"], testTimeout: 30000, fileParallelism: false},
});
