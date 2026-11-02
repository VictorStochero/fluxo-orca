// `orca plugin check` desenha o painel uma vez por cenário.
import { defineCheck, hostError } from 'orca/testing'
import { estadoExemplo } from './fixtures'

// A vigília (auto.assistir) é um long-poll que nunca responde: o check esperaria para sempre; ele só confere o desenho.
const semVigia = {
  'auto.assistir': () => {
    throw hostError('unavailable', 'sem vigília no check')
  }
}

export default defineCheck({
  carregado: { requests: { ...semVigia, 'estado.ler': () => estadoExemplo } },
  // Conta inativa ("não utilizada") na tabela do Pool.
  contaInativa: {
    requests: {
      ...semVigia,
      'estado.ler': () => ({
        ...estadoExemplo,
        pool: { ...estadoExemplo.pool, contas: estadoExemplo.pool.contas.map((c) => ({ ...c, ativo: false })) }
      })
    }
  },
  vazio: {
    requests: {
      ...semVigia,
      'estado.ler': () => ({
        ...estadoExemplo,
        aviso: 'Orca indisponível',
        fila: { ...estadoExemplo.fila, testes: [] },
        pool: { ...estadoExemplo.pool, contas: [] }
      })
    }
  },
  requisitosFaltando: {
    requests: {
      ...semVigia,
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
      ...semVigia,
      'estado.ler': () => {
        throw hostError('coletor_falhou', 'painel.sh saiu com 1')
      }
    }
  }
})
