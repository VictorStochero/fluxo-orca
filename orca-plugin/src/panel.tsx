// Painel de monitoramento do fluxo-orca. O estado vem do worker (plugin.request); o worker avisa quando muda.
import {
  atom,
  Badge,
  Button,
  Callout,
  Card,
  CodeView,
  EmptyState,
  Heading,
  KeyValue,
  plugin,
  read,
  RelativeTime,
  Row,
  set,
  Skeleton,
  Stack,
  Table,
  Text,
  type PanelContext
} from 'orca'
import type { Cota, Estado } from './protocol'

type Erro = { code: string; message: string }

const estado = atom<Estado | null>(null)
const erro = atom<Erro | null>(null)
const carregando = atom(false)

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

const nome = (caminho: string | null) => (caminho ? caminho.replace(/[\\/]+$/, '').split(/[\\/]/).pop() : '-')

function cota(c: Cota | null) {
  if (!c) return 'sem medida'
  const p = (v: number | null) => (v === null ? '-' : `${v}%`)
  return `${p(c.curta)} / ${p(c.longa)} · há ${c.medida_ha_min} min`
}

function SecaoFila({ e }: { e: Estado }) {
  const { fila } = e
  return (
    <Card title="Fila de testes" description={`modo ${fila.modo} · ${fila.vagas} vagas · teto ${fila.teto}`}>
      {fila.travas.length === 0 ? (
        <Text muted>Nenhuma trava.</Text>
      ) : (
        <Table
          label="Travas da fila"
          columns={[
            { key: 'fila', label: 'Fila' },
            { key: 'vaga', label: 'Vaga', align: 'end' },
            { key: 'worktree', label: 'Worktree' },
            { key: 'comando', label: 'Comando', hideBelow: 'sm' },
            { key: 'pid', label: 'PID', align: 'end', hideBelow: 'md' },
            { key: 'viva', label: 'Viva' }
          ]}
          rows={fila.travas.map((t) => ({
            key: `${t.fila}.${t.vaga}`,
            cells: {
              fila: t.fila,
              vaga: t.vaga,
              worktree: nome(t.worktree) ?? '-',
              comando: t.comando ?? '-',
              pid: t.pid ?? '-',
              viva: t.viva ? 'sim' : 'não'
            }
          }))}
        />
      )}
    </Card>
  )
}

function SecaoPool({ e }: { e: Estado }) {
  const { pool } = e
  return (
    <Card title="Pool de agentes" description={`máquina ${pool.maquina.usadas}/${pool.maquina.teto || '∞'} · ram_min ${pool.ram_min} GB`}>
      {pool.contas.length === 0 ? (
        <Text muted>Nenhuma conta no registro.</Text>
      ) : (
        <Table
          label="Contas do pool"
          columns={[
            { key: 'conta', label: 'Conta' },
            { key: 'vagas', label: 'Vagas', align: 'end' },
            { key: 'peso', label: 'Peso', align: 'end', hideBelow: 'sm' },
            { key: 'papeis', label: 'Papéis', hideBelow: 'md' },
            { key: 'cota', label: 'Cota curta / longa' }
          ]}
          rows={pool.contas.map((c) => ({
            key: c.nome,
            cells: {
              conta: c.nome,
              vagas: `${c.usadas}/${c.vagas || '∞'}`,
              peso: c.peso,
              papeis: c.papeis.join(', ') || '-',
              cota: cota(c.cota)
            }
          }))}
        />
      )}
      {pool.contas.some((c) => c.cota?.alerta) ? (
        <Callout tone="warning" title="Cota acima de 80%">
          {pool.contas.filter((c) => c.cota?.alerta).map((c) => c.nome).join(', ')}
        </Callout>
      ) : null}
    </Card>
  )
}

function SecaoRam({ e }: { e: Estado }) {
  const { ram, pool } = e
  const baixa = ram.disponivel_gb !== null && ram.disponivel_gb < pool.ram_min
  return (
    <Card title="RAM">
      <Row gap="sm" align="center">
        <Heading level={2}>{ram.disponivel_gb === null ? 'indisponível' : `${ram.disponivel_gb} GB disponíveis`}</Heading>
        {baixa ? <Badge tone="danger">abaixo de {pool.ram_min} GB</Badge> : null}
      </Row>
      {ram.relatorio ? <CodeView label="Sessões ociosas" code={ram.relatorio} wrap /> : null}
    </Card>
  )
}

function SecaoWorkers({ e }: { e: Estado }) {
  return (
    <Card title="Workers do Orca">
      {e.workers.length === 0 ? (
        <Text muted>Nenhum worker ativo.</Text>
      ) : (
        <Table
          label="Workers em andamento"
          columns={[
            { key: 'dispatch', label: 'Dispatch' },
            { key: 'agente', label: 'Agente / modelo', hideBelow: 'sm' },
            { key: 'estado', label: 'Estado' },
            { key: 'worktree', label: 'Worktree', hideBelow: 'sm' },
            { key: 'objetivo', label: 'Objetivo do run', hideBelow: 'md' }
          ]}
          rows={e.workers.map((w, i) => ({
            key: w.dispatch ?? `w${i}`,
            cells: {
              dispatch: w.dispatch ?? '-',
              agente: `${w.agente ?? '-'}${w.modelo ? ` / ${w.modelo}` : ''}`,
              estado: w.estado ?? '?',
              worktree: nome(w.worktree) ?? '-',
              objetivo: w.objetivo ?? '-'
            }
          }))}
        />
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
        <Heading>Fluxo Orca</Heading>
        <Button icon="refresh" size="sm" disabled={read(carregando)} onPress={() => void atualizar()}>
          Atualizar
        </Button>
      </Row>
      {x ? (
        <Callout tone="danger" title={`Coletor falhou (${x.code})`}>
          {x.message}
        </Callout>
      ) : null}
      {e === null ? (
        x ? (
          <EmptyState title="Sem dados" description="O coletor não respondeu." icon="warning" />
        ) : (
          <Skeleton shape="block" lines={4} label="Carregando o estado" />
        )
      ) : (
        <Stack gap="md">
          <Text muted size="xs">
            Atualizado <RelativeTime at={Date.parse(e.gerado_em)} />
          </Text>
          {e.aviso ? <Callout tone="warning">{e.aviso}</Callout> : null}
          {e.saude.scripts_desatualizados.length > 0 ? (
            <Callout tone="warning" title="Scripts desatualizados em ~/.cache">
              {e.saude.scripts_desatualizados.join(', ')}
            </Callout>
          ) : null}
          <KeyValue
            items={[
              { label: 'Plugin', value: e.saude.plugin_versao ?? '?' },
              { label: 'Orca', value: e.saude.orca.rodando ? (e.saude.orca.versao ?? 'rodando') : 'fora do ar' }
            ]}
          />
          <SecaoFila e={e} />
          <SecaoPool e={e} />
          <SecaoRam e={e} />
          <SecaoWorkers e={e} />
        </Stack>
      )}
    </Stack>
  )
}
