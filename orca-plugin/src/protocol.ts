// Contrato painel <-> worker, declarado uma vez: src/panel.tsx e src/worker.ts leem este arquivo.
export {}

export type Trava = {
  fila: string
  vaga: number
  worktree: string | null
  desde: string | null
  comando: string | null
  pid: number | null
  viva: boolean
}

export type Cota = {
  texto: string
  curta: number | null
  longa: number | null
  medida_ha_min: number
  alerta: boolean
}

export type Conta = {
  nome: string
  agente: string | null
  vagas: number
  usadas: number
  peso: number
  papeis: string[]
  cota: Cota | null
}

export type WorkerOrca = {
  dispatch: string | null
  estado: string | null
  agente: string | null
  modelo: string | null
  worktree: string | null
  objetivo: string | null
}

/** Saída de `painel.sh --json` (só os campos que o painel usa). */
export type Estado = {
  gerado_em: string
  aviso: string | null
  saude: { plugin_versao: string | null; scripts_desatualizados: string[]; orca: { rodando: boolean; versao: string | null } }
  fila: { modo: string; vagas: number; teto: number; travas: Trava[] }
  pool: { teto: number; ram_min: number; maquina: { usadas: number; teto: number }; contas: Conta[] }
  ram: { disponivel_gb: number | null; relatorio: string }
  workers: WorkerOrca[]
}

declare module 'orca' {
  interface PluginRequests {
    /** Roda o coletor (`~/.cache/painel.sh --json`) e devolve o estado da máquina. */
    'estado.ler': { output: Estado }
  }
  interface PluginPanelEvents {
    /** Fila ou pool mudaram em disco; o painel pede o estado de novo. */
    'estado.mudou': { em: number }
  }
}
