// Painel de fila de testes e pool de agentes. O estado e a gravação passam pelo worker (src/protocol.ts); textos em src/textos.ts.
import {
  atom,
  Button,
  Callout,
  Card,
  Checkbox,
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
  Skeleton,
  Stack,
  Table,
  Text,
  update,
  type PanelContext,
  type TableRow
} from 'orca'
import type { Conta, Estado, ItemFila, ValorFila } from './protocol'
import { t } from './textos'

type Erro = { code: string; message: string }
type Aviso = { tom: 'success' | 'danger'; texto: string }

const estado = atom<Estado | null>(null)
const erro = atom<Erro | null>(null)
const carregando = atom(false)
/** Só o que a pessoa digitou e ainda não gravou, por chave do `painel.sh --config` (ex.: `conta.pessoal.vagas`). */
const edicoes = atom<Record<string, string>>({})
const avisos = atom<Record<string, Aviso>>({})
const gravando = atom<string | null>(null)
/** Conta com o pedido de remoção aguardando confirmação. */
const removendo = atom<string | null>(null)
/** Linha aberta de cada tabela (a selecionada mostra os detalhes logo abaixo). */
const abertaTrava = atom<string | null>(null)
const abertaConta = atom<string | null>(null)

export async function atualizar(): Promise<void> {
  if (read(carregando)) return
  set(carregando, true)
  try {
    set(estado, await plugin.request('estado.ler'))
    set(erro, null)
  } catch (e) {
    const x = e as { code?: string; message?: string }
    set(erro, { code: x.code ?? 'erro', message: x.message ?? String(e) })
  } finally {
    set(carregando, false)
  }
}

export function setup(ctx: PanelContext): void {
  ctx.subscriptions.push(plugin.on('estado.mudou', () => void atualizar()))
  void atualizar()
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
  return a ? <Callout tone={a.tom === 'danger' ? 'danger' : 'success'}>{a.texto}</Callout> : null
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

type LinhaExpansivel = { key: string; cells: Record<string, string | number>; detalhes: [string, string | number][] }

/**
 * Table não expande linha: a selecionada ganha, logo abaixo, linhas de detalhe (desabilitadas) com o rótulo na
 * primeira coluna e o valor na segunda. Clicar de novo na linha aberta a recolhe.
 */
function TabelaExpansivel(props: {
  label: string
  colunas: { key: string; label: string; align?: 'start' | 'center' | 'end'; width?: 'auto' | 'xs' | 'sm' | 'md' | 'lg'; minWidth?: 'auto' | 'xs' | 'sm' | 'md' }[]
  linhas: LinhaExpansivel[]
  aberta: string | null
  onAbrir: (key: string | null) => void
}) {
  const [c0, c1] = props.colunas
  const rows: TableRow[] = props.linhas.flatMap((l) => [
    { key: l.key, cells: l.cells } as TableRow,
    ...(l.key === props.aberta
      ? l.detalhes.map(([rotulo, valor], i) => ({ key: `${l.key}#${i}`, disabled: true, cells: { [c0.key]: rotulo, [c1.key]: valor } }) as TableRow)
      : [])
  ])
  return (
    <Table
      label={props.label}
      columns={props.colunas}
      rows={rows}
      selectionMode="single"
      selected={props.aberta ? [props.aberta] : []}
      onSelectionChange={({ keys }) => props.onAbrir(keys.find((k) => !k.includes('#')) ?? null)}
    />
  )
}

const ORIGEM = t.fila.origens

function Origem({ v }: { v: ValorFila }) {
  const sobrescritas = v.projetos.map((p) => `${p.projeto}: ${p.valor}`).join(', ')
  return (
    <Text muted size="xs">
      {t.fila.origem(ORIGEM[v.origem], sobrescritas)}
    </Text>
  )
}

const ITENS_FILA: ItemFila[] = ['modo', 'vagas', 'vagas_projeto', 'teto', 'processos']

function CampoModo({ e }: { e: Estado }) {
  const v = e.fila.config.modo
  const valor = read(edicoes)['fila.modo'] ?? String(v.valor)
  return (
    <Stack gap="xs">
      <RadioGroup
        label={t.fila.campos.modo}
        value={valor}
        options={[
          { value: 'global', label: t.fila.modos.global },
          { value: 'projeto', label: t.fila.modos.projeto }
        ]}
        onChange={(x) => mudar('fila.modo', x)}
      />
      {(['global', 'projeto'] as const).map((m) => (
        <Row key={m} gap="xs" align="center">
          <Text size="xs" muted>
            {t.fila.modos[m]}
          </Text>
          <Dica texto={t.fila.dicas[m]} />
        </Row>
      ))}
      <Origem v={v} />
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
      <Origem v={v} />
    </Stack>
  )
}

function SecaoFila({ e }: { e: Estado }) {
  const { fila } = e
  const linhas: LinhaExpansivel[] = fila.travas.map((tr) => ({
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
          aberta={read(abertaTrava)}
          onAbrir={(k) => set(abertaTrava, k)}
        />
      )}
      <Collapsible title={t.fila.configurar} description={t.fila.configurarDescricao}>
        <Stack gap="sm">
          <CampoModo e={e} />
          {(['vagas', 'vagas_projeto', 'teto', 'processos'] as const).map((i) => (
            <CampoFila key={i} item={i} e={e} />
          ))}
          <Mensagem secao="fila" />
          <Salvar secao="fila" chaves={ITENS_FILA.map((i) => `fila.${i}`)} />
        </Stack>
      </Collapsible>
    </Card>
  )
}

function origemDaConta(c: Conta): string {
  if (c.origem === 'orca') return t.pool.origemOrca
  return c.detectada ? t.pool.origemManualOrca : t.pool.origemManual
}

/** Edição e ações da conta aberta: o que uma célula de tabela não comporta. */
function EdicaoConta({ c, e }: { c: Conta; e: Estado }) {
  const secao = `conta.${c.nome}`
  if (c.origem === 'orca') {
    return (
      <Card title={t.pool.editar(c.nome)}>
        <Stack gap="sm">
          <Mensagem secao={secao} />
          <Button size="sm" icon="add" disabled={read(gravando) !== null} onPress={() => void salvar(secao, [], { [`conta.${c.nome}.adicionar`]: c.agente ?? '' })}>
            {t.pool.adicionar}
          </Button>
        </Stack>
      </Card>
    )
  }
  const chaveVagas = `conta.${c.nome}.vagas`
  const chavePeso = `conta.${c.nome}.peso`
  const chavePapeis = `conta.${c.nome}.papeis`
  const chaveConfig = `conta.${c.nome}.config`
  const ed = read(edicoes)
  const papeis = (ed[chavePapeis] ?? c.papeis.join(',')).split(',').filter(Boolean)
  const alterna = (p: string, marcado: boolean) =>
    mudar(chavePapeis, e.pool.papeis_validos.filter((x) => (x === p ? marcado : papeis.includes(x))).join(','))
  return (
    <Card title={t.pool.editar(c.nome)}>
      <Stack gap="sm">
        <Input label={t.pool.vagas} value={ed[chaveVagas] ?? String(c.vagas)} onChange={(x) => mudar(chaveVagas, x)} />
        <Input label={t.pool.peso} value={ed[chavePeso] ?? String(c.peso)} onChange={(x) => mudar(chavePeso, x)} />
        <Input label={t.pool.config} value={ed[chaveConfig] ?? c.config ?? ''} onChange={(x) => mudar(chaveConfig, x)} />
        <Stack gap="xs">
          <Text weight="medium" size="sm">
            {t.pool.papeis}
          </Text>
          {e.pool.papeis_validos.map((p) => (
            <Checkbox key={p} label={p} checked={papeis.includes(p)} onChange={(m) => alterna(p, m)} />
          ))}
        </Stack>
        <Mensagem secao={secao} />
        <Salvar secao={secao} chaves={[chaveVagas, chavePeso, chavePapeis, chaveConfig]} />
        {read(removendo) === c.nome ? (
          <Callout tone="warning" title={t.pool.confirmarRemocao(c.nome)}>
            <Row gap="sm">
              <Button
                size="sm"
                tone="danger"
                icon="delete"
                onPress={() => {
                  set(removendo, null)
                  set(abertaConta, null)
                  void salvar(secao, [], { [`conta.${c.nome}.remover`]: '1' })
                }}
              >
                {t.pool.confirmar}
              </Button>
              <Button size="sm" variant="ghost" onPress={() => set(removendo, null)}>
                {t.pool.cancelar}
              </Button>
            </Row>
          </Callout>
        ) : (
          <Button size="sm" variant="outline" tone="danger" icon="delete" onPress={() => set(removendo, c.nome)}>
            {t.pool.remover}
          </Button>
        )}
      </Stack>
    </Card>
  )
}

function NovaConta({ e }: { e: Estado }) {
  const ed = read(edicoes)
  const nome = ed['nova.nome'] ?? ''
  const agente = ed['nova.agente'] ?? ''
  const criar = async () => {
    const extras: Record<string, string> = { [`conta.${nome}.adicionar`]: agente }
    if (ed['nova.config']) extras[`conta.${nome}.config`] = ed['nova.config']
    if (ed['nova.comando']) extras[`conta.${nome}.comando`] = ed['nova.comando']
    if (await salvar('nova', [], extras)) update(edicoes, (p) => Object.fromEntries(Object.entries(p).filter(([k]) => !k.startsWith('nova.'))))
  }
  return (
    <Collapsible title={t.pool.nova}>
      <Stack gap="sm">
        <Input label={t.pool.novaNome} value={nome} onChange={(x) => mudar('nova.nome', x)} />
        <Select
          label={t.pool.novaAgente}
          value={agente || undefined}
          placeholder={t.pool.novaAgentePlaceholder}
          options={e.pool.catalogo.map((a) => ({ value: a, label: a }))}
          onChange={(x) => mudar('nova.agente', x)}
        />
        <Input label={t.pool.config} value={ed['nova.config'] ?? ''} onChange={(x) => mudar('nova.config', x)} />
        <Input label={t.pool.comando} value={ed['nova.comando'] ?? ''} onChange={(x) => mudar('nova.comando', x)} />
        <Mensagem secao="nova" />
        <Button size="sm" icon="add" disabled={read(gravando) !== null || !nome || !agente} onPress={() => void criar()}>
          {t.pool.novaCriar}
        </Button>
      </Stack>
    </Collapsible>
  )
}

function SecaoPool({ e }: { e: Estado }) {
  const { pool } = e
  const ed = read(edicoes)
  const aberta = read(abertaConta)
  const conta = pool.contas.find((c) => c.nome === aberta)
  const linhas: LinhaExpansivel[] = pool.contas.map((c) => ({
    key: c.nome,
    cells: {
      conta: c.nome,
      vagas: c.origem === 'orca' ? t.pool.foraDoPool : t.pool.vagasDaConta(c.usadas, c.vagas),
      h5: t.pool.percentual(c.cota?.curta ?? null, (c.cota?.curta ?? 0) > 80),
      semanal: t.pool.percentual(c.cota?.longa ?? null, (c.cota?.longa ?? 0) > 80)
    },
    detalhes: [
      [t.pool.origem, origemDaConta(c)],
      ...(c.rotulo ? ([[t.pool.rotulo, c.rotulo]] as [string, string][]) : []),
      [t.pool.agente, c.agente ?? '-'],
      [t.pool.peso, c.peso],
      [t.pool.papeis, c.papeis.join(', ') || '-'],
      [t.pool.janelas, c.cota ? c.cota.texto : t.pool.semMedida],
      [t.pool.medidaHa, c.cota ? t.pool.minutos(c.cota.medida_ha_min) : '-'],
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
          aberta={aberta}
          onAbrir={(k) => set(abertaConta, k)}
        />
      )}
      {conta ? <EdicaoConta c={conta} e={e} /> : null}
      <NovaConta e={e} />
      <Collapsible title={t.pool.configurar}>
        <Stack gap="sm">
          <Input label={t.pool.teto} value={ed['pool.teto'] ?? String(pool.teto)} onChange={(x) => mudar('pool.teto', x)} />
          <Input label={t.pool.ramMin} value={ed['pool.ram_min'] ?? String(pool.ram_min)} onChange={(x) => mudar('pool.ram_min', x)} />
          <Select
            label={t.pool.escolha}
            value={ed['pool.escolha'] ?? pool.escolha}
            options={[{ value: 'ritmo', label: 'ritmo' }, { value: 'ordem', label: 'ordem' }]}
            onChange={(x) => mudar('pool.escolha', x)}
          />
          <Mensagem secao="pool" />
          <Salvar secao="pool" chaves={['pool.teto', 'pool.ram_min', 'pool.escolha']} />
        </Stack>
      </Collapsible>
    </Card>
  )
}

export default function Painel() {
  const e = read(estado)
  const x = read(erro)
  return (
    <Stack gap="md">
      <Row justify="between" align="center">
        <Heading>{t.titulo}</Heading>
        <Button icon="refresh" size="sm" disabled={read(carregando)} onPress={() => void atualizar()}>
          {t.atualizar}
        </Button>
      </Row>
      {x ? (
        <Callout tone="danger" title={t.coletorFalhou(x.code)}>
          {x.message}
        </Callout>
      ) : null}
      {e === null ? (
        x ? (
          <EmptyState title={t.semDados} description={t.coletorNaoRespondeu} icon="warning" />
        ) : (
          <Skeleton shape="block" lines={4} label={t.carregando} />
        )
      ) : (
        <Stack gap="md">
          <Text muted size="xs">
            {t.atualizadoEm} <RelativeTime at={Date.parse(e.gerado_em)} />
            {` · ${t.dicaLinha}`}
          </Text>
          {e.aviso ? <Callout tone="warning">{e.aviso}</Callout> : null}
          {e.saude.scripts_desatualizados.length > 0 ? (
            <Callout tone="warning" title={t.scriptsDesatualizados}>
              {e.saude.scripts_desatualizados.join(', ')}
            </Callout>
          ) : null}
          <Text size="xs" muted>
            {`${t.plugin} ${e.saude.plugin_versao ?? '?'} · ${t.orca} ${e.saude.orca.rodando ? (e.saude.orca.versao ?? t.orcaRodando) : t.orcaForaDoAr}`}
          </Text>
          <SecaoFila e={e} />
          <SecaoPool e={e} />
        </Stack>
      )}
    </Stack>
  )
}
