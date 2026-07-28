<script setup lang="ts">
/**
 * Lightweight SVG donut chart for sector mix (bulletin kinds).
 * Pure presentational, no D3 dependency; 100 LOC.
 */
import { computed } from 'vue';

interface Slice {
  label: string;
  value: number;
  color: string;
}

const props = defineProps<{ slices: Slice[] }>();

const palette: Record<string, string> = {
  VerifiedUpdate: '#0ea5e9',
  Debunk: '#f43f5e',
  Blood: '#e11d48',
  Missing: '#f59e0b',
  Supply: '#a855f7',
};

const safeSlices = computed(() =>
  props.slices.filter((s) => s.value > 0),
);

const grandTotal = computed(() =>
  safeSlices.value.reduce((a, b) => a + b.value, 0),
);

const segments = computed(() => {
  const total = grandTotal.value || 1;
  let cumulative = 0;
  return safeSlices.value.map((slice) => {
    const start = cumulative / total;
    cumulative += slice.value;
    const end = cumulative / total;
    return {
      ...slice,
      color: slice.color || palette[slice.label] || '#94a3b8',
      startAngle: start * 360,
      sweep: ((end - start) * 360) || 0.01,
    };
  });
});

function arcPath(startDeg: number, sweep: number): string {
  // Always start at top (-90°), so callers pass "angles from 12 o'clock".
  const start = (startDeg - 90) * (Math.PI / 180);
  const end = (startDeg + sweep - 90) * (Math.PI / 180);
  const r = 16;
  const cx = 20;
  const cy = 20;
  const largeArc = sweep > 180 ? 1 : 0;
  const x1 = cx + r * Math.cos(start);
  const y1 = cy + r * Math.sin(start);
  const x2 = cx + r * Math.cos(end);
  const y2 = cy + r * Math.sin(end);
  return `M ${cx} ${cy} L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${largeArc} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`;
}
</script>

<template>
  <div class="flex items-center gap-6">
    <svg viewBox="0 0 40 40" class="w-32 h-32 -rotate-90" aria-label="Bulletin kind mix">
      <circle cx="20" cy="20" r="16" fill="none" class="stroke-slate-200 dark:stroke-slate-800" stroke-width="6" />
      <path
        v-for="(seg, idx) in segments"
        :key="idx"
        :d="arcPath(seg.startAngle, seg.sweep)"
        :fill="seg.color"
        class="transition-opacity hover:opacity-90"
      >
        <title>{{ seg.label }}: {{ seg.value }}</title>
      </path>
      <circle cx="20" cy="20" r="10" class="fill-white dark:fill-slate-950" />
    </svg>
    <ul class="space-y-1 text-sm">
      <li
        v-for="seg in segments"
        :key="seg.label"
        class="flex items-center gap-2 text-slate-700 dark:text-slate-300"
      >
        <span
          class="w-2.5 h-2.5 rounded-sm"
          :style="{ background: seg.color }"
        ></span>
        <span class="font-medium">{{ seg.label }}</span>
        <span class="text-slate-500 dark:text-slate-400 tabular-nums">
          {{ seg.value }}
        </span>
      </li>
      <li v-if="!segments.length" class="text-slate-500 text-xs">
        No bulletins yet.
      </li>
    </ul>
  </div>
</template>