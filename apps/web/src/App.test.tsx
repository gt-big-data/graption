import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react';
import { afterEach, expect, test } from 'vitest';
import App from './App';
import example from '../../../schemas/fixtures/session_export.example.json';

afterEach(cleanup);
test('loads exports and opens a transcript with speaker and tone', async () => {
  render(<App />);
  const file = new File([JSON.stringify(example)], 'example.json', { type: 'application/json' });
  file.text = async () => JSON.stringify(example);
  fireEvent.change(screen.getByLabelText(/choose files/i), { target: { files: [file] } });
  await waitFor(() => expect(screen.getAllByRole('button', { name: /captions/i })).toHaveLength(2));
  fireEvent.click(screen.getByRole('button', { name: /2 captions/i }));
  expect(screen.getByText('Someone')).toBeInTheDocument();
  expect(screen.getByText('Tone: excited')).toBeInTheDocument();
  expect(screen.getByText('See you soon.')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /back to meetings/i }));
  fireEvent.click(screen.getByRole('button', { name: 'Clear' }));
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
  await screen.findByRole('button', { name: /2 captions/i });
  fireEvent.change(screen.getByLabelText('Search all meetings'), { target: { value: 'SEE YOU' } });
  expect(screen.getByRole('status')).toHaveTextContent('1 results');
  fireEvent.click(screen.getByRole('button', { name: /See you soon/i }));
  const caption = screen.getByText('See you soon.', { selector: 'p' }).closest('li');
  expect(caption).toHaveClass('highlighted');
  expect(caption).toHaveFocus();
});
