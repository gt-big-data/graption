import { useState } from 'react';

export default function MeetingAI({ meetingID, serverToken }: { meetingID: string; serverToken: string }) {
  const [question, setQuestion] = useState('');
  const [result, setResult] = useState<{ title: string; answer: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function ask(prompt?: string) {
    setBusy(true);
    setError('');
    try {
      const response = await fetch(`/api/meetings/${encodeURIComponent(meetingID)}/ai`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(serverToken ? { Authorization: `Bearer ${serverToken}` } : {}),
        },
        body: JSON.stringify(prompt ? { question: prompt } : {}),
      });
      const data = await response.json();
      if (!response.ok || typeof data.answer !== 'string') {
        throw new Error(typeof data.detail === 'string' ? data.detail : 'Meeting AI is unavailable.');
      }
      setResult({ title: prompt ?? 'Meeting summary', answer: data.answer });
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Meeting AI is unavailable.');
    } finally {
      setBusy(false);
    }
  }

  return <section className="meeting-ai" aria-labelledby="meeting-ai-heading">
    <h2 id="meeting-ai-heading">Meeting AI</h2>
    <p>Summarizing or asking a question sends this meeting’s caption text to OpenRouter.</p>
    <button type="button" disabled={busy} onClick={() => void ask()}>Generate summary</button>
    <form onSubmit={event => {
      event.preventDefault();
      if (!busy && question.trim()) void ask(question.trim());
    }}>
      <label htmlFor="meeting-question">Ask about this transcript</label>
      <div className="meeting-question">
        <input id="meeting-question" value={question} maxLength={1000} onChange={event => setQuestion(event.target.value)} />
        <button type="submit" disabled={busy || !question.trim()}>Ask</button>
      </div>
    </form>
    {error && <p role="alert">{error}</p>}
    <div aria-live="polite">
      {busy && <p>Waiting for OpenRouter…</p>}
      {result && <div className="meeting-answer">
        <h3>{result.title}</h3>
        <p>{result.answer}</p>
      </div>}
    </div>
  </section>;
}
