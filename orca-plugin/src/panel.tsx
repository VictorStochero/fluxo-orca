// Painel de fila de testes e pool de agentes. O estado e a gravação passam pelo worker (src/protocol.ts); textos em src/textos.ts.
// Só leitura nas tabelas (Fila e Pool, nativas); toda a edição fica em Configurações, no fim.
import {
  atom,
  Button,
  Card,
  Checkbox,
  Code,
  Collapsible,
  EmptyState,
  Heading,
  IconButton,
  Input,
  plugin,
  RadioGroup,
  read,
  RelativeTime,
  Row,
  Select,
  set,
  Spinner,
  Stack,
  storage,
  Tab,
  Table,
  Tabs,
  Text,
  ui,
  update,
  type OrcaNode,
  type PanelContext,
  type TableRow
} from 'orca'
import type { Conta, Estado, ItemFila, Requisitos, ValorFila } from './protocol'
import { manterAtualizando } from './atualizacao'
import { t } from './textos'

type Erro = { code: string; message: string }
type Aviso = { tom: 'success' | 'danger'; texto: string }

const estado = atom<Estado | null>(null)
/** null enquanto não lido ou quando o worker não tem o handler (painel normal). */
const requisitos = atom<Requisitos | null>(null)
const erro = atom<Erro | null>(null)
const carregando = atom(false)
/** Só o que a pessoa digitou e ainda não gravou, por chave do `painel.sh --config` (ex.: `conta.pessoal.vagas`). */
const edicoes = atom<Record<string, string>>({})
const avisos = atom<Record<string, Aviso>>({})
const gravando = atom<string | null>(null)
/** Conta com o pedido de remoção aguardando confirmação. */
const removendo = atom<string | null>(null)
/** Conta escolhida em Configurações > Pool (null = a primeira). */
const contaEscolhida = atom<string | null>(null)
/** Intervalo da atualização automática: o worker lê esta chave do storage e reprograma sozinho. */
const CHAVE_INTERVALO = 'atualizacao.intervalo_s'
const INTERVALO = { padrao: 60, min: 15, max: 3600 }
const intervalo = atom(INTERVALO.padrao)
/** Linhas abertas de cada tabela (várias ao mesmo tempo; clicar de novo recolhe). */
const abertasTrava = atom<string[]>([])
const abertasConta = atom<string[]>([])

let coletando = false

/** Worker sem o handler `requisitos.ler` (versão antiga): devolve null e o painel segue normal. */
async function lerRequisitos(): Promise<Requisitos | null> {
  try {
    return await plugin.request('requisitos.ler')
  } catch (e) {
    if ((e as { code?: string }).code === 'unknown_method') return null
    throw e
  }
}

export async function instalarRequisito(id: 'orchestration'): Promise<void> {
  set(gravando, `req:${id}`)
  try {
    set(requisitos, await plugin.request('requisitos.instalar', { id })) // devolve os requisitos já lidos de novo
    update(avisos, (p) => ({ ...p, requisitos: { tom: 'success' as const, texto: t.salvo } }))
  } catch (e) {
    update(avisos, (p) => ({ ...p, requisitos: { tom: 'danger' as const, texto: (e as { message?: string }).message ?? String(e) } }))
  } finally {
    set(gravando, null)
  }
  await atualizar()
}

/** Com uma coleta em andamento, a chamada é descartada (set() é em lote: o átomo `carregando` não serve de guarda). */
export async function atualizar(): Promise<void> {
  if (coletando) return
  coletando = true
  set(carregando, true)
  try {
    const r = await lerRequisitos()
    set(requisitos, r)
    if (r && !r.ok) return set(erro, null) // faltou requisito: só a seção Requisitos, sem coletar o resto
    set(estado, await plugin.request('estado.ler'))
    set(erro, null)
  } catch (e) {
    const x = e as { code?: string; message?: string }
    set(erro, { code: x.code ?? 'erro', message: x.message ?? String(e) })
  } finally {
    coletando = false
    set(carregando, false)
  }
}

function posicaoPapel(p: string): number {
  const i = t.pool.ordemPapeis.indexOf(p)
  return i < 0 ? t.pool.ordemPapeis.length : i
}

export function setup(ctx: PanelContext): void {
  ctx.subscriptions.push(plugin.on('estado.mudou', () => void atualizar()))
  void storage.get(CHAVE_INTERVALO).then((v) => typeof v === 'number' && set(intervalo, v))
  void manterAtualizando(ctx.signal)
  void atualizar()
}

export async function salvarIntervalo(): Promise<void> {
  const aviso = (a: Aviso) => update(avisos, (p) => ({ ...p, painel: a }))
  const bruto = (read(edicoes)['painel.intervalo'] ?? String(read(intervalo))).trim()
  const n = Number(bruto)
  if (!/^\d+$/.test(bruto) || n < INTERVALO.min || n > INTERVALO.max) {
    return aviso({ tom: 'danger', texto: t.painel.invalido(INTERVALO.min, INTERVALO.max) })
  }
  try {
    await storage.set(CHAVE_INTERVALO, n)
    set(intervalo, n)
    update(edicoes, (p) => Object.fromEntries(Object.entries(p).filter(([c]) => c !== 'painel.intervalo')))
    aviso({ tom: 'success', texto: t.salvo })
  } catch (e) {
    aviso({ tom: 'danger', texto: (e as { message?: string }).message ?? String(e) })
  }
}

/** Grava as edições das `chaves` da seção (mais os `extras`); a recusa do validador volta como mensagem da seção. */
export async function salvar(secao: string, chaves: string[], extras: Record<string, string> = {}): Promise<boolean> {
  const todas = read(edicoes)
  const valores: Record<string, string> = { ...extras }
  for (const c of chaves) if (c in todas) valores[c] = todas[c]
  const aviso = (a: Aviso) => update(avisos, (p) => ({ ...p, [secao]: a }))
  if (Object.keys(valores).length === 0) {
    aviso({ tom: 'success', texto: t.nadaAlterado })
    return false
  }
  set(gravando, secao)
  try {
    set(estado, await plugin.request('config.gravar', { valores }))
    update(edicoes, (p) => Object.fromEntries(Object.entries(p).filter(([c]) => !(c in valores))))
    aviso({ tom: 'success', texto: t.salvo })
    return true
  } catch (e) {
    aviso({ tom: 'danger', texto: (e as { message?: string }).message ?? String(e) })
    return false
  } finally {
    set(gravando, null)
  }
}

const mudar = (chave: string, valor: string) => update(edicoes, (p) => ({ ...p, [chave]: valor }))

function Mensagem({ secao }: { secao: string }) {
  const a = read(avisos)[secao]
  return a ? <Text tone={a.tom === 'danger' ? 'danger' : 'success'}>{a.texto}</Text> : null
}

function Salvar({ secao, chaves }: { secao: string; chaves: string[] }) {
  const ocupado = read(gravando) !== null
  return (
    <Row gap="sm" align="center">
      <Button size="sm" icon="check" disabled={ocupado} onPress={() => void salvar(secao, chaves)}>
        {t.salvar}
      </Button>
      {read(gravando) === secao ? (
        <Text muted size="xs">
          {t.gravando}
        </Text>
      ) : null}
    </Row>
  )
}

/** Ícone de dica: no Orca 1.4.246 o `label` é o nome acessível e o tooltip (a prop `tooltip` só existe desde a 1.4.247). */
function Dica({ texto }: { texto: string }) {
  return <IconButton icon="info" label={texto} size="xs" variant="ghost" />
}

/** Campo com o ícone de dica ao lado: o mesmo padrão do modo da fila. */
function ComDica({ texto, children }: { texto: string; children: OrcaNode }) {
  return (
    <Row gap="xs" align="end">
      {children}
      <Dica texto={texto} />
    </Row>
  )
}

type Linha = { key: string; cells: Record<string, string | number>; detalhes: [string, string | number][] }
type Coluna = { key: string; label: string; align?: 'start' | 'center' | 'end'; width?: 'auto' | 'xs' | 'sm' | 'md' | 'lg'; minWidth?: 'auto' | 'xs' | 'sm' | 'md' }

/**
 * Table nativa que expande a linha: a selecionada ganha, logo abaixo, linhas de detalhe (desabilitadas) com o rótulo na
 * primeira coluna e o valor na segunda. `selectionMode="multiple"`: várias abertas, clicar de novo recolhe. Só leitura.
 */
function TabelaExpansivel(props: {
  label: string
  colunas: Coluna[]
  linhas: Linha[]
  abertas: string[]
  onAbrir: (keys: string[]) => void
}) {
  const [c0, c1] = props.colunas
  const rows: TableRow[] = props.linhas.flatMap((l) => [
    { key: l.key, cells: l.cells } as TableRow,
    ...(props.abertas.includes(l.key)
      ? l.detalhes.map(([rotulo, valor], i) => ({ key: `${l.key}#${i}`, disabled: true, cells: { [c0.key]: rotulo, [c1.key]: valor } }) as TableRow)
      : [])
  ])
  return (
    <Table
      label={props.label}
      columns={props.colunas}
      rows={rows}
      selectionMode="multiple"
      selected={props.abertas}
      onSelectionChange={({ keys }) => props.onAbrir(keys.filter((k) => !k.includes('#')))}
    />
  )
}

function Sobrescrito({ v }: { v: ValorFila }) {
  if (v.projetos.length === 0) return null
  return (
    <Text muted size="xs">
      {t.fila.sobrescrito(v.projetos.map((p) => `${p.projeto}: ${p.valor}`).join(', '))}
    </Text>
  )
}

const ITENS_FILA: ItemFila[] = ['modo', 'vagas', 'vagas_projeto', 'teto', 'processos']

function CampoModo({ e }: { e: Estado }) {
  const v = e.fila.config.modo
  const valor = read(edicoes)['fila.modo'] ?? String(v.valor)
  return (
    <Stack gap="xs">
      <Text weight="medium" size="sm">
        {t.fila.campos.modo}
      </Text>
      {(['global', 'projeto'] as const).map((m) => (
        <Row key={m} gap="xs" align="center">
          {/* Um RadioGroup de uma opção por linha (RadioOption não tem ícone): o valor marcado é o do estado, então só uma fica selecionada. */}
          <RadioGroup
            label={`${t.fila.campos.modo}: ${t.fila.modos[m]}`}
            labelHidden
            value={valor === m ? m : undefined}
            options={[{ value: m, label: t.fila.modos[m] }]}
            onChange={(x) => mudar('fila.modo', x)}
          />
          <Dica texto={t.fila.dicas[m]} />
        </Row>
      ))}
      <Sobrescrito v={v} />
    </Stack>
  )
}

function CampoFila({ item, e }: { item: Exclude<ItemFila, 'modo'>; e: Estado }) {
  const v = e.fila.config[item]
  const chave = `fila.${item}`
  const dica = item === 'vagas' || item === 'vagas_projeto' || item === 'teto' ? t.fila.dicas[item] : null
  return (
    <Stack gap="xs">
      <Row gap="xs" align="end">
        <Input label={t.fila.campos[item]} value={read(edicoes)[chave] ?? String(v.valor)} onChange={(x) => mudar(chave, x)} />
        {dica ? <Dica texto={dica} /> : null}
      </Row>
      <Sobrescrito v={v} />
    </Stack>
  )
}

function SecaoFila({ e }: { e: Estado }) {
  const { fila } = e
  const linhas: Linha[] = fila.travas.map((tr) => ({
    key: `${tr.fila}.${tr.vaga}`,
    cells: { fila: tr.fila, vaga: tr.vaga, viva: tr.viva ? t.fila.sim : t.fila.nao },
    detalhes: [
      [t.fila.worktree, tr.worktree ?? '-'],
      [t.fila.comando, tr.comando ?? '-'],
      [t.fila.pid, tr.pid ?? '-'],
      [t.fila.desde, tr.desde ?? '-']
    ]
  }))
  return (
    <Card title={t.fila.titulo} description={t.fila.resumo(t.fila.modos[fila.modo] ?? fila.modo, fila.vagas, fila.teto)}>
      {fila.travas.length === 0 ? (
        <Text muted>{t.fila.semTravas}</Text>
      ) : (
        <TabelaExpansivel
          label={t.fila.tabela}
          colunas={[
            { key: 'fila', label: t.fila.colFila, width: 'md' },
            { key: 'vaga', label: t.fila.colVaga },
            { key: 'viva', label: t.fila.colViva, width: 'xs' }
          ]}
          linhas={linhas}
          abertas={read(abertasTrava)}
          onAbrir={(k) => set(abertasTrava, k)}
        />
      )}
    </Card>
  )
}

const percentual = (v: number | null) => t.pool.percentual(v, (v ?? 0) > 80)

function SecaoPool({ e }: { e: Estado }) {
  const { pool } = e
  const linhas: Linha[] = pool.contas.map((c) => ({
    key: c.nome,
    cells: {
      conta: c.ativo ? c.nome : `${c.nome} (${t.pool.naoUtilizada})`,
      vagas: t.pool.vagasDaConta(c.usadas, c.vagas),
      h5: percentual(c.cota?.curta ?? null),
      semanal: percentual(c.cota?.longa ?? null)
    },
    detalhes: [
      ...(c.ativo ? [] : ([[t.pool.situacao, t.pool.naoUtilizadaDetalhe]] as [string, string][])),
      ...(c.rotulo ? ([[t.pool.rotulo, c.rotulo]] as [string, string][]) : []),
      [t.pool.agente, c.agente ?? '-'],
      [t.pool.peso, c.peso],
      [t.pool.papeis, c.papeis.join(', ') || '-'],
      [t.pool.janelas, c.cota ? c.cota.texto : t.pool.semMedida],
      [t.pool.medidaHa, c.cota ? t.pool.minutos(c.cota.medida_ha_min) : '-'],
      ...(c.cota && c.cota.fonte !== 'orca' && c.cota.medida_ha_min > 30 ? ([[t.pool.aviso, t.pool.medidaAntiga(c.cota.medida_ha_min)]] as [string, string][]) : []),
      [t.pool.vagasEmUso, c.ocupantes.map((o) => o.dispatch ?? '?').join(', ') || t.pool.nenhuma]
    ]
  }))
  return (
    <Card title={t.pool.titulo} description={t.pool.resumo(pool.maquina.usadas, pool.maquina.teto, pool.ram_min, pool.escolha)}>
      {pool.contas.length === 0 ? (
        <Text muted>{t.pool.semContas}</Text>
      ) : (
        <TabelaExpansivel
          label={t.pool.tabela}
          colunas={[
            { key: 'conta', label: t.pool.colConta, width: 'md' },
            { key: 'vagas', label: t.pool.colVagas },
            { key: 'h5', label: t.pool.col5h, align: 'end', width: 'xs' },
            { key: 'semanal', label: t.pool.colSemanal, align: 'end', width: 'sm', minWidth: 'sm' }
          ]}
          linhas={linhas}
          abertas={read(abertasConta)}
          onAbrir={(k) => set(abertasConta, k)}
        />
      )}
    </Card>
  )
}

/** Sobe ou desce uma conta: grava a lista completa das contas na ordem nova. */
function mover(contas: Conta[], nome: string, delta: -1 | 1): Promise<boolean> {
  const nomes = contas.map((c) => c.nome)
  const i = nomes.indexOf(nome)
  const j = i + delta
  if (i < 0 || j < 0 || j >= nomes.length) return Promise.resolve(false)
  ;[nomes[i], nomes[j]] = [nomes[j], nomes[i]]
  return salvar('ordem', [], { 'pool.ordem': nomes.join(',') })
}

/** Edição da conta escolhida: vagas, peso, config, papéis, ordem, "Não utilizar" e remover. */
function EdicaoConta({ c, e }: { c: Conta; e: Estado }) {
  const secao = `conta.${c.nome}`
  const chaveAtivo = `conta.${c.nome}.ativo`
  const chaveVagas = `conta.${c.nome}.vagas`
  const chavePeso = `conta.${c.nome}.peso`
  const chavePapeis = `conta.${c.nome}.papeis`
  const chaveConfig = `conta.${c.nome}.config`
  const ed = read(edicoes)
  const papeis = (ed[chavePapeis] ?? c.papeis.join(',')).split(',').filter(Boolean)
  const alterna = (p: string, marcado: boolean) =>
    mudar(chavePapeis, e.pool.papeis_validos.filter((x) => (x === p ? marcado : papeis.includes(x))).join(','))
  const noPool = e.pool.contas.map((x) => x.nome)
  const naoUtilizar = (ed[chaveAtivo] ?? (c.ativo ? 'sim' : 'nao')) === 'nao'
  const ocupado = read(gravando) !== null
  return (
    <Stack gap="sm">
      <Row gap="xs" align="center">
        <Text size="sm">{t.pool.ordemNaTabela}</Text>
        <IconButton icon="collapse" label={t.pool.subir} size="xs" variant="ghost" disabled={ocupado || noPool[0] === c.nome} onPress={() => void mover(e.pool.contas, c.nome, -1)} />
        <IconButton icon="expand" label={t.pool.descer} size="xs" variant="ghost" disabled={ocupado || noPool[noPool.length - 1] === c.nome} onPress={() => void mover(e.pool.contas, c.nome, 1)} />
      </Row>
      <ComDica texto={t.pool.dicas.vagas}>
        <Input label={t.pool.vagas} value={ed[chaveVagas] ?? String(c.vagas)} onChange={(x) => mudar(chaveVagas, x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.peso}>
        <Input label={t.pool.pesoDaConta} value={ed[chavePeso] ?? String(c.peso)} onChange={(x) => mudar(chavePeso, x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.config}>
        <Input label={t.pool.config} value={ed[chaveConfig] ?? c.config ?? ''} onChange={(x) => mudar(chaveConfig, x)} />
      </ComDica>
      <Row gap="xs" align="center">
        <Checkbox label={t.pool.naoUtilizar} checked={naoUtilizar} onChange={(m) => mudar(chaveAtivo, m ? 'nao' : 'sim')} />
        <Dica texto={t.pool.dicas.naoUtilizar} />
      </Row>
      <Stack gap="xs">
        <Text weight="medium" size="sm">
          {t.pool.papeis}
        </Text>
        {[...e.pool.papeis_validos].sort((a, b) => posicaoPapel(a) - posicaoPapel(b)).map((p) => (
          <Row key={p} gap="xs" align="center">
            <Checkbox label={t.pool.nomesPapel[p] ?? p} checked={papeis.includes(p)} onChange={(m) => alterna(p, m)} />
            <Dica texto={t.pool.dicasPapel[p] ?? p} />
          </Row>
        ))}
      </Stack>
      <Mensagem secao={secao} />
      <Salvar secao={secao} chaves={[chaveVagas, chavePeso, chavePapeis, chaveConfig, chaveAtivo]} />
      {read(removendo) === c.nome ? (
        <Stack gap="xs">
          <Text tone="warning">{t.pool.confirmarRemocao(c.nome)}</Text>
          <Row gap="sm">
            <Button
              size="sm"
              tone="danger"
              icon="delete"
              onPress={() => {
                set(removendo, null)
                set(contaEscolhida, null)
                void salvar(secao, [], { [`conta.${c.nome}.remover`]: '1' })
              }}
            >
              {t.pool.confirmar}
            </Button>
            <Button size="sm" variant="ghost" onPress={() => set(removendo, null)}>
              {t.pool.cancelar}
            </Button>
          </Row>
        </Stack>
      ) : (
        <Button size="sm" variant="outline" tone="danger" icon="delete" onPress={() => set(removendo, c.nome)}>
          {t.pool.remover}
        </Button>
      )}
    </Stack>
  )
}

function NovaConta() {
  const ed = read(edicoes)
  const nome = ed['nova.nome'] ?? ''
  const comando = (ed['nova.comando'] ?? '').trim()
  const config = (ed['nova.config'] ?? '').trim()
  const criar = async () => {
    const extras: Record<string, string> = { [`conta.${nome}.adicionar`]: 'auto' }
    if (config) extras[`conta.${nome}.config`] = config
    if (comando) extras[`conta.${nome}.comando`] = comando
    if (await salvar('nova', [], extras)) update(edicoes, (p) => Object.fromEntries(Object.entries(p).filter(([k]) => !k.startsWith('nova.'))))
  }
  return (
    <Stack gap="sm">
      <Text weight="medium">{t.pool.nova}</Text>
      <Input label={t.pool.novaNome} value={nome} onChange={(x) => mudar('nova.nome', x)} />
      <ComDica texto={t.pool.dicas.novoComando}>
        <Input label={t.pool.comandoCli} value={ed['nova.comando'] ?? ''} onChange={(x) => mudar('nova.comando', x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.novoConfig}>
        <Input label={t.pool.novaConfig} value={ed['nova.config'] ?? ''} onChange={(x) => mudar('nova.config', x)} />
      </ComDica>
      <Mensagem secao="nova" />
      <Button size="sm" icon="add" disabled={read(gravando) !== null || !nome.trim() || (!comando && !config)} onPress={() => void criar()}>
        {t.pool.novaCriar}
      </Button>
    </Stack>
  )
}

function ConfigFila({ e }: { e: Estado }) {
  return (
    <Stack gap="sm">
      <Text muted size="xs">
        {t.configuracoes.linhas.fila}
      </Text>
      <Text muted size="xs">
        {t.fila.configurarDescricao}
      </Text>
      <CampoModo e={e} />
      {(['vagas', 'vagas_projeto', 'teto', 'processos'] as const).map((i) => (
        <CampoFila key={i} item={i} e={e} />
      ))}
      <Mensagem secao="fila" />
      <Salvar secao="fila" chaves={ITENS_FILA.map((i) => `fila.${i}`)} />
    </Stack>
  )
}

function ConfigPool({ e }: { e: Estado }) {
  const { pool } = e
  const ed = read(edicoes)
  return (
    <Stack gap="sm">
      <Text muted size="xs">
        {t.configuracoes.linhas.pool}
      </Text>
      <ComDica texto={t.pool.dicas.teto}>
        <Input label={t.pool.teto} value={ed['pool.teto'] ?? String(pool.teto)} onChange={(x) => mudar('pool.teto', x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.ramMin}>
        <Input label={t.pool.ramMin} value={ed['pool.ram_min'] ?? String(pool.ram_min)} onChange={(x) => mudar('pool.ram_min', x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.escolha}>
        <Select
          label={t.pool.escolha}
          value={ed['pool.escolha'] ?? pool.escolha}
          options={[{ value: 'ritmo', label: t.pool.escolhaOpcoes.ritmo }, { value: 'ordem', label: t.pool.escolhaOpcoes.ordem }]}
          onChange={(x) => mudar('pool.escolha', x)}
        />
      </ComDica>
      <Mensagem secao="pool" />
      <Salvar secao="pool" chaves={['pool.teto', 'pool.ram_min', 'pool.escolha']} />
    </Stack>
  )
}

function ConfigContas({ e }: { e: Estado }) {
  const { pool } = e
  const escolhida = read(contaEscolhida)
  const conta = pool.contas.find((c) => c.nome === escolhida) ?? pool.contas[0]
  return (
    <Stack gap="sm">
      <Text muted size="xs">
        {t.configuracoes.linhas.contas}
      </Text>
      {conta ? (
        <Stack gap="sm">
          <Select
            label={t.pool.escolherConta}
            value={conta.nome}
            options={pool.contas.map((c) => ({ value: c.nome, label: c.ativo ? c.nome : `${c.nome} (${t.pool.naoUtilizada})` }))}
            onChange={(x) => {
              set(removendo, null)
              set(contaEscolhida, x)
            }}
          />
          <EdicaoConta key={conta.nome} c={conta} e={e} />
        </Stack>
      ) : null}
      <NovaConta />
    </Stack>
  )
}

function ConfigPainel() {
  return (
    <Stack gap="sm">
      <Text muted size="xs">
        {t.configuracoes.linhas.painel}
      </Text>
      <ComDica texto={t.painel.dica}>
        <Input label={t.painel.intervalo} value={read(edicoes)['painel.intervalo'] ?? String(read(intervalo))} onChange={(x) => mudar('painel.intervalo', x)} />
      </ComDica>
      <Mensagem secao="painel" />
      <Button size="sm" icon="check" onPress={() => void salvarIntervalo()}>
        {t.salvar}
      </Button>
    </Stack>
  )
}

function SecaoConfiguracoes({ e }: { e: Estado }) {
  const abas = [
    { id: 'fila', corpo: <ConfigFila e={e} /> },
    { id: 'pool', corpo: <ConfigPool e={e} /> },
    { id: 'contas', corpo: <ConfigContas e={e} /> },
    { id: 'painel', corpo: <ConfigPainel /> }
  ] as const
  return (
    <Collapsible title={t.configuracoes.titulo} description={t.configuracoes.descricao}>
      {ui.has('Tabs') ? (
        <Tabs label={t.configuracoes.assuntos} defaultValue="fila">
          {abas.map((a) => (
            <Tab key={a.id} value={a.id} label={t.configuracoes.abas[a.id]}>
              {a.corpo}
            </Tab>
          ))}
        </Tabs>
      ) : (
        <Stack gap="sm">
          {abas.map((a) => (
            <Collapsible key={a.id} title={t.configuracoes.abas[a.id]}>
              {a.corpo}
            </Collapsible>
          ))}
        </Stack>
      )}
    </Collapsible>
  )
}

function SecaoRequisitos({ r }: { r: Requisitos }) {
  const linhas: TableRow[] = r.itens.map((i) => ({ key: i.id, cells: { requisito: i.nome, situacao: i.ok ? t.requisitos.ok : t.requisitos.falta } }))
  return (
    <Card title={t.requisitos.titulo} description={t.requisitos.explica}>
      <Table
        label={t.requisitos.tabela}
        columns={[
          { key: 'requisito', label: t.requisitos.colRequisito, width: 'lg' },
          { key: 'situacao', label: t.requisitos.colSituacao, width: 'sm' }
        ]}
        rows={linhas}
      />
      {r.itens
        .filter((i) => !i.ok)
        .map((i) => (
          <Stack key={i.id} gap="xs">
            <Text weight="medium">{i.nome}</Text>
            <Text muted size="xs">
              {i.detalhe}
            </Text>
            {i.instalar?.tipo === 'acao' ? (
              <Button size="sm" icon="download" disabled={read(gravando) !== null} onPress={() => void instalarRequisito(i.id as 'orchestration')}>
                {read(gravando) === `req:${i.id}` ? t.requisitos.instalando : t.requisitos.instalar}
              </Button>
            ) : null}
            {i.instalar?.tipo === 'comando' ? (
              <Stack gap="xs">
                <Text size="xs">{t.requisitos.copiavel}</Text>
                <Code block>{i.instalar.texto}</Code>
              </Stack>
            ) : null}
          </Stack>
        ))}
      <Mensagem secao="requisitos" />
    </Card>
  )
}

export default function Painel() {
  const e = read(estado)
  const x = read(erro)
  const r = read(requisitos)
  return (
    <Stack gap="md">
      <Row justify="between" align="center">
        <Heading>{t.titulo}</Heading>
        <Button icon="refresh" size="sm" disabled={read(carregando)} onPress={() => void atualizar()}>
          {t.atualizar}
        </Button>
      </Row>
      {x ? (
        <Stack gap="xs">
          <Text tone="danger" weight="medium">
            {t.coletorFalhou(x.code)}
          </Text>
          <Text tone="danger">{x.message}</Text>
        </Stack>
      ) : null}
      {r && !r.ok ? (
        <SecaoRequisitos r={r} />
      ) : e === null ? (
        x ? (
          <EmptyState title={t.semDados} description={t.coletorNaoRespondeu} icon="warning" />
        ) : (
          <Spinner label={t.carregando} />
        )
      ) : (
        <Stack gap="md">
          <Text muted size="xs">
            {t.atualizadoEm} <RelativeTime at={Date.parse(e.gerado_em)} />
            {` · ${t.dicaLinha}`}
          </Text>
          {e.aviso ? <Text tone="warning">{e.aviso}</Text> : null}
          {e.saude.scripts_desatualizados.length > 0 ? (
            <Text tone="warning">{`${t.scriptsDesatualizados}: ${e.saude.scripts_desatualizados.join(', ')}`}</Text>
          ) : null}
          <Text size="xs" muted>
            {`${t.plugin} ${e.saude.plugin_versao ?? '?'} · ${t.orca} ${e.saude.orca.rodando ? (e.saude.orca.versao ?? t.orcaRodando) : t.orcaForaDoAr}`}
          </Text>
          <SecaoFila e={e} />
          <SecaoPool e={e} />
          <SecaoConfiguracoes e={e} />
        </Stack>
      )}
    </Stack>
  )
}
