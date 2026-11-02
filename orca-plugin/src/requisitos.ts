// Requisitos do painel: lógica sem E/S própria (o worker injeta o CLI do Orca, o coletor e o disco).
import type { Estado, Requisitos, RequisitoItem } from './protocol'

export const ORCA_MINIMO = '1.4.246'
export const SKILLS_FLUXO = ['delegacao', 'fila-testes', 'limites-cota']
export const SCRIPTS_FLUXO = ['painel.sh', 'fila-teste.sh', 'vaga-agente.sh', 'contas.sh', 'limites.sh']
const VALIDADE_MS = 60_000
const COMANDO_PLUGIN = 'claude plugin install fluxo-orca@stochero'

export type DepsRequisitos = {
  /** Roda o CLI do Orca com o ambiente do coletor e devolve o stdout; rejeita se falhar. */
  orca: (args: string[]) => Promise<string>
  estado: () => Promise<Pick<Estado, 'saude'>>
  existe: (script: string) => boolean
  agora?: () => number
}

/** Compara `a.b.c`; ausente ou ilegível devolve null. */
export function versaoAtende(texto: string, minimo = ORCA_MINIMO): boolean | null {
  const m = /(\d+)\.(\d+)\.(\d+)/.exec(texto)
  if (!m) return null
  const a = m.slice(1, 4).map(Number)
  const b = minimo.split('.').map(Number)
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i]
  return true
}

type Entrada = { name: string; sourceKind?: string; sourceLabel?: string }

/** `orca skills installed --json` -> lista; lança se o formato não for o esperado. */
export function lerSkills(saida: string): Entrada[] {
  const lista = (JSON.parse(saida) as { result?: { skills?: unknown } })?.result?.skills
  if (!Array.isArray(lista) || lista.some((s) => typeof (s as Entrada)?.name !== 'string')) throw new Error('formato inesperado')
  return lista as Entrada[]
}

const naoVerificado = (id: string, nome: string, motivo: string, instalar?: RequisitoItem['instalar']): RequisitoItem => ({
  id,
  nome,
  ok: false,
  detalhe: `não verificado: ${motivo}`,
  ...(instalar && { instalar })
})

const mensagem = (e: unknown) => (e instanceof Error ? e.message : String(e))

export function criarRequisitos(deps: DepsRequisitos) {
  const agora = deps.agora ?? Date.now
  let guardado: { valor: Requisitos; em: number } | undefined
  let emVoo: Promise<Requisitos> | undefined

  async function coletar(): Promise<Requisitos> {
    const [versao, skills, estado] = await Promise.allSettled([deps.orca(['--version']), deps.orca(['skills', 'installed', '--json']), deps.estado()])
    const itens: RequisitoItem[] = []

    if (versao.status === 'rejected') itens.push(naoVerificado('orca', `Orca ${ORCA_MINIMO} ou mais novo`, mensagem(versao.reason)))
    else {
      const atende = versaoAtende(versao.value)
      const lida = versao.value.trim()
      itens.push(
        atende === null
          ? naoVerificado('orca', `Orca ${ORCA_MINIMO} ou mais novo`, `versão ilegível (${lida.slice(0, 40)})`)
          : { id: 'orca', nome: `Orca ${ORCA_MINIMO} ou mais novo`, ok: atende, detalhe: atende ? `versão ${lida}` : `versão ${lida}; atualize o Orca` }
      )
    }

    let lista: Entrada[] | undefined
    let erroLista = ''
    if (skills.status === 'rejected') erroLista = mensagem(skills.reason)
    else
      try {
        lista = lerSkills(skills.value)
      } catch (e) {
        erroLista = mensagem(e)
      }

    const instalarOrch = { tipo: 'acao', texto: 'orca skills install --skill orchestration' } as const
    const instalarFluxo = { tipo: 'comando', texto: COMANDO_PLUGIN } as const
    if (!lista) {
      itens.push(naoVerificado('orchestration', 'Skill orchestration do Orca', erroLista, instalarOrch))
      itens.push(naoVerificado('skills-fluxo', 'Skills do fluxo (delegacao, fila-testes, limites-cota)', erroLista, instalarFluxo))
    } else {
      const orch = lista.some((s) => s.name === 'orchestration')
      itens.push({ id: 'orchestration', nome: 'Skill orchestration do Orca', ok: orch, detalhe: orch ? 'instalada' : 'não instalada', ...(!orch && { instalar: instalarOrch }) })
      const faltam = SKILLS_FLUXO.filter((n) => !lista.some((s) => s.name === n && s.sourceKind === 'plugin' && /fluxo-orca/.test(s.sourceLabel ?? '')))
      itens.push({
        id: 'skills-fluxo',
        nome: 'Skills do fluxo (delegacao, fila-testes, limites-cota)',
        ok: faltam.length === 0,
        detalhe: faltam.length === 0 ? 'instaladas pelo plugin fluxo-orca' : `faltam: ${faltam.join(', ')}`,
        ...(faltam.length > 0 && { instalar: instalarFluxo })
      })
    }

    const ausentes = SCRIPTS_FLUXO.filter((s) => !deps.existe(s))
    const instalarScripts = { tipo: 'comando', texto: 'Reabra uma sessão do Claude Code: o hook copia os scripts para ~/.cache' } as const
    const rotuloScripts = 'Scripts do fluxo em ~/.cache'
    if (ausentes.length > 0) {
      itens.push({ id: 'scripts', nome: rotuloScripts, ok: false, detalhe: `faltam: ${ausentes.join(', ')}`, instalar: instalarScripts })
    } else if (estado.status === 'rejected') {
      itens.push(naoVerificado('scripts', rotuloScripts, mensagem(estado.reason), instalarScripts))
    } else {
      const velhos = estado.value?.saude?.scripts_desatualizados
      if (!Array.isArray(velhos)) itens.push(naoVerificado('scripts', rotuloScripts, 'o coletor não informou as versões', instalarScripts))
      else
        itens.push({
          id: 'scripts',
          nome: rotuloScripts,
          ok: velhos.length === 0,
          detalhe: velhos.length === 0 ? 'na versão do plugin' : `desatualizados: ${velhos.join(', ')}`,
          ...(velhos.length > 0 && { instalar: instalarScripts })
        })
    }

    return { ok: itens.every((i) => i.ok), itens }
  }

  function ler(): Promise<Requisitos> {
    if (guardado && agora() - guardado.em < VALIDADE_MS) return Promise.resolve(guardado.valor)
    emVoo ??= coletar()
      .then((valor) => {
        guardado = { valor, em: agora() }
        return valor
      })
      .finally(() => {
        emVoo = undefined
      })
    return emVoo
  }

  return {
    ler,
    /** Só `orchestration` é instalável pelo painel; devolve os requisitos já relidos. */
    async instalar(id: unknown): Promise<Requisitos> {
      if (id !== 'orchestration') throw Object.assign(new Error('só a skill orchestration pode ser instalada pelo painel'), { code: 'instalacao_recusada' })
      await emVoo?.catch(() => undefined) // uma leitura em curso gravaria o resultado velho depois da instalação
      try {
        await deps.orca(['skills', 'install', '--skill', 'orchestration', '--json'])
      } catch (e) {
        throw Object.assign(new Error(mensagem(e)), { code: 'instalacao_falhou' })
      } finally {
        guardado = undefined
      }
      return ler()
    }
  }
}
