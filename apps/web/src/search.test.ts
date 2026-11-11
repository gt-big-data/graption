import { expect, test } from 'vitest';
import { searchMeetings } from './search';
import example from '../../../schemas/fixtures/session_export.example.json';
test('search ignores case and accents across meetings', () => {
  const sessions = structuredClone(example.sessions);
  sessions[0].captions[0].text = 'A CAFÉ meeting';
  sessions[1].captions[0].text = 'Another café';
  expect(searchMeetings(sessions, 'cafe')).toHaveLength(2);
  expect(searchMeetings(sessions, '  CAFÉ ')).toHaveLength(2);
  expect(searchMeetings(sessions, 'missing')).toEqual([]);
  expect(searchMeetings(sessions, '  ')).toEqual([]);
});
