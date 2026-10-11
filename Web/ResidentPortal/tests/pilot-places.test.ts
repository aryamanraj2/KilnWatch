import { describe, expect, it } from 'vitest';
import { findPilotPlace } from '../src/data/pilot-places';

describe('named pilot lookup', () => {
  it.each(['Hapur', ' HAPUR ', 'हापुड़', 'हापुड', 'Hapur · pilot area'])('recognises %s', name => {
    expect(findPilotPlace(name)?.center).toEqual([77.7759, 28.7306]);
  });
  it.each(['', 'Delhi', 'Hapur outskirts', 'hap'])('does not treat %s as a supported place', name => {
    expect(findPilotPlace(name)).toBeUndefined();
  });
});
