import { afterEach, assert, hostError, mockHost, mount, test, type TestPanel } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import type { Estado } from './protocol'
import * as panel from './panel'

let view: TestPanel | undefined
afterEach(() => view?.unmount())

const POOL = { label: 'Contas do pool' }
const FILA = { label: 'Travas da fila' }

function hostCom(gravados: unknown[] = [], estado: Estado = estadoExemplo) {
  return mockHost({
    requests: {
      'estado.ler': () => estado,
      'config.gravar': ({ valores }) => {
        gravados.push(valores)
        return estado
      }
    }
  })
}

test('tabelas recolhidas: Fila · Vaga · Viva e Conta · Vagas · 5h · Semanal, sem RAM nem Workers', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.deepEqual(view.columnsOf(FILA), ['fila', 'vaga', 'viva'])
  assert.deepEqual(view.rowsOf(FILA), ['3308.1', 'teto.1'])
  assert.deepEqual(view.columnsOf(POOL), ['conta', 'vagas', 'h5', 'semanal'])
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
  assert.ok(view.find({ text: /modo Global · 5 vagas · teto 5/ }))
  assert.equal(view.find({ text: /Workers|curta|longa/ }), null)
  assert.equal(view.find({ type: 'Heading', text: /RAM/ }), null)
  assert.ok(view.find({ type: 'RelativeTime' }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
})

test('selecionar a linha abre os detalhes logo abaixo e selecionar de novo recolhe', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.selectRows(FILA, ['3308.1'])
  assert.deepEqual(view.rowsOf(FILA), ['3308.1', '3308.1#0', '3308.1#1', '3308.1#2', '3308.1#3', 'teto.1'])
  await view.selectRows(FILA, [])
  assert.deepEqual(view.rowsOf(FILA), ['3308.1', 'teto.1'])
})

test('pool: o detalhe da conta mostra Orca + agentes.conf, só agentes.conf e só Orca', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.selectRows(POOL, ['codex'])
  assert.ok(view.find({ text: /Orca \+ agentes\.conf/ }))
  await view.selectRows(POOL, ['pessoal'])
  assert.ok(view.find({ text: /agentes\.conf/ }))
  assert.equal(view.find({ text: /Orca \+ agentes\.conf/ }), null)
  await view.selectRows(POOL, ['claude-abcdef12'])
  assert.ok(view.find({ text: /Orca \(fora do pool\)/ }))
})

test('erro do coletor aparece com o código e some na próxima leitura boa', async () => {
  let falha = true
  const host = mockHost({
    requests: {
      'estado.ler': () => {
        if (falha) throw hostError('coletor_falhou', 'painel.sh saiu com 1')
        return estadoExemplo
      }
    }
  })
  view = await mount(panel, { host })
  assert.ok(view.find({ text: /coletor_falhou/ }))
  assert.ok(view.find({ text: /painel.sh saiu com 1/ }))
  falha = false
  await view.press({ text: 'Atualizar' })
  assert.equal(view.find({ text: /coletor_falhou/ }), null)
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
})

test('o post estado.mudou lê o estado de novo', async () => {
  let n = 0
  const host = mockHost({ requests: { 'estado.ler': () => ({ ...estadoExemplo, pool: { ...estadoExemplo.pool, contas: n++ ? [] : estadoExemplo.pool.contas } }) } })
  view = await mount(panel, { host })
  assert.equal(n, 1)
  await view.post('estado.mudou', { em: 1 })
  assert.equal(n, 2)
  assert.ok(view.find({ text: 'Nenhuma conta no registro.' }))
})

test('editar a conta aberta manda só o que mudou e mostra o estado novo', async () => {
  const enviados: unknown[] = []
  let atual: Estado = estadoExemplo
  const host = mockHost({
    requests: {
      'estado.ler': () => atual,
      'config.gravar': ({ valores }) => {
        enviados.push(valores)
        atual = { ...atual, pool: { ...atual.pool, contas: atual.pool.contas.map((c) => (c.nome === 'pessoal' ? { ...c, vagas: 3 } : c)) } }
        return atual
      }
    }
  })
  view = await mount(panel, { host })
  await view.selectRows(POOL, ['pessoal'])
  await view.type({ label: 'Vagas' }, '3', { replace: true })
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.deepEqual(enviados, [{ 'conta.pessoal.vagas': '3' }])
  assert.ok(view.find({ text: 'Salvo.' }))
  assert.deepEqual(view.refusals, [])
})

test('modo da fila: Global e Por projeto com dica em cada opção; grava o valor escolhido', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.toggle({ label: 'Configurar a fila' })
  assert.ok(view.find({ label: /^Uma fila por recurso, compartilhada/ }))
  assert.ok(view.find({ label: /^Cada projeto tem a própria fila/ }))
  assert.ok(view.find({ label: /^Máximo de testes ao mesmo tempo na máquina/ }))
  assert.ok(view.find({ label: /^Testes ao mesmo tempo em cada fila/ }))
  assert.ok(view.find({ label: /Só vale no modo Por projeto/ }))
  await view.select({ label: 'Modo da fila' }, 'projeto')
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.deepEqual(enviados, [{ 'fila.modo': 'projeto' }])
})

test('configuração da fila mostra a origem e quem sobrescreve', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.toggle({ label: 'Configurar a fila' })
  assert.ok(view.find({ text: /origem: variável de ambiente · sobrescrito pelo projeto \(meu-projeto: 1\)/ }))
  assert.ok(view.find({ text: /origem: fila\.conf/ }))
})

test('recusa do validador aparece em português e não limpa a edição', async () => {
  const host = mockHost({
    requests: {
      'estado.ler': () => estadoExemplo,
      'config.gravar': () => {
        throw hostError('config_recusada', 'valor inválido para fila.vagas: 0')
      }
    }
  })
  view = await mount(panel, { host })
  await view.toggle({ label: 'Configurar a fila' })
  await view.type({ label: 'Vagas' }, '0', { replace: true })
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.ok(view.find({ text: 'valor inválido para fila.vagas: 0' }))
  assert.equal(view.valueOf({ label: 'Vagas' }), '0')
})

test('Adicionar ao pool grava conta.<nome>.adicionar=<agente> da conta detectada', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.selectRows(POOL, ['claude-abcdef12'])
  await view.press({ type: 'Button', text: 'Adicionar ao pool' })
  assert.deepEqual(enviados, [{ 'conta.claude-abcdef12.adicionar': 'claude' }])
})

test('Remover do pool pede confirmação e só então grava conta.<nome>.remover=1', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.selectRows(POOL, ['codex'])
  await view.press({ type: 'Button', text: 'Remover do pool' })
  assert.deepEqual(enviados, [])
  assert.ok(view.find({ text: /Remover codex do agentes\.conf\?/ }))
  await view.press({ type: 'Button', text: 'Cancelar' })
  assert.deepEqual(enviados, [])
  await view.press({ type: 'Button', text: 'Remover do pool' })
  await view.press({ type: 'Button', text: 'Confirmar remoção' })
  assert.deepEqual(enviados, [{ 'conta.codex.remover': '1' }])
})

test('Nova conta manual: nome, agente do catálogo e config viram um único pedido', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.toggle({ label: 'Nova conta manual' })
  assert.equal(view.find({ type: 'Button', text: 'Adicionar conta' })?.disabled, true)
  await view.type({ label: 'Nome da conta' }, 'minha')
  await view.select({ label: 'Agente do catálogo' }, 'codex')
  await view.type({ label: 'Diretório de config (CLAUDE_CONFIG_DIR etc.)' }, '~/.codex-minha')
  await view.press({ type: 'Button', text: 'Adicionar conta' })
  assert.deepEqual(enviados, [{ 'conta.minha.adicionar': 'codex', 'conta.minha.config': '~/.codex-minha' }])
  assert.equal(view.valueOf({ label: 'Nome da conta' }), '')
})
