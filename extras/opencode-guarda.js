// Trava de comando remoto, bulk replace e teste fora da fila para workers do opencode (plugin global).
// Delega ao guarda-externos.sh; https://opencode.ai/docs/plugins/ (tool.execute.before: lançar erro bloqueia a chamada).
import { spawnSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

export const FluxoGuarda = async () => ({
  "tool.execute.before": async (input, output) => {
    const r = spawnSync("bash", [join(homedir(), ".cache", "guarda-externos.sh"), "exit2"], {
      input: JSON.stringify({ tool: input.tool, tool_input: output.args }),
      encoding: "utf8",
    })
    if (r.status !== 0) throw new Error(r.stderr?.trim() || "fluxo-guarda indisponível: " + (r.error?.message ?? r.status))
  },
})
