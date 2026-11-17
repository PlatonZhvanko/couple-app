import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Area, Progress, Snapshot, Task } from '../types'

// Where the progress lives. The tracker's branch is a fallback until it is merged into main.
const REPO = 'PlatonZhvanko/couple-app'
const FILE = 'progress/progress.json'
const REFS = ['main', 'claude/project-thread-mpkkkp']
const GH = ['gh', '/opt/homebrew/bin/gh', '/usr/local/bin/gh']
const DASHBOARD = 'https://claude.ai/artifact/8R6eqDe8JH782Daq7yVGDK'

const PANE = 'vdvoem-progress'
const STORE_KEY = 'last-snapshot'
const EVERY_MS = 5 * 60 * 1000
const MIN_GAP_MS = 60 * 1000

const EMPTY: Snapshot = { data: null, source: '', fetchedAt: 0 }
const snap = atom({ plugin: 'vdvoem-progress', key: 'snap' } as const, EMPTY, {
  shape: 'snap-1',
})
const isOpen = atom({ plugin: 'vdvoem-progress', key: 'isOpen' } as const, false)

// Рыжик: the orange mascot of the dashboard, as a tiny face whose mood follows the color tier.
const BODY = '#e8834a'
type Tier = { max: number; name: string; color: string | undefined; face: string; say: string }
const TIERS: Tier[] = [
  { max: 10, name: 'белый', color: undefined, face: '(-_-)zz', say: 'Рыжик ещё спит' },
  { max: 20, name: 'красный', color: '#e5484d', face: '(°_°;)', say: 'Рыжик волнуется' },
  { max: 45, name: 'оранжевый', color: '#f08a3a', face: '(ง •_•)ง', say: 'Рыжик засучил рукава' },
  { max: 60, name: 'жёлтый', color: '#f2c218', face: '(^_^)', say: 'Рыжик улыбается' },
  { max: 85, name: 'лайм', color: '#a6d83a', face: '(★_★)', say: 'Рыжик в восторге' },
  { max: 101, name: 'зелёный', color: '#2fae66', face: '\\(^o^)/', say: 'Рыжик празднует' },
]
const LAST: Tier = { max: 101, name: 'зелёный', color: '#2fae66', face: '\\(^o^)/', say: 'Рыжик празднует' }
const tierOf = (p: number): Tier => TIERS.find(t => p < t.max) ?? LAST

const SCORE: Record<string, number> = { done: 1, doing: 0.5, todo: 0 }
export function pctOf(tasks: readonly Task[]): number {
  let w = 0
  let s = 0
  for (const t of tasks) {
    const wt = typeof t.weight === 'number' && t.weight > 0 ? t.weight : 1
    w += wt
    s += wt * (SCORE[t.status] ?? 0)
  }

  return w ? Math.round((s / w) * 100) : 0
}

function parse(text: string): Progress | null {
  try {
    const raw = JSON.parse(text) as Progress
    if (!raw || !Array.isArray(raw.areas)) return null

    return {
      updated: typeof raw.updated === 'string' ? raw.updated : undefined,
      areas: raw.areas
        .filter(a => a && typeof a.title === 'string')
        .map(a => ({
          id: String(a.id ?? a.title),
          title: a.title,
          emoji: typeof a.emoji === 'string' ? a.emoji : undefined,
          tasks: (Array.isArray(a.tasks) ? a.tasks : [])
            .filter(t => t && typeof t.title === 'string')
            .map(t => ({
              title: t.title,
              status: t.status === 'done' || t.status === 'doing' ? t.status : 'todo',
              ...(typeof t.weight === 'number' ? { weight: t.weight } : {}),
            })),
        })),
    }
  } catch {
    return null
  }
}

let cwd = ''
let gh: string | null = null
let isFetching = false

async function fetchProgress($: EngineInterface): Promise<void> {
  if (isFetching) return
  isFetching = true
  try {
    const now = await $.clock.now()
    let error = 'не нашёл gh (GitHub CLI)'

    for (const ref of REFS) {
      const tries = gh ? [gh] : GH
      for (const bin of tries) {
        let result
        try {
          result = await $.process.run(
            [
              bin,
              'api',
              '-H',
              'Accept: application/vnd.github.raw',
              `repos/${REPO}/contents/${FILE}?ref=${encodeURIComponent(ref)}`,
            ],
            { timeoutMs: 20000 },
          )
        } catch {
          continue
        }
        gh = bin
        const data = result.exitCode === 0 ? parse(result.stdout) : null
        if (data) {
          const next: Snapshot = { data, source: `GitHub, ${ref}`, fetchedAt: now }
          await update($, snap, () => next)
          await $.store.set(STORE_KEY, next).catch(() => undefined)

          return
        }
        const why = (result.stderr || result.stdout).trim().split('\n')[0] ?? ''
        error = /auth|login|401/i.test(why)
          ? 'gh не вошёл в GitHub: выполните gh auth login'
          : `GitHub: ${why.slice(0, 80) || 'нет файла'}`
        break
      }
    }

    // Working inside a clone of the app: read the file from disk.
    if (cwd) {
      try {
        const data = parse(await $.fs.read(`${cwd}/${FILE}`))
        if (data) {
          const next: Snapshot = { data, source: 'файл в этой папке', fetchedAt: now }
          await update($, snap, () => next)

          return
        }
      } catch {
        // no local copy
      }
    }

    await update($, snap, old => ({ ...old, error }))
  } finally {
    isFetching = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    cwd = e.cwd
    const started = await next(e)

    const saved = (await $.store.get(STORE_KEY).catch(() => undefined)) as Snapshot | undefined
    if (saved?.data) await update($, snap, old => (old.data ? old : saved))

    await $.command.register({
      name: 'progress',
      description: 'Прогресс «Вдвоём»: все задачи с галочками',
    })
    void fetchProgress($)
    $.clock.every(EVERY_MS, () => fetchProgress($))

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    const last = (await read($, snap)).fetchedAt
    if ((await $.clock.now()) - last > MIN_GAP_MS) void fetchProgress($)

    return result
  })

  on('command.run', { command: 'progress' }, async $ => {
    void fetchProgress($)
    const opened = await $.ui.open({ id: PANE, title: 'Прогресс «Вдвоём»' })

    return {
      text: opened.isPlaced
        ? 'Открыл панель с задачами.'
        : `Панель не открылась здесь. Полный трекер: ${DASHBOARD}`,
    }
  })

  // The always-visible mini band above the prompt.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const s = await read($, snap)
    const open = await read($, isOpen)
    const width = e.props.bodyColumns

    if (!s.data) {
      return (
        <Box flexDirection="row" gap={1}>
          <Text color={BODY} weight="bold">
            Рыжик (o_o)?
          </Text>
          <Text dimColor wrap="truncate-end">
            {s.error ? `Вдвоём: ${s.error}` : 'Вдвоём: загружаю прогресс…'}
          </Text>
          <Button key="refresh" label="↻" plain dimColor onPress={() => fetchProgress($)} />
        </Box>
      )
    }

    const areas = s.data.areas
    const total = pctOf(areas.flatMap(a => a.tasks))
    const tier = tierOf(total)
    const barCells = width >= 90 ? 14 : width >= 60 ? 10 : 6

    const head = (
      <Box flexDirection="row" gap={1} key="head">
        <Text color={BODY} weight="bold">
          {tier.face}
        </Text>
        <Text weight="bold">Вдвоём</Text>
        <Text color={tier.color} weight="bold" tabular>
          {total}%
        </Text>
        {bar(Text, total, barCells)}
        {width >= 70 && (
          <Text dimColor wrap="truncate-end">
            {tier.say}
          </Text>
        )}
        <Button
          key="toggle"
          label={open ? '▾ свернуть' : '▸ разделы'}
          plain
          dimColor
          hotkey="p"
          onPress={() => update($, isOpen, v => !v)}
        />
      </Box>
    )

    if (!open) return head

    const nameWidth = Math.min(12, Math.max(...areas.map(a => a.title.length)) + 1)

    return (
      <Box flexDirection="column">
        {head}
        {areas.map(a => (
          areaRow(Box, Text, a, barCells, nameWidth)
        ))}
        <Box flexDirection="row" gap={2} key="actions">
          <Button
            key="tasks"
            label="✓ все задачи"
            plain
            dimColor
            onPress={() => $.ui.open({ id: PANE, title: 'Прогресс «Вдвоём»' })}
          />
          <Button key="refresh" label="↻ обновить" plain dimColor onPress={() => fetchProgress($)} />
          <Text dimColor wrap="truncate-end">
            {s.data.updated ? `обновлено ${s.data.updated}` : ''}
            {s.error ? ` · ${s.error}` : ''}
          </Text>
        </Box>
      </Box>
    )
  })

  // The pane with every task: ✓ done, … in progress, ○ ahead.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const s = await read($, snap)
    if (!s.data) {
      return <Text dimColor>{s.error ?? 'Загружаю прогресс…'}</Text>
    }
    const areas = s.data.areas
    const total = pctOf(areas.flatMap(a => a.tasks))
    const tier = tierOf(total)
    const order = ['done', 'doing', 'todo']

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1}>
          <Text color={BODY} weight="bold">
            {tier.face}
          </Text>
          <Text weight="bold">
            Всё приложение <Text color={tier.color}>{total}%</Text>
          </Text>
          <Text dimColor>{tier.say}</Text>
        </Box>
        {areas.map(a => {
          const p = pctOf(a.tasks)
          const tasks = [...a.tasks].sort((x, y) => order.indexOf(x.status) - order.indexOf(y.status))

          return (
            <Box flexDirection="column" key={a.id}>
              <Box flexDirection="row" gap={1}>
                <Text weight="bold">
                  {a.emoji ? `${a.emoji} ` : ''}
                  {a.title}
                </Text>
                <Text color={tierOf(p).color} weight="bold" tabular>
                  {p}%
                </Text>
                {bar(Text, p, 10)}
              </Box>
              {tasks.map(t => (
                <Text dimColor={t.status === 'todo'}>
                  {t.status === 'done' ? (
                    <Text color="#2fae66">✓ </Text>
                  ) : t.status === 'doing' ? (
                    <Text color="#f2c218">… </Text>
                  ) : (
                    '○ '
                  )}
                  {t.title}
                  {t.status === 'doing' ? <Text color={BODY}> · в работе</Text> : ''}
                </Text>
              ))}
            </Box>
          )
        })}
        <Box flexDirection="row" gap={2}>
          <Button key="pane-refresh" label="↻ обновить" plain dimColor onPress={() => fetchProgress($)} />
          <Text dimColor>
            {s.source}
            {s.error ? ` · ${s.error}` : ''}
          </Text>
        </Box>
      </Box>
    )
  })
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type El = any

function bar(Text: El, pct: number, cells: number) {
  const filled = Math.max(0, Math.min(cells, Math.round((pct / 100) * cells)))
  const color = tierOf(pct).color

  return (
    <Text>
      <Text color={color}>{'█'.repeat(filled)}</Text>
      <Text dimColor>{'░'.repeat(cells - filled)}</Text>
    </Text>
  )
}

function areaRow(Box: El, Text: El, area: Area, cells: number, nameWidth: number) {
  const p = pctOf(area.tasks)

  return (
    <Box flexDirection="row" gap={1} key={`area-${area.id}`}>
      <Text>{`  ${area.title}`.padEnd(nameWidth + 2)}</Text>
      {bar(Text, p, cells)}
      <Text color={tierOf(p).color} tabular>
        {String(p).padStart(3)}%
      </Text>
    </Box>
  )
}
