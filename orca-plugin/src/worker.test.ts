import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, assert, mountWorker, test } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import * as main from './worker'
import { acharOrca, ambienteDoColetor } from './worker'

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
