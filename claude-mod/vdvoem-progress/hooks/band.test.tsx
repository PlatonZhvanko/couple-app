import { expect, test } from 'claude-code/testing'

const DATA = JSON.stringify({
  updated: '2026-11-17',
  areas: [
    { id: 'foundation', title: 'Основа', tasks: [
      { title: 'A', status: 'done' }, { title: 'B', status: 'doing' }, { title: 'C', status: 'todo' }, { title: 'D', status: 'done' } ] },
    { id: 'sleep', title: 'Сон', tasks: [ { title: 'Обсудить', status: 'todo' } ] },
  ],
})

const BAND = {
  plugin: 'vdvoem-progress',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 20,
    bodyColumns: 100, scroll: { offset: 0, bodyRows: 20 }, view: {},
  },
} as const

const PANE = {
  plugin: 'vdvoem-progress',
  component: 'Pane',
  requestId: 'vdvoem-progress',
  props: {
    title: 'Прогресс', isFocused: false, bodyColumns: 60, placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 }, view: {},
  },
} as const

function engine(on: any, gh: { exitCode: number; stdout: string; stderr: string }) {
  on('command.register', () => ({ value: { command: 'progress' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('process.run', () => ({ value: gh }))
  on('fs.read', () => { throw new Error('ENOENT') })
  on('clock.now', () => ({ value: 1_000_000 }))
  on('clock.every', () => ({ value: undefined }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`band: collapsed shows overall %, expands to areas (${surface})`, async ($, on) => {
    engine(on, { exitCode: 0, stdout: DATA, stderr: '' })
    await $.session.start({ cwd: '/x', surface, isInteractive: true })
    const ui = await $.ui.mount({ ...BAND, surface })
    if (await ui.find({ key: 'refresh' } as any)) await ui.press({ key: 'refresh' })
    // 2.5 of 5 tasks = 50% → yellow tier
    expect((await ui.find({ type: 'Text', text: /^50%$/ }))?.text).toBe('50%')
    expect(await ui.find({ type: 'Text', text: /Сон/ })).toBeFalsy()

    await ui.press({ key: 'toggle' })
    expect((await ui.find({ type: 'Text', text: /Сон/ }))?.text).toContain('Сон')
    expect((await ui.find({ type: 'Text', text: /63%|  0%/ }))).toBeTruthy()
    await ui.unmount()

    const pane = await $.ui.mount({ ...PANE, surface })
    expect((await pane.find({ type: 'Text', text: /в работе/ }))).toBeTruthy()
    await pane.unmount()
  })
}

test('band says what is wrong when gh is not signed in', async ($, on) => {
  engine(on, { exitCode: 1, stdout: '', stderr: 'gh auth login required' })
  await $.session.start({ cwd: '/x', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'refresh' })
  expect((await ui.find({ type: 'Text', text: /gh auth login/ }))?.text).toContain('gh auth login')
  await ui.unmount()
})
