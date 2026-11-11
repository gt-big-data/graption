import { useEffect, useState, type ChangeEvent, type DragEvent } from 'react';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import schema from '../../../schemas/session_export.schema.json';
import type { SessionExport } from './generated/sessionExport';

import { searchMeetings } from './search';

type Session = SessionExport['sessions'][number];
const ajv = new Ajv2020({ allErrors: true });
addFormats(ajv);
const validate = ajv.compile(schema);
const time = (seconds: number) => `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;

export default function App() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [target, setTarget] = useState<string | null>(null);
  useEffect(() => {
    if (!target) return;
    const element = document.getElementById(`caption-${target}`);
    element?.scrollIntoView?.({ block: 'center' });
    element?.focus();
  }, [selected, target]);
  const [errors, setErrors] = useState<string[]>([]);
  async function load(files: FileList | File[]) {
    const incoming: Session[] = [];
    const failures: string[] = [];
    for (const file of Array.from(files)) {
      try {
        const data: unknown = JSON.parse(await file.text());
        if (!validate(data)) throw new Error('This is not a valid Graption export.');
        incoming.push(...(data as unknown as SessionExport).sessions);
      } catch { failures.push(`${file.name}: This is not a valid Graption export.`); }
    }
    setSessions(current => {
      const merged = new Map(current.map(session => [session.id, session]));
      incoming.forEach(session => merged.set(session.id, session));
      return [...merged.values()].sort ( (a, b) => Date.parse(b.started_at) - Date.parse(a.started_at));
    });
    setErrors(failures);
  }
  const onChange = (event: ChangeEvent<HTMLInputElement>) => { if (event.target.files) void load(event.target.files); event.target.value = ''; };
  const onDrop = (event: DragEvent) => { event.preventDefault(); void load(event.dataTransfer.files); };
  const session = sessions.find(item => item.id === selected);
  const results = searchMeetings(sessions, query);
  return <main><header><h1>Graption meetings</h1><p>Files are read on this device and never uploaded.</p></header>
    <section aria-label="Search meetings"><label htmlFor="search">Search all meetings</label><input id="search" type="search" value={query} onChange={event => setQuery(event.target.value)} /><p role="status" aria-live="polite">{query.trim() ? `${results.length} results` : ''}</p>{query.trim() && <ul className="meetings">{results.map(({ session: meeting, caption }) => <li key={`${meeting.id}-${caption.caption_id}`}><button onClick={() => { setSelected(meeting.id); setTarget(caption.caption_id); }}><strong>{new Date(meeting.started_at).toLocaleString()}</strong><span>{caption.text}</span></button></li>)}</ul>}</section>
    {session ? <section><button onClick={() => setSelected(null)}>← Back to meetings</button><h2>Transcript</h2><p>{new Date(session.started_at).toLocaleString()}</p><ol className="transcript">{session.captions.map(caption => <li key={caption.caption_id} id={`caption-${caption.caption_id}`} tabIndex={-1} className={target === caption.caption_id ? 'highlighted' : undefined}><div><strong>{caption.speaker_id === 'unknown' ? 'Someone' : caption.speaker_id}</strong> <time>{time(caption.t_start)}</time></div><p>{caption.text}</p>{caption.tone_tag !== null && <span className="tag">Tone: {caption.tone_tag}</span>}</li>)}</ol></section>
    : <><section className="drop" onDragOver={event => event.preventDefault()} onDrop={onDrop}><h2>Open meeting exports</h2><p>Choose or drop one or more JSON files.</p><label className="file">Choose files<input aria-label="Choose files" type="file" accept=".json,application/json" multiple onChange={onChange}/></label> <button className="secondary" disabled={!sessions.length && !errors.length} onClick={() => {setSessions([]); setErrors([]); setQuery(''); setTarget(null);}}>Clear</button>{errors.map(error => <p role="alert" key={error}>{error}</p>)}</section><section><h2>Meetings</h2>{sessions.length === 0 ? <p>No meetings loaded yet.</p> : <ul className="meetings">{sessions.map(item => <li key={item.id}><button onClick={() => setSelected(item.id)}><strong>{new Date(item.started_at).toLocaleString()}</strong><span>{time(item.duration)} · {item.captions.length} captions</span></button></li>)}</ul>}</section></>}
  </main>;
}
