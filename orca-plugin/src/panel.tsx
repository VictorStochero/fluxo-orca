// Painel de fila de testes e pool de agentes. O estado e a gravação passam pelo worker (src/protocol.ts); textos em src/textos.ts.
import {
  atom,
  Button,
  Callout,
  Card,
  Checkbox,
  Collapsible,
  EmptyState,
  Grid,
  Heading,
  IconButton,
  Input,
  KeyValue,
  List,
  ListItem,
  plugin,
  RadioGroup,
  read,
  RelativeTime,
  Row,
  Select,
  set,
  storage,
  Skeleton,
  Stack,
  Text,
  update,
  type OrcaNode,
  type PanelContext
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
/** Intervalo da atualização automática: o worker lê esta chave do storage e reprograma sozinho. */
const CHAVE_INTERVALO = 'atualizacao.intervalo_s'
const INTERVALO = { padrao: 60, min: 15, max: 3600 }
const intervalo = atom(INTERVALO.padrao)

/** Linhas abertas de cada lista (várias ao mesmo tempo; clicar de novo recolhe). */
const abertasTrava = atom<string[]>([])
const abertasConta = atom<string[]>([])

/** Com uma coleta em andamento, a chamada é descartada. */
let coletando = false

export async function atualizar(): Promise<void> {
  if (coletando) return // set() é em lote: o átomo `carregando` não serve de guarda entre duas chamadas seguidas
  coletando = true
  set(carregando, true)
  try {
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

export function setup(ctx: PanelContext): void {
  ctx.subscriptions.push(plugin.on('estado.mudou', () => void atualizar()))
  void storage.get(CHAVE_INTERVALO).then((v) => typeof v === 'number' && set(intervalo, v))
  // Entra no merge com o branch painel-auto: import { manterAtualizando } from './atualizacao'; void manterAtualizando(ctx.signal)
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
const alternar = (lista: typeof abertasConta, chave: string) =>
  update(lista, (a) => (a.includes(chave) ? a.filter((x) => x !== chave) : [...a, chave]))

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

/** Campo com o ícone de dica ao lado: o mesmo padrão do modo da fila. */
function ComDica({ texto, children }: { texto: string; children: OrcaNode }) {
  return (
    <Row gap="xs" align="end">
      {children}
      <Dica texto={texto} />
    </Row>
  )
}

type Celula = { texto: string; tom?: 'warning' }
type Colunas = 3 | 4

function Cabecalho({ rotulos }: { rotulos: string[] }) {
  return (
    <Grid columns={rotulos.length as Colunas} gap="xs">
      {rotulos.map((r) => (
        <Text key={r} muted size="xs" weight="medium">
          {r.toUpperCase()}
        </Text>
      ))}
    </Grid>
  )
}

/**
 * Linha de tabela montada com layout (célula de Table não comporta controle): a linha inteira é um ListItem
 * (clicável e acessível por teclado) e o bloco expandido fica logo abaixo, no mesmo contêiner.
 */
function LinhaExpansivel(props: { celulas: Celula[]; aberta: boolean; onAlternar: () => void; acoes?: OrcaNode; children: OrcaNode }) {
  return (
    <Stack gap="xs">
      <Row gap="xs" align="center">
      <List label={props.celulas[0].texto}>
        <ListItem current={props.aberta} onPress={props.onAlternar}>
          <Grid columns={props.celulas.length as Colunas} gap="xs">
            {props.celulas.map((c, i) => (
              <Text key={i} tone={c.tom} weight={i === 0 ? 'medium' : 'regular'}>
                {c.texto}
              </Text>
            ))}
          </Grid>
        </ListItem>
      </List>
      {props.acoes}
      </Row>
      {props.aberta ? <Stack gap="sm">{props.children}</Stack> : null}
    </Stack>
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

/** Campos da fila: vale para a fila inteira, não para uma trava. */
function ConfigFila({ e }: { e: Estado }) {
  return (
    <Stack gap="sm">
      <Heading level={3}>{t.configuracoes.fila}</Heading>
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

function SecaoFila({ e }: { e: Estado }) {
  const { fila } = e
  const abertas = read(abertasTrava)
  return (
    <Card title={t.fila.titulo} description={t.fila.resumo(t.fila.modos[fila.modo] ?? fila.modo, fila.vagas, fila.teto)}>
      {fila.travas.length === 0 ? (
        <Text muted>{t.fila.semTravas}</Text>
      ) : (
        <Stack gap="xs">
          <Cabecalho rotulos={[t.fila.colFila, t.fila.colVaga, t.fila.colViva]} />
          {fila.travas.map((tr) => {
            const chave = `${tr.fila}.${tr.vaga}`
            return (
              <LinhaExpansivel
                key={chave}
                celulas={[{ texto: tr.fila }, { texto: String(tr.vaga) }, { texto: tr.viva ? t.fila.sim : t.fila.nao }]}
                aberta={abertas.includes(chave)}
                onAlternar={() => alternar(abertasTrava, chave)}
              >
                <KeyValue
                  items={[
                    { label: t.fila.worktree, value: tr.worktree ?? '-', code: true },
                    { label: t.fila.comando, value: tr.comando ?? '-', code: true },
                    { label: t.fila.pid, value: tr.pid ?? '-' },
                    { label: t.fila.desde, value: tr.desde ?? '-' }
                  ]}
                />
              </LinhaExpansivel>
            )
          })}
        </Stack>
      )}
    </Card>
  )
}

/** Detalhes e configuração da conta, dentro do espaço expandido da própria linha. */
function BlocoConta({ c, e }: { c: Conta; e: Estado }) {
  const secao = `conta.${c.nome}`
  const detalhes = (
    <KeyValue
      items={[
        ...(c.rotulo ? [{ label: t.pool.rotulo, value: c.rotulo }] : []),
        { label: t.pool.agente, value: c.agente ?? '-' },
        { label: t.pool.peso, value: c.peso },
        { label: t.pool.papeis, value: c.papeis.join(', ') || '-' },
        { label: t.pool.janelas, value: c.cota ? c.cota.texto : t.pool.semMedida },
        { label: t.pool.medidaHa, value: c.cota ? t.pool.minutos(c.cota.medida_ha_min) : '-' },
        { label: t.pool.vagasEmUso, value: c.ocupantes.map((o) => o.dispatch ?? '?').join(', ') || t.pool.nenhuma }
      ]}
    />
  )
  // A cota nativa do Orca é viva; a medida das contas manuais depende do medidor local.
  const antiga = c.cota && c.cota.fonte !== 'orca' && c.cota.medida_ha_min > 30 ? <Callout tone="warning">{t.pool.medidaAntiga(c.cota.medida_ha_min)}</Callout> : null
  if (c.origem === 'orca') {
    return (
      <>
        {detalhes}
        {antiga}
        <Mensagem secao={secao} />
        <Button size="sm" icon="add" disabled={read(gravando) !== null} onPress={() => void salvar(secao, [], { [`conta.${c.nome}.adicionar`]: c.agente ?? '' })}>
          {t.pool.adicionar}
        </Button>
      </>
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
    <>
      {detalhes}
      {antiga}
      <ComDica texto={t.pool.dicas.vagas}>
        <Input label={t.pool.vagas} value={ed[chaveVagas] ?? String(c.vagas)} onChange={(x) => mudar(chaveVagas, x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.peso}>
        <Input label={t.pool.peso} value={ed[chavePeso] ?? String(c.peso)} onChange={(x) => mudar(chavePeso, x)} />
      </ComDica>
      <ComDica texto={t.pool.dicas.config}>
        <Input label={t.pool.config} value={ed[chaveConfig] ?? c.config ?? ''} onChange={(x) => mudar(chaveConfig, x)} />
      </ComDica>
      <Stack gap="xs">
        <Text weight="medium" size="sm">
          {t.pool.papeis}
        </Text>
        {e.pool.papeis_validos.map((p) => (
          <Row key={p} gap="xs" align="center">
            <Checkbox label={p} checked={papeis.includes(p)} onChange={(m) => alterna(p, m)} />
            <Dica texto={t.pool.dicasPapel[p] ?? p} />
          </Row>
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
                update(abertasConta, (a) => a.filter((x) => x !== c.nome))
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
    </>
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
        <ComDica texto={t.pool.dicas.agente}>
          <Select
            label={t.pool.novaAgente}
            value={agente || undefined}
            placeholder={t.pool.novaAgentePlaceholder}
            options={e.pool.catalogo.map((a) => ({ value: a, label: a }))}
            onChange={(x) => mudar('nova.agente', x)}
          />
        </ComDica>
        <ComDica texto={t.pool.dicas.config}>
          <Input label={t.pool.config} value={ed['nova.config'] ?? ''} onChange={(x) => mudar('nova.config', x)} />
        </ComDica>
        <ComDica texto={t.pool.dicas.comando}>
          <Input label={t.pool.comando} value={ed['nova.comando'] ?? ''} onChange={(x) => mudar('nova.comando', x)} />
        </ComDica>
        <Mensagem secao="nova" />
        <Button size="sm" icon="add" disabled={read(gravando) !== null || !nome || !agente} onPress={() => void criar()}>
          {t.pool.novaCriar}
        </Button>
      </Stack>
    </Collapsible>
  )
}

const percentual = (v: number | null): Celula => ({ texto: t.pool.percentual(v, (v ?? 0) > 80), tom: (v ?? 0) > 80 ? 'warning' : undefined })

function ConfigPool({ e }: { e: Estado }) {
  const { pool } = e
  const ed = read(edicoes)
  return (
    <Stack gap="sm">
      <Heading level={3}>{t.configuracoes.pool}</Heading>
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
          options={[{ value: 'ritmo', label: 'ritmo' }, { value: 'ordem', label: 'ordem' }]}
          onChange={(x) => mudar('pool.escolha', x)}
        />
      </ComDica>
      <Mensagem secao="pool" />
      <Salvar secao="pool" chaves={['pool.teto', 'pool.ram_min', 'pool.escolha']} />
      <NovaConta e={e} />
    </Stack>
  )
}

function ConfigPainel() {
  return (
    <Stack gap="sm">
      <Heading level={3}>{t.configuracoes.painel}</Heading>
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
  return (
    <Card title={t.configuracoes.titulo}>
      <ConfigFila e={e} />
      <ConfigPool e={e} />
      <ConfigPainel />
    </Card>
  )
}

/** Sobe ou desce uma conta do pool: grava a lista completa das contas do pool na ordem nova (as detectadas ficam fora). */
function mover(contas: Conta[], nome: string, delta: -1 | 1): Promise<boolean> {
  const nomes = contas.filter((c) => c.origem !== 'orca').map((c) => c.nome)
  const i = nomes.indexOf(nome)
  const j = i + delta
  if (i < 0 || j < 0 || j >= nomes.length) return Promise.resolve(false)
  ;[nomes[i], nomes[j]] = [nomes[j], nomes[i]]
  return salvar('ordem', [], { 'pool.ordem': nomes.join(',') })
}

function SecaoPool({ e }: { e: Estado }) {
  const { pool } = e
  const abertas = read(abertasConta)
  const noPool = pool.contas.filter((c) => c.origem !== 'orca').map((c) => c.nome)
  const ocupado = read(gravando) !== null
  return (
    <Card title={t.pool.titulo} description={t.pool.resumo(pool.maquina.usadas, pool.maquina.teto, pool.ram_min, pool.escolha)}>
      {pool.contas.length === 0 ? (
        <Text muted>{t.pool.semContas}</Text>
      ) : (
        <Stack gap="xs">
          <Cabecalho rotulos={[t.pool.colConta, t.pool.colVagas, t.pool.col5h, t.pool.colSemanal]} />
          {pool.contas.map((c) => (
            <LinhaExpansivel
              key={c.nome}
              celulas={[
                { texto: c.nome },
                { texto: c.origem === 'orca' ? t.pool.foraDoPool : t.pool.vagasDaConta(c.usadas, c.vagas) },
                percentual(c.cota?.curta ?? null),
                percentual(c.cota?.longa ?? null)
              ]}
              aberta={abertas.includes(c.nome)}
              onAlternar={() => alternar(abertasConta, c.nome)}
              acoes={
                c.origem === 'orca' ? undefined : (
                  <Row gap="xs">
                    <IconButton icon="expand" label={t.pool.subir} size="xs" variant="ghost" disabled={ocupado || noPool[0] === c.nome} onPress={() => void mover(pool.contas, c.nome, -1)} />
                    <IconButton icon="collapse" label={t.pool.descer} size="xs" variant="ghost" disabled={ocupado || noPool[noPool.length - 1] === c.nome} onPress={() => void mover(pool.contas, c.nome, 1)} />
                  </Row>
                )
              }
            >
              <BlocoConta c={c} e={e} />
            </LinhaExpansivel>
          ))}
        </Stack>
      )}
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
          <SecaoConfiguracoes e={e} />
        </Stack>
      )}
    </Stack>
  )
}
