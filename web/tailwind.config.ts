import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{vue,ts,js}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#0b0b0f',
          accent: '#10b981',
          glow: '#34d399',
          surface: {
            light: '#f8fafc',
            DEFAULT: '#0b0b0f',
            soft: '#111827',
            softer: '#1f2937',
          },
        },
      },
      boxShadow: {
        glow: '0 0 0 1px rgba(16, 185, 129, 0.35), 0 8px 24px -12px rgba(16, 185, 129, 0.45)',
      },
      animation: {
        'pulse-slow': 'pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'fade-in': 'fadeIn 240ms ease-out both',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0', transform: 'translateY(4px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
      },
    },
  },
  plugins: [],
} satisfies Config;