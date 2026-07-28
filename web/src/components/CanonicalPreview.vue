<script setup lang="ts">
/**
 * Pretty-prints canonical JSON with consistent indentation and a "sha256"
 * callout. Used by the bulletin inspector in the dashboard and the new
 * bulletin modal to demonstrate the exact bytes the server will sign.
 */
import { computed } from 'vue';

const props = defineProps<{
  payload: unknown;
  signature?: string | null;
  sha256?: string | null;
}>();

const formatted = computed(() => {
  try {
    return JSON.stringify(props.payload, null, 2);
  } catch {
    return String(props.payload);
  }
});

function shortHex(input: string | null | undefined, head = 12, tail = 8): string {
  if (!input) return '';
  if (input.length <= head + tail + 3) return input;
  return `${input.slice(0, head)}…${input.slice(-tail)}`;
}
</script>

<template>
  <div class="space-y-2">
    <pre
      class="text-[11px] leading-relaxed font-mono whitespace-pre-wrap break-all rounded-lg border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-950/70 p-3 max-h-72 overflow-auto text-slate-700 dark:text-slate-300"
    >{{ formatted }}</pre>
    <div v-if="signature || sha256" class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-[11px]">
      <div
        v-if="sha256"
        class="rounded border border-slate-200 dark:border-slate-800 px-2 py-1.5 bg-white/60 dark:bg-slate-900/60"
      >
        <div class="text-[10px] uppercase tracking-widest text-slate-500">sha256</div>
        <code class="break-all font-mono">{{ shortHex(sha256) }}</code>
      </div>
      <div
        v-if="signature"
        class="rounded border border-slate-200 dark:border-slate-800 px-2 py-1.5 bg-white/60 dark:bg-slate-900/60"
      >
        <div class="text-[10px] uppercase tracking-widest text-slate-500">signature</div>
        <code class="break-all font-mono">{{ shortHex(signature) }}</code>
      </div>
    </div>
  </div>
</template>