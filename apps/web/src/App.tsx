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
const palette = ['#ff6b6b', '#4fcfc4', '#ffe66e', '#a68cfa', '#7db5ff', '#ffb5c2'];
const speakerColor = (id: string) => {
  if (!/^f[1-9][0-9]*$/.test(id)) return '#b5bfd0';
  const number = Number(id.slice(1));
  return number <= palette.length ? palette[number - 1] : `hsl(${((number * 0.61803398875) % 1) * 360} 83.94% 68.875%)`;
};
const speakerLabel = (id: string) => /^f[1-9][0-9]*$/.test(id) ? `Speaker ${id.slice(1)}` : 'Unknown speaker';
const title = (session: Session) => session.title || `Meeting ${new Date(session.started_at).toLocaleString()}`;
const time = (seconds: number) => `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;

export default function App() {
  const [serverToken, setServerToken] = useState('');
  const [serverStatus, setServerStatus] = useState('');
  const [serverIDs, setServerIDs] = useState<Set<string>>(new Set());
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
      incoming.forEach(session => session.deleted_at ? merged.delete(session.id) : merged.set(session.id, session));
      return [...merged.values()].sort ( (a, b) => Date.parse(b.started_at) - Date.parse(a.started_at));
    });
    setErrors(failures);
  }
  async function loadServer() {
    setServerStatus('Loading…');
    try {
      const response = await fetch('/api/meetings', {
        headers: serverToken ? { Authorization: `Bearer ${serverToken}` } : {},
      });
      if (!response.ok) throw new Error(`Server returned ${response.status}`);
      const data: unknown = await response.json();
      if (!validate(data)) throw new Error('Server returned an invalid meeting export');
      const incoming = (data as unknown as SessionExport).sessions;
      setSessions(current => {
        // Refresh replaces the previous server snapshot so deleted meetings disappear.
        const merged = new Map(current.filter(session => !serverIDs.has(session.id)).map(session => [session.id, session]));
        incoming.forEach(session => session.deleted_at ? merged.delete(session.id) : merged.set(session.id, session));
        return [...merged.values()].sort((a, b) => Date.parse(b.started_at) - Date.parse(a.started_at));
      });
      setServerIDs(new Set(incoming.map(session => session.id)));
      setServerStatus(`Loaded ${incoming.filter(session => !session.deleted_at).length} saved meetings`);
    } catch (error) {
      setServerStatus(`Could not load meetings. ${error instanceof Error ? error.message : ''}`);
    }
  }
  const onChange = (event: ChangeEvent<HTMLInputElement>) => { if (event.target.files) void load(event.target.files); event.target.value = ''; };
  const onDrop = (event: DragEvent) => { event.preventDefault(); void load(event.dataTransfer.files); };
  const session = sessions.find(item => item.id === selected);
  const results = searchMeetings(sessions, query);
  return <main><header><h1>Graption meetings</h1><p>Open local exports or load meetings synced from your iPhone.</p></header>
    <section aria-label="Server meetings"><h2>Synced meetings</h2><label htmlFor="server-token">Server token (if required)</label><input id="server-token" type="password" value={serverToken} onChange={event => setServerToken(event.target.value)} autoComplete="off" /><button onClick={() => void loadServer()}>Load / refresh from server</button><p aria-live="polite">{serverStatus}</p></section>
    <section aria-label="Search meetings"><label htmlFor="search">Search all meetings</label><input id="search" type="search" value={query} onChange={event => setQuery(event.target.value)} /><p role="status" aria-live="polite">{query.trim() ? `${results.length} results` : ''}</p>{query.trim() && <ul className="meetings">{results.map(({ session: meeting, caption }) => <li key={`${meeting.id}-${caption.caption_id}`}><button onClick={() => { setSelected(meeting.id); setTarget(caption.caption_id); }}><strong>{title(meeting)}</strong><span>{caption.text}</span></button></li>)}</ul>}</section>
    {session ? <section><button onClick={() => setSelected(null)}>← Back to meetings</button><h2>{title(session)}</h2><p>{new Date(session.started_at).toLocaleString()}</p><ol className="transcript">{session.captions.map(caption => <li key={caption.caption_id} id={`caption-${caption.caption_id}`} tabIndex={-1} className={target === caption.caption_id ? 'highlighted' : undefined} style={{ borderLeft: `4px solid ${speakerColor(caption.speaker_id)}` }}><div><strong style={{ color: speakerColor(caption.speaker_id) }}>{speakerLabel(caption.speaker_id)}</strong> <time>{time(caption.t_start)}</time></div><p>{caption.text}</p>{caption.tone_tag !== null && <span className="tag">Tone: {caption.tone_tag}</span>}{caption.tone_probs && <details><summary>Tone probabilities</summary><dl>{Object.entries(caption.tone_probs).map(([label, probability]) => <div key={label}><dt>{label}</dt><dd>{((probability ?? 0) * 100).toFixed(1)}%</dd></div>)}</dl></details>}{caption.tone_scores && <details><summary>Tone dimensions</summary><dl>{Object.entries(caption.tone_scores).map(([label, score]) => <div key={label}><dt>{label}</dt><dd>{score?.toFixed(3)}</dd></div>)}</dl></details>}</li>)}</ol><h3>Sound alerts</h3>{!session.sound_events?.length ? <p>No saved sound alerts.</p> : <ul className="transcript">{session.sound_events.map(event => <li key={event.id}><strong>{event.label}</strong> <time>{time(event.t)}</time><p>{(event.confidence * 100).toFixed(0)}% confidence · {event.model_version}</p></li>)}</ul>}</section>
    : <><section className="drop" onDragOver={event => event.preventDefault()} onDrop={onDrop}><h2>Open meeting exports</h2><p>Choose or drop one or more JSON files.</p><label className="file">Choose files<input aria-label="Choose files" type="file" accept=".json,application/json" multiple onChange={onChange}/></label> <button className="secondary" disabled={!sessions.length && !errors.length} onClick={() => {setSessions([]); setErrors([]); setQuery(''); setTarget(null);}}>Clear</button>{errors.map(error => <p role="alert" key={error}>{error}</p>)}</section><section><h2>Meetings</h2>{sessions.length === 0 ? <p>No meetings loaded yet.</p> : <ul className="meetings">{sessions.map(item => <li key={item.id}><button onClick={() => setSelected(item.id)}><strong>{title(item)}</strong><span>{time(item.duration)} · {item.captions.length} captions</span></button></li>)}</ul>}</section></>}
  </main>;
}
