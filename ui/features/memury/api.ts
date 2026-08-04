import doFetchApi from '@canvas/do-fetch-api-effect'
import type {MemuryState} from './types'

export async function getState(): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/state'})
  if (!json) throw new Error('Memury returned no state')
  return json
}

export async function syncState(): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/sync', method: 'POST'})
  if (!json) throw new Error('Memury sync returned no state')
  return json
}

export async function sendAction(body: Record<string, unknown>): Promise<MemuryState> {
  const {json} = await doFetchApi<MemuryState>({path: '/memury/action', method: 'PATCH', body})
  if (!json) throw new Error('Memury action returned no state')
  return json
}
