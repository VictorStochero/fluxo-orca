import { afterEach, assert, hostError, mockHost, mount, test, type TestPanel } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import * as panel from './panel'

let view: TestPanel | undefined
afterEach(() => view?.unmount())

test('mostra fila, pool, RAM e workers do coletor', async () => {
  const host = mockHost({ requests: { 'estado.ler': () => estadoExemplo } })
  view = await mount(panel, { host })
  assert.ok(view.find({ type: 'Button', text: 'Atualizar' }))
  assert.deepEqual(view.rowsOf({ label: 'Travas da fila' }), ['3308.1', 'teto.1'])
  assert.deepEqual(view.rowsOf({ label: 'Contas do pool' }), ['pessoal', 'codex'])
  assert.deepEqual(view.rowsOf({ label: 'Workers em andamento' }), ['ctx_a'])
  assert.ok(view.find({ text: '2.5 GB disponíveis' }))
  assert.ok(view.find({ type: 'RelativeTime' }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
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
  assert.deepEqual(view.rowsOf({ label: 'Contas do pool' }), ['pessoal', 'codex'])
})

test('o post estado.mudou lê o estado de novo', async () => {
  let n = 0
  const host = mockHost({ requests: { 'estado.ler': () => ({ ...estadoExemplo, workers: n++ ? [] : estadoExemplo.workers }) } })
  view = await mount(panel, { host })
  assert.equal(n, 1)
  await view.post('estado.mudou', { em: 1 })
  assert.equal(n, 2)
  assert.ok(view.find({ text: 'Nenhum worker ativo.' }))
})
