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
  Input,
  KeyValue,
  plugin,
  read,
  RelativeTime,
  Row,
  Select,
  set,
  Skeleton,
  Stack,
  Text,
  update,
  type PanelContext
} from 'orca'
import type { Conta, Estado, ItemFila, Trava, ValorFila } from './protocol'
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

/** Grava as edições das `chaves` da seção; a recusa do validador volta como mensagem da seção. */
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

function Origem({ v }: { v: ValorFila }) {
  const sobrescritas = v.projetos.map((p) => `${p.projeto}: ${p.valor}`).join(', ')
  return (
    <Text muted size="xs">
      {t.fila.origem(t.fila.origens[v.origem], sobrescritas)}
    </Text>
  )
}

function CampoFila({ item, e }: { item: ItemFila; e: Estado }) {
  const v = e.fila.config[item]
  const chave = `fila.${item}`
  const rotulo = t.fila.campos[item]
  const valor = read(edicoes)[chave] ?? String(v.valor)
  return (
    <Stack gap="xs">
      {item === 'modo' ? (
        <Select
          label={rotulo}
          value={valor}
          options={[{ value: 'recurso', label: 'recurso' }, { value: 'projeto', label: 'projeto' }]}
          onChange={(x) => mudar(chave, x)}
        />
      ) : (
        <Input label={rotulo} value={valor} onChange={(x) => mudar(chave, x)} />
      )}
      <Origem v={v} />
    </Stack>
  )
}

const ITENS_FILA: ItemFila[] = ['modo', 'vagas', 'vagas_projeto', 'teto', 'processos']

function LinhaTrava({ tr }: { tr: Trava }) {
  return (
    <Collapsible title={t.fila.trava(tr.fila, tr.vaga, tr.viva)}>
      <KeyValue
        items={[
          { label: t.fila.worktree, value: tr.worktree ?? '-', code: true },
          { label: t.fila.comando, value: tr.comando ?? '-', code: true },
          { label: t.fila.pid, value: tr.pid ?? '-' },
          { label: t.fila.desde, value: tr.desde ?? '-' }
        ]}
      />
    </Collapsible>
  )
}

function SecaoFila({ e }: { e: Estado }) {
  const { fila } = e
  return (
    <Card title={t.fila.titulo} description={t.fila.resumo(fila.modo, fila.vagas, fila.teto)}>
      {fila.travas.length === 0 ? (
        <Text muted>{t.fila.semTravas}</Text>
      ) : (
        fila.travas.map((tr) => <LinhaTrava key={`${tr.fila}.${tr.vaga}`} tr={tr} />)
      )}
      <Collapsible title={t.fila.configurar} description={t.fila.configurarDescricao}>
        <Stack gap="sm">
          {ITENS_FILA.map((i) => (
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

function DetalhesConta({ c }: { c: Conta }) {
  const q = c.cota
  return (
    <KeyValue
      items={[
        { label: t.pool.origem, value: origemDaConta(c) },
        ...(c.rotulo ? [{ label: t.pool.rotulo, value: c.rotulo }] : []),
        { label: t.pool.agente, value: c.agente ?? '-' },
        { label: t.pool.peso, value: c.peso },
        { label: t.pool.papeis, value: c.papeis.join(', ') || '-' },
        { label: t.pool.janelas, value: q ? q.texto : t.pool.semMedida },
        { label: t.pool.medidaHa, value: q ? t.pool.minutos(q.medida_ha_min) : '-' },
        { label: t.pool.vagasEmUso, value: c.ocupantes.map((o) => o.dispatch ?? '?').join(', ') || t.pool.nenhuma, code: c.ocupantes.length > 0 }
      ]}
    />
  )
}

/** Conta detectada pelo Orca que ainda não está no agentes.conf. */
function LinhaContaOrca({ c }: { c: Conta }) {
  const secao = `conta.${c.nome}`
  return (
    <Collapsible title={t.pool.contaForaDoPool(c.nome, c.cota?.curta ?? null, c.cota?.longa ?? null)} description={origemDaConta(c)}>
      <Stack gap="sm">
        <DetalhesConta c={c} />
        <Mensagem secao={secao} />
        <Button size="sm" icon="add" disabled={read(gravando) !== null} onPress={() => void salvar(secao, [], { [`conta.${c.nome}.adicionar`]: c.agente ?? '' })}>
          {t.pool.adicionar}
        </Button>
      </Stack>
    </Collapsible>
  )
}

function LinhaConta({ c, e }: { c: Conta; e: Estado }) {
  if (c.origem === 'orca') return <LinhaContaOrca c={c} />
  const q = c.cota
  const chaveVagas = `conta.${c.nome}.vagas`
  const chavePeso = `conta.${c.nome}.peso`
  const chavePapeis = `conta.${c.nome}.papeis`
  const chaveConfig = `conta.${c.nome}.config`
  const ed = read(edicoes)
  const papeis = (ed[chavePapeis] ?? c.papeis.join(',')).split(',').filter(Boolean)
  const alterna = (p: string, marcado: boolean) =>
    mudar(chavePapeis, e.pool.papeis_validos.filter((x) => (x === p ? marcado : papeis.includes(x))).join(','))
  const secao = `conta.${c.nome}`
  return (
    <Collapsible title={t.pool.conta(Boolean(q?.alerta), c.nome, c.usadas, c.vagas, q?.curta ?? null, q?.longa ?? null)} description={origemDaConta(c)}>
      <Stack gap="sm">
        <DetalhesConta c={c} />
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
    </Collapsible>
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
  return (
    <Card title={t.pool.titulo} description={t.pool.resumo(pool.maquina.usadas, pool.maquina.teto, pool.ram_min, pool.escolha)}>
      {pool.contas.length === 0 ? <Text muted>{t.pool.semContas}</Text> : pool.contas.map((c) => <LinhaConta key={c.nome} c={c} e={e} />)}
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
          </Text>
          {e.aviso ? <Callout tone="warning">{e.aviso}</Callout> : null}
          {e.saude.scripts_desatualizados.length > 0 ? (
            <Callout tone="warning" title={t.scriptsDesatualizados}>
              {e.saude.scripts_desatualizados.join(', ')}
            </Callout>
          ) : null}
          <KeyValue
            items={[
              { label: t.plugin, value: e.saude.plugin_versao ?? '?' },
              { label: t.orca, value: e.saude.orca.rodando ? (e.saude.orca.versao ?? t.orcaRodando) : t.orcaForaDoAr }
            ]}
          />
          <SecaoFila e={e} />
          <SecaoPool e={e} />
        </Stack>
      )}
    </Stack>
  )
}
