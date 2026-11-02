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
  coletorFalhou: {
    requests: {
      'estado.ler': () => {
        throw hostError('coletor_falhou', 'painel.sh saiu com 1')
      }
    }
  }
})
