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
  requisitos: {
    titulo: 'Requisitos',
    explica: 'O painel só funciona com todos os requisitos abaixo instalados.',
    tabela: 'Requisitos do painel',
    colRequisito: 'Requisito',
    colSituacao: 'Situação',
    ok: '✓ ok',
    falta: '✗ falta',
    instalar: 'Instalar',
    instalando: 'Instalando…',
    copiavel: 'Rode no terminal:'
  },
  dicaLinha: 'Clique numa linha para ver os detalhes.',
  configuracoes: {
    titulo: 'Configurações',
    descricao: 'Fila, pool, contas e painel',
    assuntos: 'Assuntos das configurações',
    abas: { fila: 'Fila', pool: 'Pool', contas: 'Contas', painel: 'Painel' },
    linhas: {
      fila: 'Como os testes esperam a vez — ~/.claude/fila.conf',
      pool: 'Limites da máquina e como o escritor é escolhido — ~/.claude/agentes.conf',
      contas: 'Vagas, peso, papéis e ordem de cada conta — ~/.claude/agentes.conf',
      painel: 'Este painel — guardado no Orca'
    }
  },
  painel: {
    intervalo: 'Atualizar a cada (segundos)',
    dica: 'Coleta local feita pelo próprio painel, sem IA e sem gastar tokens; valores baixos só aumentam o uso de CPU.',
    invalido: (min: number, max: number) => `Informe um número inteiro de ${min} a ${max}.`
  },

  fila: {
    titulo: 'Fila de testes',
    modos: { global: 'Global', projeto: 'Por projeto' } as Record<string, string>,
    resumo: (modo: string, vagas: number, teto: number) => `modo ${modo} · ${vagas} vagas · teto ${teto}`,
    semTravas: 'Nenhuma trava.',
    tabela: 'Travas da fila',
    colFila: 'Fila',
    colVaga: 'Vaga',
    colViva: 'Viva',
    sim: 'sim',
    nao: 'não',
    worktree: 'Worktree',
    comando: 'Comando',
    pid: 'PID',
    desde: 'Desde',
    configurar: 'Configurar a fila',
    configurarDescricao: 'vale só para testes iniciados depois',
    campos: {
      modo: 'Modo da fila',
      vagas: 'Vagas',
      vagas_projeto: 'Vagas por projeto',
      teto: 'Teto da máquina',
      processos: 'Processos (--parallel)'
    },
    dicas: {
      global:
        'Uma fila por recurso, compartilhada por todos os projetos da máquina: testes Laravel que usam o mesmo banco (mesma porta) esperam uns pelos outros; container e Python/JS têm filas próprias. Use quando os projetos dividem o banco de testes.',
      projeto:
        'Cada projeto tem a própria fila (vagas por projeto), independente dos outros; só o teto da máquina limita o total. Use quando cada projeto tem banco de testes próprio.',
      vagas: 'Testes ao mesmo tempo em cada fila.',
      vagas_projeto: 'Testes ao mesmo tempo em cada projeto. Só vale no modo Por projeto.',
      teto: 'Máximo de testes ao mesmo tempo na máquina, somando todas as filas.'
    },
    sobrescrito: (projetos: string) => `sobrescrito pelo projeto (${projetos})`
  },

  pool: {
    titulo: 'Pool de agentes',
    resumo: (usadas: number, teto: number, ramMin: number, escolha: string) =>
      `máquina ${usadas}/${teto || '∞'} · ram_min ${ramMin} GB · escolha ${escolha}`,
    semContas: 'Nenhuma conta no registro.',
    tabela: 'Contas do pool',
    colConta: 'Conta',
    colVagas: 'Vagas',
    col5h: '5h',
    colSemanal: 'Semanal',
    percentual: (v: number | null, alerta: boolean) => `${alerta ? '⚠ ' : ''}${pct(v)}`,
    vagasDaConta: (usadas: number, vagas: number) => `${usadas}/${vagas || '∞'}`,
    foraDoPool: 'fora',
    agente: 'Agente',
    peso: 'Peso',
    pesoDaConta: 'Peso da conta',
    papeis: 'Papéis',
    janelas: 'Zera',
    semMedida: 'sem medida',
    aviso: 'Aviso',
    medidaHa: 'Medida há',
    medidaAntiga: (min: number) => `Medida antiga: há ${min} min. A cota desta conta vem do medidor local; rode o medidor de novo (limites.sh) antes de confiar nela.`,
    minutos: (n: number) => `${n} min`,
    vagasEmUso: 'Vagas em uso',
    nenhuma: 'nenhuma',
    vagas: 'Vagas da conta',
    configurar: 'Configurar o pool',
    teto: 'Teto da máquina (0 = sem teto)',
    ramMin: 'RAM mínima livre (GB)',
    escolha: 'Escolha do escritor',
    rotulo: 'Conta no Orca',
    editar: (nome: string) => `Editar ${nome}`,
    adicionar: 'Adicionar ao pool',
    remover: 'Remover do pool',
    confirmarRemocao: (nome: string) => `Remover ${nome} do agentes.conf?`,
    confirmar: 'Confirmar remoção',
    cancelar: 'Cancelar',
    config: 'Diretório de config (CLAUDE_CONFIG_DIR etc.)',
    comando: 'Comando do lançador',
    novaConfig: 'Diretório de config da nova conta',
    dicas: {
      vagas: 'Quantos agentes desta conta podem trabalhar ao mesmo tempo. 0 = sem limite próprio (o teto da máquina continua valendo).',
      peso: 'Prioridade na escolha do escritor: multiplica o ritmo da cota. Peso 10 é escolhido bem antes de peso 1 com a mesma folga. Ignorado quando a escolha é Ordem.',
      config: 'Pasta de configuração do agente (por exemplo CLAUDE_CONFIG_DIR) que separa esta conta das outras do mesmo agente. Vazio = a conta padrão do sistema.',
      comando: 'Comando que o lançador usa para abrir este agente, quando for diferente do comando padrão do catálogo.',
      agente: 'Agente do catálogo (agentes-catalogo.conf) a que esta conta pertence: define comando, argumentos e medidor.',
      teto: 'Máximo de agentes trabalhando ao mesmo tempo na máquina, somando todas as contas. 0 = sem limite.',
      ramMin: 'Memória livre mínima (GB) para reservar uma vaga nova. 0 = desligado.',
      escolha: 'Ritmo: escolhe o escritor pela cota que mais sobra × peso. Ordem: vale a ordem da tabela do Pool, de cima para baixo.'
    },
    dicasPapel: {
      escritor: 'Implementa a tarefa: código, testes e commit no worktree.',
      revisor: 'Gate de merge só leitura: revisa comportamento e arquitetura; também faz a auditoria antes de subir.',
      verificador: 'Contraprova só leitura: tenta refutar os achados da auditoria ou um diagnóstico.',
      mecanico: 'Tarefas mecânicas e conferíveis (fixtures, edição literal, mover por mapa) com modelo menor.',
      'segunda-opiniao': 'Revisão adversarial de outra família de modelo, só leitura, em entregas de alto risco.',
      orquestra: 'Coordena os workers; conta só com este papel nunca é escolhida para trabalho.'
    } as Record<string, string>,
    contasTitulo: 'Contas',
    escolherConta: 'Conta a configurar',
    ordemNaTabela: 'Posição na tabela (vale com a escolha Ordem)',
    foraDoPoolExplica: 'Conta detectada pelo Orca que ainda não está no agentes.conf: adicione para ela entrar no pool.',
    subir: 'Subir',
    descer: 'Descer',
    nova: 'Nova conta manual',
    novaNome: 'Nome da conta',
    novaAgente: 'Agente do catálogo',
    novaAgentePlaceholder: 'Escolha o agente',
    novaCriar: 'Adicionar conta'
  }
}
