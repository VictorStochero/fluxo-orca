import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, assert, mountWorker, test } from 'orca/testing'
import { estadoExemplo } from './fixtures'
import * as main from './worker'

const casaOriginal = { HOME: process.env.HOME, USERPROFILE: process.env.USERPROFILE }
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
  process.env.HOME = casaOriginal.HOME
  process.env.USERPROFILE = casaOriginal.USERPROFILE
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
