import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import StatCard from './StatCard.vue';

describe('StatCard', () => {
  it('renders the label and value', () => {
    const w = mount(StatCard, { props: { label: 'Bulletins', value: 42 } });
    expect(w.text()).toContain('Bulletins');
    expect(w.text()).toContain('42');
  });

  it('formats positive deltas with the up-arrow', () => {
    const w = mount(StatCard, { props: { label: 'x', value: 1, delta: 3 } });
    expect(w.text()).toContain('▲ 3');
  });

  it('formats negative deltas with the down-arrow', () => {
    const w = mount(StatCard, { props: { label: 'x', value: 1, delta: -2 } });
    expect(w.text()).toContain('▼ 2');
  });

  it('omits the delta row when no delta is supplied', () => {
    const w = mount(StatCard, { props: { label: 'x', value: 1 } });
    expect(w.text()).not.toContain('▲');
    expect(w.text()).not.toContain('▼');
  });
});