// Estado de exemplo compartilhado pelos testes e pelos cenários do `orca plugin check`.
import type { Estado } from './protocol'

export const estadoExemplo: Estado = {
  gerado_em: '2026-11-02T10:00:00-03:00',
  aviso: null,
  saude: { plugin_versao: '2.13.0', scripts_desatualizados: [], orca: { rodando: true, versao: '1.4.246' } },
  fila: {
    modo: 'global',
    vagas: 5,
    teto: 5,
    travas: [
      { fila: '3308', vaga: 1, worktree: 'C:/Herd/wt-um', desde: '20:14:25', comando: 'runner tests/X.php', pid: 4242, viva: true },
      { fila: 'teto', vaga: 1, worktree: 'C:/Herd/wt-dois', desde: null, comando: null, pid: null, viva: false }
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
        cota: { texto: 'pessoal: sessão 90% usado | semana 25% usado, zera 6 nov 20:00', curta: 90, longa: 25, medida_ha_min: 45, alerta: true }
      },
      { nome: 'codex', agente: 'codex', vagas: 1, usadas: 0, peso: 1, papeis: [], ocupantes: [], cota: { texto: '5h 24% (zera 14:48) · semana 42% (zera qua., 10:01)', curta: 24, longa: 42, medida_ha_min: 1, alerta: false, fonte: 'orca' }, origem: 'manual', rotulo: 'eu@exemplo.com', config: null, detectada: true },
      { nome: 'claude-abcdef12', agente: 'claude', vagas: 0, usadas: 0, peso: 1, papeis: [], ocupantes: [], cota: null, origem: 'orca', rotulo: 'gerenciada@exemplo.com', config: null, detectada: true }
    ]
  }
}
