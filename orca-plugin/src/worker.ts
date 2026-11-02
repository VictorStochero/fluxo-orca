// Worker do painel: roda o coletor do fluxo-orca e avisa o painel quando fila ou pool mudam em disco.
import { execFile } from 'node:child_process'
import { watch, type FSWatcher } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import type { OrcaWorkerApi } from 'orca/worker'
import type { Estado } from './protocol'

const TIMEOUT_MS = 60_000
const DEBOUNCE_MS = 300
const BASH_WINDOWS = 'C:\\Program Files\\Git\\bin\\bash.exe'

function falha(code: string, message: string): Error {
  return Object.assign(new Error(message), { code })
}

function lerEstado(cache: string): Promise<Estado> {
  const bash = process.platform === 'win32' ? BASH_WINDOWS : 'bash'
  return new Promise((resolve, reject) => {
    execFile(
      bash,
      [join(cache, 'painel.sh'), '--json'],
      { timeout: TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024, windowsHide: true, encoding: 'utf8' },
      (erro, stdout, stderr) => {
        if (erro) {
          const e = erro as NodeJS.ErrnoException & { killed?: boolean }
          if (e.code === 'ENOENT') return reject(falha('bash_ausente', `bash não encontrado (${bash})`))
          if (e.killed) return reject(falha('coletor_timeout', `o coletor passou de ${TIMEOUT_MS / 1000} s`))
          const detalhe = stderr.trim() || e.message
          return reject(falha('coletor_falhou', detalhe))
        }
        try {
          resolve(JSON.parse(stdout) as Estado)
        } catch {
          reject(falha('coletor_json_invalido', 'o coletor não devolveu JSON'))
        }
      }
    )
  })
}

const observadores: FSWatcher[] = []
let adiado: ReturnType<typeof setTimeout> | undefined

export default function activate(orca: OrcaWorkerApi): void {
  const cache = join(homedir(), '.cache')

  orca.panels.handle('estado.ler', () => lerEstado(cache))

  const mudou = () => {
    clearTimeout(adiado)
    adiado = setTimeout(() => orca.panels.post('estado.mudou', { em: Date.now() }), DEBOUNCE_MS)
  }
  // Travas da fila (gs-teste*.lock*) ficam direto em ~/.cache; as do pool e as medidas, em ~/.cache/agentes.
  const observa = (pasta: string, filtro: (nome: string) => boolean, recursivo: boolean) => {
    try {
      observadores.push(watch(pasta, { recursive: recursivo }, (_evento, nome) => filtro(nome ?? '') && mudou()))
    } catch (e) {
      orca.log(`sem observação de ${pasta}: ${e instanceof Error ? e.message : String(e)}`)
    }
  }
  observa(cache, (nome) => nome.startsWith('gs-teste'), false)
  observa(join(cache, 'agentes'), () => true, true)
}

export function deactivate(): void {
  clearTimeout(adiado)
  for (const o of observadores.splice(0)) o.close()
}
