import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import StatCard from './StatCard.vue';

describe('StatCard', () => {
  beforeEach(() => {
    // requestAnimationFrame is required for the count-up animation; in
    // vitest the default impl runs the callback synchronously, which
    // makes the duration effectively zero — perfect for fast tests.
    if (!globalThis.requestAnimationFrame) {
      globalThis.requestAnimationFrame = (cb: FrameRequestCallback) =>
        setTimeout(() => cb(performance.now()), 0) as unknown as number;
      globalThis.cancelAnimationFrame = (id: number) =>
        clearTimeout(id as unknown as ReturnType<typeof setTimeout>);
    }
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

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

  it('animates from the previous numeric value to the new one', async () => {
    const w = mount(StatCard, { props: { label: 'x', value: 0 } });
    expect(w.text()).toContain('0');
    await w.setProps({ value: 50 });
    await flushPromises();
    // The watch schedules ~12 frames over 600ms. Wait past the full
    // duration so the animation has fully settled on the target value.
    await new Promise((r) => setTimeout(r, 750));
    expect(w.text()).toContain('50');
  });

  it('renders non-numeric values verbatim without animation', async () => {
    const w = mount(StatCard, { props: { label: 'x', value: 'online' } });
    expect(w.text()).toContain('online');
    await w.setProps({ value: 'offline' });
    expect(w.text()).toContain('offline');
  });
});