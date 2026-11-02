// Worker do painel: roda o coletor do fluxo-orca e avisa o painel quando fila ou pool mudam em disco.
import { execFile } from 'node:child_process'
import { existsSync, readdirSync, statSync, watch, type FSWatcher } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, isAbsolute, join } from 'node:path'
import type { OrcaWorkerApi } from 'orca/worker'
import type { Estado } from './protocol'

const TIMEOUT_MS = 60_000
const DEBOUNCE_MS = 300
const CICLO_MS = 60_000
const MEDIDA_VELHA_MS = 5 * 60_000
const MEDICAO_TIMEOUT_MS = 120_000
const CHAVE_INTERVALO = 'atualizacao.intervalo_s'
const INTERVALO_MIN_S = 15
const INTERVALO_MAX_S = 3600
// O painel renova a vigília antes do teto de 120 s do plugin.request; a graça cobre o intervalo entre uma e outra.
const RENOVA_MS = 100_000
const GRACA_MS = 3_000
const FRESCO_MS = 2_000
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
export function ambienteDoColetor(env: NodeJS.ProcessEnv, plataforma: string, casa: string, orca?: string): NodeJS.ProcessEnv {
  const novo: NodeJS.ProcessEnv = { ...env }
  if (plataforma === 'win32') {
    novo.APPDATA ??= join(casa, 'AppData', 'Roaming')
    novo.LOCALAPPDATA ??= join(casa, 'AppData', 'Local')
  }
  if (orca) novo.ORCA_CMD = orca
  return novo
}

function rodarColetor(cache: string, args: string[], recusa: string, script = 'painel.sh', timeoutMs = TIMEOUT_MS): Promise<string> {
  const bash = process.platform === 'win32' ? BASH_WINDOWS : 'bash'
  const orca = acharOrca(process.env, process.platform, process.execPath)
  const env = ambienteDoColetor(process.env, process.platform, homedir(), orca)
  return new Promise((resolve, reject) => {
    execFile(
      bash,
      [join(cache, script), ...args],
      { timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024, windowsHide: true, encoding: 'utf8', env },
      (erro, stdout, stderr) => {
        if (erro) {
          const e = erro as NodeJS.ErrnoException & { killed?: boolean }
          if (e.code === 'ENOENT') return reject(falha('bash_ausente', `bash não encontrado (${bash})`))
          if (e.killed) return reject(falha('coletor_timeout', `${script} passou de ${timeoutMs / 1000} s`))
          return reject(falha(recusa, stderr.trim().replace(/^erro: /, '') || e.message))
        }
        resolve(stdout)
      }
    )
  })
}

/** Alguma medida de cota (`agentes/medida.<conta>`) com mais de 5 min. */
export function medidaVelha(pasta: string, agora = Date.now()): boolean {
  try {
    return readdirSync(pasta).some((n) => n.startsWith('medida.') && agora - statSync(join(pasta, n)).mtimeMs > MEDIDA_VELHA_MS)
  } catch {
    return false
  }
}

let medindo: Promise<void> | undefined

/** Renova as medidas manuais pelo limites.sh (que respeita o próprio cache de 5 min); nunca em paralelo e nunca rejeita: falha ou timeout deixam o cache como está. */
export function medirSeVelha(cache: string, log: (mensagem: string) => void, timeoutMs = MEDICAO_TIMEOUT_MS): Promise<void> {
  if (medindo) return medindo
  if (!medidaVelha(join(cache, 'agentes'))) return Promise.resolve()
  medindo = rodarColetor(cache, [], 'medicao_falhou', 'limites.sh', timeoutMs)
    .then(() => undefined)
    .catch((e) => log(`medição de cota: ${e instanceof Error ? e.message : String(e)}`))
    .finally(() => {
      medindo = undefined
    })
  return medindo
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

// Uma coleta por vez: quem pede enquanto outra roda (ciclo ou painel) recebe a mesma, e o resultado recente serve ao painel logo após o aviso.
let emVoo: Promise<Estado> | undefined
let recente: { estado: Estado; em: number } | undefined

function lerCompartilhado(cache: string): Promise<Estado> {
  if (recente && Date.now() - recente.em < FRESCO_MS) return Promise.resolve(recente.estado)
  emVoo ??= lerEstado(cache)
    .then((estado) => {
      recente = { estado, em: Date.now() }
      return estado
    })
    .finally(() => {
      emVoo = undefined
    })
  return emVoo
}

/** Segundos guardados -> ms: ausente ou não numérico usa 60 s; número fora da faixa cai no limite. */
export function intervaloMs(valor: unknown): number {
  if (typeof valor !== 'number' || !Number.isFinite(valor)) return CICLO_MS
  return Math.min(INTERVALO_MAX_S, Math.max(INTERVALO_MIN_S, Math.round(valor))) * 1000
}

type OpcoesCiclo = { coletar: () => Promise<unknown>; avisar: () => void; erro: (mensagem: string) => void; periodoMs?: number; gracaMs?: number; renovaMs?: number }

/** Coleta a cada `periodoMs` só enquanto há painel vigiando; se a coleta anterior não terminou, pula o ciclo. */
export function criarCiclo(o: OpcoesCiclo) {
  let periodoMs = o.periodoMs ?? CICLO_MS
  const { gracaMs = GRACA_MS, renovaMs = RENOVA_MS } = o
  let vigias = 0
  let relogio: ReturnType<typeof setInterval> | undefined
  let graca: ReturnType<typeof setTimeout> | undefined
  let rodando = false

  const ciclo = async () => {
    if (rodando) return
    rodando = true
    try {
      await o.coletar()
      o.avisar()
    } catch (e) {
      o.erro(`ciclo de atualização: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      rodando = false
    }
  }
  const parar = () => {
    clearInterval(relogio)
    clearTimeout(graca)
    relogio = graca = undefined
  }
  return {
    /** Novo período; com o ciclo ativo, reprograma na hora. */
    periodo(ms: number) {
      periodoMs = ms
      if (relogio === undefined) return
      clearInterval(relogio)
      relogio = setInterval(() => void ciclo(), periodoMs)
    },
    ativo: () => relogio !== undefined,
    parar,
    /** Resolve quando o painel fecha (`signal`) ou a vigília vence; o painel renova em seguida. */
    vigiar(signal: AbortSignal): Promise<true> {
      if (signal.aborted) return Promise.resolve(true)
      clearTimeout(graca)
      graca = undefined
      vigias++
      relogio ??= setInterval(() => void ciclo(), periodoMs)
      return new Promise((resolve) => {
        const fim = () => {
          clearTimeout(vence)
          signal.removeEventListener('abort', fim)
          if (--vigias === 0) graca = setTimeout(parar, gracaMs)
          resolve(true)
        }
        const vence = setTimeout(fim, renovaMs)
        signal.addEventListener('abort', fim, { once: true })
      })
    }
  }
}

const observadores: FSWatcher[] = []
const inscricoes: { dispose(): void }[] = []
let adiado: ReturnType<typeof setTimeout> | undefined
let vigia: ReturnType<typeof criarCiclo> | undefined

export default function activate(orca: OrcaWorkerApi): void {
  const cache = join(homedir(), '.cache')
  const e = process.env
  orca.log(
    `ORCA_CMD=${e.ORCA_CMD ?? '-'} ORCA_CLI_COMMAND=${e.ORCA_CLI_COMMAND ?? '-'} execPath=${process.execPath} candidato=${acharOrca(e, process.platform, process.execPath) ?? '-'}`
  )

  orca.panels.handle('estado.ler', () => lerCompartilhado(cache))
  orca.panels.handle('config.gravar', ({ valores }) => gravar(cache, valores))

  const avisar = () => orca.panels.post('estado.mudou', { em: Date.now() })
  vigia = criarCiclo({ coletar: async () => {
      await medirSeVelha(cache, orca.log)
      return lerCompartilhado(cache)
    },
    avisar, erro: orca.log })
  const lerIntervalo = async () => {
    try {
      vigia?.periodo(intervaloMs(await orca.storage.get(CHAVE_INTERVALO)))
    } catch (e) {
      orca.log(`sem intervalo guardado, usa 60 s: ${e instanceof Error ? e.message : String(e)}`)
    }
  }
  void lerIntervalo()
  inscricoes.push(orca.storage.onDidChange(({ key }) => key === CHAVE_INTERVALO && void lerIntervalo()))
  orca.panels.handle('auto.assistir', (_entrada, { signal }) => vigia!.vigiar(signal))

  const mudou = () => {
    recente = undefined // arquivo mudou: o resultado guardado já não vale
    clearTimeout(adiado)
    adiado = setTimeout(avisar, DEBOUNCE_MS)
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
  vigia?.parar()
  for (const i of inscricoes.splice(0)) i.dispose()
  vigia = undefined
  recente = emVoo = medindo = undefined
  for (const o of observadores.splice(0)) o.close()
}
