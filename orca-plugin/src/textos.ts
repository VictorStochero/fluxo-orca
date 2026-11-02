// Todos os textos da interface (pt-BR) num só módulo: ponto único para traduzir depois.
const pct = (v: number | null) => (v === null ? '-' : `${v}%`)

export const t = {
  titulo: 'Fluxo Orca',
  atualizar: 'Atualizar',
  salvar: 'Salvar',
  gravando: 'Gravando…',
  salvo: 'Salvo.',
  nadaAlterado: 'Nada alterado.',
  carregando: 'Carregando o estado',
  semDados: 'Sem dados',
  coletorNaoRespondeu: 'O coletor não respondeu.',
  coletorFalhou: (codigo: string) => `Coletor falhou (${codigo})`,
  atualizadoEm: 'Atualizado',
  scriptsDesatualizados: 'Scripts desatualizados em ~/.cache',
  plugin: 'Plugin',
  orca: 'Orca',
  orcaRodando: 'rodando',
  orcaForaDoAr: 'fora do ar',

  fila: {
    titulo: 'Fila de testes',
    resumo: (modo: string, vagas: number, teto: number) => `modo ${modo} · ${vagas} vagas · teto ${teto}`,
    semTravas: 'Nenhuma trava.',
    trava: (fila: string, vaga: number, viva: boolean) => `${fila} · vaga ${vaga} · ${viva ? 'viva' : 'morta'}`,
    worktree: 'Worktree',
    comando: 'Comando',
    pid: 'PID',
    desde: 'Desde',
    configurar: 'Configurar a fila',
    configurarDescricao: 'vale só para testes iniciados depois',
    campos: {
      modo: 'Modo da fila',
      vagas: 'Vagas por recurso',
      vagas_projeto: 'Vagas por projeto',
      teto: 'Teto da máquina',
      processos: 'Processos (--parallel)'
    },
    origem: (origem: string, projetos: string) => `origem: ${origem}${projetos ? ` · sobrescrito pelo projeto (${projetos})` : ''}`,
    origens: { padrao: 'padrão', ambiente: 'variável de ambiente', 'fila.conf': 'fila.conf' }
  },

  pool: {
    titulo: 'Pool de agentes',
    resumo: (usadas: number, teto: number, ramMin: number, escolha: string) =>
      `máquina ${usadas}/${teto || '∞'} · ram_min ${ramMin} GB · escolha ${escolha}`,
    semContas: 'Nenhuma conta no registro.',
    janela5h: '5h',
    janelaSemanal: 'Semanal',
    conta: (alerta: boolean, nome: string, usadas: number, vagas: number, curta: number | null, longa: number | null) =>
      `${alerta ? '⚠ ' : ''}${nome} · ${usadas}/${vagas || '∞'} · 5h ${pct(curta)} · Semanal ${pct(longa)}`,
    agente: 'Agente',
    peso: 'Peso',
    papeis: 'Papéis',
    janelas: 'Janelas (5h / Semanal)',
    semMedida: 'sem medida',
    medidaHa: 'Medida há',
    minutos: (n: number) => `${n} min`,
    vagasEmUso: 'Vagas em uso',
    nenhuma: 'nenhuma',
    vagas: 'Vagas',
    configurar: 'Configurar o pool',
    teto: 'Teto da máquina (0 = sem teto)',
    ramMin: 'RAM mínima livre (GB)',
    escolha: 'Escolha do escritor'
  },

  workers: {
    titulo: 'Workers do Orca',
    nenhum: 'Nenhum worker ativo.',
    tabela: 'Workers em andamento',
    dispatch: 'Dispatch',
    agente: 'Agente / modelo',
    estado: 'Estado',
    worktree: 'Worktree',
    objetivo: 'Objetivo do run'
  }
}
