// Contrato painel <-> worker, declarado uma vez: src/panel.tsx e src/worker.ts leem este arquivo.
export {}

export type Trava = {
  fila: string
  vaga: number
  worktree: string | null
  desde: string | null
  /** Início do teste em epoch (s ou ms); acrescentado pelo backend. Ausente = só o `desde` textual. */
  desde_ts?: number | null
  comando: string | null
  pid: number | null
  viva: boolean
}

/** Cota da conta: 5h = janela curta, Semanal = janela longa (percentuais de 0 a 100). */
export type Cota = {
  texto: string
  curta: number | null
  longa: number | null
  medida_ha_min: number
  alerta: boolean
  /** `orca` quando vem do `orca account list` (nativa); ausente na medida do cache. */
  fonte?: 'orca'
}

export type Ocupante = { dispatch: string | null; desde: string | null }

export type Conta = {
  nome: string
  agente: string | null
  vagas: number
  usadas: number
  peso: number
  papeis: string[]
  ocupantes: Ocupante[]
  cota: Cota | null
  /** `manual`: linha do agentes.conf; `orca`: detectada pelo Orca e ainda fora do pool. */
  origem: 'manual' | 'orca'
  rotulo: string | null
  config: string | null
  /** O Orca também enxerga esta conta (cota nativa). */
  detectada: boolean
  /** false = "Não utilizar": listada e medida, mas fora do trabalho e do teto. */
  ativo: boolean
}

export type ItemFila = 'modo' | 'vagas' | 'vagas_projeto' | 'teto' | 'processos'

/** Valor efetivo da máquina e de onde vem; `projetos` lista quem o sobrescreve no .orca/worktree.conf. */
export type ValorFila = {
  valor: string | number
  origem: 'padrao' | 'ambiente' | 'fila.conf'
  projetos: { projeto: string; valor: string | number }[]
}

/** Saída de `painel.sh --json` (só os campos que o painel usa). */
export type Estado = {
  gerado_em: string
  aviso: string | null
  saude: { plugin_versao: string | null; scripts_desatualizados: string[]; orca: { rodando: boolean; versao: string | null } }
  fila: { modo: string; vagas: number; teto: number; travas: Trava[]; config: Record<ItemFila, ValorFila> }
  pool: {
    teto: number
    ram_min: number
    escolha: string
    papeis_validos: string[]
    catalogo: string[]
    maquina: { usadas: number; teto: number }
    contas: Conta[]
  }
}

/** `acao`: o painel executa por `requisitos.instalar`; `comando`: texto para o usuário rodar. */
export type RequisitoItem = {
  id: string
  nome: string
  ok: boolean
  detalhe: string
  instalar?: { tipo: 'acao' | 'comando'; texto: string }
}

export type Requisitos = { ok: boolean; itens: RequisitoItem[] }

declare module 'orca' {
  interface PluginRequests {
    /** Orca, skills e scripts do fluxo; guardado por 60 s. Itens: orca, orchestration, skills-fluxo, scripts. */
    'requisitos.ler': { output: Requisitos }
    /** Só `orchestration` (`orca skills install --skill orchestration`); devolve `requisitos.ler` novo. Outro id: erro `instalacao_recusada`. */
    'requisitos.instalar': { input: { id: 'orchestration' }; output: Requisitos }
    /** Roda o coletor (`~/.cache/painel.sh --json`) e devolve o estado da máquina. */
    'estado.ler': { output: Estado }
    /**
     * Grava pelo `painel.sh --config chave=valor ...` (fila.conf e agentes.conf; tudo ou nada) e devolve o estado novo.
     * Recusa do validador: erro `config_recusada` com a mensagem em português.
     */
    'config.gravar': { input: { valores: Record<string, string> }; output: Estado }
  }
  interface PluginPanelEvents {
    /** Fila ou pool mudaram em disco; o painel pede o estado de novo. */
    'estado.mudou': { em: number }
  }
}
