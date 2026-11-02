// Estado de exemplo compartilhado pelos testes e pelos cenários do `orca plugin check`.
import type { Estado } from './protocol'

export const estadoExemplo: Estado = {
  gerado_em: '2026-11-02T10:00:00-03:00',
  aviso: null,
  saude: { plugin_versao: '2.13.0', scripts_desatualizados: [], orca: { rodando: true, versao: '1.4.246' } },
  fila: {
    modo: 'recurso',
    vagas: 2,
    teto: 3,
    travas: [
      { fila: '3308', vaga: 1, worktree: 'C:/Herd/wt-um', desde: '20:14:25', comando: 'runner tests/X.php', pid: 4242, viva: true },
      { fila: 'teto', vaga: 1, worktree: 'C:/Herd/wt-dois', desde: null, comando: null, pid: null, viva: false }
    ]
  },
  pool: {
    teto: 4,
    ram_min: 3,
    maquina: { usadas: 1, teto: 4 },
    contas: [
      { nome: 'pessoal', agente: 'claude', vagas: 2, usadas: 1, peso: 10, papeis: ['escritor', 'revisor'], cota: { texto: '', curta: 90, longa: 25, medida_ha_min: 3, alerta: true } },
      { nome: 'codex', agente: 'codex', vagas: 1, usadas: 0, peso: 1, papeis: [], cota: null }
    ]
  },
  ram: { disponivel_gb: 2.5, relatorio: 'wt-o:\n  PID 42: CPU 0 · 1.0 GB' },
  workers: [{ dispatch: 'ctx_a', estado: 'ready', agente: 'codex', modelo: 'm1', worktree: 'C:/x/wt-a', objetivo: 'Objetivo do run' }]
}
