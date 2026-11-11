import type { SessionExport } from './generated/sessionExport';

export const normalizeSearch = (text: string) => text.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase();

export function searchMeetings(sessions: SessionExport['sessions'], query: string) {
  const needle = normalizeSearch(query.trim());
  if (!needle) return [];
  return sessions.flatMap(session => session.captions
    .filter(caption => normalizeSearch(caption.text).includes(needle))
    .map(caption => ({ session, caption })));
}
