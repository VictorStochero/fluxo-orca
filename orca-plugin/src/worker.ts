// Worker do painel: roda o coletor do fluxo-orca e avisa o painel quando fila ou pool mudam em disco.
import { execFile } from 'node:child_process'
import { existsSync, watch, type FSWatcher } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, isAbsolute, join } from 'node:path'
import type { OrcaWorkerApi } from 'orca/worker'
import type { Estado } from './protocol'

const TIMEOUT_MS = 60_000
const DEBOUNCE_MS = 300
const BASH_WINDOWS = 'C:\\Program Files\\Git\\bin\\bash.exe'

function falha(code: string, message: string): Error {
  return Object.assign(new Error(message), { code })
}

/**
 * Caminho do CLI do Orca para o `ORCA_CMD` do coletor: o PATH do worker não traz a pasta do CLI.
 * Respeita o que já estiver definido; senão procura ao lado do executável do Orca e na instalação padrão.
 */
export function acharOrca(
  env: NodeJS.ProcessEnv,
  plataforma: string,
  execPath: string,
  existe: (caminho: string) => boolean = existsSync
): string | undefined {
  // Só vale o que já aponta um arquivo: um `orca` sem caminho, herdado do processo do Orca, não resolve sem a pasta do CLI no PATH.
  const dado = env.ORCA_CMD || env.ORCA_CLI_COMMAND
  if (dado && isAbsolute(dado) && existe(dado)) return undefined
  const candidatos: string[] = []
  if (plataforma === 'win32') {
    const local = env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local')
    candidatos.push(join(dirname(execPath), 'resources', 'bin', 'orca.exe'), join(local, 'Programs', 'orca', 'resources', 'bin', 'orca.exe'))
  } else if (plataforma === 'darwin') {
    candidatos.push(join(dirname(execPath), '..', 'Resources', 'bin', 'orca'), '/Applications/Orca.app/Contents/Resources/bin/orca')
  } else {
    candidatos.push(join(dirname(execPath), 'resources', 'bin', 'orca'), join(dirname(execPath), 'bin', 'orca'))
  }
  const achado = candidatos.find(existe)
  return achado?.replace(/\\/g, '/')
}

/**
 * Ambiente do coletor. O processo do worker chega sem APPDATA/LOCALAPPDATA (o CLI do Orca responde
 * `runtime_unavailable: APPDATA is not set`), então completa o que falta a partir da pasta do usuário e aponta o CLI.
 */
export function ambienteDoColetor(env: NodeJS.ProcessEnv, plataforma: string, casa: string, orca?: string, caminhoExtra = ''): NodeJS.ProcessEnv {
  const novo: NodeJS.ProcessEnv = { ...env }
  if (caminhoExtra) {
    // O PATH do worker chega sem as pastas do usuário (onde ficam os CLIs dos agentes): completa sem repetir entradas.
    const chave = Object.keys(novo).find((k) => k.toLowerCase() === 'path') ?? 'PATH'
    const sep = plataforma === 'win32' ? ';' : ':'
    const atual = (novo[chave] ?? '').split(sep).filter(Boolean)
    const vistos = new Set(atual.map((x) => x.toLowerCase()))
    novo[chave] = [...atual, ...caminhoExtra.split(sep).filter((x) => x && !vistos.has(x.toLowerCase()))].join(sep)
  }
  if (plataforma === 'win32') {
    novo.APPDATA ??= join(casa, 'AppData', 'Roaming')
    novo.LOCALAPPDATA ??= join(casa, 'AppData', 'Local')
  }
  if (orca) novo.ORCA_CMD = orca
  return novo
}

let caminhoDoSistema: Promise<string> | undefined

/** PATH de Machine e User lido do sistema (Windows): o do processo do Orca não traz, por exemplo, a pasta do npm global. */
function lerCaminhoDoSistema(): Promise<string> {
  if (process.platform !== 'win32') return Promise.resolve('')
  caminhoDoSistema ??= new Promise((resolve) =>
    execFile(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"],
      { timeout: 10_000, windowsHide: true, encoding: 'utf8' },
      (erro, saida) => resolve(erro ? '' : saida.trim())
    )
  )
  return caminhoDoSistema
}

async function rodarColetor(cache: string, args: string[], recusa: string): Promise<string> {
  const bash = process.platform === 'win32' ? BASH_WINDOWS : 'bash'
  const orca = acharOrca(process.env, process.platform, process.execPath)
  const env = ambienteDoColetor(process.env, process.platform, homedir(), orca, await lerCaminhoDoSistema())
  return new Promise((resolve, reject) => {
    execFile(
      bash,
      [join(cache, 'painel.sh'), ...args],
      { timeout: TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024, windowsHide: true, encoding: 'utf8', env },
      (erro, stdout, stderr) => {
        if (erro) {
          const e = erro as NodeJS.ErrnoException & { killed?: boolean }
          if (e.code === 'ENOENT') return reject(falha('bash_ausente', `bash não encontrado (${bash})`))
          if (e.killed) return reject(falha('coletor_timeout', `o coletor passou de ${TIMEOUT_MS / 1000} s`))
          return reject(falha(recusa, stderr.trim().replace(/^erro: /, '') || e.message))
        }
        resolve(stdout)
      }
    )
  })
}

async function lerEstado(cache: string): Promise<Estado> {
  const saida = await rodarColetor(cache, ['--json'], 'coletor_falhou')
  try {
    return JSON.parse(saida) as Estado
  } catch {
    throw falha('coletor_json_invalido', 'o coletor não devolveu JSON')
  }
}

async function gravar(cache: string, valores: Record<string, string>): Promise<Estado> {
  const pares = Object.entries(valores ?? {})
  if (pares.length === 0 || pares.some(([k, v]) => typeof k !== 'string' || typeof v !== 'string')) {
    throw falha('config_invalida', 'nada para gravar')
  }
  // Argumentos em array, nunca string de shell; o painel.sh valida chave e valor antes de gravar.
  await rodarColetor(cache, ['--config', ...pares.map(([k, v]) => `${k}=${v}`)], 'config_recusada')
  return lerEstado(cache)
}

const observadores: FSWatcher[] = []
let adiado: ReturnType<typeof setTimeout> | undefined

export default function activate(orca: OrcaWorkerApi): void {
  const cache = join(homedir(), '.cache')
  const e = process.env
  orca.log(
    `ORCA_CMD=${e.ORCA_CMD ?? '-'} ORCA_CLI_COMMAND=${e.ORCA_CLI_COMMAND ?? '-'} execPath=${process.execPath} candidato=${acharOrca(e, process.platform, process.execPath) ?? '-'}`
  )

  orca.panels.handle('estado.ler', () => lerEstado(cache))
  orca.panels.handle('config.gravar', ({ valores }) => gravar(cache, valores))

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
  // fila.conf e agentes.conf ficam em ~/.claude; o painel lê de novo ao gravar, então não precisam de observação.
}

export function deactivate(): void {
  clearTimeout(adiado)
  for (const o of observadores.splice(0)) o.close()
}
