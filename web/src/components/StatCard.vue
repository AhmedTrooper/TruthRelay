<script setup lang="ts">
/**
 * Single KPI tile — number on top, label + delta below.
 * Pure presentational; consumers pass in the values so this component
 * stays snapshot-friendly (no store coupling).
 */
import { computed } from 'vue';

const props = defineProps<{
  label: string;
  value: number | string;
  delta?: number | null;
  hint?: string;
  accent?: 'emerald' | 'sky' | 'amber' | 'rose' | 'violet';
}>();

const accentClass = computed(() => {
  switch (props.accent ?? 'emerald') {
    case 'sky':
      return 'from-sky-500/10 to-sky-500/0 text-sky-600 dark:text-sky-300';
    case 'amber':
      return 'from-amber-500/10 to-amber-500/0 text-amber-600 dark:text-amber-300';
    case 'rose':
      return 'from-rose-500/10 to-rose-500/0 text-rose-600 dark:text-rose-300';
    case 'violet':
      return 'from-violet-500/10 to-violet-500/0 text-violet-600 dark:text-violet-300';
    default:
      return 'from-emerald-500/10 to-emerald-500/0 text-emerald-600 dark:text-emerald-300';
  }
});

const deltaTone = computed(() => {
  if (props.delta == null) return '';
  if (props.delta > 0) return 'text-emerald-600 dark:text-emerald-300';
  if (props.delta < 0) return 'text-rose-600 dark:text-rose-300';
  return 'text-slate-500';
});

const deltaSymbol = computed(() => {
  if (props.delta == null) return '';
  if (props.delta > 0) return '▲';
  if (props.delta < 0) return '▼';
  return '·';
});
</script>

<template>
  <div
    class="surface-tile relative overflow-hidden"
    :class="`bg-gradient-to-br ${accentClass}`"
  >
    <p class="text-[11px] uppercase tracking-widest text-slate-500 dark:text-slate-400 m-0">
      {{ label }}
    </p>
    <p class="text-3xl font-bold mt-1.5 mb-0.5 text-slate-900 dark:text-slate-50">
      {{ value }}
    </p>
    <div class="flex items-center gap-2 text-xs">
      <span v-if="delta !== undefined && delta !== null" :class="deltaTone">
        {{ deltaSymbol }} {{ Math.abs(delta) }}
      </span>
      <span v-if="hint" class="text-slate-500 dark:text-slate-400">{{ hint }}</span>
    </div>
  </div>
</template>