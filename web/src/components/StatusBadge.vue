<script setup lang="ts">
defineProps<{
  kind: string;
  verified?: boolean;
}>();

function classFor(kind: string, verified?: boolean) {
  if (verified) return 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30';
  switch (kind) {
    case 'VerifiedUpdate':
      return 'bg-sky-500/15 text-sky-300 border-sky-500/30';
    case 'Debunk':
      return 'bg-rose-500/15 text-rose-300 border-rose-500/30';
    case 'Missing':
      return 'bg-amber-500/15 text-amber-300 border-amber-500/30';
    case 'Blood':
      return 'bg-rose-500/15 text-rose-300 border-rose-500/30';
    case 'Supply':
      return 'bg-violet-500/15 text-violet-300 border-violet-500/30';
    default:
      return 'bg-slate-500/15 text-slate-300 border-slate-500/30';
  }
}
</script>

<template>
  <span
    class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded border"
    :class="classFor(kind, verified)"
  >
    <span v-if="verified" class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
    <span v-else class="w-1.5 h-1.5 rounded-full bg-current opacity-60"></span>
    {{ verified ? 'VERIFIED' : kind.toUpperCase() }}
  </span>
</template>