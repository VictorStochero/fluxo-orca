import { afterEach, assert, hostError, mockHost, mount, test, type TestPanel } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import type { Estado } from './protocol'
import * as panel from './panel'

let view: TestPanel | undefined
afterEach(() => view?.unmount())

const linha = (v: TestPanel, texto: RegExp) => {
  const el = v.find({ type: 'ListItem', text: texto })
  assert.ok(el, `linha ${texto}`)
  return el
}

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

test('listas recolhidas: Fila · Vaga · Viva e Conta · Vagas · 5h · Semanal, sem RAM, Workers nem origem', async () => {
  view = await mount(panel, { host: hostCom() })
  for (const c of ['FILA', 'VAGA', 'VIVA', 'CONTA', 'VAGAS', '5H', 'SEMANAL']) assert.ok(view.find({ text: c }), c)
  assert.equal(view.findAll({ type: 'ListItem' }).length, 5) // 2 travas + 3 contas
  assert.ok(linha(view, /pessoal.*1\/2.*⚠ 90%.*25%/))
  assert.ok(linha(view, /claude-abcdef12.*fora/))
  assert.ok(view.find({ text: /modo Global · 5 vagas · teto 5/ }))
  assert.equal(view.find({ text: /Workers|curta|longa|origem|Origem|agentes\.conf \(/ }), null)
  assert.equal(view.find({ type: 'Heading', text: /RAM/ }), null)
  assert.ok(view.find({ type: 'RelativeTime' }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
})

test('fila: clicar abre os detalhes da trava, várias ficam abertas e o segundo clique recolhe', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.equal(view.find({ text: /runner tests\/X\.php/ }), null)
  await view.press(linha(view, /^3308/))
  assert.ok(view.find({ text: /runner tests\/X\.php/ }))
  await view.press(linha(view, /^teto/))
  assert.ok(view.find({ text: /wt-dois/ }) && view.find({ text: /wt-um/ })) // duas abertas ao mesmo tempo
  await view.press(linha(view, /^3308/))
  assert.equal(view.find({ text: /runner tests\/X\.php/ }), null) // só a primeira recolheu
  assert.ok(view.find({ text: /wt-dois/ }))
})

test('pool: o formulário da conta fica dentro da linha expandida e recolhe no segundo clique', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.equal(view.find({ label: 'Peso' }), null)
  await view.press(linha(view, /^pessoal/))
  assert.ok(view.find({ label: 'Vagas' }) && view.find({ label: 'Peso' }) && view.find({ type: 'Button', text: 'Remover do pool' }))
  assert.ok(view.find({ label: 'escritor' }) && view.find({ type: 'Button', text: 'Salvar' }))
  await view.press(linha(view, /^pessoal/))
  assert.equal(view.find({ label: 'Peso' }), null)
})

test('pool: duas contas abertas ao mesmo tempo, recolher uma mantém a outra', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.press(linha(view, /^pessoal/))
  await view.press(linha(view, /^codex/))
  assert.equal(view.findAll({ type: 'Button', text: 'Remover do pool' }).length, 2)
  await view.press(linha(view, /^pessoal/))
  assert.equal(view.findAll({ type: 'Button', text: 'Remover do pool' }).length, 1)
})

test('cada campo e cada papel da conta tem o ícone de dica com o texto no label', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.press(linha(view, /^pessoal/))
  for (const trecho of [/^Quantos agentes desta conta/, /^Prioridade na escolha do escritor/, /^Pasta de configuração do agente/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
  for (const trecho of [/^Implementa a tarefa/, /^Gate de merge só leitura/, /^Contraprova só leitura/, /^Tarefas mecânicas/, /^Revisão adversarial/, /^Coordena os workers/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
})

test('Configurações: Pool e Nova conta manual também têm dicas', async () => {
  view = await mount(panel, { host: hostCom() })
  for (const trecho of [/^Máximo de agentes trabalhando/, /^Memória livre mínima/, /^Ritmo: escolhe o escritor.*de cima para baixo/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
  await view.toggle({ label: 'Nova conta manual' })
  for (const trecho of [/^Agente do catálogo \(agentes-catalogo/, /^Pasta de configuração do agente/, /^Comando que o lançador/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
})

test('conta detectada fora do pool: o expandido traz Adicionar ao pool', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.press(linha(view, /^claude-abcdef12/))
  assert.equal(view.find({ label: 'Peso' }), null) // sem formulário até entrar no pool
  await view.press({ type: 'Button', text: 'Adicionar ao pool' })
  assert.deepEqual(enviados, [{ 'conta.claude-abcdef12.adicionar': 'claude' }])
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
  await view.press(linha(view, /^pessoal/))
  await view.type({ label: 'Vagas' }, '3', { replace: true })
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.deepEqual(enviados, [{ 'conta.pessoal.vagas': '3' }])
  assert.ok(view.find({ text: 'Salvo.' }))
  assert.ok(linha(view, /^pessoal.*1\/3/))
  assert.deepEqual(view.refusals, [])
})

test('Remover do pool pede confirmação e só então grava conta.<nome>.remover=1', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await view.press(linha(view, /^codex/))
  await view.press({ type: 'Button', text: 'Remover do pool' })
  assert.deepEqual(enviados, [])
  assert.ok(view.find({ text: /Remover codex do agentes\.conf\?/ }))
  await view.press({ type: 'Button', text: 'Cancelar' })
  assert.deepEqual(enviados, [])
  await view.press({ type: 'Button', text: 'Remover do pool' })
  await view.press({ type: 'Button', text: 'Confirmar remoção' })
  assert.deepEqual(enviados, [{ 'conta.codex.remover': '1' }])
})

test('modo da fila: cada opção é um rádio com o ícone de dica ao lado, sem linhas repetidas', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  const grupos = view.findAll({ role: 'radiogroup' })
  assert.deepEqual(grupos.map((g) => g.label), ['Modo da fila: Global', 'Modo da fila: Por projeto'])
  assert.equal(view.findAll({ type: 'IconButton', label: /^Uma fila por recurso|^Cada projeto tem a própria fila/ }).length, 2)
  assert.ok(view.find({ type: 'IconButton', label: /^Máximo de testes ao mesmo tempo na máquina/ }))
  assert.ok(view.find({ type: 'IconButton', label: /Só vale no modo Por projeto/ }))
  await view.select({ label: 'Modo da fila: Por projeto' }, 'projeto')
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.deepEqual(enviados, [{ 'fila.modo': 'projeto' }])
})

test('a fila mostra só o valor em uso e avisa quando um projeto o sobrescreve', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.ok(view.find({ text: /sobrescrito pelo projeto \(meu-projeto: 1\)/ }))
  assert.equal(view.find({ text: /origem|variável de ambiente|fila\.conf/ }), null)
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
  await view.type({ label: 'Vagas' }, '0', { replace: true })
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.ok(view.find({ text: 'valor inválido para fila.vagas: 0' }))
  assert.equal(view.valueOf({ label: 'Vagas' }), '0')
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
  assert.ok(linha(view, /^pessoal/))
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

test('Configurações fica no fim, com Fila, Pool e Painel, e Nova conta manual dentro do Pool', async () => {
  view = await mount(panel, { host: hostCom() })
  const titulos = view.findAll({ type: 'Heading' }).map((h) => h.text)
  assert.deepEqual(titulos.slice(-3), ['Fila', 'Pool', 'Painel'])
  assert.ok(view.find({ type: 'Card', label: 'Configurações' }) ?? view.find({ text: /^Configurações/ }))
  assert.equal(view.find({ text: /Configurar a fila|Configurar o pool/ }), null)
})

test('setas ↑/↓: gravam pool.ordem com a lista completa na ordem nova; primeira e última ficam desabilitadas; detectada fora do pool não tem setas', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  const sobem = view.findAll({ type: 'IconButton', label: 'Subir' })
  const descem = view.findAll({ type: 'IconButton', label: 'Descer' })
  assert.equal(sobem.length, 2) // pessoal e codex; claude-abcdef12 está fora do pool
  assert.deepEqual(sobem.map((b) => b.disabled), [true, false])
  assert.deepEqual(descem.map((b) => b.disabled), [false, true])
  await view.press(sobem[1])
  assert.deepEqual(enviados, [{ 'pool.ordem': 'codex,pessoal' }])
  assert.equal(view.find({ text: /Nada alterado/ }), null)
  await view.press(descem[0])
  assert.deepEqual(enviados.at(-1), { 'pool.ordem': 'codex,pessoal' })
})

test('clicar nas setas não expande a linha', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.press(view.findAll({ type: 'IconButton', label: 'Subir' })[1])
  assert.equal(view.find({ type: 'Button', text: 'Remover do pool' }), null)
})

test('medida antiga: a conta manual com medida de mais de 30 min ganha aviso; a cota nativa do Orca não', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.press(linha(view, /^pessoal/))
  assert.ok(view.find({ text: /Medida antiga: há 45 min/ }))
  await view.press(linha(view, /^pessoal/))
  await view.press(linha(view, /^codex/))
  assert.equal(view.find({ text: /Medida antiga/ }), null)
})

test('Configurações > Painel: intervalo de atualização (15 a 3600 s) grava no storage do painel', async () => {
  const host = mockHost({ capabilities: ['storage:own'], storage: { 'atualizacao.intervalo_s': 90 }, requests: { 'estado.ler': () => estadoExemplo } })
  view = await mount(panel, { host })
  assert.equal(view.valueOf({ label: 'Atualizar a cada (segundos)' }), '90')
  assert.ok(view.find({ type: 'IconButton', label: /^Coleta local feita pelo próprio painel, sem IA e sem gastar tokens/ }))
  for (const ruim of ['5', '3601', 'abc', '']) {
    await view.type({ label: 'Atualizar a cada (segundos)' }, ruim, { replace: true })
    await view.press(view.findAll({ type: 'Button', text: 'Salvar' }).at(-1)!)
    assert.ok(view.find({ text: 'Informe um número inteiro de 15 a 3600.' }), ruim)
  }
  assert.equal(host.data().storage['atualizacao.intervalo_s'], 90)
  await view.type({ label: 'Atualizar a cada (segundos)' }, '120', { replace: true })
  await view.press(view.findAll({ type: 'Button', text: 'Salvar' }).at(-1)!)
  assert.equal(host.data().storage['atualizacao.intervalo_s'], 120)
  assert.ok(view.find({ text: 'Salvo.' }))
  assert.deepEqual(view.refusals, [])
})
