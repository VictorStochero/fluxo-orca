import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { mock } from 'node:test'
import { join } from 'node:path'
import { afterEach, assert, mockHost, mountWorker, test } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import * as main from './worker'
import { acharOrca, ambienteDoColetor, criarCiclo, intervaloMs, medirSeVelha } from './worker'

const casaOriginal = { HOME: process.env.HOME, USERPROFILE: process.env.USERPROFILE, LOCALAPPDATA: process.env.LOCALAPPDATA, APPDATA: process.env.APPDATA, ORCA_CMD: process.env.ORCA_CMD, ORCA_CLI_COMMAND: process.env.ORCA_CLI_COMMAND }
let casa = ''

// Casa isolada com um painel.sh falso em ~/.cache; o worker lê homedir() ao ativar.
function novaCasa(coletor: string): string {
  casa = mkdtempSync(join(tmpdir(), 'painel-worker-'))
  process.env.HOME = process.env.USERPROFILE = casa
  mkdirSync(join(casa, '.cache', 'agentes'), { recursive: true })
  writeFileSync(join(casa, '.cache', 'painel.sh'), coletor)
  return join(casa, '.cache')
}

afterEach(() => {
  main.deactivate() // fecha os observadores mesmo quando o teste falhou antes do deactivate (senão o processo não encerra)
  process.env.HOME = casaOriginal.HOME
  process.env.USERPROFILE = casaOriginal.USERPROFILE
  if (casaOriginal.LOCALAPPDATA === undefined) delete process.env.LOCALAPPDATA
  else process.env.LOCALAPPDATA = casaOriginal.LOCALAPPDATA
  for (const k of ['APPDATA', 'ORCA_CMD', 'ORCA_CLI_COMMAND'] as const) {
    if (casaOriginal[k] === undefined) delete process.env[k]
    else process.env[k] = casaOriginal[k]
  }
  if (casa) rmSync(casa, { recursive: true, force: true })
})

async function ate(condicao: () => boolean): Promise<void> {
  for (let i = 0; i < 100 && !condicao(); i++) await new Promise((r) => setTimeout(r, 50))
}

test('estado.ler devolve o JSON do coletor', async () => {
  novaCasa(`cat <<'JSON'\n${JSON.stringify(estadoExemplo)}\nJSON\n`)
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('estado.ler'), estadoExemplo)
  assert.deepEqual(worker.refusals, [])
  await worker.deactivate()
})

test('coletor que sai com erro vira coletor_falhou com a mensagem', async () => {
  novaCasa('echo "AVISO: sem Python" >&2; exit 2\n')
  const worker = await mountWorker(main)
  await assert.rejects(worker.request('estado.ler'), (e: unknown) => {
    const x = e as { code?: string; message?: string }
    return x.code === 'coletor_falhou' && /sem Python/.test(x.message ?? '')
  })
  await worker.deactivate()
})

test('saída que não é JSON vira coletor_json_invalido', async () => {
  novaCasa('echo isto não é json\n')
  const worker = await mountWorker(main)
  await assert.rejects(worker.request('estado.ler'), (e: unknown) => (e as { code?: string }).code === 'coletor_json_invalido')
  await worker.deactivate()
})

test('trava da fila e vaga do pool disparam um único estado.mudou por rajada', async () => {
  const cache = novaCasa('echo {}\n')
  const worker = await mountWorker(main)
  mkdirSync(join(cache, 'gs-teste-3308.lock1'))
  mkdirSync(join(cache, 'agentes', 'a.lock1'))
  writeFileSync(join(cache, 'agentes', 'medida.a'), 'a: 1%')
  await ate(() => worker.posts.length > 0)
  await new Promise((r) => setTimeout(r, 600))
  assert.equal(worker.posts.length, 1)
  assert.equal(worker.posts[0].event, 'estado.mudou')
  await worker.deactivate()
})

test('arquivo alheio em ~/.cache não dispara estado.mudou', async () => {
  const cache = novaCasa('echo {}\n')
  const worker = await mountWorker(main)
  writeFileSync(join(cache, 'outro.txt'), 'x')
  await new Promise((r) => setTimeout(r, 600))
  assert.deepEqual(worker.posts, [])
  await worker.deactivate()
})

// Coletor falso: --config grava os argumentos recebidos (um por linha) e recusa chave.ruim como o painel.sh faz.
const COLETOR_CONFIG = (estado: string) => `if [ "$1" = --config ]; then
  for a in "$@"; do case "$a" in chave.ruim=*) echo "erro: chave desconhecida (chave.ruim)" >&2; exit 2 ;; esac; done
  printf '%s\n' "$@" > "$HOME/.cache/args.txt"; exit 0
fi
cat <<'JSON'
${estado}
JSON
`

test('config.gravar passa os pares como argumentos separados e devolve o estado novo', async () => {
  const cache = novaCasa(COLETOR_CONFIG(JSON.stringify(estadoExemplo)))
  const worker = await mountWorker(main)
  const valores = { 'fila.vagas': '3', 'conta.a.papeis': 'revisor,mecanico', 'pool.escolha': 'a b; rm -rf x' }
  assert.deepEqual(await worker.request('config.gravar', { valores }), estadoExemplo)
  const args = readFileSync(join(cache, 'args.txt'), 'utf8').trim().split('\n')
  assert.deepEqual(args, ['--config', 'fila.vagas=3', 'conta.a.papeis=revisor,mecanico', 'pool.escolha=a b; rm -rf x'])
  assert.deepEqual(worker.refusals, [])
  await worker.deactivate()
})

test('config.gravar: recusa do painel.sh vira config_recusada em português, sem o prefixo erro:', async () => {
  novaCasa(COLETOR_CONFIG('{}'))
  const worker = await mountWorker(main)
  await assert.rejects(worker.request('config.gravar', { valores: { 'chave.ruim': '1' } }), (e: unknown) => {
    const x = e as { code?: string; message?: string }
    return x.code === 'config_recusada' && x.message === 'chave desconhecida (chave.ruim)'
  })
  await worker.deactivate()
})

test('config.gravar sem valores é recusado antes de rodar o coletor', async () => {
  const cache = novaCasa(COLETOR_CONFIG('{}'))
  const worker = await mountWorker(main)
  await assert.rejects(worker.request('config.gravar', { valores: {} }), (e: unknown) => (e as { code?: string }).code === 'config_invalida')
  assert.equal(existsSync(join(cache, 'args.txt')), false)
  await worker.deactivate()
})

test('acharOrca: respeita o ORCA_CMD existente e procura o CLI nos lugares do Orca', () => {
  const existe = (c: string) => c.endsWith('resources/bin/orca.exe') || c.endsWith('resources\\bin\\orca.exe')
  const local = { LOCALAPPDATA: 'C:/Users/u/AppData/Local' }
  // Variável que já aponta um arquivo existente vale; `orca` sem caminho (herdado do Orca) não.
  assert.equal(acharOrca({ ORCA_CMD: 'C:/Orca/orca.exe' }, 'win32', 'C:/Orca/Orca.exe', () => true), undefined)
  assert.equal(acharOrca({ ORCA_CLI_COMMAND: 'C:/Orca/orca.exe' }, 'win32', 'C:/Orca/Orca.exe', () => true), undefined)
  for (const env of [{ ORCA_CMD: 'orca' }, { ORCA_CLI_COMMAND: 'orca' }, { ORCA_CMD: 'C:/some/orca.exe' }]) {
    assert.match(acharOrca({ ...env, ...local }, 'win32', 'C:/node.exe', (c) => c.includes('Programs')) ?? '', /Programs\/orca\/resources\/bin\/orca\.exe$/)
  }
  assert.match(acharOrca({ LOCALAPPDATA: 'C:/Users/u/AppData/Local' }, 'win32', 'C:/node.exe', (c) => c.includes('Programs')) ?? '', /^C:\/Users\/u\/AppData\/Local\/Programs\/orca\/resources\/bin\/orca\.exe$/)
  assert.equal(acharOrca({}, 'win32', 'C:/node.exe', () => false), undefined)
})

test('o coletor roda com ORCA_CMD apontando o CLI da instalação padrão', async () => {
  if (process.platform !== 'win32') return
  const cache = novaCasa('echo "{\\"cmd\\":\\"$ORCA_CMD\\",\\"appdata\\":\\"${APPDATA//\\\\//}\\"}"\n')
  const bin = join(casa, 'local', 'Programs', 'orca', 'resources', 'bin')
  mkdirSync(bin, { recursive: true })
  writeFileSync(join(bin, 'orca.exe'), '')
  process.env.LOCALAPPDATA = join(casa, 'local')
  process.env.ORCA_CMD = 'orca' // como no processo do Orca: nome sem caminho
  delete process.env.APPDATA // o worker chega sem APPDATA e o CLI do Orca recusa ('APPDATA is not set')
  delete process.env.ORCA_CLI_COMMAND
  const worker = await mountWorker(main)
  const saida = (await worker.request('estado.ler')) as unknown as { cmd: string; appdata: string }
  assert.equal(saida.cmd, join(bin, 'orca.exe').replace(/\\/g, '/'))
  assert.match(saida.appdata, /AppData.Roaming$/)
  assert.ok(cache)
  await worker.deactivate()
})

test('ambienteDoColetor completa APPDATA e LOCALAPPDATA no Windows e não mexe no que já existe', () => {
  const sem = ambienteDoColetor({ PATH: 'p' }, 'win32', 'C:/Users/u', 'C:/o/orca.exe')
  assert.match(sem.APPDATA ?? '', /u.AppData.Roaming$/)
  assert.match(sem.LOCALAPPDATA ?? '', /u.AppData.Local$/)
  assert.equal(sem.ORCA_CMD, 'C:/o/orca.exe')
  const com = ambienteDoColetor({ APPDATA: 'X', LOCALAPPDATA: 'Y' }, 'win32', 'C:/u')
  assert.deepEqual([com.APPDATA, com.LOCALAPPDATA, com.ORCA_CMD], ['X', 'Y', undefined])
  assert.equal(ambienteDoColetor({}, 'linux', '/home/u').APPDATA, undefined)
})

// Ciclo de 60 s com relógio falso; `coletar` é um contador, `abrir` devolve o AbortController do painel.
async function comRelogio(corpo: (r: { avancar: (ms: number) => Promise<void> }) => Promise<void>): Promise<void> {
  mock.timers.enable({ apis: ['setInterval', 'setTimeout'] })
  try {
    await corpo({
      avancar: async (ms) => {
        mock.timers.tick(ms)
        for (let i = 0; i < 5; i++) await Promise.resolve() // deixa as continuações da coleta rodarem
      }
    })
  } finally {
    mock.timers.reset()
  }
}

test('ciclo: com painel aberto coleta e avisa a cada 60 s', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    let avisos = 0
    const c = criarCiclo({ coletar: async () => void coletas++, avisar: () => void avisos++, erro: () => {}, renovaMs: 1_000_000 })
    const painel = new AbortController()
    void c.vigiar(painel.signal)
    await avancar(59_999)
    assert.equal(coletas, 0)
    await avancar(1)
    assert.deepEqual([coletas, avisos], [1, 1])
    await avancar(60_000)
    assert.deepEqual([coletas, avisos], [2, 2])
    painel.abort()
    c.parar()
  })
})

test('ciclo: sem painel não coleta', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    const c = criarCiclo({ coletar: async () => void coletas++, avisar: () => {}, erro: () => {} })
    await avancar(300_000)
    assert.equal(coletas, 0)
    assert.equal(c.ativo(), false)
  })
})

test('ciclo: coleta lenta não empilha e o ciclo seguinte volta ao normal', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    let avisos = 0
    let termina: () => void = () => {}
    const c = criarCiclo({
      coletar: () => {
        coletas++
        return coletas === 1 ? new Promise<void>((r) => (termina = r)) : Promise.resolve()
      },
      avisar: () => void avisos++,
      erro: () => {},
      renovaMs: 1_000_000
    })
    const painel = new AbortController()
    void c.vigiar(painel.signal)
    await avancar(60_000)
    await avancar(60_000) // a primeira ainda roda: pula
    await avancar(60_000)
    assert.deepEqual([coletas, avisos], [1, 0])
    termina()
    await avancar(0)
    assert.equal(avisos, 1)
    await avancar(60_000)
    assert.deepEqual([coletas, avisos], [2, 2])
    painel.abort()
    c.parar()
  })
})

test('ciclo: fechar o último painel para o ciclo; um painel restante o mantém', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    const c = criarCiclo({ coletar: async () => void coletas++, avisar: () => {}, erro: () => {}, gracaMs: 3_000, renovaMs: 1_000_000 })
    const a = new AbortController()
    const b = new AbortController()
    void c.vigiar(a.signal)
    void c.vigiar(b.signal)
    a.abort()
    await avancar(60_000)
    assert.equal(coletas, 1) // b segue aberto
    b.abort()
    await avancar(3_000)
    assert.equal(c.ativo(), false)
    await avancar(300_000)
    assert.equal(coletas, 1)
  })
})

test('ciclo: a renovação da vigília não derruba o ciclo (graça cobre o intervalo)', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    const c = criarCiclo({ coletar: async () => void coletas++, avisar: () => {}, erro: () => {}, renovaMs: 100_000, gracaMs: 3_000 })
    const painel = new AbortController()
    void c.vigiar(painel.signal)
    await avancar(100_000) // vence; o painel renova logo
    void c.vigiar(painel.signal)
    assert.equal(c.ativo(), true)
    await avancar(60_000)
    assert.equal(coletas, 2)
    painel.abort()
    c.parar()
  })
})

test('estado.ler seguido devolve a coleta recente sem rodar o coletor de novo', async () => {
  const cache = novaCasa(`echo x >> "$HOME/.cache/n.txt"; echo '{}'
`)
  const worker = await mountWorker(main)
  await worker.request('estado.ler')
  await worker.request('estado.ler')
  assert.equal(readFileSync(join(cache, 'n.txt'), 'utf8').trim().split('\n').length, 1)
  await worker.deactivate()
})

// limites.sh falso: conta as execuções em medidas.txt; `corpo` é o que mais ele faz.
function comLimites(corpo: string, idadeMin: number | null): string {
  const cache = novaCasa('echo {}\n')
  writeFileSync(join(cache, 'limites.sh'), `echo x >> "$HOME/.cache/medidas.txt"\n${corpo}\n`)
  if (idadeMin !== null) {
    const f = join(cache, 'agentes', 'medida.team')
    writeFileSync(f, 'team: 1%')
    const t = new Date(Date.now() - idadeMin * 60_000)
    utimesSync(f, t, t)
  }
  return cache
}
const medidas = (cache: string) => (existsSync(join(cache, 'medidas.txt')) ? readFileSync(join(cache, 'medidas.txt'), 'utf8').trim().split('\n').length : 0)

test('medição: mede quando há medida com mais de 5 min', async () => {
  const cache = comLimites('', 6)
  await medirSeVelha(cache, () => {})
  assert.equal(medidas(cache), 1)
})

test('medição: não mede quando todas as medidas são recentes ou não há nenhuma', async () => {
  const recente = comLimites('', 4)
  await medirSeVelha(recente, () => {})
  assert.equal(medidas(recente), 0)
  const nenhuma = comLimites('', null)
  await medirSeVelha(nenhuma, () => {})
  assert.equal(medidas(nenhuma), 0)
})

test('medição: timeout ou falha não rejeitam nem travam, e chamadas simultâneas não rodam em paralelo', async () => {
  const lenta = comLimites('sleep 30', 6)
  const logs: string[] = []
  const ini = Date.now()
  await Promise.all([medirSeVelha(lenta, (m) => logs.push(m), 400), medirSeVelha(lenta, (m) => logs.push(m), 400)])
  assert.ok(Date.now() - ini < 10_000)
  assert.equal(medidas(lenta), 1)
  assert.match(logs.join(), /limites\.sh passou de/)
  const quebrada = comLimites('exit 3', 6)
  await medirSeVelha(quebrada, (m) => logs.push(m))
  assert.equal(medidas(quebrada), 1)
})

test('intervalo: ausente ou inválido usa 60 s; fora da faixa cai no limite', () => {
  for (const v of [null, undefined, 'abc', NaN, {}]) assert.equal(intervaloMs(v), 60_000)
  assert.equal(intervaloMs(90), 90_000)
  assert.equal(intervaloMs(5), 15_000)
  assert.equal(intervaloMs(99999), 3_600_000)
  assert.equal(intervaloMs(-3), 15_000)
})

test('ciclo: mudar o período reprograma o relógio na hora', async () => {
  await comRelogio(async ({ avancar }) => {
    let coletas = 0
    const c = criarCiclo({ coletar: async () => void coletas++, avisar: () => {}, erro: () => {}, renovaMs: 1_000_000 })
    const painel = new AbortController()
    void c.vigiar(painel.signal)
    c.periodo(15_000)
    await avancar(15_000)
    assert.equal(coletas, 1)
    c.periodo(30_000)
    await avancar(15_000)
    assert.equal(coletas, 1)
    await avancar(15_000)
    assert.equal(coletas, 2)
    painel.abort()
    c.parar()
  })
})

test('worker lê atualizacao.intervalo_s ao iniciar e reprograma o ciclo quando a chave muda', async () => {
  novaCasa('echo {}\n')
  let valor: unknown = 20
  let ouvinte: (c: { key: string }) => void = () => {}
  let vigiar: (entrada: unknown, ctx: { signal: AbortSignal }) => unknown = () => {}
  const posts: string[] = []
  const falso = {
    log: () => {},
    storage: { get: async () => valor, onDidChange: (l: typeof ouvinte) => ((ouvinte = l), { dispose() {} }) },
    panels: { handle: (nome: string, h: typeof vigiar) => (nome === 'auto.assistir' && (vigiar = h), { dispose() {} }), post: (e: string) => void posts.push(e) }
  }
  mock.timers.enable({ apis: ['setInterval'] }) // setTimeout segue real: o coletor é um processo de verdade
  const painel = new AbortController()
  try {
    main.default(falso as never)
    await Promise.resolve()
    void vigiar(undefined, { signal: painel.signal })
    for (let i = 0; i < 5; i++) await Promise.resolve()
    mock.timers.tick(20_000)
    await ate(() => posts.includes('estado.mudou'))
    assert.equal(posts.filter((p) => p === 'estado.mudou').length, 1)
    valor = 40
    ouvinte({ key: 'outra.chave' }) // chave alheia não reprograma
    ouvinte({ key: 'atualizacao.intervalo_s' })
    for (let i = 0; i < 5; i++) await Promise.resolve()
    mock.timers.tick(20_000)
    await new Promise((r) => setTimeout(r, 400))
    assert.equal(posts.length, 1) // com 40 s, 20 s não basta
    mock.timers.tick(20_000)
    await ate(() => posts.length > 1)
    assert.equal(posts.length, 2)
  } finally {
    painel.abort()
    mock.timers.reset()
  }
})
