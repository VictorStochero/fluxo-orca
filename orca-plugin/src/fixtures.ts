// Estado de exemplo compartilhado pelos testes e pelos cenários do `orca plugin check`.
import type { Estado } from './protocol'

export const estadoExemplo: Estado = {
  gerado_em: '2026-11-02T10:00:00-03:00',
  aviso: null,
  alertas: [],
  saude: { plugin_versao: '2.13.0', scripts_desatualizados: [], orca: { rodando: true, versao: '1.4.246' } },
  fila: {
    modo: 'global',
    vagas: 5,
    teto: 5,
    testes: [
      { pid: 4242, estado: 'execucao', recurso: 'mysql 127.0.0.1:3308', worktree: 'C:/Herd/wt-um', projeto: 'wt-um', comando: 'runner tests/X.php', vaga: 1, desde_ts: 1793650465000 },
      { pid: 4120, estado: 'aguardando', recurso: 'mysql 127.0.0.1:3308', worktree: 'C:/Herd/wt-tres', projeto: 'wt-tres', comando: 'php artisan test', vaga: null, desde_ts: 1793650500000 },
      { pid: 99, estado: 'parado', recurso: 'container exec-1', worktree: 'C:/Herd/wt-dois', projeto: 'wt-dois', comando: null, vaga: 1, desde_ts: 1793640000000 }
    ],
    config: {
      modo: { valor: 'global', origem: 'padrao', projetos: [] },
      vagas: { valor: 5, origem: 'ambiente', projetos: [{ projeto: 'meu-projeto', valor: 1 }] },
      vagas_projeto: { valor: 1, origem: 'padrao', projetos: [] },
      teto: { valor: 5, origem: 'fila.conf', projetos: [] },
      processos: { valor: 8, origem: 'padrao', projetos: [] }
    }
  },
  pool: {
    teto: 4,
    ram_min: 3,
    escolha: 'ritmo',
    catalogo: ['claude', 'codex', 'opencode'],
    papeis_validos: ['escritor', 'revisor', 'verificador', 'mecanico', 'segunda-opiniao', 'orquestra'],
    maquina: { usadas: 1, teto: 4 },
    contas: [
      {
        nome: 'pessoal',
        agente: 'claude',
        vagas: 2,
        usadas: 1,
        peso: 10,
        papeis: ['escritor', 'revisor'],
        ocupantes: [{ dispatch: 'ctx_a', desde: '2026-11-02T13:00:00Z' }],
        origem: 'manual',
        rotulo: null,
        config: null,
        detectada: false,
        ativo: true,
        cota: { texto: 'pessoal: sessão 90% usado | semana 25% usado, zera 6 nov 20:00', curta: 90, longa: 25, medida_ha_min: 45, alerta: true, estado: 'antiga' }
      },
      { nome: 'codex', agente: 'codex', vagas: 1, usadas: 0, peso: 1, papeis: [], ocupantes: [], cota: { texto: '5h 24% (zera 14:48) · semana 42% (zera qua., 10:01)', curta: 24, longa: 42, medida_ha_min: 1, alerta: false, fonte: 'orca', estado: 'ok' }, origem: 'manual', rotulo: 'eu@exemplo.com', config: null, detectada: true, ativo: true },
      { nome: 'claude-abcdef12', agente: 'claude', vagas: 1, usadas: 0, peso: 1, papeis: [], ocupantes: [], cota: null, origem: 'manual', rotulo: 'gerenciada@exemplo.com', config: null, detectada: true, ativo: false }
    ]
  }
}

/** Conta team sem login, conta com erro do Orca, Orca fora do ar e um teste parado. */
export const estadoComAlertas: Estado = {
  ...estadoExemplo,
  alertas: [
    { nivel: 'erro', texto: 'Conta team desconectada: reconecte para voltar a medir a cota', acao: 'CLAUDE_CONFIG_DIR=C:/Users/x/.claude-team claude auth login' },
    { nivel: 'erro', texto: 'Conta codex com problema na leitura da cota: token expirado' },
    { nivel: 'erro', texto: 'Orca indisponível: abra o Orca para o painel e os workers funcionarem' },
    { nivel: 'aviso', texto: '1 teste(s) parado(s) na fila ocupando vaga: wt-dois' }
  ],
  saude: { ...estadoExemplo.saude, orca: { rodando: false, versao: null } },
  pool: {
    ...estadoExemplo.pool,
    contas: [
      ...estadoExemplo.pool.contas.slice(0, 1),
      { ...estadoExemplo.pool.contas[1], cota: { texto: 'token expirado', curta: null, longa: null, medida_ha_min: null, alerta: false, estado: 'erro' } },
      {
        ...estadoExemplo.pool.contas[0],
        nome: 'team',
        ativo: true,
        cota: { texto: 'team: sem login (rode CLAUDE_CONFIG_DIR=C:/Users/x/.claude-team claude auth login)', curta: 84, longa: 30, medida_ha_min: 1400, alerta: true, estado: 'sem_login', acao: 'CLAUDE_CONFIG_DIR=C:/Users/x/.claude-team claude auth login' }
      }
    ]
  }
}
