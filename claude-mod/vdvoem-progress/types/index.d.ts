export type TaskStatus = 'done' | 'doing' | 'todo'
export type Task = { title: string; status: TaskStatus; weight?: number }
export type Area = { id: string; title: string; emoji?: string; tasks: Task[] }
export type Progress = { updated?: string; areas: Area[] }
/** The last progress read: where it came from, when, and why the last try failed. */
export type Snapshot = {
  data: Progress | null
  source: string
  fetchedAt: number
  error?: string
}

declare module 'claude-code' {
  interface PluginState {
    'vdvoem-progress': { snap: Shaped<Snapshot>; isOpen: boolean }
  }
}
