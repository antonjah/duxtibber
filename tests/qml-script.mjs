import { readFileSync } from "node:fs";
import vm from "node:vm";

// Loads a `.pragma library` QML script into a plain vm context (same approach as dux-shell's own tests).
export function loadScript(url) {
    const context = vm.createContext({ console: { info() {}, warn() {} } });
    vm.runInContext(readFileSync(url, "utf8").replace(/^\.pragma.*$/gm, ""), context);
    return context;
}
