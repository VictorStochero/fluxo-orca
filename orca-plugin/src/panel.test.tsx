import { afterEach, assert, hostError, mockHost, mount, test, type TestPanel } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import type { Estado, Requisitos } from './protocol'
import * as panel from './panel'

let view: TestPanel | undefined
afterEach(() => view?.unmount())

const POOL = { label: 'Contas do pool' }

/** Configurações começa recolhida e é dividida em abas: abre e escolhe o assunto. */
async function abrir(v: TestPanel, aba?: string) {
  await v.toggle({ label: 'Configurações' })
  if (aba) await v.select({ label: 'Assuntos das configurações' }, aba)
}
const FILA = { label: 'Testes na fila' }

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

test('tabelas nativas: Testes na fila (Projeto · Fila · Estado · Há) e Contas do pool (Conta · Vagas · 5h · Semanal), sem RAM, Workers nem origem', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.deepEqual(view.columnsOf(FILA), ['projeto', 'fila', 'estado', 'ha'])
  assert.deepEqual(view.rowsOf(FILA), ['p4242', 'p4120', 'p99']) // uma linha por teste, na ordem do backend; sem linha de teto
  assert.deepEqual(view.columnsOf(POOL), ['conta', 'vagas', 'h5', 'semanal'])
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
  assert.ok(view.find({ text: /1 em execução · 1 aguardando · teto 5 · Modo Global/ }))
  const fila = { type: 'Table', label: 'Testes na fila' }
  for (const trecho of [/wt-um/, /wt-tres/, /Global/, /Em execução/, /Aguardando vaga/, /⚠ Parado/]) assert.ok(view.find({ ...fila, text: trecho }), String(trecho))
  assert.equal(view.find({ text: /Viva|Vaga|Fila teto|Rodando agora/ }), null)
  assert.ok(view.find({ type: 'IconButton', label: /^Os testes esperam a vez numa fila/ }))
  assert.equal(view.find({ text: /Workers|curta|longa|origem|Origem/ }), null)
  assert.equal(view.find({ type: 'Heading', text: /RAM/ }), null)
  assert.ok(view.find({ type: 'RelativeTime' }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
})

test('sem os componentes de layout que quebraram o desenho: Grid, Callout, Skeleton e Toolbar', async () => {
  view = await mount(panel, { host: hostCom() })
  for (const tipo of ['Grid', 'Callout', 'Skeleton', 'Toolbar']) assert.equal(view.findAll({ type: tipo }).length, 0, tipo)
})

test('fila: clicar abre os detalhes na própria tabela (onde roda, comando, pid, worktree), várias ficam abertas e o segundo clique recolhe', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.selectRows(FILA, ['p4242'])
  assert.deepEqual(view.rowsOf(FILA), ['p4242', 'p4242#0', 'p4242#1', 'p4242#2', 'p4242#3', 'p4120', 'p99'])
  assert.ok(view.find({ type: 'Table', label: 'Testes na fila', text: /Onde roda.*mysql 127\.0\.0\.1:3308/ }))
  assert.ok(view.find({ type: 'Table', label: 'Testes na fila', text: /runner tests\/X\.php/ }))
  await view.selectRows(FILA, ['p4242', 'p99'])
  assert.equal(view.rowsOf(FILA).length, 3 + 4 + 5) // o parado traz a linha extra de Situação
  assert.ok(view.find({ type: 'Table', text: /O processo terminou e deixou a vaga presa/ }))
  await view.selectRows(FILA, ['p99'])
  assert.deepEqual(view.rowsOf(FILA), ['p4242', 'p4120', 'p99', 'p99#0', 'p99#1', 'p99#2', 'p99#3', 'p99#4'])
  await view.selectRows(FILA, [])
  assert.deepEqual(view.rowsOf(FILA), ['p4242', 'p4120', 'p99'])
})

test('fila: a coluna Fila segue o modo (Global · Banco · Container · Geral · Projeto <nome>) e sem testes diz "Nenhum teste na fila"', async () => {
  const com = (modo: Estado['fila']['modo'], recursos: string[]): Estado => ({
    ...estadoExemplo,
    fila: { ...estadoExemplo.fila, modo, testes: recursos.map((recurso, i) => ({ ...estadoExemplo.fila.testes[0], pid: 10 + i, recurso })) }
  })
  const tabela = { type: 'Table', label: 'Testes na fila' }
  view = await mount(panel, { host: hostCom([], com('banco', ['mysql 127.0.0.1:3307', 'container exec-1', 'geral'])) })
  for (const trecho of [/Banco 127\.0\.0\.1:3307/, /Container/, /Geral/]) assert.ok(view.find({ ...tabela, text: trecho }), String(trecho))
  assert.ok(view.find({ text: /Modo Por banco/ }))
  await view.unmount()
  view = await mount(panel, { host: hostCom([], com('projeto', ['projeto meu-projeto'])) })
  assert.ok(view.find({ ...tabela, text: /Projeto meu-projeto/ }))
  assert.ok(view.find({ text: /Modo Por projeto/ }))
  await view.unmount()
  view = await mount(panel, { host: hostCom([], com('global', [])) })
  assert.ok(view.find({ text: 'Nenhum teste na fila' }))
  assert.equal(view.find(tabela), null)
})

test('pool: detalhes dentro da tabela, várias abertas, sem botão nem campo na linha', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.selectRows(POOL, ['pessoal', 'codex'])
  assert.ok(view.rowsOf(POOL).includes('pessoal#0') && view.rowsOf(POOL).includes('codex#0'))
  await view.selectRows(POOL, ['codex'])
  assert.ok(!view.rowsOf(POOL).includes('pessoal#0') && view.rowsOf(POOL).includes('codex#0'))
  await view.selectRows(POOL, [])
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
})

test('medida antiga: a conta manual com medida de mais de 30 min ganha aviso no detalhe; a cota nativa do Orca não', async () => {
  view = await mount(panel, { host: hostCom() })
  await view.selectRows(POOL, ['pessoal'])
  assert.ok(view.find({ type: 'Table', text: /Medida antiga: há 45 min/ }))
  await view.selectRows(POOL, ['codex'])
  assert.equal(view.find({ type: 'Table', text: /Medida antiga/ }), null)
})

test('Configurações: seção recolhida no fim, com abas Fila · Pool · Contas · Painel e a linha do que cada uma muda', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.ok(view.find({ type: 'Collapsible', label: 'Configurações', text: /Fila, pool, contas e painel/ }))
  assert.equal(view.find({ label: 'Modo da fila: Global' }), null) // recolhida: nada de formulário à mostra
  await abrir(view)
  assert.ok(view.find({ type: 'Tabs', label: 'Assuntos das configurações' }))
  assert.ok(view.find({ text: /^Como os testes esperam a vez — ~\/\.claude\/fila\.conf/ }))
  await view.select({ label: 'Assuntos das configurações' }, 'pool')
  assert.ok(view.find({ text: /^Limites da máquina e como o escritor é escolhido — ~\/\.claude\/agentes\.conf/ }))
  await view.select({ label: 'Assuntos das configurações' }, 'contas')
  assert.ok(view.find({ text: /^Vagas, peso, papéis e ordem de cada conta — ~\/\.claude\/agentes\.conf\. As contas detectadas pelo Orca entram no pool sozinhas; as manuais são CLIs personalizados/ }))
  await view.select({ label: 'Assuntos das configurações' }, 'painel')
  assert.ok(view.find({ text: /^Este painel — guardado no Orca/ }))
})

test('Configurações > Pool: escolher a conta na lista mostra o formulário dela e as dicas de cada campo e papel', async () => {
  view = await mount(panel, { host: hostCom() })
  await abrir(view, 'contas')
  assert.equal(view.valueOf({ label: 'Conta a configurar' }), 'pessoal') // a primeira
  for (const trecho of [/^Quantos agentes desta conta/, /^Prioridade na escolha do escritor/, /^Pasta de configuração do agente/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
  for (const trecho of [/^Implementa a tarefa/, /^Gate de merge só leitura/, /^Contraprova só leitura/, /^Tarefas mecânicas/, /^Revisão adversarial/, /^Coordena os workers/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
  assert.ok(view.find({ type: 'Button', text: 'Remover do pool' }))
  await view.select({ label: 'Assuntos das configurações' }, 'pool')
  for (const trecho of [/^Máximo de agentes trabalhando/, /^Memória livre mínima/, /^Ritmo da cota: o escritor é a conta com mais cota sobrando/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
})

test('conta inativa: marcada na tabela, explicada no detalhe e com "Não utilizar" marcado; não existe mais Adicionar ao pool', async () => {
  view = await mount(panel, { host: hostCom() })
  assert.ok(view.find({ type: 'Table', text: /claude-abcdef12 \(não utilizada\)/ }))
  assert.equal(view.find({ type: 'Table', text: /pessoal \(não utilizada\)/ }), null)
  await view.selectRows(POOL, ['claude-abcdef12'])
  assert.ok(view.find({ type: 'Table', text: /Não utilizada: continua listada e medida/ }))
  await abrir(view, 'contas')
  assert.equal(view.find({ type: 'Checkbox', label: 'Não utilizar' })?.props.checked, false) // a primeira (pessoal) está ativa
  await view.select({ label: 'Conta a configurar' }, 'claude-abcdef12')
  assert.equal(view.find({ type: 'Checkbox', label: 'Não utilizar' })?.props.checked, true)
  assert.equal(view.find({ type: 'Button', text: 'Adicionar ao pool' }), null)
})

test('"Não utilizar" grava conta.<nome>.ativo=nao e, desmarcada, =sim; a dica explica o efeito', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await abrir(view, 'contas')
  assert.ok(view.find({ type: 'IconButton', label: /^A conta continua listada e medida, mas não recebe trabalho nem conta no teto/ }))
  await view.toggle({ label: 'Não utilizar' })
  await view.press({ type: 'Button', text: 'Salvar' })
  await view.select({ label: 'Conta a configurar' }, 'claude-abcdef12')
  await view.toggle({ label: 'Não utilizar' })
  await view.press({ type: 'Button', text: 'Salvar' })
  assert.deepEqual(enviados, [{ 'conta.pessoal.ativo': 'nao' }, { 'conta.claude-abcdef12.ativo': 'sim' }])
})

test('editar a conta escolhida manda só o que mudou e mostra o estado novo', async () => {
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
  await abrir(view, 'contas')
  await view.type({ label: 'Vagas da conta' }, '3', { replace: true })
  await view.press({ type: 'Button', text: 'Salvar' }) // aba Contas: só o Salvar da conta aberta
  assert.deepEqual(enviados, [{ 'conta.pessoal.vagas': '3' }])
  assert.deepEqual(view.refusals, [])
})

test('setas ↑/↓ da conta escolhida: gravam pool.ordem com a lista completa; a primeira não sobe e a última não desce', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await abrir(view, 'contas')
  assert.equal(view.find({ type: 'IconButton', label: 'Subir' })?.disabled, true) // pessoal é a primeira
  assert.equal(view.find({ type: 'IconButton', label: 'Descer' })?.disabled, false)
  await view.select({ label: 'Conta a configurar' }, 'claude-abcdef12')
  assert.equal(view.find({ type: 'IconButton', label: 'Descer' })?.disabled, true) // a inativa também entra na ordem, e é a última
  await view.select({ label: 'Conta a configurar' }, 'codex')
  await view.press({ type: 'IconButton', label: 'Subir' })
  assert.deepEqual(enviados, [{ 'pool.ordem': 'codex,pessoal,claude-abcdef12' }])
})

test('Remover do pool pede confirmação e só então grava conta.<nome>.remover=1', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await abrir(view, 'contas')
  await view.select({ label: 'Conta a configurar' }, 'codex')
  await view.press({ type: 'Button', text: 'Remover do pool' })
  assert.deepEqual(enviados, [])
  assert.ok(view.find({ text: /Remover codex do agentes\.conf\?/ }))
  await view.press({ type: 'Button', text: 'Cancelar' })
  assert.deepEqual(enviados, [])
  await view.press({ type: 'Button', text: 'Remover do pool' })
  await view.press({ type: 'Button', text: 'Confirmar remoção' })
  assert.deepEqual(enviados, [{ 'conta.codex.remover': '1' }])
})

test('Nova conta manual: nome, comando do CLI e diretório de config (um dos dois basta) viram adicionar=auto, com dicas e sem agente do catálogo', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await abrir(view, 'contas')
  for (const trecho of [/^Comando que abre o CLI desta conta/, /^Pasta de configuração do CLI/]) {
    assert.ok(view.find({ type: 'IconButton', label: trecho }), String(trecho))
  }
  assert.equal(view.find({ label: 'Agente do catálogo' }), null)
  assert.equal(view.find({ type: 'Button', text: 'Adicionar conta' })?.disabled, true)
  await view.type({ label: 'Nome' }, 'minha')
  assert.equal(view.find({ type: 'Button', text: 'Adicionar conta' })?.disabled, true) // falta comando ou config
  await view.type({ label: 'Diretório de config' }, '~/.claude-b')
  await view.type({ label: 'Comando do CLI' }, 'claude-b')
  await view.press({ type: 'Button', text: 'Adicionar conta' })
  assert.deepEqual(enviados, [{ 'conta.minha.adicionar': 'auto', 'conta.minha.config': '~/.claude-b', 'conta.minha.comando': 'claude-b' }])
  assert.equal(view.valueOf({ label: 'Nome' }), '')
})

test('Nova conta manual: só o comando também vale, e a recusa do backend aparece em português', async () => {
  const host = mockHost({
    requests: {
      'estado.ler': () => estadoExemplo,
      'config.gravar': () => {
        throw hostError('config_recusada', 'Não consegui deduzir o agente de "xpto".')
      }
    }
  })
  view = await mount(panel, { host })
  await abrir(view, 'contas')
  await view.type({ label: 'Nome' }, 'minha')
  await view.type({ label: 'Comando do CLI' }, 'xpto')
  await view.press({ type: 'Button', text: 'Adicionar conta' })
  assert.ok(view.find({ text: 'Não consegui deduzir o agente de "xpto".' }))
  assert.equal(view.valueOf({ label: 'Nome' }), 'minha')
})

test('modo da fila: cada opção é um rádio com o ícone de dica ao lado, sem linhas repetidas', async () => {
  const enviados: unknown[] = []
  view = await mount(panel, { host: hostCom(enviados) })
  await abrir(view)
  const grupos = view.findAll({ role: 'radiogroup' })
  assert.deepEqual(grupos.map((g) => g.label), ['Modo da fila: Global', 'Modo da fila: Por banco', 'Modo da fila: Por projeto'])
  assert.equal(view.findAll({ type: 'IconButton', label: /^Uma fila única para a máquina|^Uma fila por banco|^Cada projeto tem a própria fila/ }).length, 3)
  assert.ok(view.find({ type: 'IconButton', label: /^Máximo de testes ao mesmo tempo na máquina/ }))
  assert.ok(view.find({ type: 'IconButton', label: /Só vale no modo Por projeto/ }))
  await view.select({ label: 'Modo da fila: Por projeto' }, 'projeto')
  await view.press(view.findAll({ type: 'Button', text: 'Salvar' })[0])
  assert.deepEqual(enviados, [{ 'fila.modo': 'projeto' }])
})

test('a fila mostra só o valor em uso e avisa quando um projeto o sobrescreve', async () => {
  view = await mount(panel, { host: hostCom() })
  await abrir(view)
  assert.ok(view.find({ text: /sobrescrito pelo projeto \(meu-projeto: 1\)/ }))
  assert.equal(view.find({ text: /origem|variável de ambiente/ }), null)
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
  await abrir(view)
  await view.type({ label: 'Vagas' }, '0', { replace: true })
  await view.press(view.findAll({ type: 'Button', text: 'Salvar' })[0])
  assert.ok(view.find({ text: 'valor inválido para fila.vagas: 0' }))
  assert.equal(view.valueOf({ label: 'Vagas' }), '0')
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

test('Configurações > Painel: intervalo de atualização (15 a 3600 s) grava no storage do painel', async () => {
  const host = mockHost({ capabilities: ['storage:own'], storage: { 'atualizacao.intervalo_s': 90 }, requests: { 'estado.ler': () => estadoExemplo } })
  view = await mount(panel, { host })
  await abrir(view, 'painel')
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

const faltando: Requisitos = {
  ok: false,
  itens: [
    { id: 'cli', nome: 'CLI do Orca', ok: true, detalhe: 'orca 1.4.246' },
    { id: 'orchestration', nome: 'Orchestrator V3', ok: false, detalhe: 'Ative o Orchestrator nas configurações do Orca.', instalar: { tipo: 'acao', texto: 'Ativar' } },
    { id: 'python', nome: 'Python 3', ok: false, detalhe: 'python3 não está no PATH.', instalar: { tipo: 'comando', texto: 'winget install Python.Python.3.12' } }
  ]
}

test('requisitos faltando: só a seção Requisitos, com ✓/✗, botão Instalar para ação e comando copiável', async () => {
  let estadoLido = 0
  const host = mockHost({ requests: { 'requisitos.ler': () => faltando, 'estado.ler': () => (estadoLido++, estadoExemplo) } })
  view = await mount(panel, { host })
  assert.deepEqual(view.rowsOf({ label: 'Requisitos do painel' }), ['cli', 'orchestration', 'python'])
  assert.equal(view.find({ type: 'Table', label: 'Testes na fila' }), null)
  assert.equal(view.find({ type: 'Table', label: 'Contas do pool' }), null)
  assert.equal(view.find({ type: 'Heading', text: 'Configurações' }), null)
  assert.equal(estadoLido, 0) // nem coleta o resto
  assert.ok(view.find({ text: /Ative o Orchestrator nas configurações do Orca/ }))
  assert.ok(view.find({ text: /python3 não está no PATH/ }))
  assert.ok(view.find({ text: 'winget install Python.Python.3.12' }))
  assert.equal(view.findAll({ type: 'Button', text: 'Instalar' }).length, 1) // só a ação; o comando é copiável
})

test('Instalar chama requisitos.instalar com o id e lê os requisitos de novo; com tudo ok volta o painel normal', async () => {
  const instalados: unknown[] = []
  let r: Requisitos = faltando
  const host = mockHost({
    requests: {
      'requisitos.ler': () => r,
      'requisitos.instalar': ({ id }) => {
        instalados.push(id)
        r = { ok: true, itens: faltando.itens.map((i) => ({ ...i, ok: true })) }
        return r
      },
      'estado.ler': () => estadoExemplo
    }
  })
  view = await mount(panel, { host })
  await view.press({ type: 'Button', text: 'Instalar' })
  assert.deepEqual(instalados, ['orchestration'])
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
  assert.equal(view.find({ type: 'Table', label: 'Requisitos do painel' }), null)
})

test('requisitos ok: o painel normal; worker sem o handler (unknown_method): também o painel normal', async () => {
  view = await mount(panel, {
    host: mockHost({ requests: { 'requisitos.ler': () => ({ ok: true, itens: [] }), 'estado.ler': () => estadoExemplo } })
  })
  assert.deepEqual(view.rowsOf(POOL), ['pessoal', 'codex', 'claude-abcdef12'])
  assert.equal(view.find({ type: 'Table', label: 'Requisitos do painel' }), null)
})
