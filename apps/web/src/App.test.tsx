import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react';
import { afterEach, expect, test, vi } from 'vitest';
import App from './App';
import example from '../../../schemas/fixtures/session_export.example.json';

afterEach(() => { cleanup(); vi.unstubAllGlobals(); window.history.replaceState(null, '', '/'); });
test('loads exports and opens a transcript with speaker and tone', async () => {
  render(<App />);
  const file = new File([JSON.stringify(example)], 'example.json', { type: 'application/json' });
  file.text = async () => JSON.stringify(example);
  fireEvent.change(screen.getByLabelText(/choose files/i), { target: { files: [file] } });
  await waitFor(() => expect(screen.getAllByRole('button', { name: /captions/i })).toHaveLength(2));
  fireEvent.click(screen.getAllByRole('button', { name: /captions/i })[1]);
  expect(screen.getByText('Speaker 1')).toBeInTheDocument();
  expect(screen.getByText('Tone: happy')).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Generate summary' })).not.toBeInTheDocument();
  expect(screen.getByText(example.sessions[0].captions[0].text)).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /back to meetings/i }));
  fireEvent.click(screen.getAllByRole('button', { name: /captions/i })[0]);
  expect(screen.getByText('Unknown speaker')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /back to meetings/i }));
  fireEvent.click(screen.getByRole('button', { name: 'Clear imports' }));
  expect(screen.getByText('No meetings loaded yet.')).toBeInTheDocument();
});
test('reports an invalid file', async () => {
  render(<App />);
  const file = new File(['{}'], 'bad.json'); file.text = async () => '{}';
  fireEvent.change(screen.getByLabelText(/choose files/i), { target: { files: [file] } });
  expect(await screen.findByRole('alert')).toHaveTextContent('bad.json');
});

test('search result opens, focuses and highlights its caption', async () => {
  render(<App />);
  const file = new File([JSON.stringify(example)], 'example.json');
  file.text = async () => JSON.stringify(example);
  fireEvent.change(screen.getByLabelText(/choose files/i), { target: { files: [file] } });
  await waitFor(() => expect(screen.getAllByRole('button', { name: /captions/i })).toHaveLength(2));
  fireEvent.change(screen.getByLabelText('Search all meetings'), { target: { value: 'TOMORROW' } });
  expect(screen.getByRole('status')).toHaveTextContent('1 results');
  fireEvent.click(screen.getByRole('button', { name: /meet again tomorrow/i }));
  const caption = screen.getByText(example.sessions[1].captions[0].text, { selector: 'p' }).closest('li');
  expect(caption).toHaveClass('highlighted');
  expect(caption).toHaveFocus();
});


test('server refresh updates titles, exposes saved details and removes deleted meetings', async () => {
  const meeting = structuredClone(example.sessions[0]);
  const detailed = { ...meeting, title: 'Planning', sound_events: [{
    id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', label: 'doorbell', t: 1,
    confidence: 0.9, model_version: 'sound-v1',
  }], captions: [{ ...meeting.captions[0], tone_probs: { happy: 0.8 },
    tone_scores: { arousal: 0.6 } }] };
  const fetcher = vi.fn().mockResolvedValueOnce({ ok: true,
    json: async () => ({ ...example, export_version: '2', sessions: [detailed] }) })
    .mockResolvedValueOnce({ ok: true,
      json: async () => ({ ...example, export_version: '2', sessions: [] }) });
  vi.stubGlobal('fetch', fetcher);
  render(<App />);
  fireEvent.click(screen.getByRole('button', { name: /refresh from server/i }));
  fireEvent.click(await screen.findByRole('button', { name: /Planning/ }));
  expect(screen.getByText('doorbell')).toBeInTheDocument();
  expect(screen.getByText('80.0%')).toBeInTheDocument();
  expect(screen.getByText('0.600')).toBeInTheDocument();
  expect(screen.getByText('Speaker 1')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /back to meetings/i }));
  fireEvent.click(screen.getByRole('button', { name: /refresh from server/i }));
  await waitFor(() => expect(screen.queryByRole('button', { name: /Planning/ })).not.toBeInTheDocument());
});

test('generates a summary and asks a transcript question for a synced meeting', async () => {
  const meeting = { ...example.sessions[0], title: 'Planning' };
  const fetcher = vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => ({ ...example, sessions: [meeting] }) })
    .mockResolvedValueOnce({ ok: true, json: async () => ({ answer: 'Summary from OpenRouter' }) })
    .mockResolvedValueOnce({ ok: true, json: async () => ({ answer: 'Answer from OpenRouter' }) });
  vi.stubGlobal('fetch', fetcher);
  render(<App />);
  fireEvent.change(screen.getByLabelText(/server token/i), { target: { value: 'test-token' } });
  fireEvent.click(screen.getByRole('button', { name: /refresh from server/i }));
  fireEvent.click(await screen.findByRole('button', { name: /Planning/ }));
  fireEvent.click(screen.getByRole('button', { name: 'Generate summary' }));
  expect(await screen.findByText('Summary from OpenRouter')).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText('Ask about this transcript'), { target: { value: 'Who spoke?' } });
  fireEvent.click(screen.getByRole('button', { name: 'Ask' }));
  expect(await screen.findByText('Answer from OpenRouter')).toBeInTheDocument();
  expect(fetcher).toHaveBeenLastCalledWith(`/api/meetings/${meeting.id}/ai`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer test-token' },
    body: JSON.stringify({ question: 'Who spoke?' }),
  });
});

test('shows a pairing QR and restores dashboard access after reopening', async () => {
  const storage = new Map<string, string>();
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
  });
  const fetcher = vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => ({ qr: '<svg/>', token: 'paired-token' }) })
    .mockResolvedValue({ ok: true, json: async () => ({ ...example, sessions: [example.sessions[0]] }) });
  vi.stubGlobal('fetch', fetcher);
  const page = render(<App />);
  fireEvent.click(screen.getByRole('button', { name: 'Pair an iPhone or iPad' }));
  const qr = await screen.findByRole('img', { name: 'Graption device pairing QR code' });
  expect(qr).toHaveAttribute('src', expect.stringContaining('data:image/svg+xml'));
  expect(fetcher).toHaveBeenCalledWith('/api/pairing', { method: 'POST' });
  expect(await screen.findByText('Loaded 1 saved meetings')).toBeInTheDocument();
  page.unmount();
  render(<App />);
  expect(fetcher).toHaveBeenLastCalledWith('/api/meetings', expect.objectContaining({
    headers: { Authorization: 'Bearer paired-token' },
  }));
  fireEvent.click(await screen.findByRole('button', { name: /captions/i }));
  expect(screen.getByText(example.sessions[0].captions[0].text)).toBeInTheDocument();
});

test('opens synced transcripts on the Mac without browser pairing state', async () => {
  const meeting = { ...example.sessions[0], title: 'Rehearsal' };
  window.history.replaceState(null, '', '/graption/');
  const fetcher = vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => ({ token: 'existing-token' }) })
    .mockResolvedValueOnce({ ok: true, json: async () => ({ ...example, sessions: [meeting] }) });
  vi.stubGlobal('fetch', fetcher);
  render(<App />);
  expect(await screen.findByRole('button', { name: /Rehearsal/ })).toBeInTheDocument();
  expect(fetcher).toHaveBeenNthCalledWith(1, '/api/pairing', expect.any(Object));
  expect(fetcher).toHaveBeenNthCalledWith(2, '/api/meetings', expect.objectContaining({
    headers: { Authorization: 'Bearer existing-token' },
  }));
});
