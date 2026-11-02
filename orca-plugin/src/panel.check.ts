// `orca plugin check` desenha o painel uma vez por cenário.
import { defineCheck, hostError } from 'orca/testing'
import { estadoExemplo } from './fixtures'

export default defineCheck({
  carregado: { requests: { 'estado.ler': () => estadoExemplo } },
  vazio: {
    requests: {
      'estado.ler': () => ({
        ...estadoExemplo,
        aviso: 'Orca indisponível',
        fila: { ...estadoExemplo.fila, travas: [] },
        pool: { ...estadoExemplo.pool, contas: [] }
      })
    }
  },
  requisitosFaltando: {
    requests: {
      'requisitos.ler': () => ({
        ok: false,
        itens: [
          { id: 'cli', nome: 'CLI do Orca', ok: true, detalhe: 'orca 1.4.246' },
          { id: 'orchestration', nome: 'Orchestrator V3', ok: false, detalhe: 'Ative o Orchestrator nas configurações do Orca.', instalar: { tipo: 'acao', texto: 'Ativar' } },
          { id: 'python', nome: 'Python 3', ok: false, detalhe: 'python3 não está no PATH.', instalar: { tipo: 'comando', texto: 'winget install Python.Python.3.12' } }
        ]
      })
    }
  },
  coletorFalhou: {
    requests: {
      'estado.ler': () => {
        throw hostError('coletor_falhou', 'painel.sh saiu com 1')
      }
    }
  }
})
