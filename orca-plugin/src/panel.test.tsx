import { afterEach, assert, hostError, mockHost, mount, test, type TestPanel } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import type { Estado } from './protocol'
import * as panel from './panel'

let view: TestPanel | undefined
afterEach(() => view?.unmount())

test('linhas recolhidas: conta com 5h e Semanal, trava com viva, sem RAM', async () => {
  const host = mockHost({ requests: { 'estado.ler': () => estadoExemplo } })
  view = await mount(panel, { host })
  assert.ok(view.find({ type: 'Button', text: 'Atualizar' }))
  assert.ok(view.find({ label: '⚠ pessoal · 1/2 · 5h 90% · Semanal 25%' }))
  assert.ok(view.find({ label: 'codex · 0/1 · 5h - · Semanal -' }))
  assert.ok(view.find({ label: '3308 · vaga 1 · viva' }))
  assert.ok(view.find({ label: 'teto · vaga 1 · morta' }))
  assert.equal(view.find({ text: /Workers/ }), null)
  assert.equal(view.find({ type: 'Heading', text: /RAM/ }), null)
  assert.equal(view.find({ text: /\bcurta\b|\blonga\b/ }), null)
  assert.ok(view.find({ type: 'RelativeTime' }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
})

test('configuração da fila mostra a origem e quem sobrescreve', async () => {
  const host = mockHost({ requests: { 'estado.ler': () => estadoExemplo } })
  view = await mount(panel, { host })
  assert.ok(view.find({ text: /origem: variável de ambiente · sobrescrito pelo projeto \(meu-projeto: 1\)/ }))
  assert.ok(view.find({ text: /origem: fila\.conf/ }))
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
  assert.ok(view.find({ label: /pessoal · 1\/2/ }))
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

test('salvar a conta manda só o que mudou e mostra o estado novo', async () => {
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
  await view.toggle({ label: '⚠ pessoal · 1/2 · 5h 90% · Semanal 25%' })
  await view.type({ label: 'Vagas' }, '3', { replace: true })
  await view.press(view.findAll({ type: 'Button', text: 'Salvar' })[0]) // só a linha aberta expõe o botão
  assert.deepEqual(enviados, [{ 'conta.pessoal.vagas': '3' }])
  assert.ok(view.find({ text: 'Salvo.' }))
  assert.ok(view.find({ label: /pessoal · 1\/3/ }))
  assert.deepEqual(view.refusals, [])
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
  await view.type({ label: 'Vagas por recurso' }, '0', { replace: true })
  await view.press(view.findAll({ type: 'Button', text: 'Salvar' })[0])
  assert.ok(view.find({ text: 'valor inválido para fila.vagas: 0' }))
  assert.equal(view.valueOf({ label: 'Vagas por recurso' }), '0')
})
